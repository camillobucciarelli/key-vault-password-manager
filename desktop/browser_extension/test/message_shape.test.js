// A007 / SR-5 — persisted config and metadata messages carry no secret.
//
// Every assertion here calls the same validator the extension calls. There is
// no second copy of the allowlist in this file: the catalogue is read back out
// of `overlay_security.js`, so adding a field to a schema without thinking
// about it will surface here rather than silently widen the surface.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  security,
  RUNTIME_ID,
  contentScriptSender,
  requestMatchesMessage,
  fillMessage,
  bootstrapMessage,
  bindingA,
  configWith,
  contextFor,
} = require("./helpers.js");

const ENABLED = ["https://example.com"];

function validMatchesResult(overrides = {}) {
  return {
    ok: true,
    type: "matchesResult",
    origin: "https://example.com",
    focusNonce: "nonce-1",
    revision: 17,
    sessionBinding: bindingA(),
    items: [
      {
        entryId: "entry-1",
        title: "Example",
        displayService: "example.com",
        matchType: "exact-origin",
        fillEligible: true,
      },
    ],
    fillToken: "token-1",
    expiresAtEpochMs: 1720000030000,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Persisted overlayConfigV1
// ---------------------------------------------------------------------------

test("a well-formed overlayConfigV1 is accepted", () => {
  assert.equal(
    security.validateOverlayConfig(
      configWith(["https://example.com", "https://example.com:8443"])
    ).ok,
    true
  );
  assert.equal(security.validateOverlayConfig(security.emptyOverlayConfig()).ok, true);
});

test("persisted config rejects password, secret, username and payload dumps", () => {
  for (const key of security.FORBIDDEN_KEYS) {
    const polluted = { ...configWith(ENABLED), [key]: "anything" };
    const result = security.validateOverlayConfig(polluted);
    assert.equal(result.ok, false, `config must reject key "${key}"`);
    // Either named as forbidden or refused as unknown — never accepted.
    assert.ok(["forbidden_key", "unknown_key"].includes(result.error));
    assert.equal(result.key, key);
  }
});

test("persisted config rejects a nested secret at any depth", () => {
  const nested = {
    ...configWith(ENABLED),
    // Not even an allowlisted key may smuggle one in as a sub-object.
    revision: 17,
  };
  nested.enabledOrigins = [{ origin: "https://example.com", password: "x" }];
  const result = security.validateOverlayConfig(nested);
  assert.equal(result.ok, false);
  // The forbidden-key sweep runs before origin canonicalization, so the
  // secret is named as such rather than being reported as a bad origin.
  assert.equal(result.error, "forbidden_key");
  assert.equal(result.key, "password");

  const deep = { version: 1, revision: 1, enabledOrigins: [], meta: { secret: "x" } };
  const deepResult = security.validateOverlayConfig(deep);
  assert.equal(deepResult.ok, false);
  assert.equal(deepResult.error, "unknown_key");
});

test("persisted config rejects unknown keys, wrong versions and wrong types", () => {
  const cases = [
    [{ ...configWith(ENABLED), dismissed: true }, "unknown_key"],
    [{ ...configWith(ENABLED), version: 2 }, "invalid_type"],
    [{ ...configWith(ENABLED), revision: -1 }, "invalid_type"],
    [{ ...configWith(ENABLED), revision: "17" }, "invalid_type"],
    [{ ...configWith(ENABLED), enabledOrigins: "https://example.com" }, "invalid_type"],
    [{ version: 1, revision: 1 }, "missing_key"],
    [null, "not_an_object"],
    [[], "not_an_object"],
    ["overlayConfigV1", "not_an_object"],
  ];
  for (const [value, expected] of cases) {
    const result = security.validateOverlayConfig(value);
    assert.equal(result.ok, false, `${JSON.stringify(value)} must be rejected`);
    assert.equal(result.error, expected, `${JSON.stringify(value)}`);
  }
});

test("persisted config rejects non-canonical, duplicate, unsorted or oversized origins", () => {
  const cases = [
    [["https://EXAMPLE.com"], "noncanonical_origin"],
    [["https://example.com/"], "noncanonical_origin"],
    [["https://example.com:443"], "noncanonical_origin"],
    [["example.com"], "noncanonical_origin"],
    [["https://alice@example.com"], "noncanonical_origin"],
    [["https://example.com", "https://example.com"], "duplicate_origin"],
    [["https://z.example", "https://a.example"], "unsorted_origins"],
  ];
  for (const [origins, expected] of cases) {
    const result = security.validateOverlayConfig({
      version: 1,
      revision: 1,
      enabledOrigins: origins,
    });
    assert.equal(result.ok, false, `${JSON.stringify(origins)} must be rejected`);
    assert.equal(result.error, expected);
  }

  const tooMany = Array.from(
    { length: security.LIMITS.ENABLED_ORIGINS + 1 },
    (_, i) => `https://host${String(i).padStart(4, "0")}.example`
  );
  const overflow = security.validateOverlayConfig({
    version: 1,
    revision: 1,
    enabledOrigins: tooMany,
  });
  assert.equal(overflow.ok, false);
  assert.equal(overflow.error, "invalid_type");
  assert.equal(overflow.key, "enabledOrigins");
});

test("an invalid stored config loads as zero enabled origins, never partially", () => {
  for (const broken of [
    undefined,
    null,
    "{}",
    { version: 2, revision: 1, enabledOrigins: ["https://example.com"] },
    { version: 1, revision: 1, enabledOrigins: ["https://example.com"], password: "x" },
    { version: 1, revision: 1, enabledOrigins: ["https://EXAMPLE.com"] },
  ]) {
    const loaded = security.loadOverlayConfigOrEmpty(broken);
    assert.deepEqual(loaded.enabledOrigins, []);
    assert.equal(security.validateOverlayConfig(loaded).ok, true);
  }
});

test("a config recovered from an invalid value authorizes nothing", () => {
  const loaded = security.loadOverlayConfigOrEmpty({ version: 9 });
  const result = security.validateContentScriptRequest(
    bootstrapMessage(),
    contentScriptSender(),
    RUNTIME_ID,
    { enabledOrigins: loaded.enabledOrigins }
  );
  assert.equal(result.ok, false);
  assert.equal(result.error, "disabled");
});

// ---------------------------------------------------------------------------
// Outbound metadata messages
// ---------------------------------------------------------------------------

test("a metadata-only matchesResult is accepted", () => {
  assert.equal(security.validateMatchesResult(validMatchesResult()).ok, true);
});

test("matchesResult rejects password, username, secret and native payload dumps", () => {
  for (const key of security.FORBIDDEN_KEYS) {
    const polluted = validMatchesResult({ [key]: "leak" });
    const result = security.validateMatchesResult(polluted);
    assert.equal(result.ok, false, `matchesResult must reject "${key}"`);
    assert.equal(result.error, "forbidden_key");
    assert.equal(result.key, key);
  }
});

test("a match item rejects password and username on the row itself", () => {
  for (const key of ["password", "username", "secret", "credential"]) {
    const item = {
      entryId: "entry-1",
      title: "Example",
      displayService: "example.com",
      matchType: "exact-origin",
      fillEligible: true,
      [key]: "leak",
    };
    const itemResult = security.validateMatchItem(item);
    assert.equal(itemResult.ok, false, `item must reject "${key}"`);
    assert.equal(itemResult.error, "forbidden_key");

    const wrapped = security.validateMatchesResult(validMatchesResult({ items: [item] }));
    assert.equal(wrapped.ok, false, `matchesResult must reject item key "${key}"`);
    assert.equal(wrapped.error, "forbidden_key");
  }
});

test("a native response cannot be attached to a metadata message", () => {
  // The exact failure mode SR-5 calls out: forwarding the raw native payload
  // "for debugging" would carry a password.
  const dumped = validMatchesResult({
    data: { username: "alice", password: "leak" },
  });
  const result = security.validateMatchesResult(dumped);
  assert.equal(result.ok, false);
  assert.equal(result.error, "forbidden_key");
  assert.equal(result.key, "data");
});

test("matchesResult rejects unknown keys and bad item shapes", () => {
  const cases = [
    [validMatchesResult({ debug: true }), "unknown_key"],
    [validMatchesResult({ items: [{ entryId: "entry-1" }] }), "missing_key"],
    [
      validMatchesResult({
        items: [
          {
            entryId: "entry-1",
            title: "Example",
            displayService: "example.com",
            matchType: "strong",
            fillEligible: true,
          },
        ],
      }),
      "invalid_type",
    ],
    [validMatchesResult({ sessionBinding: { databaseId: "db-a" } }), "invalid_type"],
    [validMatchesResult({ origin: "https://EXAMPLE.com" }), "invalid_type"],
    [validMatchesResult({ items: "none" }), "invalid_type"],
  ];
  for (const [message, expected] of cases) {
    const result = security.validateMatchesResult(message);
    assert.equal(result.ok, false);
    assert.equal(result.error, expected);
  }
});

test("matchesResult enforces the item cap", () => {
  const many = Array.from({ length: security.LIMITS.ITEMS + 1 }, (_, i) => ({
    entryId: `entry-${i}`,
    title: "Example",
    displayService: "example.com",
    matchType: "possible",
    fillEligible: false,
  }));
  const result = security.validateMatchesResult(validMatchesResult({ items: many }));
  assert.equal(result.ok, false);
  assert.equal(result.error, "invalid_type");
  assert.equal(result.key, "items");
});

test("a fill token cannot accompany a result with nothing fillable", () => {
  const possibleOnly = validMatchesResult({
    items: [
      {
        entryId: "entry-2",
        title: "Example legacy",
        displayService: "example.com",
        matchType: "possible",
        fillEligible: false,
      },
    ],
  });
  const result = security.validateMatchesResult(possibleOnly);
  assert.equal(result.ok, false);
  assert.equal(result.error, "token_without_fillable_item");

  // Without a token the same possible-only result is fine.
  delete possibleOnly.fillToken;
  delete possibleOnly.expiresAtEpochMs;
  assert.equal(security.validateMatchesResult(possibleOnly).ok, true);
});

// ---------------------------------------------------------------------------
// Inbound content messages
// ---------------------------------------------------------------------------

test("inbound content messages reject credential fields outright", () => {
  for (const key of ["password", "username", "secret", "data"]) {
    for (const base of [requestMatchesMessage(), fillMessage(), bootstrapMessage()]) {
      const result = security.validateContentScriptRequest(
        { ...base, [key]: "leak" },
        contentScriptSender(),
        RUNTIME_ID,
        contextFor(ENABLED)
      );
      assert.equal(result.ok, false, `${base.type} must reject "${key}"`);
      assert.equal(result.error, "forbidden_key");
      assert.equal(result.key, key);
    }
  }
});

test("no message schema in the catalogue declares a credential field", () => {
  // Guards the catalogue itself, not one message: a future schema edit that
  // adds `username` to a route fails here.
  const routes = [security.EXTENSION_PAGE_ROUTE, security.CONTENT_SCRIPT_ROUTE];
  for (const route of routes) {
    for (const type of security.messageTypesForRoute(route)) {
      const probe = security.validateMessageForRoute(
        { channel: security.CHANNEL, version: security.MESSAGE_VERSION, type },
        route
      );
      // A schema is missing required keys, never carrying a forbidden one.
      assert.notEqual(probe.error, "forbidden_key", `${type} declares a forbidden key`);
    }
  }
  for (const required of ["password", "secret", "username", "payload", "data"]) {
    assert.ok(
      security.FORBIDDEN_KEYS.includes(required),
      `${required} must remain forbidden`
    );
  }
});

test("assertNoForbiddenKeys walks arrays and nested objects", () => {
  assert.equal(security.assertNoForbiddenKeys({ a: { b: [{ c: 1 }] } }).ok, true);
  const nested = security.assertNoForbiddenKeys({ a: { b: [{ password: "x" }] } });
  assert.equal(nested.ok, false);
  assert.equal(nested.key, "password");
  const inArray = security.assertNoForbiddenKeys([{ ok: 1 }, { secret: "x" }]);
  assert.equal(inArray.ok, false);
  assert.equal(inArray.key, "secret");
});

test("error results never echo the offending value, only the key name", () => {
  const leaked = "kv-test-only-not-a-real-password";
  const result = security.validateContentScriptRequest(
    { ...bootstrapMessage(), password: leaked },
    contentScriptSender(),
    RUNTIME_ID,
    contextFor(ENABLED)
  );
  assert.equal(result.ok, false);
  assert.ok(!JSON.stringify(result).includes(leaked));
});
