// 009 Slice A5 — behavioural tests for the interaction surface of
// `content_overlay.js`: the frame-policy display states (A035), the
// listbox/combobox ARIA contract (A036), the keyboard contract (A037), and
// the click-vs-blur pending-action protocol (A038).
//
// Everything drives the SHIPPED file through `test/fake_page.js`, whose event
// model is composed-and-retargeting like Chrome's: UA-style events cross the
// closed shadow boundary up to the document, retargeted to the host. That is
// what makes "a closed overlay captures no page keys" FALSIFIABLE — a page
// listener at the document really does receive every keydown unless the
// overlay actively swallows it.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { FakeEvent } = require("./fake_page.js");
const security = require("../overlay_security.js");
const {
  item,
  matchesResult,
  fillResult,
  loginPage,
  statusText,
  optionRows,
  listboxEl,
  overlayCount,
} = require("./session_helpers.js");

// Runtime-assembled fill canaries: no credential-shaped source literal, ever
// (GitGuardian; see overlay_session.test.js).
const FILL_VALUE_K = ["canary", "keyboard"].join("-");
const FILL_VALUE_P = ["canary", "pointer"].join("-");

const UNSUPPORTED_TEXT =
  "The overlay is not available in this frame. Copy your login from the KeyVault app.";

async function pageWithRows(count = 2) {
  const ctx = await loginPage();
  ctx.handlers.matches = (m) =>
    matchesResult(m, {
      items: Array.from({ length: count }, (_, index) =>
        item({ entryId: `entry-${index + 1}`, title: `Row${index + 1}` })
      ),
    });
  await ctx.page.focus(ctx.password);
  assert.equal(optionRows(ctx.page).length, count);
  return ctx;
}

// ---------------------------------------------------------------------------
// A035 — frame policy surface in a SUPPORTED document: the detectable
// cross-origin iframe hint. (The unsupported-frame instance itself is covered
// in content_overlay.test.js; the worker-side gate in overlay_routes.test.js.)
// ---------------------------------------------------------------------------

test("A035: focusing a cross-origin iframe shows the manual-copy hint and sends nothing", async () => {
  const { page } = await loginPage();
  const iframe = page.document.createElement("iframe");
  iframe.setAttribute("src", "https://other.example/embedded-login");
  page.document.body.appendChild(iframe);

  await page.focus(iframe);

  assert.equal(overlayCount(page), 1, "the hint state must render");
  assert.equal(statusText(page), UNSUPPORTED_TEXT);
  // Fail closed: the hint is display-only. No metadata query, no fill, and
  // no clipboard API exists anywhere in the extension.
  assert.equal(page.sentOfType("requestMatches").length, 0);
  assert.equal(page.sentOfType("fill").length, 0);
  // An iframe is not a combobox: its ARIA is never touched.
  assert.equal(iframe.getAttribute("aria-expanded"), null);

  // Focus moving back into the page tears the hint down like any session.
  await page.click(page.document.body);
  assert.equal(overlayCount(page), 0);
});

test("A035: a same-origin iframe gets NO hint — its own injected instance owns it", async () => {
  // Absolute AND relative srcs: the browser resolves a relative src against
  // the document URL, and so must the hint check — a raw-attribute compare
  // would misread "/widget" as foreign and paint the hint over a frame that
  // already carries its own real overlay (tester finding, Slice A5).
  for (const src of [
    "https://example.com/widget",
    "/widget",
    "widget.html",
    "../nested/widget.html",
    "//example.com/widget",
  ]) {
    const { page } = await loginPage();
    const iframe = page.document.createElement("iframe");
    iframe.setAttribute("src", src);
    page.document.body.appendChild(iframe);

    await page.focus(iframe);

    assert.equal(overlayCount(page), 0, `src=${JSON.stringify(src)} must get no hint`);
    assert.equal(page.sentOfType("requestMatches").length, 0);
  }
});

