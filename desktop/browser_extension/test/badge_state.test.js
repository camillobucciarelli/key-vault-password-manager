// Spec 007 badge state machine — the `chrome.action` paint half.
//
// `refreshBadgeForTab` awaits a native-host ping BEFORE it paints, so the tab
// it is painting can be closed while that await is in flight. Chrome then
// rejects the per-tab `chrome.action` call with "No tab with id: N." and the
// console shows an unchecked `runtime.lastError` — observed live during the
// spec 007 smoke.
//
// These tests pin BOTH halves of the fix, because only the pair is a fix
// rather than a patch:
//   (a) the tab-gone rejection is swallowed and the rest of the refresh runs;
//   (b) any OTHER rejection from the very same API still propagates.
// Without (b), "swallow the rejection" is indistinguishable from "hide every
// chrome.action bug", and the mutation BADGE-M1 below proves the difference.
//
// The worker is loaded exactly as MV3 loads it (one shared global scope via
// `importScripts`, the worker_global_scope.test.js pattern), so the functions
// under test are the shipped ones, reached as globals of that scope.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const { FakeBrowser } = require("./fake_browser.js");

const EXTENSION_ROOT = path.join(__dirname, "..");

/**
 * Boots `background.js` against a FakeBrowser, plus the worker wiring the
 * badge code does not exercise (event listener registration, native
 * transport). Nothing here decides badge policy — that all lives in the
 * shipped file.
 *
 * @param {object} options
 * @param {Array<{id:number}>} options.tabs   Open tabs.
 * @param {object} options.status             Native `status` response payload.
 */
function bootWorker({ tabs = [{ id: 1 }], status = null } = {}) {
  const browser = new FakeBrowser({ tabs });
  const noopEvent = () => ({ addListener() {} });

  const chrome = {
    storage: browser.storage,
    permissions: Object.assign(browser.permissions, {
      onRemoved: noopEvent(),
    }),
    scripting: browser.scripting,
    action: browser.action,
    tabs: Object.assign(browser.tabs, {
      onActivated: noopEvent(),
      onUpdated: noopEvent(),
      onRemoved: noopEvent(),
    }),
    runtime: {
      id: "kv-test-extension",
      lastError: undefined,
      onStartup: noopEvent(),
      onInstalled: noopEvent(),
      onMessage: noopEvent(),
      getURL: (p) => `chrome-extension://kv-test-extension/${p}`,
      sendNativeMessage(_host, request, callback) {
        // Resolved on a later microtask: this is the window during which the
        // tab can be closed, which is exactly the race under test.
        Promise.resolve().then(() =>
          callback(
            status === null
              ? undefined
              : { version: 2, id: request.id, type: request.type, ...status }
          )
        );
      },
    },
  };

  const sandbox = {
    chrome,
    crypto: require("node:crypto").webcrypto,
    console,
    setTimeout,
    clearTimeout,
    URL,
    TextEncoder,
    TextDecoder,
    // The dim-icon path composites the shipped PNGs at runtime (see the
    // ponytail note in background.js). None of that is under test here, so
    // the graphics stack is stubbed to the smallest shape it consumes — the
    // assertions only ever look at which chrome.action calls were made.
    fetch: async () => ({ blob: async () => ({}) }),
    createImageBitmap: async () => ({}),
    OffscreenCanvas: class {
      getContext() {
        return { drawImage() {}, getImageData: () => ({}) };
      }
    },
  };
  const context = vm.createContext(sandbox);
  const runFile = (name) =>
    vm.runInContext(fs.readFileSync(path.join(EXTENSION_ROOT, name), "utf8"), context, {
      filename: name,
    });
  sandbox.importScripts = (...names) => names.forEach(runFile);
  sandbox.self = context;
  runFile("background.js");

  return { browser, worker: context };
}

/** A host that is reachable with the vault connected: the "count" branch. */
const HOST_UNLOCKED = { ok: true, data: { vault: { connected: true } } };

// ---------------------------------------------------------------------------
// (c) No regression: the existing states still paint on a LIVE tab.
// ---------------------------------------------------------------------------

test("007: a live tab still paints the match-count badge end to end", async () => {
  const { browser, worker } = bootWorker({ status: HOST_UNLOCKED });

  await worker.setTabMatchCount(1, 3);

  assert.deepEqual(browser.badges.get(1), {
    text: "3",
    color: "#aebf92",
    textColor: "#272e1b",
  });
  assert.deepEqual(browser.actionApisFor(1), [
    "setIcon",
    "setBadgeText",
    "setBadgeBackgroundColor",
    "setBadgeTextColor",
  ]);
});

