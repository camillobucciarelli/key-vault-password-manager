// 009 Slice A4 / A032 — executable secret-lifetime tests.
//
// METHOD. These tests run the WHOLE shipped path end to end: the content
// script in its isolated world (`fake_page.js`), the real `OverlayLifecycle`
// and `OverlayRouter` as the worker, and a fake native host that models only
// the Slice A1 transport contract. The secret searched for is the REAL one
// redeemed through the production dispatcher — never a copy planted by the
// test — so a leak anywhere on the real path is found by looking for the real
// bytes. Asserting on internal state ("the map is empty") proves nothing; an
// empty map coexists happily with a password sitting in a dataset attribute.
//
// WHAT IS CAPTURED: the full page DOM and every shadow root ever created
// (attached or detached), all element attributes/dataset/inline style/text,
// the content world's globals, its console output, every message the content
// script ever sent, the worker's durable storage, and the teardown broadcasts.
//
// WHAT IS DELIBERATELY NOT CLAIMED (SR-5): garbage collection, heap erasure,
// DevTools invisibility, performance-timeline absence, or that the page
// cannot read the value THE FILL PUT IN ITS OWN INPUT. JavaScript cannot
// verify any of those, so no test below pretends to.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { FakePage } = require("./fake_page.js");
const { FakeBrowser } = require("./fake_browser.js");
const routes = require("../overlay_routes.js");
const { OverlayLifecycle } = require("../overlay_lifecycle.js");
const { security, RUNTIME_ID, bindingA, bindingB } = require("./helpers.js");

const ORIGIN = "https://example.com";
const PAGE_URL = "https://example.com/login";

// Distinctive, grep-able, and never a plausible attribute value by accident.
// Assembled at runtime: no credential-shaped literal in the source (GitGuardian).
const A032_FILL_VALUE = ["a032", "canary", "fill", "token"].join("-");
const SECRET_USERNAME = "kv-A032-real-username-77b1e0";

/** Models the Slice A1 native transport only; no authorization decisions. */
class FakeNative {
  constructor() {
    this.binding = bindingA();
    this.items = [
      {
        entryId: "entry-1",
        title: "Example",
        displayService: "example.com",
        matchType: "exact-origin",
        fillEligible: true,
      },
    ];
  }

  send = async (type, payload) => {
    if (type === "overlayQueryCredentials") {
      return {
        ok: true,
        data: {
          metadataOnly: true,
          matchPolicy: routes.MATCH_POLICY,
          target: payload.url,
          fillAvailable: true,
          databaseId: this.binding.databaseId,
          sessionBinding: { ...this.binding },
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
          origin: payload.origin,
          sessionBinding: { ...this.binding },
          username: SECRET_USERNAME,
          password: A032_FILL_VALUE,
        },
      };
    }
    return { ok: true, data: {} };
  };
}

/**
 * The full shipped stack: real worker (lifecycle + router) answering a real
 * content script, over a fake browser and fake native transport.
 */
async function fullStack() {
  const browser = new FakeBrowser({
    storage: {
      [security.OVERLAY_CONFIG_KEY]: {
        version: 1,
        revision: 5,
        enabledOrigins: [ORIGIN],
      },
      [security.OVERLAY_REVISION_FLOOR_KEY]: 5,
    },
    granted: [security.permissionPatternForOrigin(ORIGIN)],
    tabs: [{ id: 42 }],
  });
  const native = new FakeNative();
  const lifecycle = new OverlayLifecycle({ browser });
  const router = new routes.OverlayRouter({
    lifecycle,
    runtimeId: RUNTIME_ID,
    native: native.send,
    now: () => Date.now(),
  });

  const page = new FakePage({ url: PAGE_URL });
  page.respond = (message) =>
    router.dispatch(message, {
      id: RUNTIME_ID,
      url: page.url,
      frameId: 0,
      tab: { id: 42, url: page.url },
    });

  const doc = page.document;
  const form = doc.createElement("form");
  const username = doc.createElement("input");
  username.setAttribute("type", "text");
  username.setAttribute("autocomplete", "username");
  const password = doc.createElement("input");
  password.setAttribute("type", "password");
  form.appendChild(username);
  form.appendChild(password);
  doc.body.appendChild(form);

  await page.inject();
  assert.equal(page.listenerCount, 1, "bootstrap must be approved end to end");
  return { page, browser, native, lifecycle, form, username, password };
}

