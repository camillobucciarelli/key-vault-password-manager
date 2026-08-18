// 009 Slice A3 — background trust paths and focus grants (A022–A027).
//
// HOW THESE TESTS ARE WRITTEN
// ---------------------------
// Every assertion is about an EFFECT, never about the shape of an internal
// data structure. "The token is gone from the map" proves nothing: a token
// absent from one structure may still be honoured by another path. So the
// question asked here is always the only one that matters —
//
//     can this token still cause a password to reach the page?
//
// which is answered by actually redeeming it through the production dispatcher
// and looking at whether a secret came back. The fake native host below is the
// only stub, and it models the Slice A1 contract, not the policy: it decides
// nothing about authorization.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { FakeBrowser } = require("./fake_browser.js");
const routes = require("../overlay_routes.js");
const { OverlayLifecycle } = require("../overlay_lifecycle.js");
const {
  security,
  RUNTIME_ID,
  contentScriptSender,
  extensionPageSender,
  overlayMessage,
  bindingA,
  bindingB,
} = require("./helpers.js");

const ORIGIN = "https://example.com";
const PATTERN = "https://example.com/*";
const PAGE_URL = "https://example.com/login";
const OTHER_ORIGIN = "https://other.example";
const OTHER_PATTERN = "https://other.example/*";

const USERNAME = "alice";
const PASSWORD = "kv-test-only-not-a-real-password";

function item(overrides = {}) {
  return {
    entryId: "entry-1",
    title: "Example",
    displayService: "example.com",
    matchType: "exact-origin",
    fillEligible: true,
    ...overrides,
  };
}

/**
 * Models the Slice A1 native contract (`overlayQueryCredentials` /
 * `overlayRevealForFill`) and nothing else. It applies no authorization rule
 * of its own, so a test can never pass against a policy that lives only here.
 */
class FakeNative {
  constructor({ binding = bindingA(), items = [item()] } = {}) {
    this.binding = binding;
    this.items = items;
    this.calls = [];
    /** Force the next response for a given request type. */
    this.errors = new Map();
    /**
     * Override the binding echoed by a successful reveal. Guarded by an
     * explicit flag so `null`/`undefined` are testable overrides rather than
     * "no override".
     */
    this.echoBinding = undefined;
    this.echoBindingSet = false;
    this.echoOrigin = null;
  }

  echoes(binding) {
    this.echoBinding = binding;
    this.echoBindingSet = true;
  }

  failWith(type, code) {
    this.errors.set(type, { ok: false, error: { code } });
  }

  send = async (type, payload) => {
    this.calls.push({ type, payload });
    if (this.errors.has(type)) return this.errors.get(type);

    if (type === "overlayQueryCredentials") {
      return {
        ok: true,
        data: {
          metadataOnly: true,
          matchPolicy: routes.MATCH_POLICY,
          target: payload.url,
          fillAvailable: this.binding !== null,
          databaseId: this.binding?.databaseId ?? null,
          sessionBinding: this.binding,
          items: this.items.map((entry) => ({ ...entry })),
        },
      };
    }
    if (type === "overlayRevealForFill") {
      return {
        ok: true,
        data: {
          entryId: payload.entryId,
          matchPolicy: routes.MATCH_POLICY,
          origin: this.echoOrigin ?? payload.origin,
          sessionBinding: this.echoBindingSet
            ? this.echoBinding
            : { ...this.binding },
          username: USERNAME,
          password: PASSWORD,
        },
      };
    }
    return { ok: true, data: {} };
  };

  callsOf(type) {
    return this.calls.filter((call) => call.type === type);
  }
}

/**
 * A worker instance. `restart()` builds a NEW lifecycle and router against the
 * SAME browser, which is exactly what an MV3 cold start does: durable storage
 * survives, in-memory grants do not.
 */
class Harness {
  constructor({ enabled = [ORIGIN], granted, native, revision = 5 } = {}) {
    this.browser = new FakeBrowser({
      storage: {
        [security.OVERLAY_CONFIG_KEY]: {
          version: 1,
          revision,
          enabledOrigins: [...enabled].sort(),
        },
        [security.OVERLAY_REVISION_FLOOR_KEY]: revision,
      },
      granted:
        granted ??
        [...enabled]
          .map((origin) => security.permissionPatternForOrigin(origin))
          .filter((pattern) => pattern !== null),
      tabs: [{ id: 42 }],
    });
    this.native = native ?? new FakeNative();
    this.nowMs = 1_700_000_000_000;
    this.restart();
  }

  restart() {
    this.lifecycle = new OverlayLifecycle({ browser: this.browser });
    this.router = new routes.OverlayRouter({
      lifecycle: this.lifecycle,
      runtimeId: RUNTIME_ID,
      native: this.native.send,
      legacyNative: this.native.send,
      reportMatchCount: async (tabId, count) => {
        this.reported = { tabId, count };
      },
      now: () => this.nowMs,
    });
    return this.router;
  }

  advance(ms) {
    this.nowMs += ms;
  }

  dispatch(message, sender) {
    return this.router.dispatch(message, sender);
  }

  /** Content-script `requestMatches` for the default page/frame. */
  matches(overrides = {}) {
    const { sender, ...fields } = overrides;
    return this.dispatch(
      overlayMessage("requestMatches", {
        origin: ORIGIN,
        focusNonce: "nonce-1",
        fieldKind: "password",
        ...fields,
      }),
      sender ?? contentScriptSender({ frameUrl: PAGE_URL })
    );
  }

  /** Content-script `fill`. */
  fill(overrides = {}) {
    const { sender, ...fields } = overrides;
    return this.dispatch(
      overlayMessage("fill", {
        origin: ORIGIN,
        focusNonce: "nonce-1",
        fillToken: "no-such-token",
        entryId: "entry-1",
        sessionBinding: bindingA(),
        ...fields,
      }),
      sender ?? contentScriptSender({ frameUrl: PAGE_URL })
    );
  }

  /** Mint a real token the way production does, then return it. */
  async mintToken(overrides = {}) {
    const result = await this.matches(overrides);
    assert.equal(result.ok, true, "expected a successful metadata query");
    assert.equal(typeof result.fillToken, "string", "expected a fill token");
    return result;
  }
}

/** The one question worth asking about any token. */
function revealedSecret(response) {
  return response?.ok === true ? (response.data?.password ?? null) : null;
}

// ---------------------------------------------------------------------------
// A022 — explicit route allowlists.
// ---------------------------------------------------------------------------