test("007: an unreachable host still paints the dim host-missing badge", async () => {
  // `status: null` makes sendNativeMessage answer with no response at all,
  // which the worker maps to hostReachable=false.
  const { browser, worker } = bootWorker({ status: null });

  await worker.refreshBadgeForTab(1);

  assert.equal(browser.badges.get(1).text, " ");
  assert.equal(browser.badges.get(1).color, "#f6a06b");
});

test("007: a reachable host with a locked vault paints the neutral badge", async () => {
  const { browser, worker } = bootWorker({
    status: { ok: true, data: { vault: { connected: false } } },
  });

  await worker.refreshBadgeForTab(1);

  assert.equal(browser.badges.get(1).text, " ");
  assert.equal(browser.badges.get(1).color, "#a19786");
});

// ---------------------------------------------------------------------------
// (a) The bug: the tab closes while the ping is in flight.
// ---------------------------------------------------------------------------

test("007: a tab closed during the host ping does not reject and does not throw", async () => {
  const { browser, worker } = bootWorker({ status: HOST_UNLOCKED });
  await worker.setTabMatchCount(1, 2);
  browser.actionCalls.length = 0;

  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on("unhandledRejection", onUnhandled);
  try {
    const inFlight = worker.refreshBadgeForTab(1);
    // The user closes the tab while the worker awaits the native ping.
    browser.closeTab(1);
    await inFlight; // must resolve, not reject
    await new Promise((resolve) => setImmediate(resolve));
  } finally {
    process.off("unhandledRejection", onUnhandled);
  }

  assert.deepEqual(unhandled, [], "no unhandled rejection may escape");
  // The rest of the refresh ran: every paint step was still attempted against
  // the (now dead) tab rather than the first rejection aborting the sequence.
  assert.deepEqual(browser.actionApisFor(1), [
    "setIcon",
    "setBadgeText",
    "setBadgeBackgroundColor",
    "setBadgeTextColor",
  ]);
});

test("007: a tab closed before the refresh even starts is a silent no-op", async () => {
  const { browser, worker } = bootWorker({ tabs: [], status: HOST_UNLOCKED });

  await worker.refreshBadgeForTab(404);

  // The paint is attempted (the worker has no cheap way to know, and a
  // pre-check would still race) — it just resolves into nothing.
  assert.deepEqual(browser.actionApisFor(404), ["setIcon", "setBadgeText"]);
  assert.equal(browser.badges.has(404), false, "nothing was painted");
});

// ---------------------------------------------------------------------------
// (b) The property that makes (a) a fix and not a blanket catch.
// ---------------------------------------------------------------------------

test("007 SECURITY-OF-SIGNAL: a non-tab-gone chrome.action failure is NOT swallowed", async () => {
  const { browser, worker } = bootWorker({ status: HOST_UNLOCKED });
  // A real API misuse through the exact same call the tab-gone catch wraps.
  browser.failNextAction = "Invalid color specification";

  await assert.rejects(
    () => worker.refreshBadgeForTab(1),
    /Invalid color specification/,
    "only the tab-gone rejection may be ignored; every other failure must stay visible"
  );
});

test("007: the guard is total — a SYNCHRONOUS chrome.action throw is filtered the same way", async () => {
  // The guard takes a thunk and invokes it inside the try, so a synchronous
  // throw and a rejection take one path. Chrome does not currently throw
  // synchronously for a dead tab (see `failNextActionSync` in the fake): this
  // pins defence in depth, and pins that the depth is NARROW — the sync path
  // must discriminate exactly like the async one, not swallow everything.
  const gone = bootWorker({ status: HOST_UNLOCKED });
  gone.browser.failNextActionSync = "No tab with id: 1.";
  await gone.worker.refreshBadgeForTab(1); // resolves: nothing to paint

  const real = bootWorker({ status: HOST_UNLOCKED });
  real.browser.failNextActionSync = "Invalid color specification";
  await assert.rejects(
    () => real.worker.refreshBadgeForTab(1),
    /Invalid color specification/,
    "a synchronous non-tab-gone throw must stay visible"
  );
});

test("007: a rejection merely MENTIONING a tab is not treated as tab-gone", async () => {
  const { browser, worker } = bootWorker({ status: HOST_UNLOCKED });
  browser.failNextAction = "Cannot access contents of the tab";

  await assert.rejects(
    () => worker.refreshBadgeForTab(1),
    /Cannot access contents of the tab/
  );
});
