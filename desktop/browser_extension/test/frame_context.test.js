// A005 / SR-7 — frame contexts.
//
// The single rule under test: authorization follows the SENDER FRAME.
// `sender.tab.url` is top-level context and never substitutes for
// `sender.url`, in either direction — a permitted child inside a disabled top
// works, and a disabled child inside a permitted top does not.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  security,
  RUNTIME_ID,
  contentScriptSender,
  bootstrapMessage,
  contextFor,
} = require("./helpers.js");

const TOP = "https://top.example";
const CHILD = "https://child.example";

function admit(sender, enabledOrigins, bodyOrigin) {
  return security.validateContentScriptRequest(
    bootstrapMessage(bodyOrigin),
    sender,
    RUNTIME_ID,
    contextFor(enabledOrigins)
  );
}

test("top frame: supported when its exact origin is enabled", () => {
  const sender = contentScriptSender({
    frameUrl: `${TOP}/login`,
    topUrl: `${TOP}/login`,
    frameId: 0,
  });
  const result = admit(sender, [TOP], TOP);
  assert.equal(result.ok, true);
  assert.equal(result.sender.frameId, 0);
  assert.equal(
    security.computeFrameSupport({
      frameId: 0,
      frameOrigin: TOP,
      topOrigin: TOP,
      enabledOrigins: [TOP],
    }),
    "top"
  );
});

test("same-origin child: supported and classified as same-origin", () => {
  const sender = contentScriptSender({
    frameUrl: `${TOP}/widget`,
    topUrl: `${TOP}/login`,
    frameId: 7,
  });
  const result = admit(sender, [TOP], TOP);
  assert.equal(result.ok, true);
  assert.equal(result.sender.frameId, 7);
  assert.equal(
    security.computeFrameSupport({
      frameId: 7,
      frameOrigin: TOP,
      topOrigin: TOP,
      enabledOrigins: [TOP],
    }),
    "same-origin"
  );
});

test("permitted cross-origin child: bound to the child origin, not the top", () => {
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = admit(sender, [CHILD], CHILD);
  assert.equal(result.ok, true);
  assert.equal(result.sender.origin, CHILD);
  assert.equal(result.sender.topOrigin, TOP);
  assert.equal(
    security.computeFrameSupport({
      frameId: 3,
      frameOrigin: CHILD,
      topOrigin: TOP,
      enabledOrigins: [CHILD],
    }),
    "permitted-cross-origin"
  );
});

test("a cross-origin child works even when the top origin is NOT enabled", () => {
  // Proves the child grant is genuinely independent of the top document.
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = admit(sender, [CHILD], CHILD);
  assert.equal(result.ok, true);
});

test("disabled child origin: rejected even when the top origin is enabled", () => {
  // The inverse, and the dangerous one: an enabled top must never lend its
  // authorization to a child frame from another origin.
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = admit(sender, [TOP], CHILD);
  assert.equal(result.ok, false);
  assert.equal(result.error, "disabled");
  assert.equal(
    security.computeFrameSupport({
      frameId: 3,
      frameOrigin: CHILD,
      topOrigin: TOP,
      enabledOrigins: [TOP],
    }),
    "unsupported"
  );
});

test("a child frame cannot claim the enabled top origin in its body", () => {
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = admit(sender, [TOP, CHILD], TOP);
  assert.equal(result.ok, false);
  assert.equal(result.error, "origin_mismatch");
});

test("missing injection: an enabled origin without the host permission fails closed", () => {
  // The script may still be present in an already-open document after the
  // permission was revoked. Background denies it regardless.
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = security.validateContentScriptRequest(
    bootstrapMessage(CHILD),
    sender,
    RUNTIME_ID,
    contextFor([CHILD], { grantedPatterns: [] })
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "permission_missing");
});

test("sandboxed / opaque sender is rejected", () => {
  // Chromium reports `sender.origin === "null"` for a sandboxed frame while
  // `sender.url` may still look like a normal page URL.
  const opaque = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
    origin: "null",
  });
  const result = admit(opaque, [CHILD], CHILD);
  assert.equal(result.ok, false);
  assert.equal(result.error, "opaque_sender_origin");

  // about:srcdoc / about:blank frames have no canonicalizable origin at all.
  for (const url of ["about:srcdoc", "about:blank"]) {
    const aboutFrame = contentScriptSender({
      frameUrl: url,
      topUrl: `${TOP}/login`,
      frameId: 4,
    });
    const aboutResult = admit(aboutFrame, [CHILD, TOP], CHILD);
    assert.equal(aboutResult.ok, false, `${url} must be rejected`);
    assert.equal(aboutResult.error, "invalid_sender_origin");
  }
});

