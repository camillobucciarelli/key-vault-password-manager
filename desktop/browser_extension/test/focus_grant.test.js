// A006 / SR-3 + SR-4 — focus nonce, fill token, and session binding.
//
// Tokens live only in worker memory. Every test below drives the production
// `FocusGrantStore`; the clock is passed in explicitly so expiry is asserted
// deterministically rather than slept on.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { security, bindingA, bindingB } = require("./helpers.js");

const ORIGIN = "https://example.com:8443";
const NOW = 1720000000000;

function newStore(options) {
  return new security.FocusGrantStore(options);
}

function issueDefault(store, overrides = {}) {
  return store.issue({
    tabId: 42,
    frameId: 3,
    documentId: "doc-1",
    origin: ORIGIN,
    focusNonce: "nonce-1",
    entryIds: ["entry-1"],
    sessionBinding: bindingA(),
    configRevision: 17,
    nowMs: NOW,
    ...overrides,
  });
}

function consumeDefault(store, token, overrides = {}) {
  return store.consume({
    token,
    tabId: 42,
    frameId: 3,
    documentId: "doc-1",
    origin: ORIGIN,
    focusNonce: "nonce-1",
    entryId: "entry-1",
    sessionBinding: bindingA(),
    configRevision: 17,
    currentBinding: bindingA(),
    nowMs: NOW + 1000,
    ...overrides,
  });
}

// ---------------------------------------------------------------------------
// Issue and bind
// ---------------------------------------------------------------------------

test("a grant binds tab, frame, document, origin, nonce, entry ids and binding", () => {
  const store = newStore();
  const issued = issueDefault(store);
  assert.ok(issued);

  const grant = store.peek(issued.token);
  assert.equal(grant.tabId, 42);
  assert.equal(grant.frameId, 3);
  assert.equal(grant.documentId, "doc-1");
  assert.equal(grant.origin, ORIGIN);
  assert.equal(grant.focusNonce, "nonce-1");
  assert.deepEqual(grant.entryIds, ["entry-1"]);
  assert.deepEqual(grant.sessionBinding, bindingA());
  assert.equal(grant.configRevision, 17);
});

test("tokens are random and never repeat across grants", () => {
  const store = newStore();
  const tokens = new Set();
  for (let i = 0; i < 50; i += 1) {
    const issued = issueDefault(store, { frameId: i, focusNonce: `nonce-${i}` });
    assert.ok(!tokens.has(issued.token), "token reuse");
    tokens.add(issued.token);
    assert.ok(issued.token.length >= 16);
  }
});

test("a grant is refused when its inputs are not authorizable", () => {
  const store = newStore();
  // A non-canonical origin can never back a grant.
  assert.equal(issueDefault(store, { origin: "https://EXAMPLE.com:8443" }), null);
  assert.equal(issueDefault(store, { origin: "example.com" }), null);
  // No fillable entry means no token at all.
  assert.equal(issueDefault(store, { entryIds: [] }), null);
  // A malformed session binding is not a grantable session.
  assert.equal(issueDefault(store, { sessionBinding: { databaseId: "db-a" } }), null);
  assert.equal(store.size, 0);
});

// ---------------------------------------------------------------------------
// Expiry — SR-3 caps at 30 seconds
// ---------------------------------------------------------------------------

test("expiry is capped at 30 seconds even when a longer TTL is requested", () => {
  const store = newStore();
  const issued = issueDefault(store, { ttlMs: 10 * 60 * 1000 });
  assert.equal(issued.expiresAtEpochMs, NOW + security.LIMITS.TOKEN_TTL_MS);
  assert.equal(security.LIMITS.TOKEN_TTL_MS, 30000);
});

test("a shorter TTL is honoured and never extended", () => {
  const store = newStore();
  const issued = issueDefault(store, { ttlMs: 5000 });
  assert.equal(issued.expiresAtEpochMs, NOW + 5000);
});