test("A022: a content-script sender cannot reach any extension-page route", async () => {
  const harness = new Harness();
  const sender = contentScriptSender({ frameUrl: PAGE_URL });

  for (const message of [
    overlayMessage("getSiteState", { tabId: 42, origin: ORIGIN }),
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: false }),
    { type: "KEYVAULT_V2_STATUS" },
    { type: "KEYVAULT_V2_REVEAL_FOR_FILL", entryId: "entry-1", origin: ORIGIN },
    { type: "KEYVAULT_V2_QUERY_CREDENTIALS", url: ORIGIN },
    { type: "KEYVAULT_V2_REPORT_MATCH_COUNT", tabId: 42, count: 3 },
  ]) {
    const response = await harness.dispatch(message, sender);
    assert.equal(response.ok, false, message.type);
    assert.equal(response.error.code, "forbidden", message.type);
  }

  // The effect that matters: the legacy reveal route — the one that applies the
  // LENIENT popup policy — was never reachable from a page, so no native
  // request of any kind was issued.
  assert.deepEqual(harness.native.calls, []);
  // And the durable opt-in was not touched by a page asking to change it.
  assert.deepEqual(harness.browser.config().enabledOrigins, [ORIGIN]);
});

test("A022: an extension-page sender cannot reach any content route", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();
  const sender = extensionPageSender();

  for (const message of [
    overlayMessage("bootstrap", { origin: ORIGIN }),
    overlayMessage("requestMatches", {
      origin: ORIGIN,
      focusNonce: "nonce-1",
      fieldKind: "password",
    }),
    overlayMessage("fill", {
      origin: ORIGIN,
      focusNonce: "nonce-1",
      fillToken: minted.fillToken,
      entryId: "entry-1",
      sessionBinding: bindingA(),
    }),
  ]) {
    const response = await harness.dispatch(message, sender);
    assert.equal(response.ok, false, message.type);
    assert.equal(response.error.code, "forbidden", message.type);
    assert.equal(revealedSecret(response), null);
  }

  // A real, still-valid token presented on the wrong route revealed nothing and
  // did not even reach the native host.
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
  // It is also still redeemable on its OWN route, which proves the refusal
  // above was a routing decision and not an accidental invalidation.
  assert.equal(
    revealedSecret(await harness.fill({ fillToken: minted.fillToken })),
    PASSWORD
  );
});

test("A022: the popup routes still work, under the stricter sender validator", async () => {
  const harness = new Harness();
  const sender = extensionPageSender();

  const status = await harness.dispatch({ type: "KEYVAULT_V2_STATUS" }, sender);
  assert.equal(status.ok, true);
  assert.deepEqual(harness.native.calls.at(-1), { type: "status", payload: {} });

  const query = await harness.dispatch(
    { type: "KEYVAULT_V2_QUERY_CREDENTIALS", url: ORIGIN, title: "", limit: 10 },
    sender
  );
  assert.equal(query.ok, true);
  assert.deepEqual(harness.native.calls.at(-1).payload, {
    url: ORIGIN,
    title: "",
    limit: 10,
  });

  // The popup really does send `url: null` when there is no active-tab origin.
  const search = await harness.dispatch(
    { type: "KEYVAULT_V2_SEARCH_CREDENTIALS", query: "", url: null, limit: 25 },
    sender
  );
  assert.equal(search.ok, true);

  const pending = await harness.dispatch(
    { type: "KEYVAULT_V2_CREATE_PENDING_ASSOCIATION", entryId: "e", url: ORIGIN },
    sender
  );
  assert.equal(pending.ok, true);

  const reveal = await harness.dispatch(
    { type: "KEYVAULT_V2_REVEAL_FOR_FILL", entryId: "e", origin: ORIGIN },
    sender
  );
  assert.equal(reveal.ok, true);

  const badge = await harness.dispatch(
    { type: "KEYVAULT_V2_REPORT_MATCH_COUNT", tabId: 42, count: 3 },
    sender
  );
  assert.deepEqual(badge, { ok: true });
  assert.deepEqual(harness.reported, { tabId: 42, count: 3 });

  const siteState = await harness.dispatch(
    overlayMessage("getSiteState", { tabId: 42, origin: ORIGIN }),
    sender
  );
  assert.equal(siteState.ok, true);
  assert.equal(siteState.state, "enabled");
});

test("A022: setSiteState still enables and disables through the popup route", async () => {
  const harness = new Harness({ enabled: [], granted: [PATTERN] });
  const sender = extensionPageSender();

  const enabled = await harness.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: true }),
    sender
  );
  assert.equal(enabled.state, "enabled");
  assert.deepEqual(harness.browser.config().enabledOrigins, [ORIGIN]);

  const disabled = await harness.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: false }),
    sender
  );
  assert.equal(disabled.state, "disabled");
  assert.deepEqual(harness.browser.config().enabledOrigins, []);
});

test("A022: an extension-page sender that is not this extension is refused", async () => {
  const harness = new Harness();

  for (const sender of [
    extensionPageSender({ url: "https://example.com/popup.html" }),
    extensionPageSender({ id: "someotherextensionidxxxxxxxxxxxx" }),
    extensionPageSender({ url: `chrome-extension://someoneelse/popup.html` }),
    extensionPageSender({ origin: "https://example.com" }),
  ]) {
    const response = await harness.dispatch({ type: "KEYVAULT_V2_STATUS" }, sender);
    assert.equal(response.ok, false);
    assert.equal(response.error.code, "forbidden");
  }
  assert.deepEqual(harness.native.calls, []);
});

test("A022: unknown senders, types and shapes fail deterministically", async () => {
  const harness = new Harness();
  const sender = extensionPageSender();

  const unknown = [
    [{ type: "KEYVAULT_V3_DO_ANYTHING" }, "forbidden"],
    [{ type: "" }, "forbidden"],
    [{ type: 42 }, "forbidden"],
    [{}, "forbidden"],
    // Prototype-derived names must resolve to nothing, not to a function.
    [{ type: "constructor" }, "forbidden"],
    [{ type: "__proto__" }, "forbidden"],
    [{ type: "hasOwnProperty" }, "forbidden"],
    [{ type: "toString" }, "forbidden"],
  ];
  for (const [message, code] of unknown) {
    const first = await harness.dispatch(message, sender);
    const second = await harness.dispatch(message, sender);
    assert.equal(first.ok, false, JSON.stringify(message));
    assert.equal(first.error.code, code, JSON.stringify(message));
    // Deterministic: identical input, identical answer.
    assert.deepEqual(second, first, JSON.stringify(message));
  }

  for (const message of [null, undefined, "status", 7, [], true]) {
    const response = await harness.dispatch(message, sender);
    assert.equal(response.ok, false);
    assert.equal(response.error.code, "invalid_request");
  }

  // A malformed sender object gets the same treatment.
  for (const badSender of [null, undefined, "popup", 3]) {
    const response = await harness.dispatch({ type: "KEYVAULT_V2_STATUS" }, badSender);
    assert.equal(response.ok, false);
    assert.equal(response.error.code, "forbidden");
  }

  assert.deepEqual(harness.native.calls, []);
});