test("sender.origin disagreeing with sender.url fails closed", () => {
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
    origin: TOP,
  });
  const result = admit(sender, [CHILD, TOP], CHILD);
  assert.equal(result.ok, false);
  assert.equal(result.error, "sender_origin_mismatch");
});

test("top URL and frame URL disagreement is rejected for frameId 0", () => {
  // For the top frame the two must be the same document. A record where they
  // differ is inconsistent and is refused rather than reconciled.
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 0,
  });
  const result = admit(sender, [CHILD, TOP], CHILD);
  assert.equal(result.ok, false);
  assert.equal(result.error, "top_frame_origin_mismatch");
});

test("top frame: a tab URL differing only by port or scheme is still a mismatch", () => {
  // Narrower than the test above, and the subtle version: same host, so a
  // host-level comparison would call these equal.
  const cases = [
    ["https://example.com/login", "https://example.com:8443/login"],
    ["https://example.com/login", "http://example.com/login"],
    ["https://example.com/login", "https://www.example.com/login"],
  ];
  for (const [frameUrl, topUrl] of cases) {
    const sender = contentScriptSender({ frameUrl, topUrl, frameId: 0 });
    const frameOrigin = security.canonicalOriginOrNull(frameUrl);
    const result = admit(
      sender,
      [frameOrigin, security.canonicalOriginOrNull(topUrl)],
      frameOrigin
    );
    assert.equal(result.ok, false, `${frameUrl} vs ${topUrl} must be a mismatch`);
    assert.equal(result.error, "top_frame_origin_mismatch");
  }
});

test("a missing top URL is tolerated for a child frame but not for the top frame", () => {
  // Chromium omits `tab.url` without the `tabs` permission for some pages.
  // A child frame is still authorizable from `sender.url` alone.
  const child = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: "",
    frameId: 3,
  });
  const childResult = admit(child, [CHILD], CHILD);
  assert.equal(childResult.ok, true);
  assert.equal(childResult.sender.topOrigin, null);

  const top = contentScriptSender({
    frameUrl: `${TOP}/login`,
    topUrl: "",
    frameId: 0,
  });
  const topResult = admit(top, [TOP], TOP);
  assert.equal(topResult.ok, false);
  assert.equal(topResult.error, "missing_top_origin");
});

test("frame support never upgrades an unenabled frame via its top document", () => {
  for (const frameId of [0, 1, 9]) {
    assert.equal(
      security.computeFrameSupport({
        frameId,
        frameOrigin: CHILD,
        topOrigin: TOP,
        enabledOrigins: [TOP],
      }),
      "unsupported",
      `frameId ${frameId} must stay unsupported`
    );
  }
});

test("frame support rejects an unparseable frame origin outright", () => {
  assert.equal(
    security.computeFrameSupport({
      frameId: 3,
      frameOrigin: "about:blank",
      topOrigin: TOP,
      enabledOrigins: [TOP],
    }),
    "unsupported"
  );
});

test("a different port in the same host is a different frame origin", () => {
  const sender = contentScriptSender({
    frameUrl: "https://example.com:8443/form",
    topUrl: "https://example.com/login",
    frameId: 2,
  });
  // Only the default-port origin is enabled; the :8443 frame is not.
  const result = admit(sender, ["https://example.com"], "https://example.com:8443");
  assert.equal(result.ok, false);
  assert.equal(result.error, "disabled");

  // ...and it is authorized once its own exact origin is enabled, even though
  // both share one Chromium permission pattern.
  const enabled = admit(
    sender,
    ["https://example.com", "https://example.com:8443"],
    "https://example.com:8443"
  );
  assert.equal(enabled.ok, true);
  assert.equal(
    security.permissionPatternForOrigin("https://example.com:8443"),
    security.permissionPatternForOrigin("https://example.com")
  );
});

test("documentId is bound when present and rejected when malformed", () => {
  const withDoc = contentScriptSender({ documentId: "doc-1" });
  const okResult = admit(withDoc, ["https://example.com"], "https://example.com");
  assert.equal(okResult.ok, true);
  assert.equal(okResult.sender.documentId, "doc-1");

  const badDoc = contentScriptSender({ documentId: 17 });
  const badResult = admit(badDoc, ["https://example.com"], "https://example.com");
  assert.equal(badResult.ok, false);
  assert.equal(badResult.error, "invalid_document_id");
});
