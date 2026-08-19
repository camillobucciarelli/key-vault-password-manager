// 009 Slice A2 — A015..A020.
//
// Every assertion drives the shipped `overlay_lifecycle.js` against the fake
// browser. The fake owns browser state only; all policy under test lives in
// the production module.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { FakeBrowser } = require("./fake_browser.js");
const { bindingA } = require("./helpers.js");
const security = require("../overlay_security.js");
const lifecycleModule = require("../overlay_lifecycle.js");

const {
  OverlayLifecycle,
  computeSiteControlState,
  registrationIdForPattern,
  isOverlayRegistrationId,
} = lifecycleModule;

const CONFIG_KEY = security.OVERLAY_CONFIG_KEY;
const EXT_DIR = path.join(__dirname, "..");

const HTTPS_EXAMPLE = "https://example.com";
const HTTPS_EXAMPLE_8443 = "https://example.com:8443";
const HTTP_EXAMPLE = "http://example.com";
const PATTERN_HTTPS = "https://example.com/*";
const PATTERN_HTTP = "http://example.com/*";

function newWorker(browser, options = {}) {
  return new OverlayLifecycle({ browser, ...options });
}

/** Grant + enable, the way the popup does it (gesture first, persist after). */
async function grantAndEnable(browser, worker, origin, tabId) {
  const pattern = security.permissionPatternForOrigin(origin);
  await browser.permissions.request({ origins: [pattern] });
  return worker.enableOrigin({ origin, tabId });
}

// ---------------------------------------------------------------------------
// A015 — manifest.
// ---------------------------------------------------------------------------

test("A015: manifest declares optional HTTP(S) hosts and nothing broader", () => {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(EXT_DIR, "manifest.json"), "utf8")
  );

  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, [
    "activeTab",
    "nativeMessaging",
    "scripting",
    "storage",
  ]);
  assert.deepEqual(manifest.optional_host_permissions, [
    "http://*/*",
    "https://*/*",
  ]);

  // The spec names exactly what may not appear. Absence is the requirement.
  assert.equal(manifest.host_permissions, undefined);
  assert.equal(manifest.content_scripts, undefined);
  assert.equal(manifest.optional_permissions, undefined);
  for (const forbidden of ["tabs", "webNavigation", "clipboardRead", "clipboardWrite"]) {
    assert.equal(manifest.permissions.includes(forbidden), false, forbidden);
  }
  const serialized = JSON.stringify(manifest);
  assert.equal(serialized.includes("<all_urls>"), false);
  assert.equal(serialized.includes("http://*/*"), true);
});

test("A015: every runtime file the extension loads is packaged and syntax-gated", () => {
  const packaged = fs.readFileSync(path.join(EXT_DIR, "package_extension.sh"), "utf8");
  const workflow = fs.readFileSync(
    path.join(EXT_DIR, "..", "..", ".github", "workflows", "pr.yml"),
    "utf8"
  );

  // Both lists are explicit allowlists that fail silently when a file is
  // missing from them: the ZIP builds green without the script, and CI
  // syntax-checks a file that is never named.
  //
  // The set is READ FROM DISK, not written here. A hardcoded list has the very
  // same failure mode as the two allowlists it is supposed to guard — Slice A3
  // added `overlay_routes.js` and a hardcoded list would have stayed green
  // while the file was missing from both. Every top-level `.js` in the
  // extension directory is a runtime file; tests live in `test/`.
  const runtimeFiles = fs
    .readdirSync(EXT_DIR, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".js"))
    .map((entry) => entry.name)
    .sort();
  assert.ok(runtimeFiles.length >= 5, "expected the runtime JS files to be found");

  for (const file of runtimeFiles) {
    // `replaceAll`, not `replace`: `replace` with a string pattern escapes only
    // the FIRST dot, so a name like `a.b.js` would build a regex whose second
    // dot still matches any character.
    const escaped = file.replaceAll(".", "\\.");
    assert.equal(fs.existsSync(path.join(EXT_DIR, file)), true, `${file} exists`);
    assert.match(packaged, new RegExp(`^\\s*${escaped} \\\\?$`, "m"));
    assert.match(workflow, new RegExp(`node --check desktop/browser_extension/${escaped}$`, "m"));
  }
});

