// 009 Slice A2 — behavioural tests for `content_overlay.js`.
//
// This is the one extension file that executes inside a page the user does not
// control. Until now it was covered only by `node --check` and by four
// allowlist assertions that matched its *file name*, which proves it is
// packaged and parses, and nothing whatsoever about what it does.
//
// Everything below drives the shipped file through `test/fake_page.js`, which
// evaluates it in a fresh isolated-world global exactly as Chromium would.
// The three properties under test are the three the file actually owns:
//
//   1. the idempotence guard  — one bootstrap per document, ever;
//   2. the exact-origin gate  — a document Chromium injected but the config
//      never authorized attaches nothing;
//   3. approval ordering      — no listener exists before an explicit `ok`.
//
// Several tests answer `bootstrap` with a real `OverlayLifecycle` rather than a
// canned reply, because the port case is only meaningful end to end: a
// Chromium match pattern cannot express a port, so `https://example.com:8443`
// IS injected whenever `https://example.com` is enabled, and the whole of its
// inertness lives in these two files agreeing.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { FakePage } = require("./fake_page.js");
const { FakeBrowser } = require("./fake_browser.js");
const security = require("../overlay_security.js");
const { OverlayLifecycle } = require("../overlay_lifecycle.js");

const RUNTIME_ID = "abcdefghijklmnopabcdefghijklmnop";

const HTTPS_EXAMPLE = "https://example.com";
const HTTPS_EXAMPLE_8443 = "https://example.com:8443";
const HTTP_EXAMPLE = "http://example.com";

const APPROVED = Object.freeze({
  ok: true,
  type: "bootstrapResult",
  enabled: true,
  revision: 3,
});

function teardownMessage(revision = 4) {
  return {
    channel: security.CHANNEL,
    version: security.MESSAGE_VERSION,
    type: "teardown",
    revision,
  };
}

/**
 * A world whose background is the real lifecycle worker, with `origins`
 * already opted in. `sender` is synthesised from the page URL the way Chromium
 * stamps it, so `validateContentScriptRequest` sees a genuine sender.
 */
async function pageBackedByWorker(url, enabledOrigins) {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }] });
  const worker = new OverlayLifecycle({ browser });
  for (const origin of enabledOrigins) {
    await browser.permissions.request({
      origins: [security.permissionPatternForOrigin(origin)],
    });
    await worker.enableOrigin({ origin, tabId: 1 });
  }

  const page = new FakePage({ url });
  page.respond = (message) =>
    worker.authorizeBootstrap({
      message,
      sender: {
        id: RUNTIME_ID,
        url: page.url,
        frameId: 0,
        tab: { id: 1, url: page.url },
      },
      runtimeId: RUNTIME_ID,
    });
  return { page, worker, browser };
}

// ---------------------------------------------------------------------------
// Idempotence guard.
// ---------------------------------------------------------------------------

test("content_overlay: a double injection bootstraps exactly once", async () => {
  const page = new FakePage({ url: "https://example.com/login", respond: async () => APPROVED });

  // The registered content script and the explicit `executeScript` the enable
  // path fires both hit the same document. This is the normal case, not an
  // edge case.
  await page.inject();
  await page.inject();

  assert.equal(page.sentOfType("bootstrap").length, 1);
  assert.equal(page.listenerCount, 1);
  assert.equal(page.guarded, true);
});

test("content_overlay: the guard blocks the second run before it sends anything", async () => {
  const page = new FakePage({ url: "https://example.com/login", respond: async () => APPROVED });

  await page.inject();
  const sentAfterFirst = page.sent.length;
  for (let run = 0; run < 5; run += 1) await page.inject();

  assert.equal(page.sent.length, sentAfterFirst);
  assert.equal(page.listenerCount, 1);
});

test("content_overlay: a released guard lets a later valid enable bootstrap again", async () => {
  const page = new FakePage({ url: "https://example.com/login", respond: async () => APPROVED });
  await page.inject();
  assert.equal(page.listenerCount, 1);

  // Disable: the background now refuses, so the teardown revalidation drops
  // the listener and releases the guard.
  page.respond = async () => ({ ok: false, error: { code: "disabled" } });
  await page.deliver(teardownMessage());
  assert.equal(page.listenerCount, 0);
  assert.equal(page.guarded, false);

  // Re-enable and re-inject: the document must be able to come back.
  page.respond = async () => APPROVED;
  await page.inject();
  assert.equal(page.listenerCount, 1);
  assert.equal(page.guarded, true);
});

