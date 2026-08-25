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
// chrome.action bug", and mutation A7-M1 proves the difference.
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
// Imported, never re-spelled: a test that hardcodes the prefix or a hex blob
// would keep passing after a rename while the sanitizer silently stopped
// redacting — the exact coupling these tests exist to break.
const {
  REGISTRATION_PREFIX,
  registrationIdForPattern,
} = require("../overlay_lifecycle.js");

const EXTENSION_ROOT = path.join(__dirname, "..");

/** The origin used wherever a test needs something that must NOT reach a log. */
const SECRET_PATTERN = "https://secret.example.com/*";

/**
 * Hex digits per code point, PROBED from the shipped encoder instead of
 * assumed.
 *
 * Hardcoding 4 would couple this helper to the padding width, and A2-M14 is a
 * deliberately recorded `equivalent: true` row whose entire job is to stay
 * un-killed until IDNA support lands and its reachability argument dies. A
 * decoder that breaks on unpadded hex would consume that canary for a reason
 * having nothing to do with the property it guards.
 */
const HEX_DIGITS_PER_CHAR =
  registrationIdForPattern("a").length - REGISTRATION_PREFIX.length;
assert.ok(HEX_DIGITS_PER_CHAR > 0, "could not probe the registration encoding");

/**
 * Reverses `registrationIdForPattern`: every run of 16+ hex digits in `text`
 * is decoded back to the string it encodes. The redaction tests assert on the
 * DECODED output, not on the absence of a literal — an encoded origin that
 * survives is a leak whether or not the reader recognises it as one.
 */
function decodeHexRuns(text) {
  const width = HEX_DIGITS_PER_CHAR;
  return [...text.matchAll(/[0-9a-f]{16,}/gi)].map(([run]) => {
    let decoded = "";
    for (let i = 0; i + width <= run.length; i += width) {
      decoded += String.fromCharCode(parseInt(run.slice(i, i + width), 16));
    }
    return decoded;
  });
}

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

  /**
   * A capturing `chrome.*.onX`. The listener-boundary tests need to invoke the
   * SHIPPED listener body, not a copy of it: the defect under test lives in
   * the `.catch` those bodies attach, so a harness that re-implements the
   * wiring would assert against code the extension does not run.
   *
   * Chrome dispatches these listeners fire-and-forget — it never awaits the
   * promise a listener returns — so `fire()` reproduces that and the caller
   * drains separately.
   */
  const listeners = new Map();
  const capturingEvent = (name) => {
    listeners.set(name, []);
    return {
      addListener(fn) {
        listeners.get(name).push(fn);
      },
    };
  };

  /**
   * Every console level, not just `error`: the tab-gone case must be proven
   * SILENT, and "silent" is only meaningful if the recorder would have caught
   * a warn/log/debug too. Assertions read `consoleCalls` as [level, text].
   */
  const consoleCalls = [];
  const recordingConsole = {};
  for (const level of ["log", "info", "warn", "error", "debug", "trace"]) {
    recordingConsole[level] = (...args) =>
      consoleCalls.push([level, args.map(String).join(" ")]);
  }

  const chrome = {
    storage: browser.storage,
    permissions: Object.assign(browser.permissions, {
      onRemoved: capturingEvent("permissions.onRemoved"),
    }),
    scripting: browser.scripting,
    action: browser.action,
    tabs: Object.assign(browser.tabs, {
      onActivated: capturingEvent("tabs.onActivated"),
      onUpdated: capturingEvent("tabs.onUpdated"),
      onRemoved: capturingEvent("tabs.onRemoved"),
    }),
    runtime: {
      id: "kv-test-extension",
      lastError: undefined,
      onStartup: capturingEvent("runtime.onStartup"),
      onInstalled: capturingEvent("runtime.onInstalled"),
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
    console: recordingConsole,
    setTimeout,
    clearTimeout,
    URL,
    TextEncoder,
    TextDecoder,
  };
  const context = vm.createContext(sandbox);
  const runFile = (name) =>
    vm.runInContext(fs.readFileSync(path.join(EXTENSION_ROOT, name), "utf8"), context, {
      filename: name,
    });
  sandbox.importScripts = (...names) => names.forEach(runFile);
  sandbox.self = context;
  runFile("background.js");

  /**
   * Dispatches a captured event the way Chrome does — synchronously, ignoring
   * whatever the listener returns — then lets the fire-and-forget chain settle.
   *
   * The chain behind one badge listener is entirely microtasks (native ping,
   * two storage round trips, up to four `chrome.action` calls); the only timer
   * involved is the native timeout, which is cleared on the happy path. Turning
   * the macrotask queue a fixed number of times is therefore enough and stays
   * deterministic — no wall-clock waiting, no polling.
   */
  const fire = async (name, ...args) => {
    const registered = listeners.get(name);
    assert.ok(registered?.length, `no listener registered for ${name}`);
    for (const listener of registered) listener(...args);
    for (let turn = 0; turn < 20; turn += 1) {
      await new Promise((resolve) => setImmediate(resolve));
    }
  };

  return { browser, worker: context, fire, consoleCalls, listeners };
}

