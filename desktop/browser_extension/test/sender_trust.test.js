// A003 — SR-1: the two sender trust paths are separate.
//
// The extension-page path and the content-script path are exercised
// independently, and the crossing cases are asserted in both directions. The
// property that matters is not "a bad message is rejected" but "a
// content-script message can never be admitted by the extension-page
// validator", which is why the route check is tested with an otherwise
// perfectly valid sender.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  security,
  RUNTIME_ID,
  OTHER_RUNTIME_ID,
  extensionPageSender,
  contentScriptSender,
  overlayMessage,
  bootstrapMessage,
  requestMatchesMessage,
  fillMessage,
  getSiteStateMessage,
  setSiteStateMessage,
  contextFor,
} = require("./helpers.js");

const ENABLED = ["https://example.com"];

// ---------------------------------------------------------------------------
// Route catalogue
// ---------------------------------------------------------------------------

test("every message type belongs to exactly one route", () => {
  const extensionTypes = security.messageTypesForRoute(security.EXTENSION_PAGE_ROUTE);
  const contentTypes = security.messageTypesForRoute(security.CONTENT_SCRIPT_ROUTE);

  assert.deepEqual(extensionTypes.sort(), ["getSiteState", "setSiteState"]);
  assert.deepEqual(contentTypes.sort(), ["bootstrap", "fill", "requestMatches"]);

  for (const type of extensionTypes) {
    assert.ok(!contentTypes.includes(type), `${type} must not be in both routes`);
  }
});

// ---------------------------------------------------------------------------
// Extension-page path, on its own
// ---------------------------------------------------------------------------

test("extension page: a valid popup request is admitted", () => {
  for (const message of [getSiteStateMessage(), setSiteStateMessage()]) {
    const result = security.validateExtensionPageRequest(
      message,
      extensionPageSender(),
      RUNTIME_ID
    );
    assert.equal(result.ok, true, `${message.type} must be admitted`);
    assert.equal(result.sender.route, security.EXTENSION_PAGE_ROUTE);
  }
});

test("extension page: wrong runtime id is rejected", () => {
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    extensionPageSender({ id: OTHER_RUNTIME_ID }),
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "wrong_runtime_id");
});

test("extension page: a sender URL from another extension is rejected", () => {
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    extensionPageSender({
      url: `chrome-extension://${OTHER_RUNTIME_ID}/popup.html`,
      origin: `chrome-extension://${OTHER_RUNTIME_ID}`,
    }),
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "extension_url_mismatch");
});

test("extension page: a runtime-id prefix collision is rejected", () => {
  // `chrome-extension://<id>evil/` starts with the id but is a different
  // extension. The trailing slash in the expected prefix is what stops this.
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    extensionPageSender({
      url: `chrome-extension://${RUNTIME_ID}evil/popup.html`,
      origin: undefined,
    }),
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "extension_url_mismatch");
});

test("extension page: a missing sender URL is rejected", () => {
  const sender = extensionPageSender();
  delete sender.url;
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    sender,
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "missing_sender_url");
});

test("extension page: an http page URL is rejected even with the right runtime id", () => {
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    extensionPageSender({ url: "https://example.com/login", origin: undefined }),
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "extension_url_mismatch");
});

test("extension page: a sender carrying tab context is rejected", () => {
  // This is the single most important negative case on this path: a page in a
  // tab is never an extension page, whatever it claims.
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    extensionPageSender({ tab: { id: 42, url: "https://example.com/" } }),
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "unexpected_tab");
});

test("extension page: a sender carrying a frame id is rejected", () => {
  const result = security.validateExtensionPageRequest(
    getSiteStateMessage(),
    extensionPageSender({ frameId: 0 }),
    RUNTIME_ID
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "unexpected_frame");
});

// ---------------------------------------------------------------------------
// Content-script path, on its own
// ---------------------------------------------------------------------------