test("A042: package allowlist names every runtime file and no test artifact", () => {
  const packaged = fs.readFileSync(path.join(EXT_DIR, "package_extension.sh"), "utf8");

  // Presence, not only absence: the allowlist fails silently (zip exits 0 with
  // a file missing), so every expected runtime file must be asserted by name.
  // Non-JS runtime files are enumerated from the manifest where possible so a
  // renamed popup or icon fails here instead of in the installed extension.
  const manifest = JSON.parse(
    fs.readFileSync(path.join(EXT_DIR, "manifest.json"), "utf8")
  );
  const expected = new Set(["manifest.json", "README.md"]);
  expected.add(manifest.background.service_worker);
  expected.add(manifest.action.default_popup);
  for (const icon of Object.values(manifest.icons)) expected.add(icon);
  for (const icon of Object.values(manifest.action.default_icon)) expected.add(icon);
  // CSS is referenced from popup.html, not the manifest.
  const popupHtml = fs.readFileSync(
    path.join(EXT_DIR, manifest.action.default_popup),
    "utf8"
  );
  for (const [, href] of popupHtml.matchAll(/href="([^"]+\.css)"/g)) {
    expected.add(href);
  }
  assert.ok(expected.size >= 9, "expected runtime file set looks implausibly small");

  for (const file of [...expected].sort()) {
    const escaped = file.replaceAll(".", "\\.").replaceAll("/", "\\/");
    assert.equal(fs.existsSync(path.join(EXT_DIR, file)), true, `${file} exists`);
    assert.match(
      packaged,
      // Trailing ` \` on every line except the last argument of `zip`.
      new RegExp(`^\\s*${escaped}(?: \\\\)?$`, "m"),
      `${file} present in zip allowlist`
    );
  }

  // Exclusions: nothing under test/ (session_helpers.js is harness-only),
  // no fixtures, screenshots, visual manifests, source maps, or env files.
  for (const forbidden of [
    "test/",
    "session_helpers",
    "fixtures",
    "screenshots",
    "visual_environment",
    "visual_baselines",
    ".map",
    ".env",
  ]) {
    // Only inspect the zip invocation, not comments.
    const zipBlock = packaged.slice(packaged.indexOf("zip -X"));
    assert.equal(
      zipBlock.includes(forbidden),
      false,
      `${forbidden} must not be packaged`
    );
  }
});

// ---------------------------------------------------------------------------
// A016 — overlayConfigV1.
// ---------------------------------------------------------------------------

test("A016: default state is off and reading never writes", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);

  const config = await worker.readCommittedConfig();
  assert.deepEqual(config.enabledOrigins, []);
  assert.equal(browser.callsMatching("storage.set").length, 0);
});

test("A016: enable commits sorted unique origins and bumps the revision", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await worker.reconcile();

  await grantAndEnable(browser, worker, HTTPS_EXAMPLE_8443, 7);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 7);

  const stored = browser.config();
  assert.deepEqual(stored.enabledOrigins, [HTTPS_EXAMPLE, HTTPS_EXAMPLE_8443]);
  assert.equal(security.validateOverlayConfig(stored).ok, true);
  assert.equal(stored.version, 1);
  assert.ok(stored.revision >= 2);

  // Re-enabling an already enabled origin is a no-op, not a duplicate.
  const revisionBefore = stored.revision;
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 7);
  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE, HTTPS_EXAMPLE_8443]);
  assert.equal(browser.config().revision, revisionBefore);
});

test("A016: enable refuses a non-canonical or non-HTTP(S) origin", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  for (const bad of [
    "ftp://example.com",
    "https://alice@example.com",
    "https://127.1",
    "chrome-extension://abc/page.html",
    "not a url",
  ]) {
    const result = await worker.enableOrigin({ origin: bad, tabId: 1 });
    assert.equal(result.ok, false, bad);
    assert.equal(result.error, "unsupported_origin", bad);
  }
  assert.equal(browser.config(), undefined);
});

test("A016: invalid or missing durable state migrates to disabled", async () => {
  for (const corrupt of [
    undefined,
    null,
    "nope",
    { version: 2, revision: 1, enabledOrigins: [] },
    { version: 1, revision: 1, enabledOrigins: ["https://example.com", "https://a.com"] },
    { version: 1, revision: 1, enabledOrigins: ["https://example.com", "https://example.com"] },
    { version: 1, revision: 1, enabledOrigins: ["HTTPS://EXAMPLE.COM"] },
    { version: 1, revision: 1, enabledOrigins: [], password: "kv-test-only-not-a-real-password" },
    { version: 1, revision: -1, enabledOrigins: [] },
  ]) {
    const browser = new FakeBrowser({
      storage: corrupt === undefined ? {} : { [CONFIG_KEY]: corrupt },
      granted: [PATTERN_HTTPS],
    });
    const worker = newWorker(browser);
    await worker.reconcile();

    const stored = browser.config();
    assert.equal(security.validateOverlayConfig(stored).ok, true, JSON.stringify(corrupt));
    assert.deepEqual(stored.enabledOrigins, [], JSON.stringify(corrupt));
    // Nothing may be registered on behalf of an unreadable config.
    assert.deepEqual(browser.registrationIds(), []);
    assert.deepEqual(browser.grantedPatterns(), []);
  }
});