test("A035: a protocol-relative cross-origin src still gets the hint", async () => {
  // Regression for the resolver: "//other.example/x" resolves to ANOTHER
  // origin under this document's scheme and must keep the hint.
  const { page } = await loginPage();
  const iframe = page.document.createElement("iframe");
  iframe.setAttribute("src", "//other.example/embedded-login");
  page.document.body.appendChild(iframe);

  await page.focus(iframe);

  assert.equal(overlayCount(page), 1);
  assert.equal(statusText(page), UNSUPPORTED_TEXT);
  assert.equal(page.sentOfType("requestMatches").length, 0);
});

test("A035: sandboxed/opaque iframe sources are hint targets, not fill targets", async () => {
  for (const src of ["about:srcdoc", "data:text/html,<p>x", ""]) {
    const { page } = await loginPage();
    const iframe = page.document.createElement("iframe");
    if (src !== "") iframe.setAttribute("src", src);
    page.document.body.appendChild(iframe);
    await page.focus(iframe);
    assert.equal(overlayCount(page), 1, `src=${JSON.stringify(src)}`);
    assert.equal(statusText(page), UNSUPPORTED_TEXT);
    assert.equal(page.sentOfType("requestMatches").length, 0);
  }
});

// ---------------------------------------------------------------------------
// M7 — the hint mechanism itself: window blur + activeElement, NEVER focusin
// (the parent document receives no focusin for a child browsing context; the
// fake models the real Chrome behaviour, measured live).
// ---------------------------------------------------------------------------

test("M7: no focusin ever fires for an iframe — a document focusin listener stays silent", async () => {
  const { page } = await loginPage();
  const iframe = page.document.createElement("iframe");
  iframe.setAttribute("src", "https://other.example/embedded-login");
  page.document.body.appendChild(iframe);
  const focusinTargets = [];
  page.document.addEventListener("focusin", (event) => {
    focusinTargets.push(event.target);
  });

  await page.focus(iframe);

  assert.equal(focusinTargets.length, 0, "the parent must receive no focusin");
  // The hint rendered anyway — via window blur + activeElement.
  assert.equal(overlayCount(page), 1);
  assert.equal(statusText(page), UNSUPPORTED_TEXT);
});

test("M7: focus moving from an open fill session into a cross-origin iframe swaps to the hint", async () => {
  const { page, password } = await loginPage();
  const iframe = page.document.createElement("iframe");
  iframe.setAttribute("src", "https://other.example/embedded-login");
  page.document.body.appendChild(iframe);

  await page.focus(password);
  assert.equal(overlayCount(page), 1, "fill session must be open");
  assert.notEqual(statusText(page), UNSUPPORTED_TEXT);

  await page.focus(iframe);
  assert.equal(overlayCount(page), 1, "exactly one overlay: the hint");
  assert.equal(statusText(page), UNSUPPORTED_TEXT);
  // The fill session's combobox ARIA was restored on its teardown.
  assert.equal(password.getAttribute("aria-expanded"), null);
});

test("M7: a window blur with no iframe active (app/tab switch) changes nothing", async () => {
  const { page, password } = await loginPage();
  await page.focus(password);
  assert.equal(overlayCount(page), 1);

  // The whole browser window loses focus; activeElement is still the input.
  page.window._invoke(new FakeEvent("blur", { bubbles: false }));
  await page.settle();

  assert.equal(overlayCount(page), 1, "the session must survive an app switch");
  assert.notEqual(statusText(page), UNSUPPORTED_TEXT);
});

test("M7: the one-shot post-blur poll catches an activeElement that settles late", async () => {
  const { page } = await loginPage();
  const iframe = page.document.createElement("iframe");
  iframe.setAttribute("src", "https://other.example/embedded-login");
  page.document.body.appendChild(iframe);

  // Model an engine where the blur dispatch happens BEFORE activeElement
  // reads the iframe: blur first, activeElement flips after.
  page.window._invoke(new FakeEvent("blur", { bubbles: false }));
  assert.equal(overlayCount(page), 0, "synchronous check must find nothing yet");
  page.document.activeElement = iframe;
  await page.settle(); // drains the one-shot poll

  assert.equal(overlayCount(page), 1, "the deferred re-check must show the hint");
  assert.equal(statusText(page), UNSUPPORTED_TEXT);
  assert.equal(page.sentOfType("requestMatches").length, 0);
});