/** Every observable surface EXCEPT the allowed sink (input values). */
function observableSurfaces({ page, browser }) {
  return [
    page.captureObservableState(),
    JSON.stringify(page.sent),
    JSON.stringify(browser.store),
    JSON.stringify(browser.deliveredTeardowns),
  ].join("\n");
}

function assertNoSecretIn(text, label) {
  assert.ok(!text.includes(A032_FILL_VALUE), `${label}: password leaked`);
  assert.ok(!text.includes(SECRET_USERNAME), `${label}: username leaked`);
}

function optionRow(page) {
  const row = page
    .allElements()
    .find((el) => el.getAttribute("role") === "option");
  assert.ok(row, "expected a rendered match row");
  return row;
}

// ---------------------------------------------------------------------------

test("A032: the rendered match surface contains neither password nor username", async () => {
  const stack = await fullStack();
  await stack.page.focus(stack.password);

  // The row rendered from the real worker's real metadata answer.
  assert.equal(optionRow(stack.page).textContent, "Exampleexample.com");
  assertNoSecretIn(observableSurfaces(stack), "after metadata render");
});

test("A032: after an explicit fill the secret exists in the input values and in no other captured surface", async () => {
  const stack = await fullStack();
  await stack.page.focus(stack.password);
  await stack.page.click(optionRow(stack.page));

  // The one allowed, inherent sink (SR-5): the native input values.
  assert.equal(stack.password.value, A032_FILL_VALUE);
  assert.equal(stack.username.value, SECRET_USERNAME);

  // Everything else: DOM/attributes/dataset/style/text of page AND detached
  // shadow trees, content-world globals, console, every content-sent message,
  // worker durable storage, teardown broadcasts.
  assertNoSecretIn(observableSurfaces(stack), "after fill");
  assert.deepEqual(stack.page.consoleLines, [], "nothing may be logged");
  assert.equal(stack.page.submitCount, 0);
});

test("A032: a vault switch between metadata and fill yields stale_session and the secret never appears anywhere", async () => {
  const stack = await fullStack();
  await stack.page.focus(stack.password);
  const row = optionRow(stack.page);

  // Vault B publishes under the same entry UUID and origin (SR-4 regression):
  // the reveal now answers with B's binding, which the router must refuse
  // BEFORE forwarding any secret.
  stack.native.binding = bindingB();
  await stack.page.click(row);

  assert.equal(stack.password.value, "", "no fill may happen across a vault switch");
  assert.equal(stack.username.value, "");
  assertNoSecretIn(observableSurfaces(stack), "after stale vault switch");
  // The content script renders the stale state rather than tearing down.
  const status = stack.page.allElements().find((el) => el.id === "kv-status");
  assert.equal(status.textContent, "KeyVault session changed.");
});

test("A032: a replayed fill token yields no secret on any surface", async () => {
  const stack = await fullStack();
  await stack.page.focus(stack.password);
  const firstFillToken = (await (async () => {
    await stack.page.click(optionRow(stack.page));
    return stack.page.sentOfType("fill")[0].fillToken;
  })());
  assert.equal(stack.password.value, A032_FILL_VALUE, "first fill succeeds");

  // Replay the consumed token straight at the real dispatcher, as a page that
  // captured the message would.
  stack.password.value = "";
  const replay = await stack.page.respond({
    channel: security.CHANNEL,
    version: security.MESSAGE_VERSION,
    type: "fill",
    origin: ORIGIN,
    focusNonce: stack.page.sentOfType("fill")[0].focusNonce,
    fillToken: firstFillToken,
    entryId: "entry-1",
    sessionBinding: bindingA(),
  });
  assert.equal(replay.ok, false);
  assert.equal(replay.error.code, "stale_session");
  assert.ok(!JSON.stringify(replay).includes(A032_FILL_VALUE));
  assert.equal(stack.password.value, "");
});