test("A016: a corrupt config cannot rewind the revision", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 41, enabledOrigins: ["nope"] } },
  });
  await newWorker(browser).reconcile();
  assert.equal(browser.config().revision > 41, true);
});

test("A016: the enabled-origin ceiling is enforced", async () => {
  const origins = [];
  for (let index = 0; index < security.LIMITS.ENABLED_ORIGINS; index += 1) {
    origins.push(`https://site${String(index).padStart(4, "0")}.example`);
  }
  const patterns = origins.map((origin) => security.permissionPatternForOrigin(origin));
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 3, enabledOrigins: [...origins].sort() } },
    granted: patterns,
  });
  const worker = newWorker(browser);

  const overflowPattern = security.permissionPatternForOrigin("https://one-too-many.example");
  await browser.permissions.request({ origins: [overflowPattern] });
  const result = await worker.enableOrigin({ origin: "https://one-too-many.example" });
  assert.deepEqual(result, { ok: false, error: "too_many_origins" });
});

// ---------------------------------------------------------------------------
// Slice A acceptance criterion 1 — fresh install.
// ---------------------------------------------------------------------------

test("criterion 1: fresh install grants nothing, registers nothing, injects nothing", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }, { id: 2 }] });
  const worker = newWorker(browser);

  await worker.ready();

  assert.deepEqual(browser.grantedPatterns(), []);
  assert.deepEqual(browser.registrationIds(), []);
  assert.deepEqual(browser.callsMatching("scripting.execute"), []);
  assert.deepEqual(browser.callsMatching("permissions.request"), []);
  assert.deepEqual(browser.config().enabledOrigins, []);
  assert.equal(await worker.siteState({ tabUrl: "https://example.com/login" }).then((s) => s.state), "disabled");
});

test("criterion 1: a fresh worker denies bootstrap from an uninvited document", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);

  const result = await worker.authorizeBootstrap({
    message: {
      channel: security.CHANNEL,
      version: security.MESSAGE_VERSION,
      type: "bootstrap",
      origin: HTTPS_EXAMPLE,
    },
    sender: {
      id: "abcdefghijklmnopabcdefghijklmnop",
      url: "https://example.com/login",
      frameId: 0,
      tab: { id: 42, url: "https://example.com/login" },
    },
    runtimeId: "abcdefghijklmnopabcdefghijklmnop",
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, "disabled");
});

// ---------------------------------------------------------------------------
// A018 — dynamic registration.
// ---------------------------------------------------------------------------

test("A018: enable registers an isolated-world document_idle all-frames script", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await worker.reconcile();

  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 9);

  const registered = await browser.scripting.getRegisteredContentScripts();
  assert.equal(registered.length, 1);
  const script = registered[0];
  assert.equal(script.id, registrationIdForPattern(PATTERN_HTTPS));
  assert.deepEqual(script.matches, [PATTERN_HTTPS]);
  assert.equal(script.runAt, "document_idle");
  assert.equal(script.allFrames, true);
  assert.equal(script.world, "ISOLATED");
  assert.deepEqual(script.js, ["overlay_security.js", "content_overlay.js"]);
});

test("A018: the registration id is injective, including on lossy-encoding twins", () => {
  // `registrationIdForPattern` documents injectivity as the reason it encodes
  // rather than hashes: two patterns sharing an id would unregister a script a
  // still-authorized site needs. That was a claim in a comment with nothing
  // asserting it, so a lossy encoding passed every other test in this file.
  const hosts = [];
  for (const label of ["a", "b", "ab", "a-b", "a.b", "0", "01", "x1", "1x"]) {
    hosts.push(`${label}.test`, `${label}.example`, `sub.${label}.test`);
  }
  // Same length, code points exactly 16 apart: the pairs a truncating or
  // modulo encoding merges. 'a'/'q' and 'b'/'r' differ by 16.
  hosts.push("ab.test", "qb.test", "ar.test", "qr.test", "aq.test", "qa.test");

  const patterns = new Set();
  for (const host of hosts) {
    for (const scheme of ["http", "https"]) {
      patterns.add(`${scheme}://${host}/*`);
    }
  }

  const seen = new Map();
  for (const pattern of patterns) {
    const id = registrationIdForPattern(pattern);
    assert.equal(
      seen.has(id),
      false,
      `${pattern} collides with ${seen.get(id)} on ${id}`
    );
    assert.equal(isOverlayRegistrationId(id), true, pattern);
    seen.set(id, pattern);
  }
  assert.equal(seen.size, patterns.size);
});