// ---------------------------------------------------------------------------
// A037 — keyboard.
// ---------------------------------------------------------------------------

test("A037: arrows move the selection, clamp at both ends, and are never swallowed", async () => {
  const { page } = await pageWithRows(3);
  const selected = () =>
    optionRows(page).findIndex((row) => row.getAttribute("aria-selected") === "true");

  assert.equal(selected(), 0);
  let event = await page.pressKey("ArrowDown");
  assert.equal(selected(), 1);
  assert.equal(event.defaultPrevented, false, "arrows pass through");
  await page.pressKey("ArrowDown");
  assert.equal(selected(), 2);
  await page.pressKey("ArrowDown");
  assert.equal(selected(), 2, "clamped at the last row");
  await page.pressKey("ArrowUp");
  await page.pressKey("ArrowUp");
  event = await page.pressKey("ArrowUp");
  assert.equal(selected(), 0, "clamped at the first row");
  assert.equal(event.defaultPrevented, false);
  assert.equal(listboxEl(page).getAttribute("aria-activedescendant"), "kv-option-0");
});

test("A037: Enter fills the CURRENT row and consumes only that keystroke", async () => {
  const { page, password: pwInput, handlers } = await pageWithRows(2);
  const fills = [];
  handlers.fill = (m) => {
    fills.push(m.entryId);
    return fillResult(m, { password: FILL_VALUE_K });
  };
  const pageSawKeys = [];
  page.document.addEventListener("keydown", (event) => {
    pageSawKeys.push([event.key, event.defaultPrevented]);
  });

  await page.pressKey("ArrowDown"); // select Row2
  const enter = await page.pressKey("Enter");

  assert.deepEqual(fills, ["entry-2"], "Enter must fill the SELECTED row");
  assert.equal(pwInput.value, FILL_VALUE_K);
  assert.equal(enter.defaultPrevented, true, "the fill Enter is consumed");
  // Propagation stopped for the fill Enter ONLY: the page saw the arrow but
  // never the Enter, and nothing became a submit.
  assert.deepEqual(pageSawKeys, [["ArrowDown", false]]);
  assert.equal(page.submitCount, 0);
  assert.equal(overlayCount(page), 0, "fill ends with teardown");
});

test("A037: Enter on a non-eligible row does nothing and passes through", async () => {
  const { page, password: pwInput, handlers } = await loginPage();
  handlers.matches = (m) =>
    matchesResult(m, {
      items: [
        item({ entryId: "entry-1", title: "Fillable" }),
        item({
          entryId: "entry-2",
          title: "MetadataOnly",
          matchType: "possible",
          fillEligible: false,
        }),
      ],
    });
  await page.focus(pwInput);
  await page.pressKey("ArrowDown"); // select the non-eligible row
  const enter = await page.pressKey("Enter");

  assert.equal(page.sentOfType("fill").length, 0, "a non-eligible row can never fill");
  assert.equal(enter.defaultPrevented, false, "an unused Enter is not swallowed");
  assert.equal(overlayCount(page), 1, "the session stays open");
});

test("A037: Escape dismisses the current focus session without swallowing the key", async () => {
  const { page } = await pageWithRows(1);
  const escape = await page.pressKey("Escape");
  assert.equal(overlayCount(page), 0);
  assert.equal(escape.defaultPrevented, false);
});

test("A037: Tab tears down and passes through", async () => {
  const { page } = await pageWithRows(1);
  const pageSaw = [];
  page.document.addEventListener("keydown", (event) => {
    pageSaw.push([event.key, event.defaultPrevented]);
  });
  const tab = await page.pressKey("Tab");
  assert.equal(overlayCount(page), 0, "Tab must tear the session down");
  assert.equal(tab.defaultPrevented, false, "Tab must not be swallowed");
  assert.deepEqual(pageSaw, [["Tab", false]], "the page keeps its Tab");
});

