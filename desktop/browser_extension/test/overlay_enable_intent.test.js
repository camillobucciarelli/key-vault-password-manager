// macOS grant race — the pending enable intent (popup dies at the prompt).
//
// Confirmed in manual smoke and by a user report: on macOS the OS-level
// permission dialog CLOSES the popup, so the continuation after
// `chrome.permissions.request` — the one that sends `setSiteState enable` —
// never runs. The first Allow left the site Off; only a second click (which
// found the permission already granted, no prompt) completed the enable.
//
// The fix: the popup writes a durable one-shot intent `{tabId, createdAt}` to
// `chrome.storage.session` UNDER THE GESTURE, before the request. The worker's
// `permissions.onAdded` listener — after its existing
// `reconcile({ prunePermissions: false })` — consumes the intent and finishes
// the enable through the SAME `enable` path the popup uses.
//
// SLICE C: the intent no longer carries an `origin`, because there is no
// per-site decision left to carry. The cross-check that replaces "the grant
// must cover the intent's origin" is "the grant must cover the WHOLE broad
// pair" — a narrower grant, whatever the user actually answered, enables
// nothing.
//
// Security properties pinned here (and by mutations A2-M17..M19):
//   - the grant that lands must cover the whole broad set;
//   - the intent is one-shot, burned before use (replay-proof);
//   - expired or garbage intents are deleted and never acted on;
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
const GLOBAL_PATTERNS = [...security.GLOBAL_PERMISSION_PATTERNS];
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
async function popupWritesIntent(browser, { tabId = 42, createdAt = Date.now() } = {}) {
  await browser.storage.session.set({ [INTENT_KEY]: { tabId, createdAt } });
}

function isEnabled(browser) {
  return browser.config()?.enabled === true;
}

test("macOS race: grant → popup dies before setSiteState → onAdded intent finishes the enable end-to-end", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  // Popup: intent under gesture, then the request. The popup then DIES —
  // no setSiteState is ever dispatched in this test.
  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  // The origin is durably enabled without any popup message.
  assert.equal(isEnabled(browser), true);
  // The intent was burned.
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
  // The permission survived and the real content path is served end-to-end.
  assert.equal(await browser.permissions.contains({ origins: [...GLOBAL_PATTERNS] }), true);
  const bootstrap = await router.dispatch(
    overlayMessage("bootstrap", { origin: ORIGIN }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );
  assert.equal(bootstrap.ok, true, "content bootstrap must be served");
  assert.equal(bootstrap.enabled, true);
});

// SLICE C SUBSTITUTION for "the enabled origin comes from the intent, never
// from the granted pattern (port survives)". That property existed because a
// Chromium pattern loses the port, so deriving the origin from the granted
// pattern would have enabled `https://example.com` when the user asked for
// `https://example.com:8443`. The intent carries no origin now, so there is
// nothing to derive and nothing to confuse.
//
// The check that inherits its job is grant sufficiency: the event must carry
// the WHOLE broad pair before the intent is honoured. A narrower grant — a
// leftover per-origin pattern, half the pair, or a grant the user accepted for
// some unrelated prompt — enables nothing, and the intent is still burned so
// it cannot lie in wait for a later, wider grant.
test("a grant narrower than the broad pair enables nothing and still burns the intent", async () => {
  for (const granted of [
    [PATTERN],
    ["http://*/*"],
    ["https://*/*"],
    ["https://other.example/*"],
  ]) {
    const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
    const { lifecycle } = makeWorker(browser);
    await lifecycle.ready();

    await popupWritesIntent(browser);
    await browser.permissions.request({ origins: granted });
    await Promise.all(browser.permissionEvents);

    assert.equal(
      isEnabled(browser),
      false,
      `granted=${JSON.stringify(granted)} must not enable`
    );
    assert.equal(
      browser.sessionStore[INTENT_KEY],
      undefined,
      `granted=${JSON.stringify(granted)} must still burn the intent`
    );
  }
});

// The isolating case for grant sufficiency.
//
// In the test above, `enable`'s own `permissions.contains` re-check would have
// refused anyway, so it cannot tell whether the intent path checked anything.
// Here the broad grant IS already held — the user had granted it earlier, or
// set "On all sites" by hand — and an UNRELATED grant event arrives while a
// stale intent is sitting in session storage. Nothing downstream will object,
// so the event-vs-intent cross-check is the only thing that can refuse, and it
// must: a prompt the user answered for some other site is not consent to turn
// this switch on.
test("an unrelated grant event never flips the switch, even with the broad grant held", async () => {
  const browser = new FakeBrowser({
    granted: [...GLOBAL_PATTERNS],
    tabs: [{ id: 42 }],
  });
  // Deliberately NOT `ready()`: a full reconcile would sweep the unjustified
  // broad grant and the test would prove nothing. The production listener runs
  // `reconcile({ prunePermissions: false })`, which by design leaves a freshly
  // granted permission in place — that is the exact window this covers.
  makeWorker(browser);

  await popupWritesIntent(browser);
  // The user accepts a prompt for something else entirely.
  await browser.permissions.request({ origins: ["https://other.example/*"] });
  await Promise.all(browser.permissionEvents);

  assert.equal(
    isEnabled(browser),
    false,
    "a grant the user gave for another site must not enable the overlay"
  );
  assert.equal(browser.sessionStore[INTENT_KEY], undefined, "intent still burned");
});