test("A018: enable also injects the current tab in all frames", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  let executed = null;
  const original = browser.scripting.executeScript.bind(browser.scripting);
  browser.scripting.executeScript = async (options) => {
    executed = options;
    return original(options);
  };

  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 77);

  assert.deepEqual(executed.target, { tabId: 77, allFrames: true });
  assert.deepEqual(executed.files, ["overlay_security.js", "content_overlay.js"]);
});

test("A018: a failed injection does not undo the committed opt-in", async () => {
  const browser = new FakeBrowser();
  browser.scripting.executeScript = async () => {
    throw new Error("Cannot access a chrome:// URL");
  };
  const worker = newWorker(browser);

  const result = await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 5);
  assert.equal(result.ok, true);
  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE]);
});

test("A018: repeated startup reconciliation is idempotent", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 4, enabledOrigins: [HTTPS_EXAMPLE] } },
    granted: [PATTERN_HTTPS],
  });

  for (let restart = 0; restart < 3; restart += 1) {
    const worker = newWorker(browser);
    await worker.ready();
    await worker.ready(); // second call in the same worker must not re-run
  }

  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);
  assert.equal(browser.callsMatching("scripting.register").length, 1);
  assert.equal(browser.callsMatching("scripting.unregister").length, 0);
  assert.equal(browser.config().revision, 4);
});

test("A018: two ports of one host share one registration", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE_8443, 1);

  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);
  assert.deepEqual(browser.grantedPatterns(), [PATTERN_HTTPS]);
});

test("A018: the non-enabled port stays inert even though it is injected", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);

  const runtimeId = "abcdefghijklmnopabcdefghijklmnop";
  const bootstrapFrom = (frameUrl) =>
    worker.authorizeBootstrap({
      message: {
        channel: security.CHANNEL,
        version: security.MESSAGE_VERSION,
        type: "bootstrap",
        origin: security.canonicalOriginOrNull(frameUrl),
      },
      sender: {
        id: runtimeId,
        url: frameUrl,
        frameId: 0,
        tab: { id: 42, url: frameUrl },
      },
      runtimeId,
    });

  assert.equal((await bootstrapFrom("https://example.com/login")).ok, true);
  // Chromium patterns cannot express a port, so this document IS injected.
  // Only the exact-origin check keeps it inert.
  assert.equal((await bootstrapFrom("https://example.com:8443/login")).ok, false);
  assert.equal((await bootstrapFrom("http://example.com/login")).ok, false);
  assert.equal((await bootstrapFrom("https://example.com.evil.test/login")).ok, false);
});

// ---------------------------------------------------------------------------
// A019 — crash-consistent disable.
// ---------------------------------------------------------------------------

test("A019: the durable commit is the FIRST browser mutation of the disable", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);

  browser.calls.length = 0;
  await worker.disableOrigin({ origin: HTTPS_EXAMPLE });

  // This assertion is the whole of SR-8. If `_commitConfig` is moved after any
  // cleanup phase, the first entry stops being the storage write and this
  // fails immediately.
  assert.equal(browser.calls[0], "storage.set");
  assert.deepEqual(browser.calls, [
    "storage.set",
    "tabs.sendMessage",
    "scripting.unregister",
    "permissions.remove",
  ]);
});

test("A019: a failed durable commit starts no cleanup at all", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);

  browser.calls.length = 0;
  browser.failNextSet = "QUOTA_BYTES quota exceeded";
  await assert.rejects(() => worker.disableOrigin({ origin: HTTPS_EXAMPLE }));

  assert.deepEqual(browser.calls, []);
  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE]);
  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);
  assert.deepEqual(browser.grantedPatterns(), [PATTERN_HTTPS]);
});

// The readback comparison in `_commitConfig` is a security guard, not a
// paranoia knob: it is what refuses to authorize cleanup against a storage
// layer that accepted the write and then reported something else. One test
// would leave the guard silently uncovered the day that test is renamed, so
// each distinct failure mode gets its own assertion: a divergent revision, an
// over-truncated array, and an absent field.