test("A037: a closed overlay captures no page keys", async () => {
  const { page, password: pwInput } = await pageWithRows(1);
  const pageSaw = [];
  page.document.addEventListener("keydown", (event) => {
    pageSaw.push([event.key, event.defaultPrevented]);
  });

  await page.pressKey("Escape"); // close the session; focus stays on the anchor
  assert.equal(overlayCount(page), 0);
  pageSaw.length = 0;
  const sentBefore = page.sent.length;

  for (const key of ["Enter", "ArrowDown", "ArrowUp", "Escape", "a"]) {
    await page.pressKey(key);
  }

  // Every key reached the page untouched: nothing captured, nothing
  // prevented, nothing sent, nothing rendered. Structurally so — the closed
  // overlay holds no keydown listener at all.
  assert.deepEqual(pageSaw, [
    ["Enter", false],
    ["ArrowDown", false],
    ["ArrowUp", false],
    ["Escape", false],
    ["a", false],
  ]);
  assert.equal(page.sent.length, sentBefore);
  const sessionKeydownGone = !pwInput.listenerTypes.includes("keydown");
  assert.ok(sessionKeydownGone, "session keydown listener must be aborted");
});

// ---------------------------------------------------------------------------
// A038 — click-vs-blur.
// ---------------------------------------------------------------------------

test("A038: pointer-down inside the overlay preserves the anchor focus and marks the action pending", async () => {
  const { page, password: pwInput } = await pageWithRows(1);
  const row = optionRows(page)[0];

  const mousedown = new FakeEvent("mousedown", {
    bubbles: true,
    cancelable: true,
    composed: true,
  });
  page._propagate(row, mousedown);

  assert.equal(mousedown.defaultPrevented, true, "the focus-stealing default is prevented");
  assert.equal(page.document.activeElement, pwInput, "the anchor keeps focus");
  assert.equal(overlayCount(page), 1);
});

test("A038: a deferred outside blur cannot remove the row before the click lands", async () => {
  // The race, reproduced: a spurious focusout fires at the anchor BETWEEN the
  // overlay mousedown and its click (AT and window-refocus sequences do
  // this). The pending action must hold the deferred teardown off so the
  // click still hits a live row and the fill completes.
  const { page, password: pwInput, handlers } = await pageWithRows(1);
  handlers.fill = (m) => fillResult(m, { password: FILL_VALUE_P });
  const row = optionRows(page)[0];

  const mousedown = new FakeEvent("mousedown", { bubbles: true, cancelable: true, composed: true });
  page._propagate(row, mousedown);
  page._propagate(
    pwInput,
    new FakeEvent("focusout", { bubbles: true, composed: true })
  );
  assert.equal(row.isConnected, true, "the deferred blur must not remove the row mid-pointer");

  page._propagate(row, new FakeEvent("mouseup", { bubbles: true, composed: true }));
  page._propagate(row, new FakeEvent("click", { bubbles: true, cancelable: true, composed: true }));
  await page.settle();

  assert.equal(pwInput.value, FILL_VALUE_P, "the click must win the race");
  assert.equal(page.submitCount, 0);
  assert.equal(overlayCount(page), 0, "the action still ends in teardown");
});

