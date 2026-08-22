// 009 Slice A2 — A021. Deterministic crash injection across the disable
// transaction.
//
// SR-8 claims the disable is crash-consistent, not best-effort. A claim like
// that is only worth the test that tries to break it, so every phase boundary
// gets a fault, the worker is thrown away, a cold worker reconciles, and the
// terminal state must be byte-identical to the clean run.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { FakeBrowser } = require("./fake_browser.js");
const security = require("../overlay_security.js");
const {
  OverlayLifecycle,
  DISABLE_PHASES,
  GLOBAL_REGISTRATION_ID,
} = require("../overlay_lifecycle.js");

const CONFIG_KEY = security.OVERLAY_CONFIG_KEY;
const RUNTIME_ID = "abcdefghijklmnopabcdefghijklmnop";

const HTTPS_EXAMPLE = "https://example.com";
const HTTPS_EXAMPLE_8443 = "https://example.com:8443";
const GLOBAL_PATTERNS = security.GLOBAL_PERMISSION_PATTERNS;

class SimulatedWorkerCrash extends Error {}

/**
 * Durable browser state with `origins` already enabled, exactly as a healthy
 * worker would have left it.
 */
async function browserWithEnabled() {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }, { id: 2 }] });
  const worker = new OverlayLifecycle({ browser });
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  await worker.enable({ tabId: 1 });
  browser.calls.length = 0;
  browser.deliveredTeardowns.length = 0;
  return browser;
}

/** Everything a later worker can observe. Two runs must agree on all of it. */
async function terminalState(browser) {
  return {
    config: browser.config(),
    registrations: browser.registrationIds(),
    permissions: browser.grantedPatterns(),
  };
}

function bootstrapFrom(worker, frameUrl) {
  return worker.authorizeBootstrap({
    message: {
      channel: security.CHANNEL,
      version: security.MESSAGE_VERSION,
      type: "bootstrap",
      origin: security.canonicalOriginOrNull(frameUrl),
    },
    sender: {
      id: RUNTIME_ID,
      url: frameUrl,
      frameId: 0,
      tab: { id: 1, url: frameUrl },
    },
    runtimeId: RUNTIME_ID,
  });
}

// ---------------------------------------------------------------------------

test("A021: the clean disable and every crashed disable reach one terminal state", async (t) => {
  const clean = await browserWithEnabled();
  await new OverlayLifecycle({ browser: clean }).disable();
  const expected = await terminalState(clean);

  // Sanity: the clean run really did revoke everything.
  assert.deepEqual(expected.config.enabled, false);
  assert.deepEqual(expected.registrations, []);
  assert.deepEqual(expected.permissions, []);

  for (const phase of DISABLE_PHASES) {
    await t.test(`crash after ${phase}`, async () => {
      const browser = await browserWithEnabled();
      const dying = new OverlayLifecycle({
        browser,
        onFault: (completed) => {
          if (completed === phase) throw new SimulatedWorkerCrash(completed);
        },
      });

      await assert.rejects(
        () => dying.disable(),
        SimulatedWorkerCrash
      );

      // The worker is dead from here on. Authorization must already be gone,
      // before any cleanup has had a chance to run.
      assert.deepEqual(
        browser.config().enabled,
        false,
        "durable commit must precede every cleanup phase"
      );

      // Cold start.
      const restarted = new OverlayLifecycle({ browser });
      await restarted.ready();

      assert.deepEqual(await terminalState(browser), expected);
      assert.equal((await bootstrapFrom(restarted, "https://example.com/login")).ok, false);
    });
  }
});

test("A021: after D1 the origin is denied even with permission and script still live", async () => {
  const browser = await browserWithEnabled();
  const dying = new OverlayLifecycle({
    browser,
    onFault: (phase) => {
      if (phase === "D1") throw new SimulatedWorkerCrash(phase);
    },
  });

  await assert.rejects(() => dying.disable(), SimulatedWorkerCrash);

  // Residue is deliberately still present at this point...
  assert.deepEqual(browser.grantedPatterns(), [...GLOBAL_PATTERNS].sort());
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
  // ...and buys the page nothing, because the durable config already says no.
  const restarted = new OverlayLifecycle({ browser });
  const denied = await bootstrapFrom(restarted, "https://example.com/login");
  assert.equal(denied.ok, false);
});

test("A021: a crash mid-disable never reinstates a higher-revision authorization", async () => {
  const browser = await browserWithEnabled();
  const before = browser.config().revision;

  const dying = new OverlayLifecycle({
    browser,
    onFault: (phase) => {
      if (phase === "D2") throw new SimulatedWorkerCrash(phase);
    },
  });
  await assert.rejects(() => dying.disable(), SimulatedWorkerCrash);
  assert.equal(browser.config().revision, before + 1);

  await new OverlayLifecycle({ browser }).ready();
  assert.equal(browser.config().revision >= before + 1, true);
  assert.equal(browser.config().enabled, false);
});

