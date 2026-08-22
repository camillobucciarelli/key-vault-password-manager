// 009 Gate A2 — the grant/enable race Chrome exposes and the Node fake did not.
//
// Found in manual Chrome smoke: `permissions.onAdded` fires the instant the
// user accepts the popup's `permissions.request`, BEFORE the popup's
// `setSiteState` message reaches the worker. The reconcile that listener
// triggers then sees a granted pattern that no committed config justifies,
// classifies it as an orphan, and revokes it — so `enable`'s own
// `permissions.contains` re-check (a defence pinned by mutation A2-M3) fails
// and the enable dies silently.
//
// The fix: the onAdded-triggered reconcile defers the orphan-permission sweep
// (`reconcile({ prunePermissions: false })` in background.js). That is safe
// because the durable config, never the browser permission alone, is the
// authorization source of truth — a permission without config is inert — and
// the sweep still runs on cold start, popup open, onRemoved and disable (D5).
//
// Every assertion here is observable behaviour driven through the production
// router and lifecycle: the enable response, the browser's own answer to
// `permissions.contains`, and a real content bootstrap being served.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { FakeBrowser } = require("./fake_browser.js");
const routes = require("../overlay_routes.js");
const lifecycleModule = require("../overlay_lifecycle.js");
const { OverlayLifecycle } = lifecycleModule;
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

const nativeStub = async () => ({ ok: true, data: {} });

function makeWorker(browser) {
  const lifecycle = new OverlayLifecycle({ browser });
  const router = new routes.OverlayRouter({
    lifecycle,
    runtimeId: RUNTIME_ID,
    native: nativeStub,
    legacyNative: nativeStub,
    reportMatchCount: async () => {},
  });
  // Exactly the wiring background.js installs. `reconcile()` cannot be called
  // with default arguments here or the test would assert against a policy the
  // production listener does not run.
  browser.permissions.onAdded.addListener(() =>
    lifecycle.reconcile({ prunePermissions: false }).catch(() => {})
  );
  return { lifecycle, router };
}

test("Gate A2: onAdded reconcile between grant and setSiteState does not revoke the fresh permission", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const { lifecycle, router } = makeWorker(browser);

  // Worker is warm and reconciled (popup already open) before the grant.
  await lifecycle.ready();

  // Popup flow step 1: the user accepts the permission prompt.
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });

  // Chrome fires onAdded immediately; worst case, the triggered reconcile runs
  // to completion before the popup's setSiteState message arrives. Awaiting
  // the dispatched listener work reproduces exactly that interleaving.
  await Promise.all(browser.permissionEvents);

  // Popup flow step 2: setSiteState enable, through the production route.
  const enabled = await router.dispatch(
    overlayMessage("setSiteState", { tabId: 42, enabled: true }),
    extensionPageSender()
  );
  assert.equal(enabled.ok, true, "enable must survive the onAdded reconcile");
  assert.equal(enabled.state, "enabled");

  // The permission granted seconds ago is still held — not auto-revoked.
  assert.equal(
    await browser.permissions.contains({ origins: [...GLOBAL_PATTERNS] }),
    true,
    "the just-granted permission must not be revoked as an orphan"
  );

  // And the real content path is served: an injected script on that origin
  // bootstraps successfully through the same router the extension runs.
  const bootstrap = await router.dispatch(
    overlayMessage("bootstrap", { origin: ORIGIN }),
    contentScriptSender({ frameUrl: PAGE_URL })
  );
  assert.equal(bootstrap.ok, true, "content bootstrap must be served");
  assert.equal(bootstrap.enabled, true);
});

test("Gate A2: the onAdded reconcile still reconciles everything except the permission sweep", async () => {
  // A stale overlay registration nothing justifies, plus a granted pattern
  // nothing justifies YET (the race window). The onAdded-triggered reconcile
  // must clean up the registration but leave the permission for the enable
  // that is about to arrive.
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const stale = {
    id: lifecycleModule.registrationIdForPattern("https://stale.example/*"),
    matches: ["https://stale.example/*"],
    js: ["overlay_security.js", "content_overlay.js"],
  };
  browser.registered.set(stale.id, stale);
  const { lifecycle } = makeWorker(browser);
  await lifecycle.ready();
  // ready() already pruned; re-plant the stale registration so the next
  // reconcile — the onAdded one — is the one observed doing registration
  // hygiene.
  browser.registered.set(stale.id, stale);

  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await Promise.all(browser.permissionEvents);

  assert.deepEqual(
    browser.registrationIds(),
    [],
    "orphan registrations are still removed on the onAdded trigger"
  );
  assert.equal(
    await browser.permissions.contains({ origins: [...GLOBAL_PATTERNS] }),
    true,
    "the fresh permission is retained on the onAdded trigger"
  );
});

test("A020/A2-M9 regression: cold-start reconcile still removes truly orphan permissions", async () => {
  // A pattern granted with no committed config behind it — e.g. left behind by
  // the deferred onAdded sweep after the popup died before setSiteState. It is
  // inert (no config authorizes it), and the next cold start cleans it up.
  const browser = new FakeBrowser({
    granted: [PATTERN],
    storage: {
      [security.OVERLAY_CONFIG_KEY]: {
        version: 2,
        revision: 3,
        enabled: false,
      },
      [security.OVERLAY_REVISION_FLOOR_KEY]: 3,
    },
  });
  const lifecycle = new OverlayLifecycle({ browser });
  await lifecycle.ready();

  assert.equal(
    await browser.permissions.contains({ origins: [PATTERN] }),
    false,
    "an orphan permission must not survive a cold-start reconcile"
  );
});