test("A022: an unknown key on a legacy popup route is rejected, not forwarded", async () => {
  const harness = new Harness();
  const response = await harness.dispatch(
    {
      type: "KEYVAULT_V2_REVEAL_FOR_FILL",
      entryId: "entry-1",
      origin: ORIGIN,
      matchPolicy: "anythingGoes",
    },
    extensionPageSender()
  );
  assert.equal(response.ok, false);
  assert.equal(response.error.code, "invalid_request");
  assert.deepEqual(harness.native.calls, []);
});

// ---------------------------------------------------------------------------
// A023 — the frame origin comes from `sender.url`.
// ---------------------------------------------------------------------------

test("A023: the origin forwarded to the native host is the sender-derived one", async () => {
  const harness = new Harness({ enabled: [ORIGIN] });
  await harness.mintToken();

  const query = harness.native.callsOf("overlayQueryCredentials").at(-1);
  assert.equal(query.payload.url, ORIGIN);
  assert.equal(query.payload.matchPolicy, routes.MATCH_POLICY);

  const minted = await harness.mintToken();
  await harness.fill({ fillToken: minted.fillToken });
  const reveal = harness.native.callsOf("overlayRevealForFill").at(-1);
  assert.equal(reveal.payload.origin, ORIGIN);
});

test("A023: a body origin that disagrees with sender.url never reaches the host", async () => {
  const harness = new Harness({ enabled: [ORIGIN, OTHER_ORIGIN] });

  // Both origins are enabled and permitted, so the ONLY thing refusing this is
  // the sender-derived origin check: the page claims to be the other site.
  const spoofed = await harness.matches({ origin: OTHER_ORIGIN });
  assert.equal(spoofed.ok, false);
  assert.equal(spoofed.error.code, "forbidden");

  const spoofedFill = await harness.fill({ origin: OTHER_ORIGIN });
  assert.equal(spoofedFill.ok, false);
  assert.equal(revealedSecret(spoofedFill), null);

  assert.deepEqual(harness.native.calls, []);
});

test("A023: port, scheme and host differences are separate origins", async () => {
  const harness = new Harness({ enabled: [ORIGIN] });

  for (const frameUrl of [
    "https://example.com:8443/login",
    "http://example.com/login",
    "https://example.com.evil.test/login",
    "https://www.example.com/login",
  ]) {
    const sender = contentScriptSender({ frameUrl });
    const response = await harness.matches({
      sender,
      origin: security.canonicalOriginOrNull(frameUrl),
    });
    assert.equal(response.ok, false, frameUrl);
    assert.equal(response.error.code, "disabled", frameUrl);
  }
  assert.deepEqual(harness.native.calls, []);
});

test("A023: a disabled origin or a missing permission is refused before native I/O", async () => {
  const disabled = new Harness({ enabled: [] });
  const refusedDisabled = await disabled.matches();
  assert.equal(refusedDisabled.error.code, "disabled");
  assert.deepEqual(disabled.native.calls, []);

  const unpermitted = new Harness({ enabled: [ORIGIN], granted: [] });
  const refusedPermission = await unpermitted.matches();
  assert.equal(refusedPermission.error.code, "disabled");
  assert.deepEqual(unpermitted.native.calls, []);
});

test("A023: tab id, frame id and document id are validated before native I/O", async () => {
  const harness = new Harness();

  const senders = [
    // `tab`/`frameId` are removed outright, not defaulted: an absent tab id is
    // the sender record a non-content context produces.
    contentScriptSender({ frameUrl: PAGE_URL, tab: undefined }),
    contentScriptSender({ frameUrl: PAGE_URL, tab: { url: PAGE_URL } }),
    contentScriptSender({ frameUrl: PAGE_URL, tab: { id: "42", url: PAGE_URL } }),
    contentScriptSender({ frameUrl: PAGE_URL, frameId: 1.5 }),
    contentScriptSender({ frameUrl: PAGE_URL, frameId: -1 }),
    contentScriptSender({ frameUrl: PAGE_URL, documentId: "" }),
    contentScriptSender({ frameUrl: PAGE_URL, documentId: 7 }),
    // Top frame whose tab URL disagrees with the frame URL.
    contentScriptSender({ frameUrl: PAGE_URL, topUrl: OTHER_ORIGIN, frameId: 0 }),
    // Opaque/sandboxed sender origin.
    contentScriptSender({ frameUrl: PAGE_URL, origin: "null" }),
  ];
  for (const sender of senders) {
    const response = await harness.matches({ sender });
    assert.equal(response.ok, false);
    assert.equal(response.error.code, "forbidden");
  }
  assert.deepEqual(harness.native.calls, []);
});

test("A023: the grant is bound to the document id the sender reported", async () => {
  const harness = new Harness();
  const senderA = contentScriptSender({ frameUrl: PAGE_URL, documentId: "doc-a" });
  const minted = await harness.mintToken({ sender: senderA });

  // Same tab, same frame, different document: a navigation replaced the page.
  const senderB = contentScriptSender({ frameUrl: PAGE_URL, documentId: "doc-b" });
  const wrongDocument = await harness.fill({
    sender: senderB,
    fillToken: minted.fillToken,
  });
  assert.equal(revealedSecret(wrongDocument), null);
  assert.equal(wrongDocument.error.code, "forbidden");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A023: a grant cannot be redeemed from another tab or frame", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  const otherTab = await harness.fill({
    sender: contentScriptSender({ frameUrl: PAGE_URL, tabId: 99 }),
    fillToken: minted.fillToken,
  });
  assert.equal(revealedSecret(otherTab), null);

  const otherFrame = await harness.fill({
    sender: contentScriptSender({ frameUrl: PAGE_URL, frameId: 3, topUrl: PAGE_URL }),
    fillToken: minted.fillToken,
  });
  assert.equal(revealedSecret(otherFrame), null);

  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

// ---------------------------------------------------------------------------
// SR-7 — frame behaviour.
// ---------------------------------------------------------------------------