test("a token is stale exactly at and after its expiry", () => {
  const store = newStore();
  const justInside = issueDefault(store);
  assert.equal(
    consumeDefault(store, justInside.token, {
      nowMs: NOW + security.LIMITS.TOKEN_TTL_MS - 1,
    }).ok,
    true
  );

  const atBoundary = issueDefault(store);
  const boundary = consumeDefault(store, atBoundary.token, {
    nowMs: NOW + security.LIMITS.TOKEN_TTL_MS,
  });
  assert.equal(boundary.ok, false);
  assert.equal(boundary.error, "stale_session");

  const past = issueDefault(store);
  const expired = consumeDefault(store, past.token, {
    nowMs: NOW + security.LIMITS.TOKEN_TTL_MS + 1,
  });
  assert.equal(expired.ok, false);
  assert.equal(expired.error, "stale_session");
});

test("an expired token is refused even when every other field matches exactly", () => {
  // Independent of the boundary test above: here the only thing wrong is the
  // clock. Tab, frame, document, origin, nonce, entry, revision and binding
  // are all correct, so nothing but the expiry check can reject this.
  for (const elapsed of [30000, 30001, 60000, 24 * 60 * 60 * 1000]) {
    const store = newStore();
    const issued = issueDefault(store);
    const result = consumeDefault(store, issued.token, { nowMs: NOW + elapsed });
    assert.equal(result.ok, false, `elapsed ${elapsed}ms must be refused`);
    assert.equal(result.error, "stale_session");
    assert.equal(result.grant, undefined);
  }
});

test("a token issued with a short TTL expires on its own schedule, not the cap", () => {
  // Catches an expiry check that compares against the 30s ceiling instead of
  // the grant's own recorded expiry.
  const store = newStore();
  const issued = issueDefault(store, { ttlMs: 2000 });
  const afterOwnExpiry = consumeDefault(store, issued.token, { nowMs: NOW + 2500 });
  assert.equal(afterOwnExpiry.ok, false);
  assert.equal(afterOwnExpiry.error, "stale_session");
});

test("a missing or non-integer clock is treated as expired, not as valid", () => {
  for (const nowMs of [undefined, null, NaN, "1720000001000"]) {
    const store = newStore();
    const issued = issueDefault(store);
    const result = consumeDefault(store, issued.token, { nowMs });
    assert.equal(result.ok, false, `clock ${String(nowMs)} must fail closed`);
    assert.equal(result.error, "stale_session");
  }
});

// ---------------------------------------------------------------------------
// One-shot consumption
// ---------------------------------------------------------------------------

test("a token is consumed once; a replay is stale", () => {
  const store = newStore();
  const issued = issueDefault(store);
  assert.equal(consumeDefault(store, issued.token).ok, true);

  const replay = consumeDefault(store, issued.token);
  assert.equal(replay.ok, false);
  assert.equal(replay.error, "stale_session");
  assert.equal(store.size, 0);
});

test("a token is burned even when the attempt fails a later check", () => {
  // Otherwise an attacker could probe entry ids with one token repeatedly.
  const store = newStore();
  const issued = issueDefault(store);
  const wrongEntry = consumeDefault(store, issued.token, { entryId: "entry-2" });
  assert.equal(wrongEntry.ok, false);
  assert.equal(wrongEntry.error, "forbidden");

  const retry = consumeDefault(store, issued.token);
  assert.equal(retry.ok, false);
  assert.equal(retry.error, "stale_session");
});

test("an unknown or malformed token is stale", () => {
  const store = newStore();
  issueDefault(store);
  for (const token of ["not-a-token", "", null, undefined, 42]) {
    const result = consumeDefault(store, token);
    assert.equal(result.ok, false);
    assert.equal(result.error, "stale_session");
  }
});

// ---------------------------------------------------------------------------
// Sender context must match
// ---------------------------------------------------------------------------

test("a token from another tab, frame, document or origin is refused", () => {
  const cases = [
    [{ tabId: 43 }, "forbidden"],
    [{ frameId: 4 }, "forbidden"],
    [{ documentId: "doc-2" }, "forbidden"],
    [{ documentId: null }, "forbidden"],
    [{ origin: "https://example.com" }, "forbidden"],
    [{ origin: "http://example.com:8443" }, "forbidden"],
    [{ focusNonce: "nonce-2" }, "stale_session"],
    [{ configRevision: 18 }, "stale_session"],
    [{ entryId: "entry-9" }, "forbidden"],
  ];
  for (const [overrides, expected] of cases) {
    const store = newStore();
    const issued = issueDefault(store);
    const result = consumeDefault(store, issued.token, overrides);
    assert.equal(result.ok, false, `${JSON.stringify(overrides)} must be refused`);
    assert.equal(result.error, expected, `${JSON.stringify(overrides)}`);
  }
});

