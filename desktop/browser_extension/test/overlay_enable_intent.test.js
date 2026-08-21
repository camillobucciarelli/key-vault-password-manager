// macOS grant race — the pending enable intent (popup dies at the prompt).
//
// Confirmed in manual smoke and by a user report: on macOS the OS-level
// permission dialog CLOSES the popup, so the continuation after
// `chrome.permissions.request` — the one that sends `setSiteState enable` —
// never runs. The first Allow left the site Off; only a second click (which
// found the permission already granted, no prompt) completed the enable.
//
// The fix: the popup writes a durable one-shot intent
// `{origin, tabId, createdAt}` to `chrome.storage.session` UNDER THE GESTURE,
// before the request. The worker's `permissions.onAdded` listener — after its
// existing `reconcile({ prunePermissions: false })` — consumes the intent and
// finishes the enable through the SAME `enableOrigin` path the popup uses.
//
// Security properties pinned here (and by mutations A2-M17..M19):
//   - the enabled origin comes ONLY from the intent, never derived from the
//     granted pattern (the pattern loses the port);
//   - the intent is one-shot, burned before use (replay-proof);
//   - expired or garbage intents are deleted and never acted on;
//   - a grant for a different pattern enables nothing;
//   - no intent → behaviour identical to before the fix.

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
} = require("./helpers.js");

const ORIGIN = "https://example.com";
const PATTERN = "https://example.com/*";
const PAGE_URL = "https://example.com/login";
const INTENT_KEY = security.OVERLAY_ENABLE_INTENT_KEY;

const nativeStub = async () => ({ ok: true, data: {} });

/** Exactly the wiring background.js installs for permissions.onAdded. */
function makeWorker(browser) {
  const lifecycle = new OverlayLifecycle({ browser });
  const router = new routes.OverlayRouter({
    lifecycle,
    runtimeId: RUNTIME_ID,
    native: nativeStub,
    legacyNative: nativeStub,
    reportMatchCount: async () => {},
  });
  browser.permissions.onAdded.addListener((added) =>
    lifecycle
      .reconcile({ prunePermissions: false })
      .then(() =>
        lifecycle.consumeEnableIntent({
          grantedOrigins: Array.isArray(added?.origins) ? added.origins : [],
        })
      )
      .catch(() => {})
  );
  return { lifecycle, router };
}

/** Exactly what the popup writes under the user gesture, before the request. */
async function popupWritesIntent(browser, { origin = ORIGIN, tabId = 42, createdAt = Date.now() } = {}) {
  await browser.storage.session.set({ [INTENT_KEY]: { origin, tabId, createdAt } });
}

function enabledOrigins(browser) {
  return browser.config()?.enabledOrigins ?? [];
}

test("macOS race: grant → popup dies before setSiteState → onAdded intent finishes the enable end-to-end", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  // Popup: intent under gesture, then the request. The popup then DIES —
  // no setSiteState is ever dispatched in this test.
  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);

  // The origin is durably enabled without any popup message.
  assert.deepEqual(enabledOrigins(browser), [ORIGIN]);
  // The intent was burned.
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
  // The permission survived and the real content path is served end-to-end.
  assert.equal(await browser.permissions.contains({ origins: [PATTERN] }), true);
  const bootstrap = await router.dispatch(
    overlayMessage("bootstrap", { origin: ORIGIN }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );
  assert.equal(bootstrap.ok, true, "content bootstrap must be served");
  assert.equal(bootstrap.enabled, true);
});

test("the enabled origin comes from the intent, never from the granted pattern (port survives)", async () => {
  const portedOrigin = "https://example.com:8443";
  // Precondition of the whole property: the pattern loses the port.
  assert.equal(security.permissionPatternForOrigin(portedOrigin), PATTERN);

  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await popupWritesIntent(browser, { origin: portedOrigin });
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);

  // EXACTLY the intent's origin — the pattern-derived (port-stripped) origin
  // must not be authorized.
  assert.deepEqual(enabledOrigins(browser), [portedOrigin]);
  assert.equal(enabledOrigins(browser).includes(ORIGIN), false);
});

test("expired intent: nothing is enabled, the intent is deleted", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await popupWritesIntent(browser, {
    createdAt: Date.now() - security.ENABLE_INTENT_TTL_MS - 1,
  });
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);

  assert.deepEqual(enabledOrigins(browser), []);
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
});

test("TTL boundary is exact and clock-skew is refused (direct consume)", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);

  // Exactly at the TTL edge: still valid.
  await popupWritesIntent(browser, { createdAt: 1000 });
  const atEdge = await lifecycle.consumeEnableIntent({
    grantedOrigins: [PATTERN],
    now: 1000 + security.ENABLE_INTENT_TTL_MS,
  });
  assert.equal(atEdge.ok, true);

  // A createdAt from the future is not "fresh", it is refused.
  await lifecycle.disableOrigin({ origin: ORIGIN });
  await popupWritesIntent(browser, { createdAt: 5000 });
  const fromFuture = await lifecycle.consumeEnableIntent({
    grantedOrigins: [PATTERN],
    now: 4999,
  });
  assert.equal(fromFuture.ok, false);
  assert.equal(fromFuture.error, "expired_intent");
  assert.deepEqual(enabledOrigins(browser), []);
});

