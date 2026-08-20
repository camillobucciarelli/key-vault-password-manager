// 009 Slice A4/A5 — content-script bootstrap + metadata overlay + explicit fill.
//
// Slice A2 shipped the guarded bootstrap handshake below; Slice A4 (A028–A034)
// added everything that runs AFTER approval: eligible-field detection, the
// closed-shadow metadata overlay, its states, and the explicit fill path.
// Slice A5 (A035–A039) adds the frame policy surface (unsupported-frame
// states that direct manual copy from the app — never a clipboard API),
// listbox/combobox ARIA with live fallback, the keyboard contract, the
// click-vs-blur pending-action protocol, and real anchor geometry
// (flip above / viewport clamp / scroll + resize tracking).
//
// This file is registered together with `overlay_security.js`
// (see CONTENT_SCRIPT_FILES in overlay_lifecycle.js) so the SR-2 canonical
// origin rule is the shipped one, not a second copy living in the page world.
//
// SHARED-SCOPE RULE (PR #54): both files are injected into ONE isolated-world
// global scope. Every binding in this file lives inside the IIFE; the only
// global this file touches is the non-secret bootstrap guard.
//
// SR-6 / A034 — what the closed shadow root does and does not do:
// `host.shadowRoot === null` for page code is STYLE/COLLISION ISOLATION ONLY.
// The page can still observe the host's insertion/removal, its layout, the
// filled input values, and the bubbling `input`/`change` events we dispatch.
// None of that is claimed to be hidden. Security rests on sender validation,
// exact origin, the one-shot fill token, app unlock, and explicit user action.

"use strict";