test("only entry ids advertised as fillable can be filled", () => {
  const store = newStore();
  const issued = issueDefault(store, { entryIds: ["entry-1", "entry-3"] });
  assert.equal(consumeDefault(store, issued.token, { entryId: "entry-3" }).ok, true);

  const second = issueDefault(store, { entryIds: ["entry-1", "entry-3"] });
  const refused = consumeDefault(store, second.token, { entryId: "entry-2" });
  assert.equal(refused.ok, false);
  assert.equal(refused.error, "forbidden");
});

// ---------------------------------------------------------------------------
// SR-4 — vault / cache / bridge generation binding
// ---------------------------------------------------------------------------

test("all three binding fields are compared; changing any one is stale", () => {
  const mutations = [
    { databaseId: "db-z" },
    { cacheGeneration: "cache-a2" },
    { bridgeGeneration: "bridge-a2" },
  ];
  for (const mutation of mutations) {
    const store = newStore();
    const issued = issueDefault(store);
    const result = consumeDefault(store, issued.token, {
      sessionBinding: { ...bindingA(), ...mutation },
    });
    assert.equal(result.ok, false, `${JSON.stringify(mutation)} must be stale`);
    assert.equal(result.error, "stale_session");
  }
});

test("a cache republish of the same vault invalidates the grant", () => {
  const store = newStore();
  const issued = issueDefault(store);
  const republished = { ...bindingA(), cacheGeneration: "cache-a2" };
  const result = consumeDefault(store, issued.token, { currentBinding: republished });
  assert.equal(result.ok, false);
  assert.equal(result.error, "stale_session");
});

test("a bridge restart of the same vault invalidates the grant", () => {
  const store = newStore();
  const issued = issueDefault(store);
  const restarted = { ...bindingA(), bridgeGeneration: "bridge-a2" };
  const result = consumeDefault(store, issued.token, { currentBinding: restarted });
  assert.equal(result.ok, false);
  assert.equal(result.error, "stale_session");
});

test("REGRESSION vault A -> B: same entry UUID and same exact origin stay stale", () => {
  // The scenario spec 009 marks mandatory. Everything the attacker controls is
  // identical between the two vaults: same entry id, same origin, same tab,
  // same frame, same nonce, same token. Only the session binding differs.
  const ENTRY_UUID = "11111111-2222-3333-4444-555555555555";
  const store = newStore();
  const issued = store.issue({
    tabId: 42,
    frameId: 3,
    documentId: "doc-1",
    origin: ORIGIN,
    focusNonce: "nonce-1",
    entryIds: [ENTRY_UUID],
    sessionBinding: bindingA(),
    configRevision: 17,
    nowMs: NOW,
  });

  // The worker has not yet observed the vault switch: the grant is still in
  // the map, and the content script echoes vault A's binding faithfully.
  const usedAfterSwitch = store.consume({
    token: issued.token,
    tabId: 42,
    frameId: 3,
    documentId: "doc-1",
    origin: ORIGIN,
    focusNonce: "nonce-1",
    entryId: ENTRY_UUID,
    sessionBinding: bindingA(),
    configRevision: 17,
    currentBinding: bindingB(), // vault B is what is actually live now
    nowMs: NOW + 1000,
  });
  assert.equal(usedAfterSwitch.ok, false);
  assert.equal(usedAfterSwitch.error, "stale_session");
  assert.equal(usedAfterSwitch.grant, undefined, "no grant is handed back");

  // A delayed reveal response from vault A, arriving after the switch, is
  // discarded at the comparison boundary.
  assert.equal(
    security.validateResponseBinding({
      echoed: bindingA(),
      expected: bindingA(),
      current: bindingB(),
    }),
    "stale_session"
  );

  // And a response that echoes vault B against a vault A expectation — i.e. an
  // attempt to deliver B's secret through A's grant — is equally refused.
  assert.equal(
    security.validateResponseBinding({
      echoed: bindingB(),
      expected: bindingA(),
      current: bindingB(),
    }),
    "stale_session"
  );

  // The only accepted shape is full agreement.
  assert.equal(
    security.validateResponseBinding({
      echoed: bindingA(),
      expected: bindingA(),
      current: bindingA(),
    }),
    null
  );
});

