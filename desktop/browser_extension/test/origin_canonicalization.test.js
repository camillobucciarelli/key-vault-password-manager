// A004 — shared canonicalization fixture (SR-2).
//
// Every expected value lives in fixtures/origin_canonicalization_v1.json. This
// file asserts against the fixture and against the production canonicalizer;
// it never states an expected origin inline. From Slice A1 the Dart suite reads
// the same file, so a divergence between the two implementations shows up as a
// test failure rather than as a silent authorization gap.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  security,
  RUNTIME_ID,
  loadOriginFixture,
  fixtureCaseById,
  contentScriptSender,
  bootstrapMessage,
  contextFor,
} = require("./helpers.js");

const fixture = loadOriginFixture();

test("fixture declares version 1 with unique ids and every required id", () => {
  assert.equal(fixture.version, 1);
  assert.ok(Array.isArray(fixture.cases));

  const ids = fixture.cases.map((entry) => entry.id);
  assert.equal(new Set(ids).size, ids.length, "fixture case ids must be unique");

  // The required inventory from data-model.md may be extended but never
  // shrunk: a removed case is a silently dropped security vector.
  for (const requiredId of fixture.requiredIds) {
    assert.ok(ids.includes(requiredId), `required fixture id missing: ${requiredId}`);
  }
  assert.equal(fixture.cases.length, ids.length);
  assert.ok(
    fixture.cases.length >= fixture.requiredIds.length,
    "fixture must cover at least the required inventory"
  );
});

test("fixture contains no credential-shaped material", () => {
  // A canonicalization vector never needs a password. Userinfo cases carry a
  // placeholder so a scanner never has to decide whether this is a real leak.
  // Case ids are allowed to *name* the vector (`userinfo-password`); the
  // inputs are what must never carry credential-shaped material.
  const inputs = fixture.cases.map((entry) => entry.input).join("\n").toLowerCase();
  for (const banned of ["password", "passwd", "secret", "token", "apikey"]) {
    assert.ok(!inputs.includes(banned), `fixture input must not contain "${banned}"`);
  }
});

test("every fixture case matches the production canonicalizer", () => {
  for (const entry of fixture.cases) {
    const result = security.canonicalizeOrigin(entry.input);
    assert.equal(result.ok, entry.valid, `validity mismatch for ${entry.id}`);

    if (entry.valid) {
      assert.equal(
        result.origin.serialized,
        entry.canonicalOrigin,
        `canonical origin mismatch for ${entry.id}`
      );
      assert.equal(
        result.origin.effectivePort,
        entry.effectivePort,
        `effective port mismatch for ${entry.id}`
      );
      assert.equal(
        result.permissionPattern,
        entry.permissionPattern,
        `permission pattern mismatch for ${entry.id}`
      );
      assert.equal(entry.error, null, `valid case ${entry.id} must have no error`);
      // Canonical output must be a fixed point: re-canonicalizing it changes
      // nothing. Without this, two spellings could canonicalize to two values
      // that each look "canonical".
      assert.equal(
        security.canonicalOriginOrNull(entry.canonicalOrigin),
        entry.canonicalOrigin,
        `canonical origin for ${entry.id} is not a fixed point`
      );
    } else {
      assert.equal(result.error, entry.error, `error code mismatch for ${entry.id}`);
      assert.equal(result.origin, null);
      assert.equal(
        security.canonicalOriginOrNull(entry.input),
        null,
        `invalid case ${entry.id} must not yield an origin`
      );
    }
  }
});

test("userinfo is rejected by the RAW authority check, not only by the parser", () => {
  // `https://@example.com` is the case that proves the raw check earns its
  // place: the URL parser reports an empty username and password, so a
  // parser-only guard would happily canonicalize this to https://example.com.
  const parsed = new URL("https://@example.com/a");
  assert.equal(parsed.username, "");
  assert.equal(parsed.password, "");
  assert.equal(parsed.hostname, "example.com");

  for (const input of [
    "https://@example.com/a",
    "https://:@example.com/a",
    "https://alice@example.com/a",
    "https://example.com@evil.test/a",
  ]) {
    const result = security.canonicalizeOrigin(input);
    assert.equal(result.ok, false, `${input} must be rejected`);
    assert.equal(result.error, "userinfo_forbidden");
  }
});

test("non-canonical IPv4 spellings are rejected before the parser rewrites them", () => {
  // Each of these is silently normalized to 127.0.0.1 by the URL parser, which
  // would let one enabled origin be reached by five different spellings.
  for (const input of [
    "https://127.1/a",
    "https://127.000.000.001/a",
    "https://0177.0.0.1/a",
    "https://0x7f.0.0.1/a",
    "https://2130706433/a",
  ]) {
    assert.equal(new URL(input).hostname, "127.0.0.1", `${input} parser assumption`);
    const result = security.canonicalizeOrigin(input);
    assert.equal(result.ok, false, `${input} must be rejected`);
    assert.equal(result.error, "noncanonical_ipv4");
  }
  // The canonical spelling still works.
  assert.equal(
    security.canonicalOriginOrNull("https://127.0.0.1/a"),
    "https://127.0.0.1"
  );
});