test("A023/SR-7: bootstrap reports the frame's own support classification", async () => {
  const harness = new Harness({ enabled: [ORIGIN, OTHER_ORIGIN] });
  const bootstrap = (sender) =>
    harness.dispatch(overlayMessage("bootstrap", {
      origin: security.canonicalOriginOrNull(sender.url),
    }), sender);

  const top = await bootstrap(contentScriptSender({ frameUrl: PAGE_URL }));
  assert.equal(top.ok, true);
  assert.equal(top.frameSupport, "top");
  assert.equal(top.origin, ORIGIN);
  assert.equal(top.frameId, 0);

  const sameOrigin = await bootstrap(
    contentScriptSender({ frameUrl: PAGE_URL, topUrl: PAGE_URL, frameId: 2 })
  );
  assert.equal(sameOrigin.frameSupport, "same-origin");

  const crossOrigin = await bootstrap(
    contentScriptSender({
      frameUrl: `${OTHER_ORIGIN}/login`,
      topUrl: PAGE_URL,
      frameId: 3,
    })
  );
  assert.equal(crossOrigin.frameSupport, "permitted-cross-origin");
  assert.equal(crossOrigin.origin, OTHER_ORIGIN);

  // Bootstrap discloses no credential metadata at all.
  assert.equal("items" in crossOrigin, false);
  assert.equal("fillToken" in crossOrigin, false);
});

test("A023/SR-7: an unsupported frame is refused before native I/O", async () => {
  const harness = new Harness({ enabled: [ORIGIN] });
  // A child frame on an enabled origin whose top document cannot be
  // canonicalized (a restricted or opaque top-level page).
  const sender = contentScriptSender({
    frameUrl: PAGE_URL,
    topUrl: "about:blank",
    frameId: 4,
  });

  const bootstrap = await harness.dispatch(
    overlayMessage("bootstrap", { origin: ORIGIN }),
    sender
  );
  assert.equal(bootstrap.ok, true);
  assert.equal(bootstrap.frameSupport, "unsupported");

  const response = await harness.matches({ sender });
  assert.equal(response.ok, false);
  assert.equal(response.error.code, "unsupported_frame");
  assert.deepEqual(harness.native.calls, []);

  const filled = await harness.fill({ sender });
  assert.equal(filled.error.code, "unsupported_frame");
  assert.equal(revealedSecret(filled), null);
  assert.deepEqual(harness.native.calls, []);
});

test("A023/SR-7: a permitted cross-origin child binds to its OWN origin", async () => {
  const harness = new Harness({
    enabled: [ORIGIN, OTHER_ORIGIN],
    granted: [PATTERN, OTHER_PATTERN],
  });
  // Child frame on OTHER_ORIGIN inside a top document on ORIGIN. Both are
  // enabled, so the only question is which one the request binds to.
  const child = contentScriptSender({
    frameUrl: `${OTHER_ORIGIN}/login`,
    topUrl: PAGE_URL,
    frameId: 3,
  });

  const minted = await harness.mintToken({ sender: child, origin: OTHER_ORIGIN });
  assert.equal(minted.origin, OTHER_ORIGIN);
  const query = harness.native.callsOf("overlayQueryCredentials").at(-1);
  assert.equal(query.payload.url, OTHER_ORIGIN);

  const filled = await harness.fill({
    sender: child,
    origin: OTHER_ORIGIN,
    fillToken: minted.fillToken,
  });
  assert.equal(revealedSecret(filled), PASSWORD);
  assert.equal(filled.origin, OTHER_ORIGIN);
  const reveal = harness.native.callsOf("overlayRevealForFill").at(-1);
  // The top document's origin never became the authorization target.
  assert.equal(reveal.payload.origin, OTHER_ORIGIN);
  assert.notEqual(reveal.payload.origin, ORIGIN);
});

test("A023/SR-7: a cross-origin child whose own origin is not enabled fails closed", async () => {
  const harness = new Harness({ enabled: [ORIGIN] });
  const sender = contentScriptSender({
    frameUrl: `${OTHER_ORIGIN}/login`,
    topUrl: PAGE_URL,
    frameId: 3,
  });
  const response = await harness.matches({ sender, origin: OTHER_ORIGIN });
  assert.equal(response.ok, false);
  // Authorization follows the FRAME, never the enabled top document.
  assert.equal(response.error.code, "disabled");
  assert.deepEqual(harness.native.calls, []);
});

// ---------------------------------------------------------------------------
// A024 — token minting.
// ---------------------------------------------------------------------------

test("A024: no token is minted until an exact-origin metadata query succeeds", async () => {
  const harness = new Harness();
  harness.native.failWith("overlayQueryCredentials", "app_bridge_unavailable");

  const failed = await harness.matches();
  assert.equal(failed.ok, false);
  assert.equal(failed.error.code, "locked");

  // Nothing was minted, so nothing can be redeemed — including the token value
  // a caller might guess from a previous successful session.
  const filled = await harness.fill({ fillToken: "anything" });
  assert.equal(revealedSecret(filled), null);
  assert.equal(filled.error.code, "stale_session");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A024: a metadata response with no fillable item mints no token", async () => {
  const harness = new Harness({
    native: new FakeNative({
      items: [item({ entryId: "entry-2", matchType: "possible", fillEligible: false })],
    }),
  });

  const response = await harness.matches();
  assert.equal(response.ok, true);
  assert.equal(response.items.length, 1);
  assert.equal("fillToken" in response, false);
  assert.equal("expiresAtEpochMs" in response, false);
});

test("A024: the grant covers only the fill-eligible entry ids", async () => {
  const harness = new Harness({
    native: new FakeNative({
      items: [
        item({ entryId: "eligible" }),
        item({ entryId: "possible-only", matchType: "possible", fillEligible: false }),
      ],
    }),
  });
  const minted = await harness.mintToken();

  const refused = await harness.fill({
    fillToken: minted.fillToken,
    entryId: "possible-only",
  });
  assert.equal(revealedSecret(refused), null);
  assert.equal(refused.error.code, "forbidden");
  // A host/domain-only match cannot reveal, and does not even ask.
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);

  // The token is one-shot, so the refused attempt also burned it: the eligible
  // entry now needs a fresh metadata query. That is the intended behaviour.
  const eligible = await harness.fill({
    fillToken: minted.fillToken,
    entryId: "eligible",
  });
  assert.equal(revealedSecret(eligible), null);
  assert.equal(eligible.error.code, "stale_session");
});

test("A024: a metadata response carries no username or password", async () => {
  const harness = new Harness();
  const response = await harness.mintToken();

  // Executed by the shipped validator, not by a copy: a forbidden key at any
  // depth is a hard failure.
  assert.equal(security.validateMatchesResult(response).ok, true);
  const serialized = JSON.stringify(response);
  assert.equal(serialized.includes(PASSWORD), false);
  assert.equal(serialized.includes(USERNAME), false);
});