/** Only the reported failures, as plain strings. */
const reportedErrors = (consoleCalls) =>
  consoleCalls.filter(([level]) => level === "error").map(([, text]) => text);

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

// ---------------------------------------------------------------------------
// (d) The boundary. Everything above proves `refreshBadgeForTab` REJECTS on a
// real failure — but no caller in the shipped worker is a test. Every caller
// is an event listener, and each one used to end in `.catch(() => {})`, which
// threw that rejection away. The guard produced a signal; the boundary
// deleted it, which is why the badge defect survived to the manual smoke.
//
// These tests pin the boundary itself, driving the SHIPPED listener bodies:
//   - a non-tab-gone failure is REPORTED and NOT propagated;
//   - the tab-gone case stays SILENT, so the fix adds signal, not noise;
//   - nothing reported can carry an origin into the console.
// ---------------------------------------------------------------------------

test("007 SIGNAL-AT-THE-BOUNDARY: a non-tab-gone failure inside a listener is reported", async () => {
  const { browser, fire, consoleCalls } = bootWorker({ status: HOST_UNLOCKED });
  browser.failNextAction = "Invalid color specification";

  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on("unhandledRejection", onUnhandled);
  try {
    await fire("tabs.onActivated", { tabId: 1 });
  } finally {
    process.off("unhandledRejection", onUnhandled);
  }

  // Reported: the failure the guard deliberately rethrew reaches a human.
  assert.deepEqual(
    reportedErrors(consoleCalls).length,
    1,
    "the listener must report exactly one failure"
  );
  const [reported] = reportedErrors(consoleCalls);
  assert.match(reported, /Invalid color specification/);
  // ...and it says WHICH listener, so the report is actionable.
  assert.match(reported, /tabs\.onActivated/);

  // Not propagated: a listener that rejects is MV3 noise.
  assert.deepEqual(unhandled, [], "a listener must never propagate a rejection");
});

test("007 SIGNAL-AT-THE-BOUNDARY: the tab-gone case stays silent", async () => {
  // Otherwise the fix has only MOVED the noise: tab-gone is not an error, it
  // is a tab that closed, and logging it on every navigation would train
  // everyone to ignore this exact channel.
  const { browser, worker, fire, consoleCalls } = bootWorker({
    status: HOST_UNLOCKED,
  });
  await worker.setTabMatchCount(1, 2);
  browser.closeTab(1);

  await fire("tabs.onActivated", { tabId: 1 });

  assert.deepEqual(consoleCalls, [], "a closed tab must produce no output");
});

/** Drives one message through the real listener path and returns the report. */
async function reportFor(message) {
  const { browser, fire, consoleCalls } = bootWorker({ status: HOST_UNLOCKED });
  browser.failNextAction = message;
  await fire("tabs.onActivated", { tabId: 1 });
  const [reported] = reportedErrors(consoleCalls);
  assert.ok(reported, `nothing was reported for: ${message}`);
  return reported;
}

test("007 SIGNAL-AT-THE-BOUNDARY: a reported failure never carries an origin", async () => {
  // Every shape a host reaches an error message in. The scheme-less ones are
  // not hypothetical: Chrome's own complaint about a scheme-less pattern is
  // "Missing scheme separator", which quotes the bare host back at you.
  const leaks = [
    "failed https://secret.example.com/login?token=hunter2",
    "Missing scheme separator in secret.example.com:8443",
    "connect refused at localhost:8000",
    "pattern *.secret.example.com/* is not allowed",
    "bad match pattern *://*.secret.example.com/*",
    "blocked request for secret.example.com",
  ];

  for (const message of leaks) {
    const reported = await reportFor(message);
    assert.ok(
      !reported.includes("secret.example.com"),
      `an origin leaked: ${message} -> ${reported}`
    );
    assert.ok(
      !reported.includes("localhost"),
      `a scheme-less host leaked: ${message} -> ${reported}`
    );
    assert.ok(
      !reported.includes("hunter2"),
      `a query payload leaked: ${message} -> ${reported}`
    );
  }
});