test("A019: a mismatched readback aborts the disable before any cleanup", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);

  browser.calls.length = 0;
  browser.corruptNextReadback = { version: 1, revision: 99, enabledOrigins: [HTTPS_EXAMPLE] };
  await assert.rejects(() => worker.disableOrigin({ origin: HTTPS_EXAMPLE }));

  assert.deepEqual(browser.calls, ["storage.set"]);
  assert.deepEqual(browser.callsMatching("permissions.remove"), []);
  assert.deepEqual(browser.callsMatching("scripting.unregister"), []);
});

test("A019: a TRUNCATED readback aborts the disable before any cleanup", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);
  await grantAndEnable(browser, worker, HTTP_EXAMPLE, 42);

  browser.calls.length = 0;
  // A partial write: the revision is exactly the expected one, so a
  // revision-only check would wave this through, but an origin that is still
  // authorized has vanished from the array. Removing the permission for
  // `HTTP_EXAMPLE` on the strength of this value would revoke a site the user
  // never disabled.
  const expectedRevision = browser.config().revision + 1;
  browser.corruptNextReadback = {
    version: 1,
    revision: expectedRevision,
    enabledOrigins: [],
  };
  await assert.rejects(
    () => worker.disableOrigin({ origin: HTTPS_EXAMPLE }),
    /overlay_config_readback_mismatch/
  );

  assert.deepEqual(browser.calls, ["storage.set"]);
  assert.deepEqual(browser.callsMatching("permissions.remove"), []);
  assert.deepEqual(browser.callsMatching("scripting.unregister"), []);
  assert.deepEqual(browser.callsMatching("tabs.sendMessage"), []);
});

test("A019: a readback missing a field aborts the disable before any cleanup", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);

  browser.calls.length = 0;
  browser.corruptNextReadback = { version: 1, revision: browser.config().revision + 1 };
  await assert.rejects(
    () => worker.disableOrigin({ origin: HTTPS_EXAMPLE }),
    /overlay_config_readback_mismatch/
  );

  assert.deepEqual(browser.calls, ["storage.set"]);
  assert.deepEqual(browser.grantedPatterns(), [PATTERN_HTTPS]);
  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);
});

test("A018: a partial readback aborts the enable before anything is registered", async () => {
  // Same guard on the other transaction. Registering a script on the strength
  // of a value storage never confirmed would inject into a site whose opt-in
  // may not have survived.
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await worker.reconcile();
  await browser.permissions.request({ origins: [PATTERN_HTTPS] });

  browser.calls.length = 0;
  // The write claims to have landed, but the new origin is absent from it.
  browser.corruptNextReadback = {
    version: 1,
    revision: browser.config().revision + 1,
    enabledOrigins: [],
  };
  await assert.rejects(
    () => worker.enableOrigin({ origin: HTTPS_EXAMPLE, tabId: 42 }),
    /overlay_config_readback_mismatch/
  );

  assert.deepEqual(browser.callsMatching("scripting.register"), []);
  assert.deepEqual(browser.callsMatching("scripting.execute"), []);
  assert.deepEqual(browser.registrationIds(), []);
});

// ---------------------------------------------------------------------------
// Gate A2 (real-Chrome smoke): `chrome.storage.local.get` returns objects with
// keys in ALPHABETICAL order, not insertion order (measured on Chrome 151:
// set {version, revision, enabledOrigins} reads back as
// {enabledOrigins, revision, version}). The first test PINS that behaviour in
// the fake — without it, every other test here runs against a storage layer
// real Chrome does not ship. The second proves the commit readback survives it.
// ---------------------------------------------------------------------------

test("Gate A2: the fake's storage.local.get returns keys alphabetically, like real Chrome", async () => {
  const browser = new FakeBrowser();
  // Insertion order is deliberately NOT alphabetical, at both depths.
  await browser.storage.local.set({
    probe: { version: 1, revision: 7, enabledOrigins: ["https://example.com"] },
  });
  const readback = (await browser.storage.local.get(["probe"])).probe;
  assert.deepEqual(Object.keys(readback), ["enabledOrigins", "revision", "version"]);
  // The VALUE is still intact — only key order changed.
  assert.deepEqual(readback, {
    version: 1,
    revision: 7,
    enabledOrigins: ["https://example.com"],
  });
});