test("A024: an item the host decorated with extra fields is not forwarded verbatim", async () => {
  const harness = new Harness({
    native: new FakeNative({ items: [{ ...item(), note: "extra" }] }),
  });
  const response = await harness.matches();
  // The item failed the shipped item validator, so the whole response is
  // refused rather than sanitized into something plausible.
  assert.equal(response.ok, false);
  assert.equal(response.error.code, "internal_error");
});

test("A024: a host returning more items than the contract allows is refused", async () => {
  const overLimit = [];
  for (let index = 0; index <= security.LIMITS.ITEMS; index += 1) {
    overLimit.push(item({ entryId: `entry-${index}` }));
  }
  const harness = new Harness({ native: new FakeNative({ items: overLimit }) });

  const response = await harness.matches();
  // Refused outright rather than truncated to a plausible-looking ten: the
  // outbound message is checked by the shipped validator before it leaves.
  assert.equal(response.ok, false);
  // The HOST broke the contract, so the code names a host capability problem.
  // `internal_error` is reserved for this worker producing something invalid;
  // conflating the two would blame the extension for the host's misbehaviour.
  assert.equal(response.error.code, "unsupported_capability");

  // And no token was handed out for a response that was never sent.
  const filled = await harness.fill({ fillToken: "anything" });
  assert.equal(revealedSecret(filled), null);
});

test("A024: the token map is bounded and evicts the oldest grant", async () => {
  const harness = new Harness();
  const capacity = security.LIMITS.GRANTS;

  // One grant per tab, so the per-(tab,frame) replacement rule does not hide
  // the eviction being measured here.
  const oldest = await harness.mintToken({
    sender: contentScriptSender({ frameUrl: PAGE_URL, tabId: 1 }),
  });
  for (let tabId = 2; tabId <= capacity + 1; tabId += 1) {
    await harness.mintToken({
      sender: contentScriptSender({ frameUrl: PAGE_URL, tabId }),
    });
  }
  const newest = await harness.mintToken({
    sender: contentScriptSender({ frameUrl: PAGE_URL, tabId: capacity + 2 }),
  });

  const evicted = await harness.fill({
    sender: contentScriptSender({ frameUrl: PAGE_URL, tabId: 1 }),
    fillToken: oldest.fillToken,
  });
  assert.equal(revealedSecret(evicted), null);
  assert.equal(evicted.error.code, "stale_session");

  const survivor = await harness.fill({
    sender: contentScriptSender({ frameUrl: PAGE_URL, tabId: capacity + 2 }),
    fillToken: newest.fillToken,
  });
  assert.equal(revealedSecret(survivor), PASSWORD);
});

test("A024: a new focus in the same frame replaces the previous grant", async () => {
  const harness = new Harness();
  const first = await harness.mintToken({ focusNonce: "nonce-1" });
  const second = await harness.mintToken({ focusNonce: "nonce-2" });

  const stale = await harness.fill({
    fillToken: first.fillToken,
    focusNonce: "nonce-1",
  });
  assert.equal(revealedSecret(stale), null);
  assert.equal(stale.error.code, "stale_session");

  const current = await harness.fill({
    fillToken: second.fillToken,
    focusNonce: "nonce-2",
  });
  assert.equal(revealedSecret(current), PASSWORD);
});

test("A024: the token is never written to durable storage", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  const durable = JSON.stringify(harness.browser.store);
  assert.equal(durable.includes(minted.fillToken), false);
  assert.equal(durable.includes(bindingA().cacheGeneration), false);
  assert.equal(durable.includes(bindingA().bridgeGeneration), false);
  assert.equal(durable.includes(bindingA().databaseId), false);
  assert.equal(durable.includes("entry-1"), false);

  // The durable value still holds exactly what Slice A2 defined, nothing else.
  assert.deepEqual(Object.keys(harness.browser.config()).sort(), [
    "enabledOrigins",
    "revision",
    "version",
  ]);
});

test("A024: the token lifetime never exceeds the 30-second ceiling", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();
  assert.ok(minted.expiresAtEpochMs - harness.nowMs <= 30000);

  harness.advance(30000);
  const expired = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(expired), null);
  assert.equal(expired.error.code, "stale_session");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A024: a token just short of expiry still works", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();
  harness.advance(29999);
  assert.equal(
    revealedSecret(await harness.fill({ fillToken: minted.fillToken })),
    PASSWORD
  );
});

// ---------------------------------------------------------------------------
// A025 — explicit fill.
// ---------------------------------------------------------------------------

test("A025: an explicit fill with a valid grant returns the credential once", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  const filled = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(filled.ok, true);
  assert.equal(filled.type, "fillResult");
  assert.equal(filled.origin, ORIGIN);
  assert.equal(filled.focusNonce, "nonce-1");
  assert.equal(filled.entryId, "entry-1");
  assert.deepEqual(filled.sessionBinding, bindingA());
  assert.deepEqual(filled.data, { username: USERNAME, password: PASSWORD });

  // The expected binding forwarded to the host came from the grant.
  const reveal = harness.native.callsOf("overlayRevealForFill").at(-1);
  assert.equal(reveal.payload.expectedDatabaseId, bindingA().databaseId);
  assert.equal(reveal.payload.expectedCacheGeneration, bindingA().cacheGeneration);
  assert.equal(reveal.payload.expectedBridgeGeneration, bindingA().bridgeGeneration);
  assert.equal(reveal.payload.matchPolicy, routes.MATCH_POLICY);
});

test("A025: the token is one-shot — a replay reveals nothing", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  const first = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(first), PASSWORD);

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const replay = await harness.fill({ fillToken: minted.fillToken });
    assert.equal(revealedSecret(replay), null);
    assert.equal(replay.error.code, "stale_session");
  }

  // The host was contacted exactly once: the replays never became a request.
  assert.equal(harness.native.callsOf("overlayRevealForFill").length, 1);
});

test("A025: the token is consumed even when the native reveal fails", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();
  harness.native.failWith("overlayRevealForFill", "app_bridge_unavailable");

  const failed = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(failed.error.code, "locked");

  // The failed attempt burned the grant, so a retry cannot re-enter the host
  // with the same token — that is what makes consumption a race the attacker
  // loses by construction rather than by timing.
  harness.native.errors.clear();
  const retry = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(retry), null);
  assert.equal(retry.error.code, "stale_session");
  assert.equal(harness.native.callsOf("overlayRevealForFill").length, 1);
});