// ---------------------------------------------------------------------------
// Exact-origin gate.
// ---------------------------------------------------------------------------

test("content_overlay: an injected non-enabled port attaches no listener", async () => {
  // Chromium injects this document because `https://example.com/*` is the only
  // pattern it can express. Nothing but the exact-origin check keeps it inert.
  const { page } = await pageBackedByWorker(
    "https://example.com:8443/login",
    [HTTPS_EXAMPLE]
  );

  await page.inject();

  assert.deepEqual(page.sentOfType("bootstrap").map((m) => m.origin), [
    HTTPS_EXAMPLE_8443,
  ]);
  assert.equal(page.listenerCount, 0);
  assert.equal(page.guarded, false);
});

test("content_overlay: the enabled port on the same host does attach", async () => {
  const { page } = await pageBackedByWorker("https://example.com/login", [HTTPS_EXAMPLE]);

  await page.inject();

  assert.equal(page.listenerCount, 1);
  assert.equal(page.guarded, true);
});

test("content_overlay: a sibling scheme and a suffix lookalike both stay inert", async () => {
  for (const url of [
    "http://example.com/login",
    "https://example.com.evil.test/login",
    "https://evil.test/?next=https://example.com",
  ]) {
    const { page } = await pageBackedByWorker(url, [HTTPS_EXAMPLE]);
    await page.inject();
    assert.equal(page.listenerCount, 0, url);
    assert.equal(page.guarded, false, url);
  }
});

test("content_overlay: the bootstrap claims this document's own exact origin", async () => {
  for (const [url, expected] of [
    ["https://example.com/login?a=b#c", HTTPS_EXAMPLE],
    ["https://example.com:8443/login", HTTPS_EXAMPLE_8443],
    ["http://example.com/login", HTTP_EXAMPLE],
    ["https://EXAMPLE.com:443/login", HTTPS_EXAMPLE],
  ]) {
    const page = new FakePage({ url, respond: async () => APPROVED });
    await page.inject();
    assert.equal(page.sent[0].origin, expected, url);
    assert.equal(page.sent[0].channel, security.CHANNEL, url);
    assert.equal(page.sent[0].version, security.MESSAGE_VERSION, url);
    assert.equal(page.sent[0].type, "bootstrap", url);
  }
});

test("content_overlay: a non-canonicalizable document never speaks at all", async () => {
  for (const url of [
    "about:blank",
    "file:///tmp/local.html",
    "data:text/html,<p>x",
    "chrome-extension://abcdefghijklmnopabcdefghijklmnop/popup.html",
    "https://alice@example.com/login",
  ]) {
    const page = new FakePage({ url, respond: async () => APPROVED });
    await page.inject();

    assert.deepEqual(page.sent, [], url);
    assert.equal(page.listenerCount, 0, url);
    // The guard is released, so the document is not permanently poisoned.
    assert.equal(page.guarded, false, url);
  }
});

test("content_overlay: without the security module the bootstrap does not run", async () => {
  const page = new FakePage({
    url: "https://example.com/login",
    respond: async () => APPROVED,
    loadSecurity: false,
  });

  await page.inject();

  assert.deepEqual(page.sent, []);
  assert.equal(page.listenerCount, 0);
  // Nothing was claimed, so a correctly ordered later injection still works.
  assert.equal(page.guarded, false);
});

// ---------------------------------------------------------------------------
// Approval ordering.
// ---------------------------------------------------------------------------

test("content_overlay: a refused bootstrap attaches nothing and releases the guard", async () => {
  for (const response of [
    { ok: false, error: { code: "disabled" } },
    { ok: false, error: { code: "permission_missing" } },
    { ok: true, enabled: false, revision: 2 },
    { ok: true, revision: 2 },
    undefined,
    null,
    {},
    "yes",
  ]) {
    const page = new FakePage({
      url: "https://example.com/login",
      respond: async () => response,
    });
    await page.inject();

    const label = JSON.stringify(response) ?? "undefined";
    assert.equal(page.listenerCount, 0, label);
    assert.equal(page.guarded, false, label);
  }
});

test("content_overlay: a dead worker attaches nothing", async () => {
  const page = new FakePage({
    url: "https://example.com/login",
    respond: async () => {
      throw new Error("Could not establish connection.");
    },
  });

  await page.inject();

  assert.equal(page.listenerCount, 0);
  assert.equal(page.guarded, false);
});