// SLICE C RETIREMENT. "A021: a shared pattern survives every crash phase of a
// sibling port disable" is gone. It pinned refcounting across a crash: with two
// ports of one host enabled, disabling one had to keep the permission and the
// registration the other still needed, at every fault point. Under one global
// switch there is no sibling to preserve and no refcount to get wrong — the
// disable converges on "nothing granted, nothing registered" by construction,
// which the first test in this file already checks at every phase.
//
// What replaces it is the property that grew rather than shrank: after a
// crashed disable and a cold start, NO origin may bootstrap. Slice A2 only had
// to prove that for the one origin being disabled; Slice C has to prove it for
// every origin the broad grant used to cover.
test("A021: after a crashed disable and a cold start, no origin bootstraps", async (t) => {
  for (const phase of DISABLE_PHASES) {
    await t.test(`crash after ${phase} denies every origin`, async () => {
      const browser = await browserWithEnabled();
      const dying = new OverlayLifecycle({
        browser,
        onFault: (completed) => {
          if (completed === phase) throw new SimulatedWorkerCrash(completed);
        },
      });
      await assert.rejects(() => dying.disable(), SimulatedWorkerCrash);

      const restarted = new OverlayLifecycle({ browser });
      await restarted.ready();

      for (const frameUrl of [
        "https://example.com/login",
        "https://example.com:8443/login",
        "http://example.com/login",
        "https://unrelated.test/login",
      ]) {
        assert.equal(
          (await bootstrapFrom(restarted, frameUrl)).ok,
          false,
          `${frameUrl} must be denied after a crash at ${phase}`
        );
      }
    });
  }
});

test("A021: an unreachable injected document cannot block or survive the revoke", async () => {
  const browser = await browserWithEnabled();
  // The document is gone, frozen, or simply has no listener: teardown delivery
  // fails. JavaScript already running in a page cannot be unloaded at all.
  browser.tabs.sendMessage = async () => {
    throw new Error("Could not establish connection. Receiving end does not exist.");
  };

  const worker = new OverlayLifecycle({ browser });
  const result = await worker.disable();

  assert.equal(result.ok, true);
  assert.equal(browser.config().enabled, false);
  assert.deepEqual(browser.registrationIds(), []);
  assert.deepEqual(browser.grantedPatterns(), []);
  // The still-running script is denied at the boundary it cannot bypass.
  assert.equal((await bootstrapFrom(worker, "https://example.com/login")).ok, false);
});

test("A021: cleanup left behind by a crash is finished by an unrelated later cold start", async () => {
  const browser = await browserWithEnabled();
  const dying = new OverlayLifecycle({
    browser,
    onFault: (phase) => {
      if (phase === "D3") throw new SimulatedWorkerCrash(phase);
    },
  });
  await assert.rejects(() => dying.disable(), SimulatedWorkerCrash);
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);

  // Several cold starts later, with no disable call in sight.
  for (let restart = 0; restart < 3; restart += 1) {
    await new OverlayLifecycle({ browser }).ready();
  }

  assert.deepEqual(browser.registrationIds(), []);
  assert.deepEqual(browser.grantedPatterns(), []);
});

test("A021: a crash before the durable commit leaves the site fully enabled", async () => {
  // The inverse guarantee: an aborted disable must not half-revoke. A user who
  // sees "on" still has a working, permitted, registered site.
  const browser = await browserWithEnabled();
  browser.failNextSet = "simulated storage failure";

  const worker = new OverlayLifecycle({ browser });
  await assert.rejects(() => worker.disable());

  const restarted = new OverlayLifecycle({ browser });
  await restarted.ready();

  assert.equal(browser.config().enabled, true);
  assert.deepEqual(browser.grantedPatterns(), [...GLOBAL_PATTERNS].sort());
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
  assert.equal((await bootstrapFrom(restarted, "https://example.com/login")).ok, true);
});

test("A021: durable state stays valid after a crash at every phase", async (t) => {
  for (const phase of DISABLE_PHASES) {
    await t.test(`config remains schema-valid after ${phase}`, async () => {
      const browser = await browserWithEnabled();
      const dying = new OverlayLifecycle({
        browser,
        onFault: (completed) => {
          if (completed === phase) throw new SimulatedWorkerCrash(completed);
        },
      });
      await assert.rejects(
        () => dying.disable(),
        SimulatedWorkerCrash
      );
      const stored = browser.store[CONFIG_KEY];
      assert.equal(security.validateOverlayConfig(stored).ok, true);
      assert.equal(stored.enabled, false);
    });
  }
});