test("binding equality requires all three fields to be present and exact", () => {
  assert.equal(security.sessionBindingsEqual(bindingA(), bindingA()), true);
  assert.equal(security.sessionBindingsEqual(bindingA(), bindingB()), false);
  const partial = { databaseId: "db-a", cacheGeneration: "cache-a1" };
  assert.equal(security.sessionBindingsEqual(bindingA(), partial), false);
  const extra = { ...bindingA(), extra: "x" };
  assert.equal(security.sessionBindingsEqual(bindingA(), extra), false);
  assert.equal(security.sessionBindingsEqual(null, null), false);
});

// ---------------------------------------------------------------------------
// Invalidation, eviction, worker reset
// ---------------------------------------------------------------------------

test("a newer focus on the same frame replaces the previous grant", () => {
  const store = newStore();
  const first = issueDefault(store);
  const second = issueDefault(store, { focusNonce: "nonce-2" });
  assert.equal(store.size, 1);
  assert.equal(store.peek(first.token), null);

  const stale = consumeDefault(store, first.token);
  assert.equal(stale.error, "stale_session");
  assert.equal(consumeDefault(store, second.token, { focusNonce: "nonce-2" }).ok, true);
});

test("disable invalidates every grant for that origin only", () => {
  const store = newStore();
  const target = issueDefault(store);
  const other = issueDefault(store, {
    frameId: 9,
    origin: "https://other.example",
  });
  store.invalidateOrigin(ORIGIN);
  assert.equal(store.peek(target.token), null);
  assert.ok(store.peek(other.token));
});

test("a config revision bump invalidates older grants", () => {
  const store = newStore();
  const old = issueDefault(store, { configRevision: 17 });
  const fresh = issueDefault(store, { frameId: 9, configRevision: 18 });
  store.invalidateBelowRevision(18);
  assert.equal(store.peek(old.token), null);
  assert.ok(store.peek(fresh.token));
});

test("a newer advertised binding eagerly drops grants carrying the older tuple", () => {
  const store = newStore();
  const a = issueDefault(store);
  const b = issueDefault(store, { frameId: 9, sessionBinding: bindingB() });
  store.invalidateOtherBindings(bindingB());
  assert.equal(store.peek(a.token), null);
  assert.ok(store.peek(b.token));
});

test("the grant map is bounded and evicts oldest first", () => {
  const store = newStore({ maxGrants: 5 });
  const tokens = [];
  for (let i = 0; i < 8; i += 1) {
    tokens.push(issueDefault(store, { frameId: i }).token);
  }
  assert.equal(store.size, 5);
  for (const token of tokens.slice(0, 3)) {
    assert.equal(store.peek(token), null, "oldest grants must be evicted");
  }
  for (const token of tokens.slice(3)) {
    assert.ok(store.peek(token), "newest grants must survive");
  }
});

test("expired grants are pruned on the next issue", () => {
  const store = newStore();
  const stale = issueDefault(store, { ttlMs: 1000 });
  issueDefault(store, { frameId: 9, nowMs: NOW + 5000 });
  assert.equal(store.peek(stale.token), null);
});

test("a worker reset loses every grant, and the next fill is stale", () => {
  // MV3 termination is modelled as a new store: nothing is persisted, so
  // there is no path by which a token could survive.
  const before = newStore();
  const issued = issueDefault(before);
  assert.ok(before.peek(issued.token));

  const afterRestart = newStore();
  assert.equal(afterRestart.size, 0);
  const result = consumeDefault(afterRestart, issued.token);
  assert.equal(result.ok, false);
  assert.equal(result.error, "stale_session");
});

test("clear() empties the map without leaving a usable token", () => {
  const store = newStore();
  const issued = issueDefault(store);
  store.clear();
  assert.equal(store.size, 0);
  assert.equal(consumeDefault(store, issued.token).error, "stale_session");
});

test("no grant field ever holds a credential", () => {
  const store = newStore();
  const issued = issueDefault(store);
  const grant = store.peek(issued.token);
  const check = security.assertNoForbiddenKeys(grant);
  assert.equal(check.ok, true, `grant carries forbidden key ${check.key}`);
  assert.ok(!("password" in grant));
  assert.ok(!("username" in grant));
});