test("A025: a fill whose message binding does not match the grant is refused", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  const wrongBinding = await harness.fill({
    fillToken: minted.fillToken,
    sessionBinding: bindingB(),
  });
  assert.equal(revealedSecret(wrongBinding), null);
  assert.equal(wrongBinding.error.code, "stale_session");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A025: each of the three generations is compared, not just the database id", async () => {
  const base = bindingA();
  const variants = [
    { ...base, databaseId: "db-other" },
    { ...base, cacheGeneration: "cache-other" },
    { ...base, bridgeGeneration: "bridge-other" },
  ];
  for (const sessionBinding of variants) {
    const harness = new Harness();
    const minted = await harness.mintToken();
    const response = await harness.fill({
      fillToken: minted.fillToken,
      sessionBinding,
    });
    assert.equal(revealedSecret(response), null, JSON.stringify(sessionBinding));
    assert.equal(response.error.code, "stale_session");
    assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
  }
});

test("A025: a success whose echoed binding drifted does not forward the secret", async () => {
  const base = bindingA();
  const drifted = [
    { ...base, databaseId: "db-b" },
    { ...base, cacheGeneration: "cache-b" },
    { ...base, bridgeGeneration: "bridge-b" },
    null,
    undefined,
    { databaseId: base.databaseId },
  ];
  for (const echoBinding of drifted) {
    const harness = new Harness();
    const minted = await harness.mintToken();
    harness.native.echoes(echoBinding);

    const response = await harness.fill({ fillToken: minted.fillToken });
    assert.equal(revealedSecret(response), null, JSON.stringify(echoBinding));
    assert.equal(response.error.code, "stale_session");
    // The host DID answer with a password; it was dropped here.
    assert.equal(harness.native.callsOf("overlayRevealForFill").length, 1);
    assert.equal(JSON.stringify(response).includes(PASSWORD), false);
  }
});

test("A025: a success echoing a different origin does not forward the secret", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();
  harness.native.echoOrigin = OTHER_ORIGIN;

  const response = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(response), null);
  assert.equal(response.error.code, "stale_session");
});

test("A025: vault A -> B rejects the old token without revealing the B secret", async () => {
  // Same entry UUID, same exact origin, different vault. The only thing that
  // differs is the session binding, which is exactly the point of SR-4.
  const harness = new Harness();
  const minted = await harness.mintToken();

  // The worker observes the republish through a later metadata query.
  harness.native.binding = bindingB();
  const afterSwitch = await harness.matches({ focusNonce: "nonce-2" });
  assert.equal(afterSwitch.ok, true);
  assert.deepEqual(afterSwitch.sessionBinding, bindingB());

  const oldToken = await harness.fill({
    fillToken: minted.fillToken,
    focusNonce: "nonce-1",
    sessionBinding: bindingA(),
  });
  assert.equal(revealedSecret(oldToken), null);
  assert.equal(oldToken.error.code, "stale_session");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A027: an unobserved republish is refused, and the host is given what it needs to refuse", async () => {
  // The case A027 names explicitly: the vault switches and the worker has NOT
  // observed it, because no later query ran. `invalidateOtherBindings` has
  // therefore not fired and the grant is still in the map.
  //
  // This is the scenario `FocusGrantStore.consume` once appeared to cover via a
  // `currentBinding` argument that production never passed. The worker has no
  // independent view of the live session, so the check belongs to the native
  // host — and the worker's real obligation is to hand the host the binding the
  // grant was issued against, unmodified, so the host can compare it.
  const harness = new Harness();
  const minted = await harness.mintToken();

  harness.native.binding = bindingB(); // vault B is live; no query has run since

  const response = await harness.fill({
    fillToken: minted.fillToken,
    sessionBinding: bindingA(),
  });

  assert.equal(revealedSecret(response), null);
  assert.equal(response.error.code, "stale_session");

  // The request carried vault A's binding — the grant's, not the caller's and
  // not the live one. That is precisely the tuple the host compares against the
  // live cache and bridge descriptor before it touches the credential store.
  const [reveal] = harness.native.callsOf("overlayRevealForFill");
  assert.ok(reveal, "the host must be consulted; the worker cannot decide this");
  assert.equal(reveal.payload.expectedDatabaseId, bindingA().databaseId);
  assert.equal(reveal.payload.expectedCacheGeneration, bindingA().cacheGeneration);
  assert.equal(reveal.payload.expectedBridgeGeneration, bindingA().bridgeGeneration);
});

test("A025: the fill result is the only message that ever carries a secret", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();
  const bootstrap = await harness.dispatch(
    overlayMessage("bootstrap", { origin: ORIGIN }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );
  const filled = await harness.fill({ fillToken: minted.fillToken });

  assert.equal(JSON.stringify(minted).includes(PASSWORD), false);
  assert.equal(JSON.stringify(bootstrap).includes(PASSWORD), false);
  assert.equal(JSON.stringify(filled).includes(PASSWORD), true);
});

// ---------------------------------------------------------------------------
// A026 — stable, non-sensitive error codes.
// ---------------------------------------------------------------------------

test("A026: native error codes map to the stable public set", async () => {
  const expected = [
    ["app_bridge_unavailable", "locked"],
    ["app_bridge_timeout", "timeout"],
    ["timeout", "timeout"],
    ["no_host", "no_host"],
    ["stale_session", "stale_session"],
    ["database_mismatch", "stale_session"],
    ["unsupported_type", "unsupported_capability"],
    ["unsupported_version", "unsupported_capability"],
    ["not_found", "unsupported_capability"],
    ["forbidden", "forbidden"],
    ["strong_match_required", "forbidden"],
    ["invalid_request", "invalid_request"],
    ["credential_unavailable", "internal_error"],
    ["app_bridge_invalid_response", "internal_error"],
    // Anything unmapped fails closed rather than leaking the raw reason.
    ["some_new_native_code", "internal_error"],
    [undefined, "internal_error"],
  ];

  for (const [nativeCode, publicCodeExpected] of expected) {
    const harness = new Harness();
    harness.native.failWith("overlayQueryCredentials", nativeCode);
    const response = await harness.matches();
    assert.equal(response.ok, false, String(nativeCode));
    assert.equal(response.error.code, publicCodeExpected, String(nativeCode));
    assert.equal(response.type, "matchesResult");
    assert.equal(response.focusNonce, "nonce-1");
  }
});

test("A026: an old native host without the overlay capability fails closed", async () => {
  const harness = new Harness();
  // A host predating Slice A1 does not know the request type at all.
  harness.native.failWith("overlayQueryCredentials", "unsupported_type");
  const response = await harness.matches();
  assert.equal(response.error.code, "unsupported_capability");

  // It must not degrade to the lenient legacy route on the content path.
  assert.deepEqual(harness.native.callsOf("queryCredentials"), []);
  assert.deepEqual(harness.native.callsOf("revealForFill"), []);
});

