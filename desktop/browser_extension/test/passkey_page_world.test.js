// spec 023 T503 / US3 — the MAIN-world wrapper, evaluated the way a page gets
// it: as a script in a scope that owns `window` and `navigator`.
//
// Until now nothing exercised this file, and both properties below were wrong
// because of it. `mediation: "conditional"` was sent to the app, so passkey
// autofill — which login pages fire on load, with no gesture — popped a
// confirmation on every page load and held the browser's own autofill UI for
// the app's whole budget. And `publicKey.user.id` was never forwarded, so a
// registration stored a handle of ours instead of the site's.

"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const SOURCE = fs.readFileSync(
  path.join(__dirname, "..", "passkey_page.js"),
  "utf8"
);

const CHANNEL = "keyvault-passkey";

function buffer(bytes) {
  return new Uint8Array(bytes).buffer;
}

/// A page world: the two objects the wrapper touches, plus a `postMessage`
/// that stands in for the isolated-world bridge.
///
/// `answer` decides what the bridge replies with; `null` means it refuses, so
/// the wrapper must fall through to the original call.
function pageWorld({ answer = () => ({ ok: false }) } = {}) {
  const calls = { get: [], create: [], posted: [] };
  const listeners = [];

  const credentials = {
    get: async (options) => {
      calls.get.push(options);
      return "browser-get";
    },
    create: async (options) => {
      calls.create.push(options);
      return "browser-create";
    },
  };

  const window = {
    addEventListener: (type, handler) => {
      if (type === "message") listeners.push(handler);
    },
    location: { origin: "https://example.com", hostname: "example.com" },
    postMessage: (message) => {
      calls.posted.push(message);
      const reply = answer(message);
      if (reply === null) return;
      for (const handler of listeners) {
        handler({
          source: window,
          data: {
            channel: CHANNEL,
            kind:
              message.kind === "passkey-create"
                ? "passkey-create-result"
                : "passkey-get-result",
            requestId: message.requestId,
            ...reply,
          },
        });
      }
    },
  };
  window.window = window;

  const sandbox = {
    window,
    navigator: { credentials },
    btoa: (value) => Buffer.from(value, "binary").toString("base64"),
    atob: (value) => Buffer.from(value, "base64").toString("binary"),
    Uint8Array,
    Promise,
    Map,
    String,
    console,
  };
  vm.runInNewContext(SOURCE, sandbox);
  return { calls, credentials, window };
}

const SIGN_IN = { publicKey: { challenge: buffer([1, 2, 3]) } };

test("023 T503: conditional mediation is left to the browser", async () => {
  const { calls, credentials } = pageWorld();

  const result = await credentials.get({
    ...SIGN_IN,
    mediation: "conditional",
  });

  // Not one message to the app: no dialog, and no hold on the browser's own
  // autofill UI.
  assert.deepEqual(calls.posted, []);
  assert.equal(result, "browser-get");
  assert.equal(calls.get.length, 1);
});

test("023 T503: silent mediation is left to the browser", async () => {
  const { calls, credentials } = pageWorld();

  await credentials.get({ ...SIGN_IN, mediation: "silent" });

  assert.deepEqual(calls.posted, []);
});

test("023 T503: a modal sign-in still reaches the app", async () => {
  const { calls, credentials } = pageWorld();

  // Both the default (no mediation) and the explicit modal form.
  await credentials.get(SIGN_IN);
  await credentials.get({ ...SIGN_IN, mediation: "required" });

  assert.equal(calls.posted.length, 2);
  assert.equal(calls.posted[0].kind, "passkey-get");
});

test("023 US3: the site's user.id is forwarded as base64url", async () => {
  const { calls, credentials } = pageWorld();

  await credentials.create({
    publicKey: {
      challenge: buffer([1, 2, 3]),
      rp: { id: "example.com" },
      user: { name: "ada", id: buffer([1, 2, 3, 4]) },
    },
  });

  assert.equal(calls.posted[0].kind, "passkey-create");
  assert.equal(calls.posted[0].userHandle, "AQIDBA");
  assert.equal(calls.posted[0].username, "ada");
});

test("023 US3: a registration with no user.id forwards an empty handle", async () => {
  const { calls, credentials } = pageWorld();

  await credentials.create({
    publicKey: {
      challenge: buffer([1, 2, 3]),
      rp: { id: "example.com" },
      user: { name: "ada" },
    },
  });

  // Legitimate: the app then picks a handle. Refusing here would send the
  // registration to the browser for no reason.
  assert.equal(calls.posted[0].userHandle, "");
});

test("023 US3: a site that will not take ES256 goes to the browser", async () => {
  const { calls, credentials } = pageWorld();

  const result = await credentials.create({
    publicKey: {
      challenge: buffer([1, 2, 3]),
      user: { name: "ada" },
      pubKeyCredParams: [{ alg: -257 }],
    },
  });

  assert.deepEqual(calls.posted, []);
  assert.equal(result, "browser-create");
});

test("023 T503: a refusal falls through to the browser", async () => {
  const { calls, credentials } = pageWorld({ answer: () => ({ ok: false }) });

  const result = await credentials.get(SIGN_IN);

  assert.equal(calls.posted.length, 1);
  assert.equal(result, "browser-get");
});

test("023 T503: an assertion is handed back as a credential", async () => {
  const { credentials } = pageWorld({
    answer: () => ({
      ok: true,
      credentialId: "AQIDBA",
      authenticatorData: "YXV0aA",
      signature: "c2ln",
      clientDataJSON: "Y2xpZW50",
      userHandle: "AQIDBA",
    }),
  });

  const credential = await credentials.get(SIGN_IN);

  assert.equal(credential.id, "AQIDBA");
  assert.equal(credential.type, "public-key");
  assert.ok(credential.response.signature instanceof ArrayBuffer);
});