test("content_overlay: no listener exists before the approval arrives", async () => {
  let release;
  const approved = new Promise((resolve) => {
    release = resolve;
  });
  const page = new FakePage({
    url: "https://example.com/login",
    respond: async () => {
      // Observed from inside the round trip: the guard is already taken, but
      // the document is not listening to anything yet.
      assert.equal(page.listenerCount, 0, "listener attached before approval");
      await approved;
      return APPROVED;
    },
  });

  page.evaluate("content_overlay.js");
  assert.equal(page.listenerCount, 0);
  release();
  await page.settle();

  assert.equal(page.listenerCount, 1);
});

// ---------------------------------------------------------------------------
// Teardown.
// ---------------------------------------------------------------------------

test("content_overlay: teardown for a still-authorized document keeps the listener", async () => {
  // A2/G3: the broadcast names no origin, so an enabled document must not be
  // torn down just because some other origin was disabled.
  const { page, worker } = await pageBackedByWorker("https://example.com/login", [
    HTTPS_EXAMPLE,
    HTTP_EXAMPLE,
  ]);
  await page.inject();
  assert.equal(page.listenerCount, 1);

  await worker.disableOrigin({ origin: HTTP_EXAMPLE });
  await page.deliver(teardownMessage());

  assert.equal(page.listenerCount, 1, "an unrelated disable tore down this document");
  assert.equal(page.guarded, true);
});

test("content_overlay: teardown after this origin is disabled removes the listener", async () => {
  const { page, worker } = await pageBackedByWorker("https://example.com/login", [
    HTTPS_EXAMPLE,
    HTTP_EXAMPLE,
  ]);
  await page.inject();

  await worker.disableOrigin({ origin: HTTPS_EXAMPLE });
  await page.deliver(teardownMessage());

  assert.equal(page.listenerCount, 0);
  assert.equal(page.guarded, false);
});

test("content_overlay: teardown revalidation fails closed when the worker is gone", async () => {
  const page = new FakePage({ url: "https://example.com/login", respond: async () => APPROVED });
  await page.inject();

  page.respond = async () => {
    throw new Error("Extension context invalidated.");
  };
  await page.deliver(teardownMessage());

  assert.equal(page.listenerCount, 0);
  assert.equal(page.guarded, false);
});

test("content_overlay: a foreign or malformed message is ignored entirely", async () => {
  const page = new FakePage({ url: "https://example.com/login", respond: async () => APPROVED });
  await page.inject();
  const sentAfterBootstrap = page.sent.length;

  for (const message of [
    undefined,
    null,
    "teardown",
    { type: "teardown" },
    { channel: "other-extension", type: "teardown", revision: 9 },
    { channel: security.CHANNEL, type: "bootstrapResult", revision: 9 },
    { channel: security.CHANNEL, type: "fill", revision: 9 },
  ]) {
    await page.deliver(message);
  }

  // Not one revalidation round trip was provoked, and nothing was torn down.
  assert.equal(page.sent.length, sentAfterBootstrap);
  assert.equal(page.listenerCount, 1);
  assert.equal(page.guarded, true);
});

test("content_overlay: teardown revalidation re-sends the same exact-origin claim", async () => {
  const page = new FakePage({ url: "https://example.com:8443/login", respond: async () => APPROVED });
  await page.inject();

  await page.deliver(teardownMessage());

  assert.equal(page.sentOfType("bootstrap").length, 2);
  for (const message of page.sentOfType("bootstrap")) {
    assert.equal(message.origin, HTTPS_EXAMPLE_8443);
    assert.equal(security.assertNoForbiddenKeys(message).ok, true);
  }
  // Still approved, so nothing changed.
  assert.equal(page.listenerCount, 1);
});

test("content_overlay: a torn-down document stops answering teardown", async () => {
  const page = new FakePage({ url: "https://example.com/login", respond: async () => APPROVED });
  await page.inject();

  page.respond = async () => ({ ok: false, error: { code: "disabled" } });
  await page.deliver(teardownMessage());
  const sentAfterTeardown = page.sent.length;

  await page.deliver(teardownMessage(5));
  assert.equal(page.sent.length, sentAfterTeardown);
  assert.equal(page.listenerCount, 0);
});