// A Slice A2 intent, left in storage.session by an older popup across an
// extension update, is not a valid v2 intent and must be discarded rather than
// interpreted. It would otherwise be the one place a stale per-origin decision
// could still reach a global enable.
test("a Slice A2 {origin, tabId, createdAt} intent is refused, not reinterpreted", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await browser.storage.session.set({
    [INTENT_KEY]: { origin: ORIGIN, tabId: 42, createdAt: Date.now() },
  });
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  assert.equal(isEnabled(browser), false);
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
});

test("expired intent: nothing is enabled, the intent is deleted", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await popupWritesIntent(browser, {
    createdAt: Date.now() - security.ENABLE_INTENT_TTL_MS - 1,
  });
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  assert.equal(isEnabled(browser), false);
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
});

test("TTL boundary is exact and clock-skew is refused (direct consume)", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  // Exactly at the TTL edge: still valid.
  await popupWritesIntent(browser, { createdAt: 1000 });
  const atEdge = await lifecycle.consumeEnableIntent({
    grantedOrigins: [...GLOBAL_PATTERNS],
    now: 1000 + security.ENABLE_INTENT_TTL_MS,
  });
  assert.equal(atEdge.ok, true);

  // A createdAt from the future is not "fresh", it is refused.
  await lifecycle.disable();
  await popupWritesIntent(browser, { createdAt: 5000 });
  const fromFuture = await lifecycle.consumeEnableIntent({
    grantedOrigins: [...GLOBAL_PATTERNS],
    now: 4999,
  });
  assert.equal(fromFuture.ok, false);
  assert.equal(fromFuture.error, "expired_intent");
  assert.equal(isEnabled(browser), false);
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
    await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
    await Promise.all(browser.permissionEvents);

    assert.equal(isEnabled(browser), false, JSON.stringify(garbage));
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

  assert.equal(isEnabled(browser), false);
  // One-shot even on refusal: the intent must not lie in wait for a later
  // unrelated grant.
  assert.equal(browser.sessionStore[INTENT_KEY], undefined);
});

test("replay: a second onAdded finds no intent and re-enables nothing", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);
  assert.equal(isEnabled(browser), true);

  // User turns the site off through the production route.
  const disabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, enabled: false }),
    extensionPageSender()
  );
  assert.equal(disabled.ok, true);
  assert.equal(isEnabled(browser), false);

  // A later grant fires onAdded again. The intent was burned — no re-enable.
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);
  assert.equal(isEnabled(browser), false);
});

test("popup survives (Linux/Windows): intent path + setSiteState produce one coherent outcome", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  // Full popup flow: intent, request (onAdded consumes it and enables), then
  // the surviving popup's own setSiteState enable, then its intent cleanup.
  await popupWritesIntent(browser);
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  const revisionAfterIntent = browser.config().revision;
  const enabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, enabled: true }),
    extensionPageSender()
  );
  await browser.storage.session.remove(INTENT_KEY); // popup's clearEnableIntent()

  assert.equal(enabled.ok, true);
  assert.equal(enabled.state, "enabled");
  assert.equal(isEnabled(browser), true);
  // enable is idempotent: the second completion commits nothing, so the
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
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] }); // no listener runs

  // Cold worker wakes for the event: exactly the background.js listener body.
  const { lifecycle } = makeWorker(browser);
  await lifecycle.reconcile({ prunePermissions: false });
  const result = await lifecycle.consumeEnableIntent({ grantedOrigins: [...GLOBAL_PATTERNS] });

  assert.equal(result.ok, true);
  assert.equal(isEnabled(browser), true);
  assert.equal(browser.sessionStore[INTENT_KEY], undefined, "intent burned");
});

test("no intent stored: onAdded behaviour is identical to before the fix", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { router, lifecycle } = makeWorker(browser);
  await lifecycle.ready();

  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  // Nothing was enabled by the listener alone...
  assert.equal(isEnabled(browser), false);
  // ...and the fresh permission was not revoked, so the popup's own
  // setSiteState (A2-M15 property) still completes.
  const enabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, enabled: true }),
    extensionPageSender()
  );
  assert.equal(enabled.ok, true);
  assert.equal(enabled.state, "enabled");
});