test("A038: a teardown broadcast wins over a pending pointer action", async () => {
  // The broadcast is a revocation signal: rendering may never outlive the
  // revision that authorized it, and a pointer press in flight is not a
  // stay of execution. Today this holds structurally (the broadcast handler
  // has no pending-action guard); this test pins it BEHAVIOURALLY so a
  // future "finish the click first" guard cannot slip in unnoticed
  // (mutation A5-M10 is exactly that guard).
  const { page, password: pwInput } = await pageWithRows(1);
  const row = optionRows(page)[0];

  page._propagate(
    row,
    new FakeEvent("mousedown", { bubbles: true, cancelable: true, composed: true })
  );

  // The broadcast lands mid-pointer; revalidation still approves the origin,
  // so the listener survives — the SESSION must not.
  await page.deliver({
    channel: security.CHANNEL,
    version: security.MESSAGE_VERSION,
    type: "teardown",
    revision: 4,
  });
  assert.equal(overlayCount(page), 0, "the broadcast must remove the host despite the pending action");

  // The click that follows hits a dead row: no fill request, no message of
  // any kind, no secret in the input.
  const sentBefore = page.sent.length; // bootstrap + matches + revalidation
  page._propagate(row, new FakeEvent("mouseup", { bubbles: true, composed: true }));
  page._propagate(
    row,
    new FakeEvent("click", { bubbles: true, cancelable: true, composed: true })
  );
  await page.settle();

  assert.equal(page.sentOfType("fill").length, 0);
  assert.equal(page.sent.length, sentBefore, "a dead row must not speak at all");
  assert.equal(pwInput.value, "");
});

test("A038: a genuine outside blur still tears down promptly (after the pointer task)", async () => {
  const { page } = await pageWithRows(1);
  await page.click(page.document.body);
  assert.equal(overlayCount(page), 0);
  assert.equal(page._timeouts.size, 0, "no orphan deferred timer");
});

test("A038: overlay controls are type=button, outside every page form, and produce zero submits", async () => {
  const { page, form } = await pageWithRows(2);
  const shadowButtons = page
    .allElements()
    .filter((el) => el.tagName === "BUTTON");
  assert.ok(shadowButtons.length >= 3, "rows + generate control expected");
  for (const button of shadowButtons) {
    assert.equal(button.getAttribute("type"), "button");
    assert.equal(button.form, null, "overlay controls must not join a page form");
  }
  let submitSeen = 0;
  form.addEventListener("submit", () => {
    submitSeen += 1;
  });
  await page.click(optionRows(page)[0]);
  assert.equal(page.submitCount, 0);
  assert.equal(submitSeen, 0);
});

// ---------------------------------------------------------------------------
// A039 — input delivery and late-ineligibility refusals (the five REQUIRED
// named DOM assertions live in content_overlay.test.js).
// ---------------------------------------------------------------------------

test("A039: fill drives framework-controlled inputs through the prototype value setter", async () => {
  const { page, password: pwInput, handlers } = await loginPage();
  handlers.fill = (m) => fillResult(m, { password: FILL_VALUE_P });
  await page.focus(pwInput);

  // A framework shadows `value` with an instance accessor to track writes.
  // The fill must go through the PROTOTYPE (native) setter — updating the
  // real value storage, bypassing the framework interceptor — and notify via
  // the bubbling `input` event, which is how the framework actually learns.
  let interceptorWrites = 0;
  Object.defineProperty(pwInput, "value", {
    configurable: true,
    get: () => "",
    set: () => {
      interceptorWrites += 1;
    },
  });
  const inputEvents = [];
  pwInput.addEventListener("input", (event) => inputEvents.push(event.type));

  await page.click(optionRows(page)[0]);

  assert.equal(pwInput._value, FILL_VALUE_P, "the native storage must hold the value");
  assert.equal(interceptorWrites, 0, "the framework interceptor must be bypassed");
  assert.deepEqual(inputEvents, ["input"], "the framework is notified by the event");
});

test("A039: no fill lands on a field made read-only or hidden after the query", async () => {
  for (const sabotage of [
    (pwInput) => {
      pwInput.readOnly = true;
    },
    (pwInput) => {
      pwInput.setAttribute("hidden", "");
    },
    (pwInput) => {
      pwInput.disabled = true;
    },
  ]) {
    const { page, password: pwInput } = await pageWithRows(1);
    sabotage(pwInput);
    await page.click(optionRows(page)[0]);
    assert.equal(pwInput.value, "", "an ineligible field must never receive the secret");
    assert.equal(overlayCount(page), 0, "the refusal fails closed");
  }
});