test("Gate A2: enable commits despite Chrome's alphabetical readback key order", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await worker.reconcile();

  // Must not throw overlay_config_readback_mismatch on the reordered readback.
  const result = await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);
  assert.equal(result.ok, true);
  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE]);
  // The phases AFTER the commit actually ran: registration + explicit inject.
  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);
  assert.equal(browser.callsMatching("scripting.execute").length, 1);
});

test("A019: disabling one port keeps the pattern the other port still needs", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 42);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE_8443, 42);

  await worker.disableOrigin({ origin: HTTPS_EXAMPLE_8443 });

  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE]);
  // Shared pattern is retained; the removed port is nevertheless unauthorized.
  assert.deepEqual(browser.grantedPatterns(), [PATTERN_HTTPS]);
  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);

  await worker.disableOrigin({ origin: HTTPS_EXAMPLE });
  assert.deepEqual(browser.config().enabledOrigins, []);
  assert.deepEqual(browser.grantedPatterns(), []);
  assert.deepEqual(browser.registrationIds(), []);
});

test("A019: a different scheme is a different pattern and survives independently", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);
  await grantAndEnable(browser, worker, HTTP_EXAMPLE, 1);

  await worker.disableOrigin({ origin: HTTP_EXAMPLE });

  assert.deepEqual(browser.grantedPatterns(), [PATTERN_HTTPS]);
  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE]);
});

test("A019: disable broadcasts teardown to every tab, naming no origin", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }, { id: 2 }, { id: 3 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);
  await grantAndEnable(browser, worker, HTTP_EXAMPLE, 1);

  await worker.disableOrigin({ origin: HTTP_EXAMPLE });

  assert.equal(browser.deliveredTeardowns.length, 3);
  for (const { message } of browser.deliveredTeardowns) {
    assert.equal(message.type, "teardown");
    assert.equal(security.assertNoForbiddenKeys(message).ok, true);
    // Without the `tabs` permission this cannot be targeted, so it reaches the
    // document on the STILL-ENABLED origin too. Naming the disabled origin
    // would hand that document a cross-origin fact about the user's settings
    // for free. Only the revision travels; the receiver revalidates its own
    // origin against the worker.
    assert.deepEqual(Object.keys(message).sort(), [
      "channel",
      "revision",
      "type",
      "version",
    ]);
    assert.equal(JSON.stringify(message).includes("example.com"), false);
  }
});

test("A019: disable is idempotent and still reconciles", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);

  await worker.disableOrigin({ origin: HTTPS_EXAMPLE });
  const revisionAfterFirst = browser.config().revision;
  await worker.disableOrigin({ origin: HTTPS_EXAMPLE });

  assert.deepEqual(browser.config().enabledOrigins, []);
  assert.equal(browser.config().revision, revisionAfterFirst + 1);
  assert.deepEqual(browser.grantedPatterns(), []);
  assert.deepEqual(browser.registrationIds(), []);
});

// ---------------------------------------------------------------------------
// A020 — fail-closed reconciliation.
// ---------------------------------------------------------------------------

test("A020: a permission revoked outside the popup durably disables the origin", async () => {
  const browser = new FakeBrowser({
    storage: {
      [CONFIG_KEY]: {
        version: 1,
        revision: 8,
        enabledOrigins: [HTTPS_EXAMPLE, HTTP_EXAMPLE].sort(),
      },
    },
    granted: [PATTERN_HTTPS],
    tabs: [{ id: 1 }],
  });

  await newWorker(browser).ready();

  assert.deepEqual(browser.config().enabledOrigins, [HTTPS_EXAMPLE]);
  assert.equal(browser.config().revision, 9);
  assert.deepEqual(browser.registrationIds(), [registrationIdForPattern(PATTERN_HTTPS)]);
  // Reconciliation still nudges injected documents to revalidate, and still
  // without naming which origin lost its permission.
  assert.equal(browser.deliveredTeardowns.length > 0, true);
  for (const { message } of browser.deliveredTeardowns) {
    assert.equal(message.type, "teardown");
    assert.equal(message.revision, 9);
    assert.equal(Object.prototype.hasOwnProperty.call(message, "origin"), false);
  }
});

