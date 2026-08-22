// A005 / SR-7 — frame contexts.
//
// The single rule under test: IDENTITY follows the SENDER FRAME.
// `sender.tab.url` is top-level context and never substitutes for
// `sender.url`, in either direction.
//
// Slice C turned the opt-in into one global switch, so these tests no longer
// vary WHICH origins are enabled. What they still pin — and what Slice C could
// not be allowed to weaken — is that every frame is bound to its own exact
// origin, port and scheme included, and that a frame can never borrow its
// parent's identity to widen what the app will reveal to it.

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

function admit(sender, bodyOrigin) {
  return security.validateContentScriptRequest(
    bootstrapMessage(bodyOrigin),
    sender,
    RUNTIME_ID,
    contextFor()
  );
}

test("top frame: supported when its exact origin is enabled", () => {
  const sender = contentScriptSender({
    frameUrl: `${TOP}/login`,
    topUrl: `${TOP}/login`,
    frameId: 0,
  });
  const result = admit(sender, TOP);
  assert.equal(result.ok, true);
  assert.equal(result.sender.frameId, 0);
  assert.equal(
    security.computeFrameSupport({
      frameId: 0,
      frameOrigin: TOP,
      topOrigin: TOP,
      enabled: true,
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
  const result = admit(sender, TOP);
  assert.equal(result.ok, true);
  assert.equal(result.sender.frameId, 7);
  assert.equal(
    security.computeFrameSupport({
      frameId: 7,
      frameOrigin: TOP,
      topOrigin: TOP,
      enabled: true,
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
  const result = admit(sender, CHILD);
  assert.equal(result.ok, true);
  assert.equal(result.sender.origin, CHILD);
  assert.equal(result.sender.topOrigin, TOP);
  assert.equal(
    security.computeFrameSupport({
      frameId: 3,
      frameOrigin: CHILD,
      topOrigin: TOP,
      enabled: true,
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
  const result = admit(sender, CHILD);
  assert.equal(result.ok, true);
});

// SLICE C REPLACEMENT. The Slice A2 form asserted that a child frame on a
// NOT-ENABLED origin was refused inside an enabled top. With one global switch
// there is no such thing as a not-enabled origin, so that exact outcome is
// gone — but the property it protected is not, and it is the dangerous half:
// an authorized top document must never lend its identity to a cross-origin
// child. What enforces it now is that the authoritative origin is derived from
// the CHILD's own `sender.url`, so the child is bound to itself and queries the
// native host as itself.
test("an authorized top never lends its identity to a cross-origin child", () => {
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = admit(sender, CHILD);
  assert.equal(result.ok, true);
  // The binding is the child's own origin, never the top's.
  assert.equal(result.sender.origin, CHILD);
  assert.notEqual(result.sender.origin, TOP);
  assert.equal(result.sender.topOrigin, TOP);
  assert.equal(
    security.computeFrameSupport({
      frameId: 3,
      frameOrigin: CHILD,
      topOrigin: TOP,
      enabled: true,
    }),
    "permitted-cross-origin"
  );
});

test("a child frame cannot claim the enabled top origin in its body", () => {
  const sender = contentScriptSender({
    frameUrl: `${CHILD}/form`,
    topUrl: `${TOP}/login`,
    frameId: 3,
  });
  const result = admit(sender, TOP);
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
    contextFor({ grantedPatterns: [] })
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
  const result = admit(opaque, CHILD);
  assert.equal(result.ok, false);
  assert.equal(result.error, "opaque_sender_origin");

  // about:srcdoc / about:blank frames have no canonicalizable origin at all.
  for (const url of ["about:srcdoc", "about:blank"]) {
    const aboutFrame = contentScriptSender({
      frameUrl: url,
      topUrl: `${TOP}/login`,
      frameId: 4,
    });
    const aboutResult = admit(aboutFrame, CHILD);
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
  const result = admit(sender, CHILD);
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
  const result = admit(sender, CHILD);
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
    const result = admit(sender, frameOrigin
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
  const childResult = admit(child, CHILD);
  assert.equal(childResult.ok, true);
  assert.equal(childResult.sender.topOrigin, null);

  const top = contentScriptSender({
    frameUrl: `${TOP}/login`,
    topUrl: "",
    frameId: 0,
  });
  const topResult = admit(top, TOP);
  assert.equal(topResult.ok, false);
  assert.equal(topResult.error, "missing_top_origin");
});

test("frame support never upgrades any frame while the switch is off", () => {
  for (const frameId of [0, 1, 9]) {
    for (const enabled of [false, undefined, null, "true", 1]) {
      assert.equal(
        security.computeFrameSupport({
          frameId,
          frameOrigin: CHILD,
          topOrigin: TOP,
          enabled,
        }),
        "unsupported",
        `frameId ${frameId} with enabled=${String(enabled)} must stay unsupported`
      );
    }
  }
});

// A035 REACHABILITY PROOF, kept as an executable claim rather than a comment.
// The broad grant covers every http(s) FRAME, but the top document's origin
// comes from `sender.tab.url`, which is not canonicalizable when the TAB is a
// `file://`, `view-source:`, `data:` or PDF document. An http(s) iframe inside
// one of those is injected and must classify as unsupported.
test("a child frame under a non-canonicalizable top is still unsupported", () => {
  const tops = [
    "file:///home/user/page.html",
    "view-source:https://x.example",
    "data:text/html,x",
    "",
    null,
  ];
  for (const topUrl of tops) {
    assert.equal(
      security.computeFrameSupport({
        frameId: 3,
        frameOrigin: CHILD,
        topOrigin: topUrl,
        enabled: true,
      }),
      "unsupported",
      `top ${String(topUrl)} must leave the child unsupported`
    );
  }
});

test("frame support rejects an unparseable frame origin outright", () => {
  assert.equal(
    security.computeFrameSupport({
      frameId: 3,
      frameOrigin: "about:blank",
      topOrigin: TOP,
      enabled: true,
    }),
    "unsupported"
  );
});

// SLICE C: the port is no longer what decides whether a frame is ENABLED —
// one switch covers every origin. It is still what decides the frame's
// IDENTITY, which is the half that matters for the reveal: the authoritative
// origin keeps the port, and a body claiming the sibling port is refused.
test("a different port in the same host is still a different frame origin", () => {
  const sender = contentScriptSender({
    frameUrl: "https://example.com:8443/form",
    topUrl: "https://example.com/login",
    frameId: 2,
  });

  // Claiming the default-port origin from an :8443 frame is a mismatch, not a
  // tolerated approximation.
  const spoofed = admit(sender, "https://example.com");
  assert.equal(spoofed.ok, false);
  assert.equal(spoofed.error, "origin_mismatch");

  // Its own exact origin is admitted, and carries the port through to the
  // value the native query and the reveal are bound to.
  const honest = admit(sender, "https://example.com:8443");
  assert.equal(honest.ok, true);
  assert.equal(honest.sender.origin, "https://example.com:8443");
});

test("documentId is bound when present and rejected when malformed", () => {
  const withDoc = contentScriptSender({ documentId: "doc-1" });
  const okResult = admit(withDoc, "https://example.com");
  assert.equal(okResult.ok, true);
  assert.equal(okResult.sender.documentId, "doc-1");

  const badDoc = contentScriptSender({ documentId: 17 });
  const badResult = admit(badDoc, "https://example.com");
  assert.equal(badResult.ok, false);
  assert.equal(badResult.error, "invalid_document_id");
});
