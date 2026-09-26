// spec 023 T503 — `passkeyGet`: the worker asks the app to sign, and nothing
// about a refusal tells the page what this vault holds.
//
// Written the same way as overlay_routes.test.js: every assertion is about an
// effect the page could observe, and the fake native host models the T501
// contract without applying any policy of its own.

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
} = require("./helpers.js");

const ORIGIN = "https://example.com";
const PAGE_URL = "https://example.com/login";

const REGISTRATION = Object.freeze({
  credentialId: "Y3JlZA",
  attestationObject: "YXR0",
  clientDataJSON: "Y2xpZW50",
  publicKeyCose: "Y29zZQ",
});

const ASSERTION = Object.freeze({
  credentialId: "AQIDBAU",
  authenticatorData: "YXV0aA",
  signature: "c2ln",
  clientDataJSON: "Y2xpZW50",
  userHandle: "CQk",
});

class FakeNative {
  constructor() {
    this.calls = [];
    /** Replaces the next `passkeyAssert` answer. */
    this.response = { ok: true, data: { ...ASSERTION } };
    /** Replaces the next `passkeyCreate` answer. */
    this.createResponse = { ok: true, data: { ...REGISTRATION } };
  }

  send = async (type, payload) => {
    this.calls.push({ type, payload });
    if (type === "passkeyAssert") return this.response;
    if (type === "passkeyCreate") return this.createResponse;
    return { ok: true, data: {} };
  };

  callsOf(type) {
    return this.calls.filter((call) => call.type === type);
  }
}

function harness({ enabled = true, granted } = {}) {
  const browser = new FakeBrowser({
    storage: {
      [security.OVERLAY_CONFIG_KEY]: { version: 2, revision: 5, enabled },
      [security.OVERLAY_REVISION_FLOOR_KEY]: 5,
    },
    granted: granted ?? (enabled ? [...security.GLOBAL_PERMISSION_PATTERNS] : []),
    tabs: [{ id: 42 }],
  });
  const native = new FakeNative();
  const router = new routes.OverlayRouter({
    lifecycle: new OverlayLifecycle({ browser }),
    runtimeId: RUNTIME_ID,
    native: native.send,
    legacyNative: native.send,
    reportMatchCount: async () => {},
    refreshBadge: async () => {},
  });
  return { browser, native, router };
}

function request(overrides = {}) {
  return {
    type: "passkeyGet",
    rpId: "example.com",
    challenge: "Y2hhbGxlbmdl",
    allowCredentials: [],
    ...overrides,
  };
}