test("declared equal groups are equal under the full origin tuple", () => {
  for (const group of fixture.equalGroups) {
    const members = group.caseIds.map((id) => fixtureCaseById(fixture, id));
    const [first, ...rest] = members;
    for (const other of rest) {
      assert.ok(
        security.originsEqual(first.input, other.input),
        `${group.id}: ${first.id} and ${other.id} must be the same origin`
      );
      assert.equal(first.canonicalOrigin, other.canonicalOrigin);
    }
  }
});

test("declared distinct groups differ pairwise", () => {
  for (const group of fixture.distinctGroups) {
    const members = group.caseIds.map((id) => fixtureCaseById(fixture, id));
    for (let i = 0; i < members.length; i += 1) {
      for (let j = i + 1; j < members.length; j += 1) {
        assert.ok(
          !security.originsEqual(members[i].input, members[j].input),
          `${group.id}: ${members[i].id} must differ from ${members[j].id}`
        );
        assert.notEqual(members[i].canonicalOrigin, members[j].canonicalOrigin);
      }
    }
  }
});

test("scheme, port and phishing suffix are the three named inequalities", () => {
  // Spelled out because SR-2 names these three explicitly; the fixture groups
  // above would still pass if one of them were quietly dropped from the file.
  assert.ok(!security.originsEqual("http://example.com", "https://example.com"));
  assert.ok(!security.originsEqual("https://example.com", "https://example.com:8443"));
  assert.ok(
    !security.originsEqual("https://example.com", "https://example.com.evil.test")
  );
});

test("host-prefix labels are never stripped for authorization", () => {
  // The Dart possible-match helper routes through _cleanHost, which removes
  // www./m./mobile.. If that rule ever reaches this path, these fail.
  for (const prefixed of [
    "https://www.example.com",
    "https://m.example.com",
    "https://mobile.example.com",
  ]) {
    assert.ok(
      !security.originsEqual(prefixed, "https://example.com"),
      `${prefixed} must not collapse to https://example.com`
    );
    assert.equal(security.canonicalOriginOrNull(prefixed), prefixed);
  }
});

test("permission pattern drops the port, so exact-origin checks stay mandatory", () => {
  const plain = fixtureCaseById(fixture, "https-plain");
  const ported = fixtureCaseById(fixture, "https-nondefault-port");
  assert.equal(plain.permissionPattern, ported.permissionPattern);
  assert.notEqual(plain.canonicalOrigin, ported.canonicalOrigin);
});

test("body origin is derived from sender.url, not sender.tab.url and not the host", () => {
  // A permitted cross-origin child frame: the top document is a different
  // origin, and the shared registrable host is irrelevant.
  const frameOrigin = "https://child.example";
  const topOrigin = "https://top.example";
  const sender = contentScriptSender({
    frameUrl: `${frameOrigin}/form`,
    topUrl: `${topOrigin}/page`,
    frameId: 3,
  });

  const accepted = security.validateContentScriptRequest(
    bootstrapMessage(frameOrigin),
    sender,
    RUNTIME_ID,
    contextFor([frameOrigin])
  );
  assert.equal(accepted.ok, true);
  assert.equal(accepted.sender.origin, frameOrigin);
  assert.equal(accepted.sender.topOrigin, topOrigin);

  // Claiming the top origin in the body is rejected even though the top
  // document is a real, enabled origin of this very tab.
  const spoofedTop = security.validateContentScriptRequest(
    bootstrapMessage(topOrigin),
    sender,
    RUNTIME_ID,
    contextFor([frameOrigin, topOrigin])
  );
  assert.equal(spoofedTop.ok, false);
  assert.equal(spoofedTop.error, "origin_mismatch");

  // Claiming a bare host is rejected: a host is not an origin.
  const spoofedHost = security.validateContentScriptRequest(
    bootstrapMessage("child.example"),
    sender,
    RUNTIME_ID,
    contextFor([frameOrigin])
  );
  assert.equal(spoofedHost.ok, false);
  assert.equal(spoofedHost.key, "origin");
});

test("a non-canonical spelling of the correct origin is still rejected in the body", () => {
  const sender = contentScriptSender({ frameUrl: "https://example.com/login" });
  for (const spelling of [
    "https://example.com:443",
    "https://EXAMPLE.com",
    "https://example.com/",
    "https://example.com.",
  ]) {
    const result = security.validateContentScriptRequest(
      bootstrapMessage(spelling),
      sender,
      RUNTIME_ID,
      contextFor(["https://example.com"])
    );
    assert.equal(result.ok, false, `${spelling} must not be accepted verbatim`);
  }
});