test("A026: a host that does not echo the exact policy or target is refused", async () => {
  for (const mutate of [
    (data) => ({ ...data, matchPolicy: "hostMatch" }),
    (data) => ({ ...data, target: OTHER_ORIGIN }),
    (data) => ({ ...data, metadataOnly: false }),
  ]) {
    const harness = new Harness();
    const inner = harness.native.send;
    harness.native.send = async (type, payload) => {
      const response = await inner(type, payload);
      return type === "overlayQueryCredentials"
        ? { ...response, data: mutate(response.data) }
        : response;
    };
    harness.restart();

    const response = await harness.matches();
    assert.equal(response.ok, false);
    assert.equal(response.error.code, "unsupported_capability");
  }
});

test("A026: no error response leaks a native message, URL or entry id", async () => {
  const harness = new Harness();
  harness.native.errors.set("overlayQueryCredentials", {
    ok: false,
    error: {
      code: "forbidden",
      message: `Entry entry-secret-1 is not authorized for ${PAGE_URL}`,
    },
  });

  const response = await harness.matches();
  const serialized = JSON.stringify(response);
  assert.equal(serialized.includes("entry-secret-1"), false);
  assert.equal(serialized.includes("/login"), false);
  assert.equal(serialized.includes("not authorized for"), false);
  assert.deepEqual(Object.keys(response.error).sort(), ["code", "message"]);
  assert.equal(
    response.error.message,
    routes.PUBLIC_ERROR_MESSAGES.forbidden
  );
});

test("A026: every produced error code is in the published set", async () => {
  const harness = new Harness({ enabled: [] });
  const produced = [
    await harness.matches(),
    await harness.fill(),
    await harness.dispatch({ type: "nope" }, extensionPageSender()),
    await harness.dispatch(null, extensionPageSender()),
  ];
  for (const response of produced) {
    assert.equal(response.ok, false);
    assert.ok(
      routes.PUBLIC_ERROR_CODES.includes(response.error.code),
      response.error.code
    );
  }
});

test("A026: the worker logs neither the message nor the native response", async () => {
  const harness = new Harness();
  const captured = [];
  const original = {};
  for (const level of ["log", "info", "warn", "error", "debug", "trace"]) {
    original[level] = console[level];
    console[level] = (...args) => captured.push([level, ...args]);
  }
  try {
    const minted = await harness.mintToken();
    await harness.fill({ fillToken: minted.fillToken });
    await harness.fill({ fillToken: minted.fillToken });
    harness.native.failWith("overlayQueryCredentials", "forbidden");
    await harness.matches();
    await harness.dispatch({ type: "unknown" }, extensionPageSender());
  } finally {
    for (const [level, fn] of Object.entries(original)) console[level] = fn;
  }
  assert.deepEqual(captured, []);
});

// ---------------------------------------------------------------------------
// A027 — worker restart, eager invalidation, native backstop.
// ---------------------------------------------------------------------------

test("A027: an MV3 worker restart invalidates every grant", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  // Cold start: same durable storage, new worker.
  harness.restart();

  const afterRestart = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(afterRestart), null);
  assert.equal(afterRestart.error.code, "stale_session");
  // No reconnect loop and no durable token: the refusal happened before any
  // native request, so the restart cost exactly zero host round trips.
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A027: the next request recovers through a fresh metadata query", async () => {
  const harness = new Harness();
  await harness.mintToken();
  harness.restart();

  const refused = await harness.fill({ fillToken: "stale" });
  assert.equal(refused.error.code, "stale_session");

  // Recovery is one ordinary metadata query, not a retry of the fill.
  const reMinted = await harness.mintToken({ focusNonce: "nonce-2" });
  const filled = await harness.fill({
    fillToken: reMinted.fillToken,
    focusNonce: "nonce-2",
  });
  assert.equal(revealedSecret(filled), PASSWORD);
  assert.equal(harness.native.callsOf("overlayRevealForFill").length, 1);
});

test("A027: a query advertising a new binding eagerly clears older grants", async () => {
  const harness = new Harness();
  const tabOne = contentScriptSender({ frameUrl: PAGE_URL, tabId: 1 });
  const tabTwo = contentScriptSender({ frameUrl: PAGE_URL, tabId: 2 });
  const oldGrant = await harness.mintToken({ sender: tabOne });

  // A different tab queries after a republish and learns binding B.
  harness.native.binding = bindingB();
  await harness.mintToken({ sender: tabTwo });

  // The grant in the FIRST tab is gone even though that tab never queried
  // again and never observed the republish itself.
  const stale = await harness.fill({
    sender: tabOne,
    fillToken: oldGrant.fillToken,
    sessionBinding: bindingA(),
  });
  assert.equal(revealedSecret(stale), null);
  assert.equal(stale.error.code, "stale_session");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A027: a binding the worker never observed still fails at the native host", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  // The republish happens with no later metadata query, so the worker's grant
  // still looks internally consistent. The native host is the backstop.
  harness.native.failWith("overlayRevealForFill", "stale_session");

  const response = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(response), null);
  assert.equal(response.error.code, "stale_session");
  // It DID reach the host — that is the point: the worker was not the only
  // line of defence, and the host refused with the current binding.
  assert.equal(harness.native.callsOf("overlayRevealForFill").length, 1);
  const forwarded = harness.native.callsOf("overlayRevealForFill").at(-1);
  assert.equal(forwarded.payload.expectedCacheGeneration, bindingA().cacheGeneration);
});

test("A027: losing the bridge binding clears grants and reports locked", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  // Bridge stopped: the host still answers, with no session binding.
  harness.native.binding = null;
  const afterStop = await harness.matches({ focusNonce: "nonce-2" });
  assert.equal(afterStop.ok, false);
  assert.equal(afterStop.error.code, "locked");

  const stale = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(stale), null);
  assert.equal(stale.error.code, "stale_session");
});

test("A027: disabling the origin invalidates an outstanding grant", async () => {
  const harness = new Harness();
  const minted = await harness.mintToken();

  await harness.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: false }),
    extensionPageSender()
  );

  const response = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(response), null);
  assert.equal(response.error.code, "disabled");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

// ---------------------------------------------------------------------------
// A023 — the durable monotonic revision floor (the Slice A2 KNOWN GAP).
// ---------------------------------------------------------------------------