test("garbage intent: deleted, nothing enabled, no throw", async () => {
  const garbageValues = [
    null,
    "https://example.com",
    { origin: ORIGIN }, // missing keys
    { origin: ORIGIN, tabId: 42, createdAt: Date.now(), extra: true }, // extra key
    { origin: "not-an-origin", tabId: 42, createdAt: Date.now() },
    { origin: "https://example.com/path", tabId: 42, createdAt: Date.now() }, // non-canonical
    { origin: ORIGIN, tabId: "42", createdAt: Date.now() }, // wrong type
    { origin: ORIGIN, tabId: 42, createdAt: "now" },
  ];
  for (const garbage of garbageValues) {
    const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
    const { lifecycle } = makeWorker(browser);
    await lifecycle.ready();

    await browser.storage.session.set({ [INTENT_KEY]: garbage });
    await browser.permissions.request({ origins: [PATTERN] });
    await Promise.all(browser.permissionEvents);

    assert.deepEqual(enabledOrigins(browser), [], JSON.stringify(garbage));
    assert.equal(
      browser.sessionStore[INTENT_KEY],
      undefined,
      `garbage must be deleted: ${JSON.stringify(garbage)}`
    );
  }
});

test("grant for a different pattern than the intent's origin enables nothing", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  // Intent names example.com, but the grant that lands is for another site
  // (e.g. the user answered a different prompt in the meantime).
  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: ["https://other.example/*"] });
  await Promise.all(browser.permissionEvents);

  assert.deepEqual(enabledOrigins(browser), []);
  // One-shot even on refusal: the intent must not lie in wait for a later
  // unrelated grant.
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
});

test("replay: a second onAdded finds no intent and re-enables nothing", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);
  assert.deepEqual(enabledOrigins(browser), [ORIGIN]);

  // User turns the site off through the production route.
  const disabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: false }),
    extensionPageSender()
  );
  assert.equal(disabled.ok, true);
  assert.deepEqual(enabledOrigins(browser), []);

  // A later grant fires onAdded again. The intent was burned — no re-enable.
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);
  assert.deepEqual(enabledOrigins(browser), []);
});

test("popup survives (Linux/Windows): intent path + setSiteState produce one coherent outcome", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  // Full popup flow: intent, request (onAdded consumes it and enables), then
  // the surviving popup's own setSiteState enable, then its intent cleanup.
  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);

  const revisionAfterIntent = browser.config().revision;
  const enabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: true }),
    extensionPageSender()
  );
  await browser.storage.session.remove(INTENT_KEY); // popup's clearEnableIntent()

  assert.equal(enabled.ok, true);
  assert.equal(enabled.state, "enabled");
  assert.deepEqual(enabledOrigins(browser), [ORIGIN]);
  // enableOrigin is idempotent: the second completion commits nothing, so the
  // double path never produces a visible double revision bump.
  assert.equal(browser.config().revision, revisionAfterIntent);
});

test("worker restart between grant and consume: the intent survives in storage.session", async () => {
  // The reason the intent lives in storage.session and not in a worker
  // variable: MV3 kills the worker at will, and on macOS the grant lands
  // while no worker is necessarily alive. Chrome then WAKES a fresh worker
  // to deliver permissions.onAdded — modelled here as a new lifecycle against
  // the same fake, with ZERO listeners installed at grant time.
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [PATTERN] }); // no listener runs

  // Cold worker wakes for the event: exactly the background.js listener body.
  const { lifecycle } = makeWorker(browser);
  await lifecycle.reconcile({ prunePermissions: false });
  const result = await lifecycle.consumeEnableIntent({ grantedOrigins: [PATTERN] });

  assert.equal(result.ok, true);
  assert.deepEqual(enabledOrigins(browser), [ORIGIN]);
  assert.equal(browser.sessionStore[INTENT_KEY], undefined, "intent burned");
});

test("no intent stored: onAdded behaviour is identical to before the fix", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await browser.permissions.request({ origins: [PATTERN] });
  await Promise.all(browser.permissionEvents);

  // Nothing was enabled by the listener alone...
  assert.deepEqual(enabledOrigins(browser), []);
  // ...and the fresh permission was not revoked, so the popup's own
  // setSiteState (A2-M15 property) still completes.
  const enabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, origin: ORIGIN, enabled: true }),
    extensionPageSender()
  );
  assert.equal(enabled.ok, true);
  assert.equal(enabled.state, "enabled");
});