test("023 T503: a signed assertion reaches the page", async () => {
  const { native, router } = harness();

  const response = await router.dispatch(
    request(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.equal(response.ok, true);
  assert.equal(response.credentialId, ASSERTION.credentialId);
  assert.equal(response.signature, ASSERTION.signature);
  assert.equal(response.userHandle, ASSERTION.userHandle);

  const call = native.callsOf("passkeyAssert")[0];
  assert.equal(call.payload.rpId, "example.com");
  assert.equal(call.payload.challenge, "Y2hhbGxlbmdl");
});

// The one property that makes the page world safe to run the wrapper in: the
// page cannot ask for another site's passkey by claiming to be that site.
test("023 T503: the origin comes from the sender, never from the message", async () => {
  const { native, router } = harness();

  await router.dispatch(
    request({ origin: "https://bank.example" }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.equal(native.callsOf("passkeyAssert")[0].payload.origin, ORIGIN);
});

test("023 T503: a refusal says nothing but no", async () => {
  const { native, router } = harness();
  native.response = { ok: true, data: { reason: "declined" } };

  const response = await router.dispatch(
    request(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  // No reason, no code, no hint that a passkey for this site exists at all.
  assert.deepEqual(response, { ok: false });
});

test("023 T503: a partial assertion is refused rather than half-used", async () => {
  const { native, router } = harness();
  native.response = { ok: true, data: { credentialId: "AQIDBAU" } };

  const response = await router.dispatch(
    request(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.deepEqual(response, { ok: false });
});

test("023 T503: with the switch off nothing is signed", async () => {
  const { native, router } = harness({ enabled: false });

  const response = await router.dispatch(
    request(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.deepEqual(response, { ok: false });
  assert.deepEqual(native.callsOf("passkeyAssert"), []);
});

// An externally revoked permission must fail closed on the next request,
// before any reconcile has had a chance to run.
test("023 T503: a revoked host permission stops the request", async () => {
  const { native, router } = harness({ granted: [] });

  const response = await router.dispatch(
    request(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.deepEqual(response, { ok: false });
  assert.deepEqual(native.callsOf("passkeyAssert"), []);
});

test("023 T503: an extension page cannot ask for a signature", async () => {
  const { native, router } = harness();

  const response = await router.dispatch(request(), extensionPageSender());

  assert.deepEqual(response, { ok: false });
  assert.deepEqual(native.callsOf("passkeyAssert"), []);
});

test("023 T503: a missing or oversize field never reaches the app", async () => {
  const { native, router } = harness();
  const sender = contentScriptSender({ frameUrl: PAGE_URL });

  assert.deepEqual(
    await router.dispatch(request({ challenge: "" }), sender),
    { ok: false }
  );
  assert.deepEqual(
    await router.dispatch(request({ rpId: "x".repeat(254) }), sender),
    { ok: false }
  );
  assert.deepEqual(
    await router.dispatch(request({ challenge: 42 }), sender),
    { ok: false }
  );
  assert.deepEqual(native.callsOf("passkeyAssert"), []);
});

test("023 T503: allowCredentials is bounded and filtered, not rejected", async () => {
  const { native, router } = harness();

  await router.dispatch(
    request({
      allowCredentials: ["AQIDBAU", 7, "", "x".repeat(513), "Ynk"],
    }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  // A malformed hint must not become a signing failure the site cannot
  // explain: the usable ids go through and the rest are dropped.
  assert.deepEqual(native.callsOf("passkeyAssert")[0].payload.allowCredentials, [
    "AQIDBAU",
    "Ynk",
  ]);
});

test("023 T503: passkeyGet is not one of the overlay's content routes", () => {
  // The overlay's set is frozen at four types with its own exact-shape
  // envelope; this request has neither that shape nor an `origin` claim.
  assert.equal(routes.CONTENT_ROUTES.has("passkeyGet"), false);
  assert.equal(routes.EXTENSION_PAGE_ROUTES.has("passkeyGet"), false);
});

// ---------------------------------------------------------------------------
// spec 023 US3 — passkeyCreate.
// ---------------------------------------------------------------------------

function createRequest(overrides = {}) {
  return {
    type: "passkeyCreate",
    rpId: "example.com",
    challenge: "Y2hhbGxlbmdl",
    username: "ada",
    ...overrides,
  };
}

test("023 US3: a created credential reaches the page", async () => {
  const { native, router } = harness();

  const response = await router.dispatch(
    createRequest(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.equal(response.ok, true);
  assert.equal(response.credentialId, REGISTRATION.credentialId);
  assert.equal(response.attestationObject, REGISTRATION.attestationObject);
  assert.equal(response.publicKeyCose, REGISTRATION.publicKeyCose);

  const call = native.callsOf("passkeyCreate")[0];
  assert.equal(call.payload.rpId, "example.com");
  assert.equal(call.payload.username, "ada");
  // The same authority rule as the sign-in path.
  assert.equal(call.payload.origin, ORIGIN);
});

test("023 US3: an empty username is allowed, not refused", async () => {
  const { native, router } = harness();

  const response = await router.dispatch(
    createRequest({ username: "" }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.equal(response.ok, true);
  assert.equal(native.callsOf("passkeyCreate")[0].payload.username, "");
});

test("023 US3: a declined creation says nothing but no", async () => {
  const { router, native } = harness();
  native.createResponse = { ok: true, data: { reason: "declined" } };

  const response = await router.dispatch(
    createRequest(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.deepEqual(response, { ok: false });
});

test("023 US3: a partial registration is refused rather than half-used", async () => {
  const { router, native } = harness();
  native.createResponse = { ok: true, data: { credentialId: "Y3JlZA" } };

  const response = await router.dispatch(
    createRequest(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.deepEqual(response, { ok: false });
});

test("023 US3: with the switch off nothing is created", async () => {
  const { native, router } = harness({ enabled: false });

  const response = await router.dispatch(
    createRequest(),
    contentScriptSender({ frameUrl: PAGE_URL })
  );

  assert.deepEqual(response, { ok: false });
  assert.deepEqual(native.callsOf("passkeyCreate"), []);
});

test("023 US3: an extension page cannot create a passkey", async () => {
  const { native, router } = harness();

  const response = await router.dispatch(createRequest(), extensionPageSender());

  assert.deepEqual(response, { ok: false });
  assert.deepEqual(native.callsOf("passkeyCreate"), []);
});

test("023 US3: passkeyCreate is not one of the overlay's content routes", () => {
  assert.equal(routes.CONTENT_ROUTES.has("passkeyCreate"), false);
  assert.equal(routes.EXTENSION_PAGE_ROUTES.has("passkeyCreate"), false);
});