test("A020: reconciliation makes an outstanding fill token unusable, at an unchanged revision", async () => {
  // spec.md:296 requires reconcile() to clear every in-memory focus grant.
  //
  // This asserts the EFFECT, not the bookkeeping: it never reads
  // `worker.grants.size`. A grant that is merely missing from a Map proves
  // nothing — the property that matters is that the token can no longer
  // authorize a fill. So the token is redeemed through the real
  // `FocusGrantStore.consume()` path, which is what the fill handler calls.
  //
  // The setup is chosen so that NOTHING ELSE can explain the rejection. The
  // permission is still granted and the config is valid, so this reconcile
  // commits nothing and the revision does not move. The grant therefore stays
  // valid against every downstream check — TTL, tab, frame, document, origin,
  // nonce, entry id, session binding, and above all the `configRevision`
  // comparison that is the reason this survivor was not exploitable. With the
  // revision pinned, the only remaining reason a consume can fail after this
  // reconcile is that reconcile dropped the grant.
  //
  // `reconcile()` is invoked directly because that is the production path:
  // background.js wires `permissions.onAdded` / `onRemoved` straight to it.
  const browser = new FakeBrowser({
    storage: {
      [CONFIG_KEY]: { version: 1, revision: 8, enabledOrigins: [HTTPS_EXAMPLE] },
    },
    granted: [PATTERN_HTTPS],
    tabs: [{ id: 1 }],
  });
  const worker = newWorker(browser);
  await worker.ready();

  const revision = browser.config().revision;
  const nowMs = 1720000000000;

  const mint = (frameId) =>
    worker.grants.issue({
      tabId: 42,
      frameId,
      documentId: "doc-1",
      origin: HTTPS_EXAMPLE,
      focusNonce: "nonce-1",
      entryIds: ["entry-1"],
      sessionBinding: bindingA(),
      configRevision: revision,
      nowMs,
    });

  const redeem = (frameId, token) =>
    worker.grants.consume({
      token,
      tabId: 42,
      frameId,
      documentId: "doc-1",
      origin: HTTPS_EXAMPLE,
      focusNonce: "nonce-1",
      entryId: "entry-1",
      sessionBinding: bindingA(),
      configRevision: revision,
      nowMs: nowMs + 1000,
    });

  // Two grants on different frames: `issue` replaces a grant on the same
  // (tab, frame, document), and `consume` is one-shot, so a single grant cannot
  // be both the control and the subject.
  const control = mint(3);
  const subject = mint(4);
  assert.ok(control);
  assert.ok(subject);

  // CONTROL — redeemed before the reconcile. Without this the test could pass
  // vacuously: a consume that was always going to fail (wrong field, expired
  // clock, bad binding) would look exactly like a cleared grant.
  assert.deepEqual(
    { ok: redeem(3, control.token).ok },
    { ok: true },
    "the token must be genuinely redeemable before the reconcile"
  );

  await worker.reconcile();

  // Load-bearing: if the revision moved, the assertion below would be
  // satisfied by the stale-revision check instead of by the grant clear, and
  // the test would go green with the clear deleted.
  assert.equal(
    browser.config().revision,
    revision,
    "this reconcile must not commit; otherwise the revision check, not the " +
      "grant clear, is what rejects the token"
  );

  const afterReconcile = redeem(4, subject.token);
  assert.equal(afterReconcile.ok, false, "reconcile must invalidate the fill token");
  assert.equal(afterReconcile.error, "stale_session");
});

test("A020: a registration no config justifies is removed on cold start", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 2, enabledOrigins: [] } },
  });
  await browser.scripting.registerContentScripts([
    {
      id: registrationIdForPattern(PATTERN_HTTPS),
      matches: [PATTERN_HTTPS],
      js: ["overlay_security.js", "content_overlay.js"],
    },
  ]);

  await newWorker(browser).ready();

  assert.deepEqual(browser.registrationIds(), []);
});

test("A020: a granted permission no config justifies is removed on cold start", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 2, enabledOrigins: [] } },
    granted: [PATTERN_HTTPS, PATTERN_HTTP],
  });

  await newWorker(browser).ready();

  assert.deepEqual(browser.grantedPatterns(), []);
});

test("A020: reconciliation never touches a registration the extension does not own", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 2, enabledOrigins: [] } },
  });
  await browser.scripting.registerContentScripts([
    { id: "some-other-feature", matches: ["https://other.test/*"], js: ["other.js"] },
  ]);

  await newWorker(browser).ready();

  assert.deepEqual(browser.registrationIds(), ["some-other-feature"]);
});