test("007 SIGNAL-AT-THE-BOUNDARY: an encoded origin is unreachable by decoding the report", async () => {
  // The registration id is built with the SHIPPED encoder, so this test still
  // means something after the encoding or the prefix changes. Asserting on the
  // absence of a literal would not: the threat is that the value is
  // RECOVERABLE, not that it is recognisable.
  const id = registrationIdForPattern(SECRET_PATTERN);
  assert.ok(
    decodeHexRuns(id).includes(SECRET_PATTERN),
    "precondition: the id must really be reversible, or this test proves nothing"
  );

  // Both with the prefix and stripped of it — a bare hex run is just as
  // reversible, and the prefix rule alone would miss it.
  for (const injected of [id, id.slice(REGISTRATION_PREFIX.length)]) {
    const reported = await reportFor(`Duplicate script ID ${injected}`);
    assert.deepEqual(
      decodeHexRuns(reported),
      [],
      `a reversible hex run survived: ${reported}`
    );
    assert.ok(!reported.includes(id), `the raw id survived: ${reported}`);
    // Still useful: the operator learns what failed, just not on whom.
    assert.match(reported, /Duplicate script ID/);
  }
});

test("007 SIGNAL-AT-THE-BOUNDARY: redaction is derived from the shipped prefix constant", async () => {
  // Anti-coupling. The sanitizer reads REGISTRATION_PREFIX from
  // overlay_lifecycle.js instead of re-spelling it, so this holds by
  // construction after a rename — and the assertion is written against the
  // imported constant so it renames with it.
  const id = registrationIdForPattern(SECRET_PATTERN);
  const reported = await reportFor(`Duplicate script ID ${id}`);

  assert.match(
    reported,
    new RegExp(`${REGISTRATION_PREFIX}<redacted>`),
    `the prefix-labelled redaction did not fire: ${reported}`
  );
});

test("007 SIGNAL-AT-THE-BOUNDARY: redaction does not eat the diagnostics", async () => {
  // The opposite failure, and just as real: a report where everything is
  // <redacted> is a channel people switch off. Each of these must survive
  // VERBATIM — none of them is a host, however dotted or colon-separated.
  const mustSurvive = [
    // NOT "No tab with id: 3." — that is the tab-gone literal, which is
    // swallowed before it ever reaches the reporter.
    ["a tab id", "Frame 0 of tab 3 is not injectable", "tab 3"],
    ["a version number", "Requires Chrome 151.0.7977.54 or later", "151.0.7977.54"],
    ["a numeric code", "native host exited code:42", "code:42"],
    ["a source filename", "importScripts failed for overlay_lifecycle.js", "overlay_lifecycle.js"],
    ["an asset filename", "missing icons/icon-16.png", "icon-16.png"],
    ["a plain message", "Invalid color specification", "Invalid color specification"],
  ];

  for (const [label, message, fragment] of mustSurvive) {
    const reported = await reportFor(message);
    assert.ok(
      reported.includes(fragment),
      `${label} was over-redacted: ${message} -> ${reported}`
    );
  }
});

test("007 SIGNAL-AT-THE-BOUNDARY: the permission listeners report too, not only the badge ones", async () => {
  // Nine call sites share one reporter; a suite that only ever drives
  // tabs.onActivated would not notice eight of them going mute. This covers
  // the other family, through a real reconcile failure rather than a stub.
  const { browser, fire, consoleCalls } = bootWorker({ status: HOST_UNLOCKED });

  // A stale overlay registration that no committed config justifies: the
  // orphan sweep inside reconcile() will try to unregister it, and Chrome's
  // real failure for that call quotes the script id — which encodes an origin.
  const orphanId = registrationIdForPattern(SECRET_PATTERN);
  browser.registered.set(orphanId, { id: orphanId, matches: [SECRET_PATTERN] });
  browser.scripting.unregisterContentScripts = async ({ ids = [] } = {}) => {
    throw new Error(`Nonexistent script ID '${ids[0]}'`);
  };

  await fire("permissions.onRemoved");

  const [reported] = reportedErrors(consoleCalls);
  assert.ok(reported, "a failing reconcile must reach the console");
  assert.match(reported, /permissions\.onRemoved/);
  assert.match(reported, /Nonexistent script ID/);
  assert.deepEqual(
    decodeHexRuns(reported),
    [],
    `the orphan id was reported in reversible form: ${reported}`
  );
});

test("007 SIGNAL-AT-THE-BOUNDARY: a pathological message cannot flood the log", async () => {
  const { browser, fire, consoleCalls } = bootWorker({ status: HOST_UNLOCKED });
  browser.failNextAction = `overflow ${"A".repeat(5000)}`;

  await fire("tabs.onActivated", { tabId: 1 });

  const [reported] = reportedErrors(consoleCalls);
  assert.ok(reported.length < 300, `unbounded report: ${reported.length} chars`);
  assert.match(reported, /overflow/);
});