test("content script: a valid bootstrap/matches/fill is admitted", () => {
  for (const message of [
    bootstrapMessage(),
    requestMatchesMessage(),
    fillMessage(),
  ]) {
    const result = security.validateContentScriptRequest(
      message,
      contentScriptSender(),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(result.ok, true, `${message.type} must be admitted`);
    assert.equal(result.sender.route, security.CONTENT_SCRIPT_ROUTE);
    assert.equal(result.sender.origin, "https://example.com");
  }
});

test("content script: wrong runtime id is rejected", () => {
  const result = security.validateContentScriptRequest(
    bootstrapMessage(),
    contentScriptSender({ id: OTHER_RUNTIME_ID }),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "wrong_runtime_id");
});

test("content script: a missing tab, tab id, frame id or sender URL is rejected", () => {
  const cases = [
    ["missing_tab", (sender) => delete sender.tab],
    ["missing_tab_id", (sender) => delete sender.tab.id],
    ["missing_frame_id", (sender) => delete sender.frameId],
    ["missing_sender_url", (sender) => delete sender.url],
  ];
  for (const [expected, mutate] of cases) {
    const sender = contentScriptSender();
    mutate(sender);
    const result = security.validateContentScriptRequest(
      bootstrapMessage(),
      sender,
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(result.ok, false, `expected rejection for ${expected}`);
    assert.equal(result.error, expected);
  }
});

test("content script: a non-integer frame id or tab id is rejected", () => {
  for (const frameId of ["0", 1.5, null, NaN, -1]) {
    const result = security.validateContentScriptRequest(
      bootstrapMessage(),
      contentScriptSender({ frameId }),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(result.ok, false, `frameId ${String(frameId)} must be rejected`);
    assert.equal(result.error, "missing_frame_id");
  }
  const badTab = security.validateContentScriptRequest(
    bootstrapMessage(),
    contentScriptSender({ tabId: "42" }),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(badTab.ok, false);
  assert.equal(badTab.error, "missing_tab_id");
});

test("content script: a non-HTTP(S) sender URL is rejected", () => {
  for (const url of [
    "chrome-extension://abcdefghijklmnopabcdefghijklmnop/popup.html",
    "file:///tmp/page.html",
    "about:blank",
    "data:text/html,<b>x</b>",
    "",
  ]) {
    const result = security.validateContentScriptRequest(
      bootstrapMessage(),
      contentScriptSender({ frameUrl: url, topUrl: url }),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(result.ok, false, `${url} must be rejected`);
    assert.equal(result.error, "invalid_sender_origin");
  }
});

test("content script: a disabled origin is rejected even when fully well formed", () => {
  const result = security.validateContentScriptRequest(
    bootstrapMessage("https://other.example"),
    contentScriptSender({ frameUrl: "https://other.example/login" }),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "disabled");
});

test("content script: a missing host permission is rejected even when enabled", () => {
  const result = security.validateContentScriptRequest(
    bootstrapMessage(),
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED, { grantedPatterns: [] })
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "permission_missing");
});

// ---------------------------------------------------------------------------
// SR-1 — the crossing cases
// ---------------------------------------------------------------------------

test("a content-script message is never admitted by the extension-page validator", () => {
  const contentMessages = [bootstrapMessage(), requestMatchesMessage(), fillMessage()];

  for (const message of contentMessages) {
    // With the real content sender: the sender check fails first.
    const withContentSender = security.validateExtensionPageRequest(
      message,
      contentScriptSender(),
      RUNTIME_ID
    );
    assert.equal(withContentSender.ok, false, `${message.type} via content sender`);
    assert.equal(withContentSender.error, "unexpected_tab");

    // With a genuine extension-page sender: the route check must still refuse.
    // This is the guard that survives if sender classification is ever wrong.
    const withExtensionSender = security.validateExtensionPageRequest(
      message,
      extensionPageSender(),
      RUNTIME_ID
    );
    assert.equal(
      withExtensionSender.ok,
      false,
      `${message.type} must not be an extension-page route`
    );
    assert.equal(withExtensionSender.error, "wrong_route");
  }
});

test("an extension-page message is never admitted by the content-script validator", () => {
  for (const message of [getSiteStateMessage(), setSiteStateMessage()]) {
    const withExtensionSender = security.validateContentScriptRequest(
      message,
      extensionPageSender(),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(withExtensionSender.ok, false);
    assert.equal(withExtensionSender.error, "missing_tab");

    // Same message, but arriving from a real content script: the route check
    // rejects it independently of the sender.
    const withContentSender = security.validateContentScriptRequest(
      message,
      contentScriptSender(),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(withContentSender.ok, false);
    assert.equal(withContentSender.error, "wrong_route");
  }
});

test("route classification and validation disagree safely", () => {
  // classifySenderRoute only picks a validator; it never authorizes. A sender
  // with a bogus tab object classifies as content and is then rejected.
  assert.equal(
    security.classifySenderRoute(extensionPageSender()),
    security.EXTENSION_PAGE_ROUTE
  );
  assert.equal(
    security.classifySenderRoute(contentScriptSender()),
    security.CONTENT_SCRIPT_ROUTE
  );

  const bogus = extensionPageSender({ tab: { id: "not-a-number" } });
  assert.equal(security.classifySenderRoute(bogus), security.CONTENT_SCRIPT_ROUTE);
  const result = security.validateContentScriptRequest(
    bootstrapMessage(),
    bogus,
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "missing_tab_id");
});

// ---------------------------------------------------------------------------
// Message shape
// ---------------------------------------------------------------------------

test("the envelope must carry the exact channel and version", () => {
  const wrongChannel = { ...bootstrapMessage(), channel: "other-channel" };
  const wrongVersion = { ...bootstrapMessage(), version: 2 };

  for (const [message, expected] of [
    [wrongChannel, "unknown_channel"],
    [wrongVersion, "unsupported_version"],
  ]) {
    const result = security.validateContentScriptRequest(
      message,
      contentScriptSender(),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(result.ok, false);
    assert.equal(result.error, expected);
  }
});

test("an unknown message type is rejected on both routes", () => {
  const message = overlayMessage("exfiltrate", { origin: "https://example.com" });
  const asContent = security.validateContentScriptRequest(
    message,
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(asContent.error, "unknown_message_type");

  const asExtension = security.validateExtensionPageRequest(
    message,
    extensionPageSender(),
    RUNTIME_ID
  );
  assert.equal(asExtension.error, "unknown_message_type");
});

test("unknown keys are rejected, not ignored", () => {
  const result = security.validateContentScriptRequest(
    { ...bootstrapMessage(), extra: "surprise" },
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "unknown_key");
  assert.equal(result.key, "extra");
});

test("missing required keys are rejected per message type", () => {
  const message = requestMatchesMessage();
  delete message.fieldKind;
  const result = security.validateContentScriptRequest(
    message,
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "missing_key");
  assert.equal(result.key, "fieldKind");
});

test("wrong field types are rejected", () => {
  const cases = [
    [requestMatchesMessage({ fieldKind: "totp" }), "fieldKind"],
    [requestMatchesMessage({ focusNonce: 12345 }), "focusNonce"],
    [fillMessage({ entryId: { id: "entry-1" } }), "entryId"],
    [fillMessage({ sessionBinding: "db-a" }), "sessionBinding"],
    [getSiteStateMessage({ tabId: "42" }), "tabId"],
    [setSiteStateMessage({ enabled: "true" }), "enabled"],
  ];
  for (const [message, key] of cases) {
    const isExtensionRoute =
      security.messageTypesForRoute(security.EXTENSION_PAGE_ROUTE).includes(message.type);
    const result = isExtensionRoute
      ? security.validateExtensionPageRequest(message, extensionPageSender(), RUNTIME_ID)
      : security.validateContentScriptRequest(
          message,
          contentScriptSender(),
          RUNTIME_ID,
          contextFor(ENABLED)
        );
    assert.equal(result.ok, false, `${message.type}.${key} must be rejected`);
    assert.equal(result.error, "invalid_type");
    assert.equal(result.key, key);
  }
});

test("oversize values are rejected", () => {
  const huge = "x".repeat(security.LIMITS.TOKEN + 1);
  const overlong = security.validateContentScriptRequest(
    requestMatchesMessage({ focusNonce: huge }),
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(overlong.ok, false);
  assert.equal(overlong.error, "invalid_type");
  assert.equal(overlong.key, "focusNonce");

  const hugeEntryId = "y".repeat(security.LIMITS.ENTRY_ID + 1);
  const overlongEntry = security.validateContentScriptRequest(
    fillMessage({ entryId: hugeEntryId }),
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(overlongEntry.ok, false);
  assert.equal(overlongEntry.key, "entryId");

  // An oversize URL never reaches the URL parser at all.
  const hugeUrl = `https://example.com/${"z".repeat(security.LIMITS.URL)}`;
  const result = security.canonicalizeOrigin(hugeUrl);
  assert.equal(result.ok, false);
  assert.equal(result.error, "oversize_value");
});

test("a prototype-polluting or exotic message object is rejected", () => {
  for (const message of [
    null,
    undefined,
    "bootstrap",
    42,
    [bootstrapMessage()],
    Object.assign(Object.create({ channel: security.CHANNEL }), { type: "bootstrap" }),
  ]) {
    const result = security.validateContentScriptRequest(
      message,
      contentScriptSender(),
      RUNTIME_ID,
      contextFor(ENABLED)
    );
    assert.equal(result.ok, false, `${String(message)} must be rejected`);
  }
});