(() => {
  const security = globalThis.KeyVaultOverlaySecurity;
  if (!security) return;

  // Idempotent startup: the browser can run the registered script and an
  // explicit `executeScript` injection against the same document (that is the
  // normal case right after a grant). The guard lives in the isolated world,
  // is non-secret, and is cleared on teardown so a later valid enable can
  // bootstrap again.
  const GUARD = "__keyVaultOverlayBootstrapV1";
  if (globalThis[GUARD] === true) return;
  globalThis[GUARD] = true;

  const clearGuard = () => {
    globalThis[GUARD] = false;
  };

  // Exact-origin check. A Chromium host-permission pattern cannot express a
  // port, so `https://example.com:8443` gets injected whenever
  // `https://example.com` is enabled. Both this check and the background
  // authorization below keep that other port inert.
  const origin = security.canonicalOriginOrNull(location.href);
  if (origin === null) {
    clearGuard();
    return;
  }

  const bootstrap = {
    channel: security.CHANNEL,
    version: security.MESSAGE_VERSION,
    type: "bootstrap",
    origin,
  };

  // SR-7: the three frame kinds the policy supports. `unsupported` is a real
  // answer for an enabled origin — a child frame whose top document cannot be
  // canonicalized, for instance. A035: such an instance is not silently inert
  // any more — it renders the honest unsupported-frame state on eligible
  // focus (directing manual copy from the app) and NEVER queries or fills;
  // the worker refuses `requestMatches`/`fill` for it anyway (defence in
  // depth, `overlay_routes.js` SR-7 gate).
  const SUPPORTED_FRAMES = ["top", "same-origin", "permitted-cross-origin"];

  const approved = (response) =>
    response?.ok === true &&
    response.enabled === true &&
    SUPPORTED_FRAMES.includes(response.frameSupport);

  /** Enabled origin, but a frame the policy cannot serve (A035). */
  const approvedUnsupportedFrame = (response) =>
    response?.ok === true &&
    response.enabled === true &&
    response.frameSupport === "unsupported";

  // =========================================================================
  // A4 — overlay session engine. Nothing below runs before approval.
  // =========================================================================

  // SR-3: the focus session can never outlive the token TTL ceiling.
  const SESSION_TTL_MS = security.LIMITS.TOKEN_TTL_MS;
  const WATCHDOG_MS = 1000;

  // A030 — one honest sentence per state. Error TEXT is a fixed local map
  // keyed by the stable code; the worker's `error.message` is deliberately
  // never rendered, so no upstream component can inject copy into the page.
  const STATE_TEXT = Object.freeze({
    loading: "Loading KeyVault suggestions…",
    "no-fillable": "Matches exist but cannot be filled here. Open KeyVault.",
    "no-matches": "No KeyVault entries for this site.",
    locked: "Open and unlock KeyVault.",
    no_host: "KeyVault native host is unavailable.",
    timeout: "KeyVault did not respond in time.",
    unsupported_frame:
      "The overlay is not available in this frame. Copy your login from the KeyVault app.",
    // Neutral on purpose: the missing capability can be an old native host OR
    // an old app (B007 advertises generation only when the app declares it).
    unsupported_capability: "Update KeyVault to use this feature.",
    stale_session: "KeyVault session changed.",
  });

  // B010/B013 — honest copy for both Generate states. The row is ACTIVE only
  // when the worker's matchesResult affirmatively advertises the
  // `generatePendingEntryV1` capability AND carries a one-shot generate
  // token; an old host/app peer keeps the disabled text, which directs the
  // user to the app and never promises in-page generation. The active copy
  // says who owns the save: KeyVault, after the user confirms there — the
  // extension neither saves nor remembers the generated password.
  const GENERATE_TEXT = "Open KeyVault to generate a password.";
  const GENERATE_ACTIVE_TEXT =
    "Generate a password — confirm the save in KeyVault.";

  // Codes that render an A030 state. Anything else — disabled, forbidden,
  // invalid_request, internal_error, an unknown code — is an authorization or
  // contract failure and tears the session down instead of rendering.
  const RENDERABLE_ERRORS = new Set([
    "locked",
    "no_host",
    "timeout",
    "unsupported_frame",
    "unsupported_capability",
    "stale_session",
  ]);

  /** The single live focus session for this frame, or null. */
  let session = null;
  /** Owns the document/window listeners attached at approval. */
  let instanceAbort = null;
  /**
   * A035 — what the worker said this frame is: "supported" frames run the
   * full query/fill session; "unsupported" frames (enabled origin, refused
   * classification) run display-only sessions that render the unsupported
   * state and never send `requestMatches`/`fill`.
   */
  let instanceMode = "supported";

  // -------------------------------------------------------------------------
  // A028 — eligible field detection.
  // -------------------------------------------------------------------------

  const isVisible = (el) =>
    typeof el.getClientRects === "function" && el.getClientRects().length > 0;

  const isWritablePasswordInput = (el) =>
    el != null &&
    el.tagName === "INPUT" &&
    el.type === "password" &&
    el.disabled !== true &&
    el.readOnly !== true &&
    isVisible(el);

  const hasUsernameAutocomplete = (el) => {
    const tokens = String(el.getAttribute("autocomplete") ?? "")
      .toLowerCase()
      .split(/\s+/);
    return tokens.includes("username") || tokens.includes("email");
  };

  const isUsernameInput = (el) =>
    el != null &&
    el.tagName === "INPUT" &&
    (el.type === "text" || el.type === "email") &&
    el.disabled !== true &&
    el.readOnly !== true &&
    isVisible(el) &&
    hasUsernameAutocomplete(el);

  const formInputs = (el) => {
    const form = el.form;
    if (!form || !form.elements) return [];
    return Array.from(form.elements);
  };

  /**
   * @returns {{fieldKind: "password"|"username", passwordEl, usernameEl}|null}
   *
   * A password field is eligible on its own. A username/email-autocomplete
   * field is eligible ONLY when its form also contains an eligible password
   * field (A028) — a lone email field is not a credential form.
   */
  const classifyField = (el) => {
    if (el == null || typeof el.tagName !== "string") return null;
    if (isWritablePasswordInput(el)) {
      const usernameEl = formInputs(el).find(isUsernameInput) ?? null;
      return { fieldKind: "password", passwordEl: el, usernameEl };
    }
    if (isUsernameInput(el)) {
      const passwordEl = formInputs(el).find(isWritablePasswordInput) ?? null;
      if (passwordEl === null) return null;
      return { fieldKind: "username", passwordEl, usernameEl: el };
    }
    return null;
  };

  /**
   * A035/SR-7 — "where the top frame can detect iframe focus, show an
   * unsupported state directing manual copy from the app". Focus entering an
   * iframe fires `focusin` at the iframe ELEMENT in this document. A frame
   * whose `src` canonicalizes to THIS document's own origin is skipped: a
   * same-origin child carries its own injected instance and renders its own
   * overlay. Everything else — cross-origin, sandboxed, `data:`, srcdoc,
   * unparseable — gets the honest hint only. KNOWN LIMIT (documented, not
   * hidden): this document cannot know whether a cross-origin child's own
   * origin is separately enabled, so a separately-enabled child renders its
   * real overlay inside the frame while this hint also shows; cosmetic only,
   * no authorization is derived from it.
   */
  const isFrameHintTarget = (el) => {
    if (el == null || el.tagName !== "IFRAME") return false;
    const raw = el.getAttribute("src");
    // No src (or blank) is an about:blank frame: no registered script ever
    // runs there, so the honest answer is the hint.
    if (typeof raw !== "string" || raw.trim().length === 0) return true;
    // Resolve like the browser does: a RELATIVE src ("/login", "widget.html",
    // "//host/x") resolves against this document's URL. Canonicalizing the
    // raw attribute instead would read every relative same-origin src as
    // "not my origin" and paint the hint over a frame that already carries
    // its own real overlay.
    let resolved = raw;
    try {
      resolved = new URL(raw, location.href).href;
    } catch (_) {
      // Unresolvable exotic value: keep the raw attribute; the
      // canonicalization below fails it closed into the hint.
    }
    return security.canonicalOriginOrNull(resolved) !== origin;
  };

  // -------------------------------------------------------------------------
  // A033 — teardown. One function, called from every trigger.
  // -------------------------------------------------------------------------

  /**
   * Removes the overlay host, aborts every session listener, stops the
   * watchdog timer, restores the anchor's pre-existing ARIA, and nulls every
   * local reference. Best-effort by design (SR-5): JS strings are immutable,
   * so "clear" means removing reachability, never claiming memory erasure.
   *
   * This session uses no MutationObserver and no requestAnimationFrame; the
   * abortables are exactly: the AbortController-owned listeners and the one
   * watchdog interval. Anchor disconnect and timeout are detected by the
   * watchdog rather than an observer — one timer covers both.
   */
  const teardownSession = () => {
    if (session === null) return;
    const s = session;
    session = null;
    try {
      s.teardownController.abort();
    } catch (_) {
      // An abort listener throwing must not stop the teardown.
    }
    clearInterval(s.watchdogId);
    if (s.blurTimerId !== 0) clearTimeout(s.blurTimerId);
    s.blurTimerId = 0;
    const anchor = s.anchorEl;
    if (anchor != null) {
      // A036 — restore EVERY ARIA attribute this session touched to exactly
      // its pre-session value (absent stays absent).
      for (const [name, original] of s.savedAria) {
        if (original === null) anchor.removeAttribute(name);
        else anchor.setAttribute(name, original);
      }
    }
    if (s.overlayHost != null) s.overlayHost.remove();
    s.anchorEl = null;
    s.usernameEl = null;
    s.passwordEl = null;
    s.overlayHost = null;
    s.shadowRoot = null;
    s.statusEl = null;
    s.listEl = null;
    s.retryEl = null;
    s.generateEl = null;
    s.items = null;
    s.fillToken = null;
    s.generateToken = null;
    s.sessionBinding = null;
    s.savedAria = null;
  };

  /** Record-once, then set: the FIRST value seen is the one restored. */
  const setAnchorAria = (name, value) => {
    const anchor = session.anchorEl;
    if (!session.savedAria.has(name)) {
      session.savedAria.set(name, anchor.getAttribute(name));
    }
    anchor.setAttribute(name, value);
  };

  // -------------------------------------------------------------------------
  // A029/A030 — closed-shadow metadata overlay and its states.
  // -------------------------------------------------------------------------

  const clearChildren = (el) => {
    while (el.firstChild) el.firstChild.remove();
  };

  // A039 — the visual contract, static and local. Light is the base; dark,
  // forced-colors (system colors only, no authored contrast), and reduced
  // motion (no transition) are media-query overrides, so the browser — never
  // this script — decides which applies. Sized to the geometry fallback below.
  const OVERLAY_CSS = [
    ".kv-overlay{box-sizing:border-box;width:320px;max-height:240px;overflow-y:auto;",
    "font:13px/1.4 system-ui,sans-serif;background:#ffffff;color:#1a1a1a;",
    "border:1px solid #c8c8c8;border-radius:6px;box-shadow:0 4px 16px rgba(0,0,0,0.25);",
    "transition:opacity 120ms ease;}",
    ".kv-overlay button{display:block;width:100%;text-align:left;background:inherit;",
    "color:inherit;border:0;font:inherit;padding:6px 10px;}",
    '.kv-overlay [role="option"][aria-selected="true"]{background:#dce6f7;}',
    "@media (prefers-color-scheme: dark){.kv-overlay{background:#202124;color:#e8eaed;",
    "border-color:#5f6368;}",
    '.kv-overlay [role="option"][aria-selected="true"]{background:#3c4043;}}',
    "@media (forced-colors: active){.kv-overlay{background:Canvas;color:CanvasText;",
    "border-color:CanvasText;box-shadow:none;}",
    '.kv-overlay [role="option"][aria-selected="true"]{background:Highlight;color:HighlightText;}}',
    "@media (prefers-reduced-motion: reduce){.kv-overlay{transition:none;}}",
  ].join("");

  // A039 — geometry. `getBoundingClientRect` is viewport-relative, so the
  // host is positioned `fixed` and re-anchored on scroll/resize. When the
  // host cannot be measured yet, the CSS sizes above are the estimate.
  const OVERLAY_FALLBACK_SIZE = Object.freeze({ width: 320, height: 240 });

  const overlaySize = () => {
    const host = session.overlayHost;
    const rect =
      typeof host.getBoundingClientRect === "function"
        ? host.getBoundingClientRect()
        : null;
    return {
      width: rect && rect.width > 0 ? rect.width : OVERLAY_FALLBACK_SIZE.width,
      height: rect && rect.height > 0 ? rect.height : OVERLAY_FALLBACK_SIZE.height,
    };
  };

  /**
   * Anchor below; flip above when the space below is short AND the space
   * above fits; clamp the final box to the viewport either way. Zoom needs no
   * special case: Chrome scales CSS pixels, and both the rects and
   * `innerWidth`/`innerHeight` are already in CSS pixels.
   */
  const updatePosition = () => {
    if (session === null || session.overlayHost === null) return;
    const anchor = session.anchorEl;
    if (anchor == null || typeof anchor.getBoundingClientRect !== "function") return;
    const rect = anchor.getBoundingClientRect();
    if (!rect) return;
    const { width, height } = overlaySize();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    let top = rect.bottom;
    if (rect.bottom + height > viewportHeight && rect.top - height >= 0) {
      top = rect.top - height; // flip above
    }
    top = Math.min(Math.max(top, 0), Math.max(viewportHeight - height, 0));
    const left = Math.min(Math.max(rect.left, 0), Math.max(viewportWidth - width, 0));

    const host = session.overlayHost;
    host.style.position = "fixed";
    host.style.top = `${top}px`;
    host.style.left = `${left}px`;
  };

  /**
   * A038 — a pointer press inside the overlay: keep the anchor focused
   * (prevent the mousedown default) and mark the action pending so a
   * deferred outside blur cannot remove the row before the click lands.
   */
  const markPendingAction = (event) => {
    event.preventDefault();
    if (session === null) return;
    session.pendingAction = true;
    if (session.blurTimerId !== 0) {
      clearTimeout(session.blurTimerId);
      session.blurTimerId = 0;
    }
  };

  const settlePendingAction = () => {
    if (session === null) return;
    session.pendingAction = false;
    if (session.blurTimerId !== 0) {
      clearTimeout(session.blurTimerId);
      session.blurTimerId = 0;
    }
  };

  const buildOverlay = () => {
    const signal = session.teardownController.signal;
    const host = document.createElement("div");
    // SR-6/A034: closed mode. `host.shadowRoot` reads null from page code;
    // that is a collision/style boundary, not invisibility — see file header.
    const shadow = host.attachShadow({ mode: "closed" });

    const styleEl = document.createElement("style");
    styleEl.textContent = OVERLAY_CSS;

    const sectionEl = document.createElement("section");
    sectionEl.setAttribute("class", "kv-overlay");
    sectionEl.setAttribute("aria-label", "KeyVault suggestions");
    // A038 — pending-action protocol; see markPendingAction. The controls are
    // all `type=button` inside this shadow section, OUTSIDE every page form,
    // so no pointer or keyboard action can ever become a submit.
    sectionEl.addEventListener("mousedown", markPendingAction, { signal });
    sectionEl.addEventListener(
      "click",
      () => {
        settlePendingAction();
      },
      { signal }
    );

    const statusEl = document.createElement("div");
    statusEl.id = "kv-status";
    statusEl.setAttribute("role", "status");
    statusEl.setAttribute("aria-live", "polite");

    const listEl = document.createElement("div");
    listEl.id = "kv-list";
    listEl.setAttribute("role", "listbox");

    const generateEl = document.createElement("button");
    generateEl.id = "kv-generate";
    generateEl.setAttribute("type", "button");
    generateEl.disabled = true;
    generateEl.setAttribute("disabled", "");
    generateEl.setAttribute("aria-disabled", "true");
    generateEl.textContent = GENERATE_TEXT;
    // Inert until a matchesResult advertises the capability with a token;
    // attemptGenerate refuses while `session.generateToken` is null, so a
    // click delivered to the disabled control cannot do anything either.
    generateEl.addEventListener(
      "click",
      () => {
        attemptGenerate();
      },
      { signal }
    );

    sectionEl.appendChild(statusEl);
    sectionEl.appendChild(listEl);
    sectionEl.appendChild(generateEl);
    shadow.appendChild(styleEl);
    shadow.appendChild(sectionEl);

    (document.body ?? document.documentElement).appendChild(host);

    session.overlayHost = host;
    session.shadowRoot = shadow;
    session.statusEl = statusEl;
    session.listEl = listEl;
    session.generateEl = generateEl;

    updatePosition();
    // Re-anchor while the session lives. Scroll is capture-phase so inner
    // scrollable containers reposition too, not only the root scroller.
    document.addEventListener("scroll", updatePosition, { capture: true, signal });
    window.addEventListener("resize", updatePosition, { signal });
    // A drag that starts inside the overlay but ends elsewhere must not leave
    // the pending flag armed forever; mouseup is composed and reaches here.
    document.addEventListener(
      "mouseup",
      () => {
        if (session !== null) session.pendingAction = false;
      },
      { signal }
    );
  };

  /** Status text + optional retry control. Rows are rendered separately. */
  const renderState = (code) => {
    if (session === null) return;
    session.statusEl.textContent = STATE_TEXT[code] ?? STATE_TEXT.stale_session;
    if (code !== "matches") clearChildren(session.listEl);

    const wantRetry = code === "stale_session";
    if (wantRetry && session.retryEl === null) {
      const retryEl = document.createElement("button");
      retryEl.id = "kv-retry";
      retryEl.setAttribute("type", "button");
      retryEl.textContent = "Try again";
      retryEl.addEventListener(
        "click",
        () => {
          if (session === null) return;
          renderState("loading");
          requestMatches();
        },
        { signal: session.teardownController.signal }
      );
      session.statusEl.parentNode.appendChild(retryEl);
      session.retryEl = retryEl;
    } else if (!wantRetry && session.retryEl !== null) {
      session.retryEl.remove();
      session.retryEl = null;
    }
  };

  /**
   * A036 — selection state. `aria-selected` and `aria-activedescendant`
   * always agree on `kv-option-<selectedIndex>`, an id that exists in the
   * list by construction. Closed-shadow IDREF support varies across AT
   * stacks, so the polite live region additionally announces the selected
   * label and position ("Example, 1 of 2") — the mandatory fallback.
   */
  const updateSelection = ({ announce } = { announce: true }) => {
    if (session === null || session.listEl === null) return;
    const rows = session.listEl.childNodes;
    const itemCount = session.items === null ? 0 : session.items.length;
    const index = session.selectedIndex;
    // B010 — the active Generate row is the virtual last option, reachable
    // only by explicit arrow navigation (never auto-selected), so Enter can
    // never generate without the user having moved onto the row first.
    const onGenerate = session.generateToken !== null && index === itemCount;
    for (let at = 0; at < rows.length; at += 1) {
      rows[at].setAttribute(
        "aria-selected",
        !onGenerate && at === index ? "true" : "false"
      );
    }
    if (session.generateEl !== null && session.generateToken !== null) {
      session.generateEl.setAttribute("aria-selected", onGenerate ? "true" : "false");
    }
    if (onGenerate) {
      session.listEl.removeAttribute("aria-activedescendant");
      if (announce) {
        session.statusEl.textContent = `${GENERATE_ACTIVE_TEXT}, ${index + 1} of ${itemCount + 1}`;
      }
      return;
    }
    if (itemCount === 0 || rows.length === 0 || index < 0) {
      session.listEl.removeAttribute("aria-activedescendant");
      return;
    }
    session.listEl.setAttribute("aria-activedescendant", `kv-option-${index}`);
    if (announce) {
      const entry = session.items[index];
      session.statusEl.textContent = `${entry.title}, ${index + 1} of ${itemCount}`;
    }
  };

  /**
   * A029 — rows expose title + displayService ONLY. The row carries no
   * dataset entry, no attribute, and no text derived from anything else in
   * the match item; the entry id lives in the click closure, not the DOM.
   */
  const renderItems = () => {
    const listEl = session.listEl;
    clearChildren(listEl);
    session.items.forEach((entry, index) => {
      const row = document.createElement("button");
      row.id = `kv-option-${index}`;
      row.setAttribute("type", "button");
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", "false");
      const titleEl = document.createElement("span");
      titleEl.textContent = entry.title;
      const serviceEl = document.createElement("span");
      serviceEl.textContent = entry.displayService;
      row.appendChild(titleEl);
      row.appendChild(serviceEl);
      if (entry.fillEligible === true) {
        row.addEventListener(
          "click",
          () => {
            attemptFill(entry.entryId);
          },
          { signal: session.teardownController.signal }
        );
      } else {
        row.disabled = true;
        row.setAttribute("disabled", "");
        row.setAttribute("aria-disabled", "true");
      }
      listEl.appendChild(row);
    });
    session.selectedIndex = 0;
    updateSelection({ announce: false });
    updatePosition();
  };

  // -------------------------------------------------------------------------
  // Metadata query.
  // -------------------------------------------------------------------------

  const requestMatches = () => {
    const nonce = session.focusNonce;
    chrome.runtime.sendMessage(
      {
        channel: security.CHANNEL,
        version: security.MESSAGE_VERSION,
        type: "requestMatches",
        origin: session.origin,
        focusNonce: nonce,
        fieldKind: session.fieldKind,
      },
      (response) => {
        if (chrome.runtime.lastError) {
          // Dead worker: nothing can be authorized, so nothing may render.
          teardownSession();
          return;
        }
        // SR-3: a response whose nonce is no longer current is ignored — it
        // can neither render nor fill, even if it arrives well-formed.
        if (session === null || session.focusNonce !== nonce) return;
        handleMatches(response);
      }
    );
  };

  /** B010 — flip the Generate row between its two honest states. */
  const setGenerateState = (active) => {
    const el = session?.generateEl;
    if (el == null) return;
    if (active) {
      el.disabled = false;
      el.removeAttribute("disabled");
      el.setAttribute("aria-disabled", "false");
      el.textContent = GENERATE_ACTIVE_TEXT;
    } else {
      el.disabled = true;
      el.setAttribute("disabled", "");
      el.setAttribute("aria-disabled", "true");
      el.textContent = GENERATE_TEXT;
    }
  };

  const handleMatches = (response) => {
    if (response?.ok !== true) {
      const code = response?.error?.code;
      if (RENDERABLE_ERRORS.has(code)) renderState(code);
      else teardownSession();
      return;
    }
    // The worker already validated the outbound message, but this world only
    // trusts what it re-checks: exact shape, metadata-only items, no
    // forbidden key anywhere (A029/SR-5), and this session's own origin.
    if (
      !security.validateMatchesResult(response).ok ||
      response.origin !== session.origin
    ) {
      teardownSession();
      return;
    }

    session.items = response.items.map((entry) => ({
      entryId: entry.entryId,
      title: entry.title,
      displayService: entry.displayService,
      matchType: entry.matchType,
      fillEligible: entry.fillEligible === true,
    }));
    session.sessionBinding = {
      databaseId: response.sessionBinding.databaseId,
      cacheGeneration: response.sessionBinding.cacheGeneration,
      bridgeGeneration: response.sessionBinding.bridgeGeneration,
    };
    session.fillToken =
      typeof response.fillToken === "string" ? response.fillToken : null;
    // B010 — the row is active ONLY on an affirmative capability plus its
    // one-shot token. Absent, false, or token-less: disabled with the copy
    // that directs the user to the app.
    session.generateToken =
      response.generateAvailable === true &&
      typeof response.generateToken === "string"
        ? response.generateToken
        : null;
    setGenerateState(session.generateToken !== null);
    if (
      Number.isInteger(response.expiresAtEpochMs) &&
      response.expiresAtEpochMs < session.expiresAtEpochMs
    ) {
      session.expiresAtEpochMs = response.expiresAtEpochMs;
    }

    if (session.items.length === 0) {
      // Nothing auto-selected: Enter stays with the page until the user
      // explicitly arrows onto the Generate row (when it is active).
      session.selectedIndex = -1;
      renderState("no-matches");
      updateSelection({ announce: false });
      return;
    }
    if (session.fillToken === null) {
      renderState("no-fillable");
      renderItems();
      return;
    }
    renderState("matches");
    session.statusEl.textContent = `${session.items.length} KeyVault suggestions`;
    renderItems();
  };

  // -------------------------------------------------------------------------
  // A031 — explicit fill.
  // -------------------------------------------------------------------------

  /**
   * A039 — set through the PROTOTYPE `value` setter when one exists. A
   * framework-controlled input shadows `value` with an instance accessor to
   * observe writes; going through the native prototype setter updates the
   * real value storage and lets the framework learn about the change from the
   * bubbling `input` event — the same technique every autofill uses. Plain
   * inputs take the same path (the prototype setter IS the normal setter).
   */
  const setNativeValue = (el, value) => {
    let proto = Object.getPrototypeOf(el);
    let descriptor;
    while (proto != null) {
      descriptor = Object.getOwnPropertyDescriptor(proto, "value");
      if (descriptor !== undefined) break;
      proto = Object.getPrototypeOf(proto);
    }
    if (descriptor && typeof descriptor.set === "function") {
      descriptor.set.call(el, value);
    } else {
      el.value = value;
    }
  };

  const dispatchFieldValue = (el, value) => {
    setNativeValue(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  };

  const attemptFill = (entryId) => {
    if (session === null || session.filling === true) return;
    if (typeof session.fillToken !== "string") return;
    const item = session.items.find(
      (entry) => entry.entryId === entryId && entry.fillEligible === true
    );
    if (!item) return;

    session.filling = true;
    const nonce = session.focusNonce;
    const request = {
      channel: security.CHANNEL,
      version: security.MESSAGE_VERSION,
      type: "fill",
      origin: session.origin,
      focusNonce: nonce,
      fillToken: session.fillToken,
      entryId,
      sessionBinding: { ...session.sessionBinding },
    };
    // One-shot on this side too: the token cannot be reused from a second
    // click even before the worker answers.
    session.fillToken = null;

    chrome.runtime.sendMessage(request, (response) => {
      if (chrome.runtime.lastError) {
        teardownSession();
        return;
      }
      if (session === null || session.focusNonce !== nonce) return;
      handleFill(response, entryId);
    });
  };

  const handleFill = (response, entryId) => {
    if (response?.ok !== true) {
      session.filling = false;
      const code = response?.error?.code;
      if (RENDERABLE_ERRORS.has(code)) renderState(code);
      else teardownSession();
      return;
    }
    // A031 — verify the response against the CURRENT session before any
    // secret is used: type, origin, entry, nonce-checked already, binding.
    if (
      response.type !== "fillResult" ||
      response.origin !== session.origin ||
      response.entryId !== entryId ||
      !security.sessionBindingsEqual(response.sessionBinding, session.sessionBinding)
    ) {
      teardownSession();
      return;
    }
    // The anchor must still be the live, focused element it was when the user
    // clicked. Anything else fills an input the user is not looking at.
    const anchor = session.anchorEl;
    if (anchor == null || anchor.isConnected !== true || document.activeElement !== anchor) {
      teardownSession();
      return;
    }
    // A039 — the page can have made the field read-only, disabled, or hidden
    // between the query and the reveal. Never write into a field that would
    // no longer be eligible; fail closed instead.
    if (!isWritablePasswordInput(session.passwordEl)) {
      teardownSession();
      return;
    }
    const data = response.data;
    if (
      !security.isPlainObject(data) ||
      typeof data.username !== "string" ||
      typeof data.password !== "string"
    ) {
      teardownSession();
      return;
    }

    // SR-5 — the secret lives in these two locals and the input values only.
    let username = data.username;
    let password = data.password;
    try {
      // Best-effort blank of the mutable response fields. The response object
      // is this world's structured clone, so this cannot fail for shared
      // ownership reasons; a frozen object simply keeps its copy (best-effort
      // is the contract, not erasure).
      data.username = "";
      data.password = "";
      response.data = null;
    } catch (_) {
      // Frozen/exotic clone: the references still die with this scope.
    }

    if (
      session.usernameEl != null &&
      username.length > 0 &&
      isUsernameInput(session.usernameEl)
    ) {
      dispatchFieldValue(session.usernameEl, username);
    }
    dispatchFieldValue(session.passwordEl, password);
    // A031: never submit — no submit() call, no submit event, ever.

    username = null;
    password = null;
    teardownSession();
  };

  // -------------------------------------------------------------------------
  // B010/B011 — explicit generate.
  // -------------------------------------------------------------------------

  /**
   * Runs only from an explicit click on the active Generate row or an Enter
   * while it is the arrow-selected option. One-shot on this side: the token
   * dies before the worker answers, so a second activation sends nothing.
   */
  const attemptGenerate = () => {
    if (session === null || session.filling === true || session.generating === true) {
      return;
    }
    if (typeof session.generateToken !== "string") return;
    if (session.sessionBinding === null) return;

    session.generating = true;
    const nonce = session.focusNonce;
    const request = {
      channel: security.CHANNEL,
      version: security.MESSAGE_VERSION,
      type: "generate",
      origin: session.origin,
      focusNonce: nonce,
      generateToken: session.generateToken,
      sessionBinding: { ...session.sessionBinding },
    };
    session.generateToken = null;
    // Busy: not activatable while the request is in flight. The copy is not
    // reset to the disabled sentence — this is "working", not "old peer".
    const el = session.generateEl;
    if (el != null) {
      el.disabled = true;
      el.setAttribute("disabled", "");
      el.setAttribute("aria-disabled", "true");
    }

    chrome.runtime.sendMessage(request, (response) => {
      if (chrome.runtime.lastError) {
        teardownSession();
        return;
      }
      // SR-3: a response whose nonce is no longer current can neither render
      // nor fill — a late/stale generate answer for a previous session dies
      // here, even if it arrives well-formed.
      if (session === null || session.focusNonce !== nonce) return;
      handleGenerate(response);
    });
  };

  const handleGenerate = (response) => {
    session.generating = false;
    if (response?.ok !== true) {
      const code = response?.error?.code;
      if (RENDERABLE_ERRORS.has(code)) renderState(code);
      else teardownSession();
      return;
    }
    // B011 — verify against the CURRENT session before the secret is used:
    // type, origin, nonce-checked already, binding.
    if (
      response.type !== "generateResult" ||
      response.origin !== session.origin ||
      !security.sessionBindingsEqual(response.sessionBinding, session.sessionBinding)
    ) {
      teardownSession();
      return;
    }
    // The anchor must still be the live, focused element the user acted on.
    const anchor = session.anchorEl;
    if (anchor == null || anchor.isConnected !== true || document.activeElement !== anchor) {
      teardownSession();
      return;
    }
    if (!isWritablePasswordInput(session.passwordEl)) {
      teardownSession();
      return;
    }
    const data = response.data;
    if (
      !security.isPlainObject(data) ||
      typeof data.password !== "string" ||
      data.password.length === 0
    ) {
      teardownSession();
      return;
    }

    // SR-5 — the generated secret lives in this local and the password input
    // value only. Never the DOM (attributes/dataset/title), storage, logs, or
    // any durable binding; the response carries no pending id to keep.
    let generated = data.password;
    try {
      data.password = "";
      response.data = null;
    } catch (_) {
      // Frozen/exotic clone: the references still die with this scope.
    }

    dispatchFieldValue(session.passwordEl, generated);
    // B011: never submit — the app owns the save; the user confirms it there.

    generated = null;
    teardownSession();
  };

  // -------------------------------------------------------------------------
  // A028 — focus session lifecycle.
  // -------------------------------------------------------------------------

  /**
   * A037 — the keyboard contract, attached to the ANCHOR for the session's
   * lifetime only (the session AbortController owns it). A closed overlay
   * therefore has NO keydown listener at all: it structurally cannot capture,
   * prevent, or observe page keys. Only the Enter that actually fills
   * prevents its default and stops propagation; every other key — arrows,
   * Escape, Tab, everything unhandled — passes through untouched.
   */
  const onSessionKeyDown = (event) => {
    if (session === null) return;
    if (event.key === "Escape") {
      // Dismisses the current focus session. Not prevented: only the fill
      // action may swallow a key.
      teardownSession();
      return;
    }
    if (event.key === "Tab") {
      // Teardown AND pass-through: the browser keeps the focus move.
      teardownSession();
      return;
    }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      const itemCount = session.items === null ? 0 : session.items.length;
      // B010 — the active Generate row is one extra, LAST option.
      const maxIndex =
        session.generateToken !== null ? itemCount : itemCount - 1;
      if (maxIndex < 0) return;
      const delta = event.key === "ArrowDown" ? 1 : -1;
      const next = Math.min(Math.max(session.selectedIndex + delta, 0), maxIndex);
      if (next !== session.selectedIndex) {
        session.selectedIndex = next;
        updateSelection();
      }
      return;
    }
    if (event.key === "Enter") {
      const itemCount = session.items === null ? 0 : session.items.length;
      if (
        session.generateToken !== null &&
        session.selectedIndex === itemCount
      ) {
        // B011 — explicit Enter on the arrow-selected Generate row.
        event.preventDefault();
        event.stopPropagation();
        attemptGenerate();
        return;
      }
      const entry = session.items?.[session.selectedIndex];
      if (
        entry == null ||
        entry.fillEligible !== true ||
        typeof session.fillToken !== "string"
      ) {
        // Not a fill action: the page keeps its Enter (and its submit, if it
        // has one — the overlay never swallows a key it did not use).
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      attemptFill(entry.entryId);
    }
  };

  /**
   * @param {"fill"|"hint"} kind  `fill` is the normal query/fill session.
   *        `hint` renders the unsupported-frame state only (A035): sessions
   *        started for an unsupported frame classification, or anchored to a
   *        detectable non-same-origin iframe in a supported document. A hint
   *        session sends NO `requestMatches`, mints no fill path, and sets no
   *        combobox ARIA on its anchor (an iframe is not a combobox).
   */
  const startSession = (anchorEl, fieldInfo, kind = "fill") => {
    session = {
      origin,
      kind,
      // SR-3: cryptographically random, one per eligible focus.
      focusNonce: security.randomToken(),
      fieldKind: fieldInfo === null ? null : fieldInfo.fieldKind,
      anchorEl,
      usernameEl: fieldInfo === null ? null : fieldInfo.usernameEl,
      passwordEl: fieldInfo === null ? null : fieldInfo.passwordEl,
      overlayHost: null,
      shadowRoot: null,
      statusEl: null,
      listEl: null,
      retryEl: null,
      generateEl: null,
      items: [],
      selectedIndex: 0,
      fillToken: null,
      generateToken: null,
      sessionBinding: null,
      filling: false,
      generating: false,
      pendingAction: false,
      blurTimerId: 0,
      savedAria: new Map(),
      expiresAtEpochMs: Date.now() + SESSION_TTL_MS,
      watchdogId: 0,
      teardownController: new AbortController(),
    };
    if (kind === "fill") {
      // A036 — the anchor exposes the combobox expanded state while open;
      // originals are recorded by setAnchorAria and restored on teardown.
      setAnchorAria("aria-expanded", "true");
      setAnchorAria("aria-haspopup", "listbox");
    }
    // A033: anchor disconnect and timeout share one watchdog timer.
    session.watchdogId = setInterval(() => {
      if (session === null) return;
      if (
        session.anchorEl.isConnected !== true ||
        Date.now() >= session.expiresAtEpochMs
      ) {
        teardownSession();
      }
    }, WATCHDOG_MS);
    anchorEl.addEventListener("keydown", onSessionKeyDown, {
      signal: session.teardownController.signal,
    });
    buildOverlay();
    if (kind === "hint" || instanceMode === "unsupported") {
      // A035 — fail closed with an honest state: no query, no fill, manual
      // copy from the app. No clipboard path exists in the extension.
      renderState("unsupported_frame");
      return;
    }
    renderState("loading");
    requestMatches();
  };

  const onFocusIn = (event) => {
    const target = event.target;
    if (session !== null && session.anchorEl === target) {
      // Focus returned to the anchor: a scheduled outside-blur teardown is
      // obsolete.
      if (session.blurTimerId !== 0) {
        clearTimeout(session.blurTimerId);
        session.blurTimerId = 0;
      }
      return;
    }
    // A028: a new focus always tears down the previous session first.
    teardownSession();
    const fieldInfo = classifyField(target);
    if (fieldInfo !== null) {
      startSession(target, fieldInfo, "fill");
      return;
    }
    if (instanceMode === "supported" && isFrameHintTarget(target)) {
      startSession(target, null, "hint");
    }
  };

  const onFocusOut = (event) => {
    // Outside blur. A press inside the overlay never gets here (mousedown
    // default is prevented), so this is a REAL departure — but a page can
    // also blur programmatically mid-pointer-sequence. A038: defer the
    // teardown past the current pointer task; a pending overlay action
    // cancels it, anything else lets it run.
    if (session === null || event.target !== session.anchorEl) return;
    if (session.pendingAction === true) return;
    if (session.blurTimerId !== 0) return;
    const s = session;
    s.blurTimerId = setTimeout(() => {
      if (session === s) {
        s.blurTimerId = 0;
        teardownSession();
      }
    }, 0);
  };

  const onVisibilityChange = () => {
    if (document.visibilityState === "hidden") teardownSession();
  };

  const onPageHide = () => {
    teardownSession();
  };

  const activate = () => {
    if (instanceAbort !== null) return;
    instanceAbort = new AbortController();
    const signal = instanceAbort.signal;
    document.addEventListener("focusin", onFocusIn, { signal });
    document.addEventListener("focusout", onFocusOut, { signal });
    document.addEventListener("visibilitychange", onVisibilityChange, { signal });
    window.addEventListener("pagehide", onPageHide, { signal });
  };

  const deactivate = () => {
    teardownSession();
    if (instanceAbort !== null) {
      instanceAbort.abort();
      instanceAbort = null;
    }
  };

  // =========================================================================
  // Bootstrap handshake (Slice A2, unchanged in substance).
  // =========================================================================

  chrome.runtime.sendMessage(bootstrap, (response) => {
    // Reading lastError is what suppresses the "unchecked runtime.lastError"
    // console noise when the worker is gone.
    if (chrome.runtime.lastError) {
      clearGuard();
      return;
    }
    if (approved(response)) {
      instanceMode = "supported";
    } else if (approvedUnsupportedFrame(response)) {
      // A035 — enabled origin, unsupported frame: activate in display-only
      // mode so the honest unsupported state can render on eligible focus.
      // Nothing in this mode ever sends `requestMatches` or `fill`.
      instanceMode = "unsupported";
    } else {
      clearGuard();
      return;
    }

    // Approved. Listeners are attached only here, never before.
    activate();

    const onMessage = (message) => {
      if (message?.channel !== security.CHANNEL || message.type !== "teardown") return;

      // A033: any teardown broadcast — disable, permission removal, stale
      // revision — drops the live session immediately, before revalidation.
      // Rendering must never outlive the revision that authorized it.
      teardownSession();

      // The broadcast deliberately does NOT name the disabled origin. It is
      // delivered to every injected document, so naming it would tell a
      // document on enabled origin A which origin B the user just turned off —
      // a free cross-origin disclosure. The message is only a "revalidate now"
      // nudge; this document re-derives authorization for its OWN exact origin
      // from the background, which is the single authority anyway. Anything
      // other than an explicit approval — including a dead worker — tears this
      // instance down.
      chrome.runtime.sendMessage(bootstrap, (revalidation) => {
        if (chrome.runtime.lastError) {
          deactivate();
          chrome.runtime.onMessage.removeListener(onMessage);
          clearGuard();
          return;
        }
        if (approved(revalidation)) {
          instanceMode = "supported";
        } else if (approvedUnsupportedFrame(revalidation)) {
          instanceMode = "unsupported";
        } else {
          deactivate();
          chrome.runtime.onMessage.removeListener(onMessage);
          clearGuard();
        }
      });
    };
    chrome.runtime.onMessage.addListener(onMessage);
  });
})();
