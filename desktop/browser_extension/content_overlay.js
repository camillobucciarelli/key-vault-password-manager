// 009 Slice A4 — content-script bootstrap + metadata overlay + explicit fill.
//
// Slice A2 shipped the guarded bootstrap handshake below; Slice A4 (A028–A034)
// adds everything that runs AFTER approval: eligible-field detection, the
// closed-shadow metadata overlay, its states, and the explicit fill path.
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
  // canonicalized, for instance — and it must leave this instance inert.
  const SUPPORTED_FRAMES = ["top", "same-origin", "permitted-cross-origin"];

  const approved = (response) =>
    response?.ok === true &&
    response.enabled === true &&
    SUPPORTED_FRAMES.includes(response.frameSupport);

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
    unsupported_frame: "The overlay is not available in this frame.",
    unsupported_capability: "Update the KeyVault native host to use the overlay.",
    stale_session: "KeyVault session changed.",
  });

  // Slice A has no generation contract (spec: Slice B). The control exists,
  // is disabled, and says exactly what the user can actually do.
  const GENERATE_TEXT = "Open KeyVault to generate a password.";

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
    const anchor = s.anchorEl;
    if (anchor != null) {
      if (s.savedAriaExpanded === null) anchor.removeAttribute("aria-expanded");
      else anchor.setAttribute("aria-expanded", s.savedAriaExpanded);
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
    s.items = null;
    s.fillToken = null;
    s.sessionBinding = null;
  };

  // -------------------------------------------------------------------------
  // A029/A030 — closed-shadow metadata overlay and its states.
  // -------------------------------------------------------------------------

  const clearChildren = (el) => {
    while (el.firstChild) el.firstChild.remove();
  };

  const buildOverlay = () => {
    const signal = session.teardownController.signal;
    const host = document.createElement("div");
    // SR-6/A034: closed mode. `host.shadowRoot` reads null from page code;
    // that is a collision/style boundary, not invisibility — see file header.
    const shadow = host.attachShadow({ mode: "closed" });

    const sectionEl = document.createElement("section");
    sectionEl.setAttribute("class", "kv-overlay");
    sectionEl.setAttribute("aria-label", "KeyVault suggestions");
    // Pointer-down inside the overlay must not steal the anchor's focus:
    // preventing the mousedown default keeps focus on the input, so no blur
    // teardown races the click. (A038 refines this; this is the minimum that
    // makes an explicit click possible at all.)
    sectionEl.addEventListener(
      "mousedown",
      (event) => {
        event.preventDefault();
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

    sectionEl.appendChild(statusEl);
    sectionEl.appendChild(listEl);
    sectionEl.appendChild(generateEl);
    shadow.appendChild(sectionEl);

    // ponytail: minimal absolute placement below the anchor. A039 (Slice A5)
    // owns real geometry — flip above, viewport clamp, scroll/resize tracking.
    host.style.position = "absolute";
    if (typeof session.anchorEl.getBoundingClientRect === "function") {
      const rect = session.anchorEl.getBoundingClientRect();
      if (rect) {
        host.style.left = `${rect.left}px`;
        host.style.top = `${rect.bottom}px`;
      }
    }
    (document.body ?? document.documentElement).appendChild(host);

    session.overlayHost = host;
    session.shadowRoot = shadow;
    session.statusEl = statusEl;
    session.listEl = listEl;
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
      row.setAttribute("aria-selected", index === 0 ? "true" : "false");
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
    session.sessionBinding =
      typeof response.fillToken === "string"
        ? {
            databaseId: response.sessionBinding.databaseId,
            cacheGeneration: response.sessionBinding.cacheGeneration,
            bridgeGeneration: response.sessionBinding.bridgeGeneration,
          }
        : null;
    session.fillToken =
      typeof response.fillToken === "string" ? response.fillToken : null;
    if (
      Number.isInteger(response.expiresAtEpochMs) &&
      response.expiresAtEpochMs < session.expiresAtEpochMs
    ) {
      session.expiresAtEpochMs = response.expiresAtEpochMs;
    }

    if (session.items.length === 0) {
      renderState("no-matches");
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

  const dispatchFieldValue = (el, value) => {
    el.value = value;
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

    if (session.usernameEl != null && username.length > 0) {
      dispatchFieldValue(session.usernameEl, username);
    }
    dispatchFieldValue(session.passwordEl, password);
    // A031: never submit — no submit() call, no submit event, ever.

    username = null;
    password = null;
    teardownSession();
  };

  // -------------------------------------------------------------------------
  // A028 — focus session lifecycle.
  // -------------------------------------------------------------------------

  const startSession = (anchorEl, fieldInfo) => {
    session = {
      origin,
      // SR-3: cryptographically random, one per eligible focus.
      focusNonce: security.randomToken(),
      fieldKind: fieldInfo.fieldKind,
      anchorEl,
      usernameEl: fieldInfo.usernameEl,
      passwordEl: fieldInfo.passwordEl,
      overlayHost: null,
      shadowRoot: null,
      statusEl: null,
      listEl: null,
      retryEl: null,
      items: [],
      fillToken: null,
      sessionBinding: null,
      filling: false,
      savedAriaExpanded: anchorEl.getAttribute("aria-expanded"),
      expiresAtEpochMs: Date.now() + SESSION_TTL_MS,
      watchdogId: 0,
      teardownController: new AbortController(),
    };
    anchorEl.setAttribute("aria-expanded", "true");
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
    buildOverlay();
    renderState("loading");
    requestMatches();
  };

  const onFocusIn = (event) => {
    const target = event.target;
    if (session !== null && session.anchorEl === target) return;
    // A028: a new focus always tears down the previous session first.
    teardownSession();
    const fieldInfo = classifyField(target);
    if (fieldInfo === null) return;
    startSession(target, fieldInfo);
  };

  const onFocusOut = (event) => {
    // Outside blur. A click inside the overlay never gets here: the overlay's
    // mousedown preventDefault keeps focus on the anchor.
    if (session !== null && event.target === session.anchorEl) teardownSession();
  };

  const onKeyDown = (event) => {
    if (session !== null && event.key === "Escape") teardownSession();
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
    document.addEventListener("keydown", onKeyDown, { signal });
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
    if (chrome.runtime.lastError || !approved(response)) {
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
        if (chrome.runtime.lastError || !approved(revalidation)) {
          deactivate();
          chrome.runtime.onMessage.removeListener(onMessage);
          clearGuard();
        }
      });
    };
    chrome.runtime.onMessage.addListener(onMessage);
  });
})();