test("A020: bootstrap is served only after reconciliation has run", async () => {
  const browser = new FakeBrowser({
    storage: {
      [CONFIG_KEY]: { version: 1, revision: 6, enabledOrigins: [HTTPS_EXAMPLE] },
    },
    granted: [], // permission gone: config is stale and must fail closed
  });
  const worker = newWorker(browser);
  const runtimeId = "abcdefghijklmnopabcdefghijklmnop";

  const result = await worker.authorizeBootstrap({
    message: {
      channel: security.CHANNEL,
      version: security.MESSAGE_VERSION,
      type: "bootstrap",
      origin: HTTPS_EXAMPLE,
    },
    sender: {
      id: runtimeId,
      url: "https://example.com/login",
      frameId: 0,
      tab: { id: 42, url: "https://example.com/login" },
    },
    runtimeId,
  });

  assert.equal(result.ok, false);
  assert.deepEqual(browser.config().enabledOrigins, []);
});

test("A020: a failing reconciliation is retried, never cached as ready", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 1, revision: 1, enabledOrigins: ["bogus"] } },
  });
  const worker = newWorker(browser);

  browser.failNextSet = "transient";
  await assert.rejects(() => worker.ready());

  await worker.ready();
  assert.deepEqual(browser.config().enabledOrigins, []);
});

test("A020: concurrent mutations are serialized, never interleaved", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  const patterns = ["https://a.test", "https://b.test", "https://c.test"];
  for (const origin of patterns) {
    await browser.permissions.request({
      origins: [security.permissionPatternForOrigin(origin)],
    });
  }

  await Promise.all(patterns.map((origin) => worker.enableOrigin({ origin, tabId: 1 })));

  assert.deepEqual(browser.config().enabledOrigins, patterns);
  assert.equal(security.validateOverlayConfig(browser.config()).ok, true);
});

// ---------------------------------------------------------------------------
// A017 — popup control states.
// ---------------------------------------------------------------------------

test("A017: control state covers unsupported, reconciliation, enabled, disabled, denied", () => {
  const config = security.emptyOverlayConfig(1);
  const enabled = { version: 1, revision: 2, enabledOrigins: [HTTPS_EXAMPLE] };

  assert.equal(
    computeSiteControlState({ tabUrl: "chrome://extensions", config }).state,
    "unsupported"
  );
  assert.equal(
    computeSiteControlState({ tabUrl: "file:///tmp/a.html", config }).state,
    "unsupported"
  );
  assert.equal(computeSiteControlState({ tabUrl: "", config }).state, "unsupported");
  assert.equal(
    computeSiteControlState({ tabUrl: "https://example.com/login", config, ready: false }).state,
    "reconciling"
  );
  assert.equal(
    computeSiteControlState({ tabUrl: "https://example.com/login", config: enabled }).state,
    "enabled"
  );
  assert.equal(
    computeSiteControlState({ tabUrl: "https://example.com/login", config }).state,
    "disabled"
  );
  assert.equal(
    computeSiteControlState({
      tabUrl: "https://example.com/login",
      config,
      lastRequestDenied: true,
    }).state,
    "denied"
  );
  // An enabled sibling port must not make this one look enabled.
  assert.equal(
    computeSiteControlState({ tabUrl: "https://example.com:8443/login", config: enabled }).state,
    "disabled"
  );
});

test("A017: a declined prompt persists nothing", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await worker.ready();

  // The popup never calls enableOrigin without a grant; if it ever did, the
  // worker still refuses, because the browser is the authority on the grant.
  const result = await worker.enableOrigin({ origin: HTTPS_EXAMPLE, tabId: 1 });

  assert.deepEqual(result, { ok: false, error: "permission_missing" });
  assert.deepEqual(browser.config().enabledOrigins, []);
  assert.deepEqual(browser.registrationIds(), []);
});

test("A017: siteState reports the committed origin, not the requested one", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);

  assert.equal((await worker.siteState({ tabUrl: "https://example.com/x?y#z" })).state, "enabled");
  assert.equal((await worker.siteState({ tabUrl: "https://example.com:8443/x" })).state, "disabled");
  assert.equal((await worker.siteState({ tabUrl: "http://example.com/x" })).state, "disabled");
});

// ---------------------------------------------------------------------------
// Persistence hygiene.
// ---------------------------------------------------------------------------

test("no secret-shaped key is ever written to storage", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, HTTPS_EXAMPLE, 1);
  await worker.disableOrigin({ origin: HTTPS_EXAMPLE });

  const serialized = JSON.stringify(browser.store);
  for (const forbidden of security.FORBIDDEN_KEYS) {
    assert.equal(serialized.includes(`"${forbidden}"`), false, forbidden);
  }
  // The permission pattern/refcount is derived, never stored.
  assert.equal(serialized.includes("/*"), false);
  assert.deepEqual(Object.keys(browser.config()).sort(), [
    "enabledOrigins",
    "revision",
    "version",
  ]);
});