test("A023: a totally corrupt config cannot rewind the revision below the floor", async () => {
  for (const corrupt of [undefined, null, 7, "nope", [], { revision: "x" }, { revision: -3 }]) {
    const harness = new Harness({ revision: 41 });
    if (corrupt === undefined) {
      delete harness.browser.store[security.OVERLAY_CONFIG_KEY];
    } else {
      harness.browser.store[security.OVERLAY_CONFIG_KEY] = corrupt;
    }
    harness.restart();

    await harness.lifecycle.reconcile();
    const committed = harness.browser.config();
    assert.equal(security.validateOverlayConfig(committed).ok, true);
    assert.deepEqual(committed.enabledOrigins, []);
    // The floor survived in its own key, so the counter moved FORWARD.
    assert.ok(committed.revision > 41, JSON.stringify(corrupt));
    assert.ok(
      harness.browser.store[security.OVERLAY_REVISION_FLOOR_KEY] >= committed.revision
    );
  }
});

test("A023: a rolled-back but well-formed config is treated as corrupt", async () => {
  const harness = new Harness({ revision: 41 });
  // A valid value from an older revision is restored under a floor of 41.
  harness.browser.store[security.OVERLAY_CONFIG_KEY] = {
    version: 1,
    revision: 12,
    enabledOrigins: [ORIGIN],
  };
  harness.restart();

  const response = await harness.matches();
  assert.equal(response.ok, false);
  // The rollback re-authorized nothing: the origin is gone and the revision
  // moved past the floor.
  assert.deepEqual(harness.browser.config().enabledOrigins, []);
  assert.ok(harness.browser.config().revision > 41);
  assert.deepEqual(harness.native.calls, []);
});

test("A023: observing a corrupt config invalidates outstanding grants", async () => {
  const harness = new Harness({ revision: 41 });
  const minted = await harness.mintToken();

  // Corruption inside a LIVE worker, after reconciliation already ran.
  harness.browser.store[security.OVERLAY_CONFIG_KEY] = { revision: 41 };

  const refused = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(refused), null);
  assert.equal(refused.error.code, "stale_session");
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});

test("A023: the worker self-heals after corruption instead of wedging", async () => {
  const harness = new Harness({ revision: 41 });
  // Reconciliation has already run for this worker, so the corruption below is
  // observed by an authorization read rather than fixed by a cold start.
  await harness.lifecycle.ready();
  harness.browser.store[security.OVERLAY_CONFIG_KEY] = { revision: 41 };

  const refused = await harness.matches();
  assert.equal(refused.error.code, "stale_session");

  // The next request reconciles: the config is valid again and the origin is
  // durably disabled, so the answer is now the honest "disabled", not a
  // permanent refusal to serve.
  const healed = await harness.matches();
  assert.equal(healed.error.code, "disabled");
  assert.equal(security.validateOverlayConfig(harness.browser.config()).ok, true);
  assert.ok(harness.browser.config().revision > 41);
});

test("A023: the floor and the config commit in one storage write", async () => {
  const harness = new Harness({ enabled: [], granted: [] });
  await harness.lifecycle.ready();
  // The popup requests the permission under the user gesture; only then does
  // enable persist anything.
  harness.browser.granted.add(PATTERN);
  harness.browser.calls.length = 0;

  await harness.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: true }),
    extensionPageSender()
  );

  // SR-8/D1 remains a SINGLE durable commit: a floor written separately could
  // be lost while the config it protects survives.
  assert.equal(harness.browser.callsMatching("storage.set").length, 1);
  assert.equal(
    harness.browser.store[security.OVERLAY_REVISION_FLOOR_KEY],
    harness.browser.config().revision
  );
});

test("A023: a transient storage read failure cannot lower the floor", async () => {
  const harness = new Harness({ revision: 9 });
  harness.restart();

  // The cold read fails ONCE — a transient `storage.local.get` error, the
  // realistic trigger, not theoretical corruption. `_readConfig` cannot consult
  // the floor when the read itself failed, so it reports revision 0 and
  // reconcile commits revision 1: a commit whose revision sits far BELOW the
  // floor of 9.
  harness.browser.failNextGet = "transient";
  harness.browser.calls.length = 0;
  await harness.lifecycle.reconcile();

  // The floor is a high-water mark. A commit may RAISE it; nothing may lower
  // it. Writing `next.revision` unconditionally here silently disarms the
  // prevention half of A023 and contradicts `_readConfig`'s stated invariant
  // ("every commit raises it"), leaving containment as the only defence of two
  // that are documented as independent.
  assert.equal(harness.browser.store[security.OVERLAY_REVISION_FLOOR_KEY], 9);

  // SR-8/D1 — reading the prior floor must not have split the commit. The
  // config and the floor still travel in ONE `storage.local.set`.
  assert.equal(harness.browser.callsMatching("storage.set").length, 1);
});

test("A023: the worker climbs back above the floor after a transient read failure", async () => {
  const harness = new Harness({ revision: 9 });
  harness.restart();

  harness.browser.failNextGet = "transient";
  await harness.lifecycle.reconcile();

  // Storage works again. The below-floor config written by the previous
  // reconcile now reads as the rollback it is, so the worker self-heals PAST
  // the floor instead of handing out revisions 2, 3, 4 … that a grant minted
  // before the failure could still match.
  harness.restart();
  await harness.lifecycle.reconcile();

  const config = harness.browser.config();
  assert.equal(security.validateOverlayConfig(config).ok, true);
  assert.ok(config.revision > 9, `revision ${config.revision} must clear the floor`);
  assert.ok(
    harness.browser.store[security.OVERLAY_REVISION_FLOOR_KEY] >= config.revision
  );
});

test("A023: a pre-A3 install with no floor key still moves forward", async () => {
  const harness = new Harness({ revision: 9 });
  delete harness.browser.store[security.OVERLAY_REVISION_FLOOR_KEY];
  harness.restart();

  await harness.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: false }),
    extensionPageSender()
  );
  assert.equal(harness.browser.config().revision, 10);
  assert.equal(harness.browser.store[security.OVERLAY_REVISION_FLOOR_KEY], 10);
});

test("A023: a grant does not survive a revision change", async () => {
  const harness = new Harness({ enabled: [ORIGIN, OTHER_ORIGIN], granted: [PATTERN, OTHER_PATTERN] });
  const minted = await harness.mintToken();

  // Disabling an UNRELATED origin advances the global revision.
  await harness.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: OTHER_ORIGIN, enabled: false }),
    extensionPageSender()
  );

  const response = await harness.fill({ fillToken: minted.fillToken });
  assert.equal(revealedSecret(response), null);
  assert.deepEqual(harness.native.callsOf("overlayRevealForFill"), []);
});
