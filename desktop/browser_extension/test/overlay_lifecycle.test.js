// 009 Slice A2 — A015..A020, as revised by Slice C.
//
// Every assertion drives the shipped `overlay_lifecycle.js` against the fake
// browser. The fake owns browser state only; all policy under test lives in
// the production module.
//
// SLICE C: the durable opt-in became ONE GLOBAL BOOLEAN instead of a list of
// enabled origins. A015 is deliberately unchanged and must stay that way — the
// manifest still declares no mandatory `host_permissions`, and the broad pair
// is still only ever OPTIONAL. What changed is the shape of what the popup
// asks for at runtime, not whether the extension can demand it up front.
//
// Tests that pinned per-origin bookkeeping are RETIRED in place, each with a
// comment naming the property and why it no longer has a subject. Tests that
// pinned crash-consistency, fail-closed parsing, monotonic revisions, orphan
// cleanup and exact-origin binding are ADAPTED, never relaxed.

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
  computeGlobalControlState,
  registrationIdForPattern,
  isOverlayRegistrationId,
  GLOBAL_REGISTRATION_ID,
} = lifecycleModule;

const CONFIG_KEY = security.OVERLAY_CONFIG_KEY;
const EXT_DIR = path.join(__dirname, "..");

const GLOBAL_PATTERNS = security.GLOBAL_PERMISSION_PATTERNS;
const RUNTIME_ID = "abcdefghijklmnopabcdefghijklmnop";

const HTTPS_EXAMPLE = "https://example.com";
const HTTPS_EXAMPLE_8443 = "https://example.com:8443";
const HTTP_EXAMPLE = "http://example.com";
const PATTERN_HTTPS = "https://example.com/*";
const PATTERN_HTTP = "http://example.com/*";

function newWorker(browser, options = {}) {
  return new OverlayLifecycle({ browser, ...options });
}

/** Grant + enable, the way the popup does it (gesture first, persist after). */
async function grantAndEnable(browser, worker, tabId) {
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });
  return worker.enable({ tabId });
}

/**
 * A well-formed bootstrap call from a top-level document at `frameUrl`.
 *
 * `claimedOrigin` defaults to the frame's real canonical origin; passing a
 * different one models a content script LYING about where it runs, which the
 * worker must refuse rather than believe.
 */
function bootstrapCall(frameUrl, claimedOrigin) {
  return {
    message: {
      channel: security.CHANNEL,
      version: security.MESSAGE_VERSION,
      type: "bootstrap",
      origin: claimedOrigin ?? security.canonicalOriginOrNull(frameUrl),
    },
    sender: {
      id: RUNTIME_ID,
      url: frameUrl,
      frameId: 0,
      tab: { id: 42, url: frameUrl },
    },
    runtimeId: RUNTIME_ID,
  };
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
// A016 — overlayConfigV2, and the v1 -> v2 migration.
// ---------------------------------------------------------------------------

test("A016: default state is off and reading never writes", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);

  const config = await worker.readCommittedConfig();
  assert.equal(config.enabled, false);
  assert.equal(browser.callsMatching("storage.set").length, 0);
});

test("A016: enable commits the switch on and bumps the revision exactly once", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await worker.reconcile();

  await grantAndEnable(browser, worker, 7);

  const stored = browser.config();
  assert.equal(stored.enabled, true);
  assert.equal(security.validateOverlayConfig(stored).ok, true);
  assert.equal(stored.version, 2);
  assert.ok(stored.revision >= 1);

  // Re-enabling an already enabled switch is a no-op, not a second commit.
  const revisionBefore = stored.revision;
  await grantAndEnable(browser, worker, 7);
  assert.equal(browser.config().enabled, true);
  assert.equal(browser.config().revision, revisionBefore);
});

// SLICE C RETIREMENT. "A016: enable refuses a non-canonical or non-HTTP(S)
// origin" is gone: `enable()` takes no origin, so `unsupported_origin` has no
// producer left. The property that replaces it is below — the only thing that
// can now stop an enable is the browser not actually holding the broad grant.

test("A016: enable refuses unless the browser holds the WHOLE broad grant", async () => {
  for (const granted of [[], [PATTERN_HTTP], [PATTERN_HTTPS], ["https://example.com/*"]]) {
    const browser = new FakeBrowser({ granted });
    const worker = newWorker(browser);
    await worker.reconcile();

    const result = await worker.enable({ tabId: 1 });
    assert.deepEqual(
      result,
      { ok: false, error: "permission_missing" },
      `granted=${JSON.stringify(granted)} must not enable`
    );
    assert.equal(browser.config().enabled, false);
    assert.deepEqual(browser.registrationIds(), []);
  }
});

test("A016: invalid or missing durable state migrates to disabled", async () => {
  for (const corrupt of [
    undefined,
    null,
    "nope",
    { version: 1, revision: 1, enabled: true },
    { version: 3, revision: 1, enabled: true },
    { version: 2, revision: 1, enabled: "true" },
    { version: 2, revision: 1, enabled: true, dismissed: false },
    { version: 2, revision: 1, enabled: true, password: "kv-test-only-not-a-real-value" },
    { version: 2, revision: -1, enabled: false },
    { version: 2, revision: 1 },
  ]) {
    const browser = new FakeBrowser({
      storage: corrupt === undefined ? {} : { [CONFIG_KEY]: corrupt },
      granted: [...GLOBAL_PATTERNS],
    });
    const worker = newWorker(browser);
    await worker.reconcile();

    const stored = browser.config();
    assert.equal(security.validateOverlayConfig(stored).ok, true, JSON.stringify(corrupt));
    assert.equal(stored.enabled, false, JSON.stringify(corrupt));
    // Nothing may be registered or held on behalf of an unreadable config.
    assert.deepEqual(browser.registrationIds(), []);
    assert.deepEqual(browser.grantedPatterns(), []);
  }
});

// ===========================================================================
// THE MIGRATION. Slice C's single highest-risk behaviour: an upgrade must not
// turn a per-site opt-in into a global one, and must not leave the per-site
// permissions it can no longer justify lying around.
// ===========================================================================

test("A016: a Slice A2 config with enabled origins migrates to DISABLED", async () => {
  for (const origins of [
    [],
    [HTTPS_EXAMPLE],
    [HTTPS_EXAMPLE, HTTPS_EXAMPLE_8443, HTTP_EXAMPLE].sort(),
  ]) {
    const browser = new FakeBrowser({
      storage: {
        overlayConfigV1: { version: 1, revision: 12, enabledOrigins: origins },
        overlayRevisionFloorV1: 12,
      },
      granted: origins.length > 0 ? [PATTERN_HTTPS, PATTERN_HTTP] : [],
      tabs: [{ id: 1 }],
    });

    await newWorker(browser).ready();

    const stored = browser.config();
    assert.equal(security.validateOverlayConfig(stored).ok, true);
    assert.equal(
      stored.enabled,
      false,
      `v1 with ${JSON.stringify(origins)} must never become enabled`
    );
    // Revision monotonicity holds ACROSS the version boundary: the floor key
    // is deliberately not renamed with the config key.
    assert.ok(stored.revision > 12, "the v1 revision must not be rewound");
  }
});

// The hard case, and the one the other migration tests cannot see.
//
// Chrome lets the user set "Site access -> On all sites" by hand from
// chrome://extensions, which grants exactly the broad pair this build asks
// for. A Slice A2 install can therefore arrive at the upgrade with a v1 config
// listing origins AND the broad grant already held — so the fail-closed grant
// check in `reconcile` never fires, and the migration rule is the only thing
// standing between the old per-site opt-in and a global one.
//
// A browser permission is not consent to the feature. The switch starts off.
test("A016: a v1 config migrates to disabled even when the broad grant is already held", async () => {
  const browser = new FakeBrowser({
    storage: {
      overlayConfigV1: {
        version: 1,
        revision: 12,
        enabledOrigins: [HTTP_EXAMPLE, HTTPS_EXAMPLE].sort(),
      },
      overlayRevisionFloorV1: 12,
    },
    granted: [...GLOBAL_PATTERNS],
    tabs: [{ id: 1 }],
  });

  await newWorker(browser).ready();

  assert.equal(
    browser.config().enabled,
    false,
    "a held browser permission must not be read as consent to the feature"
  );
  assert.deepEqual(browser.registrationIds(), []);
  // And the broad grant is handed back, because no committed config justifies
  // it any more.
  assert.deepEqual(browser.grantedPatterns(), []);
  assert.equal(browser.legacyConfig(), undefined);
});

test("A016: migration revokes every residual per-origin grant and registration", async () => {
  const browser = new FakeBrowser({
    storage: {
      overlayConfigV1: {
        version: 1,
        revision: 5,
        enabledOrigins: [HTTP_EXAMPLE, HTTPS_EXAMPLE].sort(),
      },
      overlayRevisionFloorV1: 5,
    },
    granted: [PATTERN_HTTPS, PATTERN_HTTP],
    tabs: [{ id: 1 }],
  });
  // Exactly what Slice A2 persisted: one registration per pattern, surviving
  // the browser restart via persistAcrossSessions.
  await browser.scripting.registerContentScripts([
    { id: registrationIdForPattern(PATTERN_HTTPS), matches: [PATTERN_HTTPS], js: ["x.js"] },
    { id: registrationIdForPattern(PATTERN_HTTP), matches: [PATTERN_HTTP], js: ["x.js"] },
  ]);

  await newWorker(browser).ready();

  // No orphan permission: the user is not left with an "can read example.com"
  // grant that no committed config justifies.
  assert.deepEqual(browser.grantedPatterns(), []);
  // No orphan registration: those scripts would otherwise keep injecting.
  assert.deepEqual(browser.registrationIds(), []);
  // No orphan storage value that a later bug could resurrect as an opt-in.
  assert.equal(browser.legacyConfig(), undefined);
});

test("A016: a corrupt config cannot rewind the revision", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 41, enabled: "nope" } },
  });
  await newWorker(browser).reconcile();
  assert.equal(browser.config().revision > 41, true);
});

// SLICE C RETIREMENT. "A016: the enabled-origin ceiling is enforced" is gone
// with `LIMITS.ENABLED_ORIGINS`: a boolean has no length to overflow, so
// `too_many_origins` has no producer. Nothing replaces it — the resource the
// ceiling protected (unbounded storage growth from an unbounded origin list)
// no longer exists.

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
  assert.equal(browser.config().enabled, false);
  assert.equal(
    await worker.siteState({ tabUrl: "https://example.com/login" }).then((s) => s.state),
    "disabled"
  );
});

test("criterion 1: a fresh worker denies bootstrap from an uninvited document", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);

  const result = await worker.authorizeBootstrap(bootstrapCall("https://example.com/login"));

  assert.equal(result.ok, false);
  assert.equal(result.error.code, "disabled");
});

// ---------------------------------------------------------------------------
// A018 — dynamic registration.
// ---------------------------------------------------------------------------

test("A018: enable registers ONE isolated-world document_idle all-frames script", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await worker.reconcile();

  await grantAndEnable(browser, worker, 9);

  const registered = await browser.scripting.getRegisteredContentScripts();
  assert.equal(registered.length, 1);
  const script = registered[0];
  assert.equal(script.id, GLOBAL_REGISTRATION_ID);
  assert.deepEqual(script.matches, ["http://*/*", "https://*/*"]);
  assert.equal(script.runAt, "document_idle");
  assert.equal(script.allFrames, true);
  assert.equal(script.world, "ISOLATED");
  assert.deepEqual(script.js, ["overlay_security.js", "content_overlay.js"]);
});

test("A018: the registration matches exactly the manifest's optional hosts", () => {
  // The registration may not reach beyond what the user can even be asked to
  // grant. A `matches` entry with no corresponding optional host permission is
  // a script that either never injects or injects without a grant.
  const manifest = JSON.parse(
    fs.readFileSync(path.join(EXT_DIR, "manifest.json"), "utf8")
  );
  assert.deepEqual(
    [...security.GLOBAL_PERMISSION_PATTERNS],
    manifest.optional_host_permissions
  );
  assert.deepEqual(
    lifecycleModule.globalRegistration().matches,
    manifest.optional_host_permissions
  );
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

  // SLICE C: injectivity is what makes the upgrade clean. The global id must
  // differ from every per-origin id a Slice A2 install could have registered,
  // so those are classified as orphans instead of mistaken for this one.
  assert.equal(isOverlayRegistrationId(GLOBAL_REGISTRATION_ID), true);
  assert.equal(seen.has(GLOBAL_REGISTRATION_ID), false);
  for (const pattern of ["https://example.com/*", "http://*/*", "https://*/*"]) {
    assert.notEqual(registrationIdForPattern(pattern), GLOBAL_REGISTRATION_ID);
  }
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

  await grantAndEnable(browser, worker, 77);

  assert.deepEqual(executed.target, { tabId: 77, allFrames: true });
  assert.deepEqual(executed.files, ["overlay_security.js", "content_overlay.js"]);
});

test("A018: a failed injection does not undo the committed opt-in", async () => {
  const browser = new FakeBrowser();
  browser.scripting.executeScript = async () => {
    throw new Error("Cannot access a chrome:// URL");
  };
  const worker = newWorker(browser);

  const result = await grantAndEnable(browser, worker, 5);
  assert.equal(result.ok, true);
  assert.equal(browser.config().enabled, true);
});

test("A018: enabling without a tab still commits and registers", async () => {
  // The popup can be open on a `chrome://` page. Turning the overlay ON there
  // is legitimate: the grant is global, and the next http(s) page picks up the
  // registration. Only the courtesy injection is skipped.
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });

  const result = await worker.enable({ tabId: null });

  assert.equal(result.ok, true);
  assert.equal(browser.config().enabled, true);
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
  assert.deepEqual(browser.callsMatching("scripting.execute"), []);
});

test("A018: repeated startup reconciliation is idempotent", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 4, enabled: true } },
    granted: [...GLOBAL_PATTERNS],
  });

  for (let restart = 0; restart < 3; restart += 1) {
    const worker = newWorker(browser);
    await worker.ready();
    await worker.ready(); // second call in the same worker must not re-run
  }

  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
  assert.equal(browser.callsMatching("scripting.register").length, 1);
  assert.equal(browser.callsMatching("scripting.unregister").length, 0);
  assert.equal(browser.config().revision, 4);
});

// SLICE C RETIREMENT. "A018: two ports of one host share one registration" and
// "A019: a different scheme is a different pattern and survives independently"
// are gone. Both asserted refcount-like behaviour over a SET of per-origin
// patterns; there is one registration and one permission pair now, so there is
// no sharing to get wrong. The risk they covered — revoking a permission a
// still-authorized origin needed — cannot occur when the only two states are
// "all" and "none".

test("A018: every http(s) origin bootstraps once the switch is on, each bound to itself", async () => {
  // SLICE C MODEL CHANGE, stated as a test rather than left implicit. Under
  // Slice A2 only the exactly-enabled origin bootstrapped; now every http(s)
  // origin does. What did NOT change is the binding: each frame is admitted as
  // its own exact origin, and a frame claiming a different one is refused.
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 1);

  for (const frameUrl of [
    "https://example.com/login",
    "https://example.com:8443/login",
    "http://example.com/login",
    "https://example.com.evil.test/login",
  ]) {
    const result = await worker.authorizeBootstrap(bootstrapCall(frameUrl));
    assert.equal(result.ok, true, `${frameUrl} must bootstrap`);
    assert.equal(
      result.origin,
      security.canonicalOriginOrNull(frameUrl),
      `${frameUrl} must be bound to its own exact origin`
    );
  }

  // The exact-origin binding is still enforced against a lying body: a frame
  // on :8443 cannot present itself as the default-port origin to widen what
  // the app will reveal to it.
  const spoofed = await worker.authorizeBootstrap(
    bootstrapCall("https://example.com:8443/login", HTTPS_EXAMPLE)
  );
  assert.equal(spoofed.ok, false);
  assert.equal(spoofed.error.code, "origin_mismatch");
});

// ---------------------------------------------------------------------------
// A019 — crash-consistent disable.
// ---------------------------------------------------------------------------

test("A019: the durable commit is the FIRST browser mutation of the disable", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 42);

  browser.calls.length = 0;
  await worker.disable();

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

test("A019: disable hands the broad permission back and drops the registration", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 42);
  assert.deepEqual(browser.grantedPatterns(), [...GLOBAL_PATTERNS].sort());
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);

  await worker.disable();

  // Leaving either behind is the failure this pins: a revoked opt-in that
  // still shows "can read all sites" on the extension page, or a registration
  // that keeps injecting into every page the user visits.
  assert.equal(browser.config().enabled, false);
  assert.deepEqual(browser.grantedPatterns(), []);
  assert.deepEqual(browser.registrationIds(), []);
});

test("A019: a failed durable commit starts no cleanup at all", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 42);

  browser.calls.length = 0;
  browser.failNextSet = "QUOTA_BYTES quota exceeded";
  await assert.rejects(() => worker.disable());

  assert.deepEqual(browser.calls, []);
  assert.equal(browser.config().enabled, true);
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
  assert.deepEqual(browser.grantedPatterns(), [...GLOBAL_PATTERNS].sort());
});

// The readback comparison in `_commitConfig` is a security guard, not a
// paranoia knob: it is what refuses to authorize cleanup against a storage
// layer that accepted the write and then reported something else. One test
// would leave the guard silently uncovered the day that test is renamed, so
// each distinct failure mode gets its own assertion: a divergent revision, a
// divergent VALUE at the expected revision, and an absent field.

test("A019: a mismatched readback aborts the disable before any cleanup", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 42);

  browser.calls.length = 0;
  browser.corruptNextReadback = { version: 2, revision: 99, enabled: false };
  await assert.rejects(() => worker.disable());

  assert.deepEqual(browser.calls, ["storage.set"]);
  assert.deepEqual(browser.callsMatching("permissions.remove"), []);
  assert.deepEqual(browser.callsMatching("scripting.unregister"), []);
});

test("A019: a readback with the RIGHT revision and the WRONG switch aborts", async () => {
  // The Slice A2 form of this case was a truncated `enabledOrigins` array. The
  // v2 analogue is sharper: the revision is exactly the expected one, so a
  // revision-only check waves it through, but the committed switch says the
  // opposite of what was written. Running D2–D5 against that value would tear
  // down an overlay the durable state still reports as ON.
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 42);

  browser.calls.length = 0;
  const expectedRevision = browser.config().revision + 1;
  browser.corruptNextReadback = {
    version: 2,
    revision: expectedRevision,
    enabled: true,
  };
  await assert.rejects(() => worker.disable(), /overlay_config_readback_mismatch/);

  assert.deepEqual(browser.calls, ["storage.set"]);
  assert.deepEqual(browser.callsMatching("permissions.remove"), []);
  assert.deepEqual(browser.callsMatching("scripting.unregister"), []);
  assert.deepEqual(browser.callsMatching("tabs.sendMessage"), []);
});

test("A019: a readback missing a field aborts the disable before any cleanup", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 42);

  browser.calls.length = 0;
  browser.corruptNextReadback = { version: 2, revision: browser.config().revision + 1 };
  await assert.rejects(() => worker.disable(), /overlay_config_readback_mismatch/);

  assert.deepEqual(browser.calls, ["storage.set"]);
  assert.deepEqual(browser.grantedPatterns(), [...GLOBAL_PATTERNS].sort());
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
});

test("A018: a partial readback aborts the enable before anything is registered", async () => {
  // Same guard on the other transaction. Registering a script on the strength
  // of a value storage never confirmed would inject into every page the user
  // visits without a durable opt-in behind it.
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await worker.reconcile();
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });

  browser.calls.length = 0;
  // The write claims to have landed, but the switch is absent from it.
  browser.corruptNextReadback = {
    version: 2,
    revision: browser.config().revision + 1,
    enabled: false,
  };
  await assert.rejects(
    () => worker.enable({ tabId: 42 }),
    /overlay_config_readback_mismatch/
  );

  assert.deepEqual(browser.callsMatching("scripting.register"), []);
  assert.deepEqual(browser.callsMatching("scripting.execute"), []);
  assert.deepEqual(browser.registrationIds(), []);
});

// ---------------------------------------------------------------------------
// Gate A2 (real-Chrome smoke): `chrome.storage.local.get` returns objects with
// keys in ALPHABETICAL order, not insertion order (measured on Chrome 151:
// set {version, revision, enabled} reads back as {enabled, revision, version}).
// The first test PINS that behaviour in the fake — without it, every other test
// here runs against a storage layer real Chrome does not ship. The second
// proves the commit readback survives it.
// ---------------------------------------------------------------------------

test("Gate A2: the fake's storage.local.get returns keys alphabetically, like real Chrome", async () => {
  const browser = new FakeBrowser();
  // Insertion order is deliberately NOT alphabetical.
  await browser.storage.local.set({
    probe: { version: 2, revision: 7, enabled: true },
  });
  const readback = (await browser.storage.local.get(["probe"])).probe;
  assert.deepEqual(Object.keys(readback), ["enabled", "revision", "version"]);
  // The VALUE is still intact — only key order changed.
  assert.deepEqual(readback, { version: 2, revision: 7, enabled: true });
});

test("Gate A2: enable commits despite Chrome's alphabetical readback key order", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 42 }] });
  const worker = newWorker(browser);
  await worker.reconcile();

  // Must not throw overlay_config_readback_mismatch on the reordered readback.
  const result = await grantAndEnable(browser, worker, 42);
  assert.equal(result.ok, true);
  assert.equal(browser.config().enabled, true);
  // The phases AFTER the commit actually ran: registration + explicit inject.
  assert.deepEqual(browser.registrationIds(), [GLOBAL_REGISTRATION_ID]);
  assert.equal(browser.callsMatching("scripting.execute").length, 1);
});

test("A019: disable broadcasts teardown to every tab, naming no origin", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }, { id: 2 }, { id: 3 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 1);

  await worker.disable();

  assert.equal(browser.deliveredTeardowns.length, 3);
  for (const { message } of browser.deliveredTeardowns) {
    assert.equal(message.type, "teardown");
    assert.equal(security.assertNoForbiddenKeys(message).ok, true);
    // Without the `tabs` permission this cannot be targeted. Only the revision
    // travels; the receiver revalidates its own origin against the worker.
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
  await grantAndEnable(browser, worker, 1);

  await worker.disable();
  const revisionAfterFirst = browser.config().revision;
  await worker.disable();

  assert.equal(browser.config().enabled, false);
  assert.equal(browser.config().revision, revisionAfterFirst + 1);
  assert.deepEqual(browser.grantedPatterns(), []);
  assert.deepEqual(browser.registrationIds(), []);
});

// ---------------------------------------------------------------------------
// A020 — fail-closed reconciliation.
// ---------------------------------------------------------------------------

test("A020: a permission revoked outside the popup durably disables the overlay", async () => {
  // The user goes to chrome://extensions and takes "on all sites" away. The
  // durable opt-in must follow, or the config would keep claiming an
  // authorization the browser no longer backs.
  for (const surviving of [[], [PATTERN_HTTPS], ["http://*/*"], ["https://*/*"]]) {
    const browser = new FakeBrowser({
      storage: { [CONFIG_KEY]: { version: 2, revision: 8, enabled: true } },
      granted: surviving,
      tabs: [{ id: 1 }],
    });

    await newWorker(browser).ready();

    assert.equal(
      browser.config().enabled,
      false,
      `granted=${JSON.stringify(surviving)} must disable`
    );
    assert.equal(browser.config().revision, 9);
    assert.deepEqual(browser.registrationIds(), []);
    // The RESIDUAL half is handed back too, and this is asserted on the
    // revocation-induced path specifically.
    //
    // The partial-revoke cases above are the ones that need it: the user took
    // one pattern away from chrome://extensions and the other is still granted.
    // Once the config commits `enabled: false` nothing justifies that leftover,
    // so leaving it would hand the user an extension that still reports host
    // access for a feature they have switched off. C-M4 pins the same sweep on
    // the DISABLE path (D5) and would stay green through a regression here, so
    // this assertion is not redundant with it — see C-M8.
    assert.deepEqual(
      browser.grantedPatterns(),
      [],
      `granted=${JSON.stringify(surviving)} must leave no residual permission`
    );
    // Reconciliation still nudges injected documents to revalidate, and still
    // without naming any origin.
    assert.equal(browser.deliveredTeardowns.length > 0, true);
    for (const { message } of browser.deliveredTeardowns) {
      assert.equal(message.type, "teardown");
      assert.equal(message.revision, 9);
      assert.equal(Object.prototype.hasOwnProperty.call(message, "origin"), false);
    }
  }
});

test("A020: an externally revoked grant fails the very next request closed", async () => {
  // Belt and braces: even BEFORE any reconciliation has run, a request that
  // arrives while the config still says `enabled: true` must be refused,
  // because `authorizeContentRequest` re-reads the browser's granted patterns
  // on every call rather than trusting the committed config alone.
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 8, enabled: true } },
    granted: [PATTERN_HTTPS], // a leftover narrow grant, not the broad pair
  });
  const worker = newWorker(browser);

  const result = await worker.authorizeBootstrap(bootstrapCall("https://example.com/login"));
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "disabled");
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
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 8, enabled: true } },
    granted: [...GLOBAL_PATTERNS],
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
    storage: { [CONFIG_KEY]: { version: 2, revision: 2, enabled: false } },
  });
  // Both shapes: a Slice A2 per-origin registration, and this build's own
  // global one left over from a config that has since been turned off.
  await browser.scripting.registerContentScripts([
    {
      id: registrationIdForPattern(PATTERN_HTTPS),
      matches: [PATTERN_HTTPS],
      js: ["overlay_security.js", "content_overlay.js"],
    },
    {
      id: GLOBAL_REGISTRATION_ID,
      matches: [...GLOBAL_PATTERNS],
      js: ["overlay_security.js", "content_overlay.js"],
    },
  ]);

  await newWorker(browser).ready();

  assert.deepEqual(browser.registrationIds(), []);
});

test("A020: a granted permission no config justifies is removed on cold start", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 2, enabled: false } },
    granted: [PATTERN_HTTPS, PATTERN_HTTP, ...GLOBAL_PATTERNS],
  });

  await newWorker(browser).ready();

  assert.deepEqual(browser.grantedPatterns(), []);
});

test("A020: reconciliation never touches a registration the extension does not own", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 2, enabled: false } },
  });
  await browser.scripting.registerContentScripts([
    { id: "some-other-feature", matches: ["https://other.test/*"], js: ["other.js"] },
  ]);

  await newWorker(browser).ready();

  assert.deepEqual(browser.registrationIds(), ["some-other-feature"]);
});

test("A020: bootstrap is served only after reconciliation has run", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 6, enabled: true } },
    granted: [], // permission gone: config is stale and must fail closed
  });
  const worker = newWorker(browser);

  const result = await worker.authorizeBootstrap(bootstrapCall("https://example.com/login"));

  assert.equal(result.ok, false);
  assert.equal(browser.config().enabled, false);
});

test("A020: a failing reconciliation is retried, never cached as ready", async () => {
  const browser = new FakeBrowser({
    storage: { [CONFIG_KEY]: { version: 2, revision: 1, enabled: "bogus" } },
  });
  const worker = newWorker(browser);

  browser.failNextSet = "transient";
  await assert.rejects(() => worker.ready());

  await worker.ready();
  assert.equal(browser.config().enabled, false);
});

test("A020: concurrent mutations are serialized, never interleaved", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }] });
  const worker = newWorker(browser);
  await browser.permissions.request({ origins: [...GLOBAL_PATTERNS] });

  // Enable and disable racing inside one worker. Whatever order the lock
  // picks, the committed value must be a valid config and the browser state
  // must agree with it — never "off but still registered", never "on but the
  // permission was swept".
  await Promise.all([
    worker.enable({ tabId: 1 }),
    worker.disable(),
    worker.enable({ tabId: 1 }),
  ]);

  const stored = browser.config();
  assert.equal(security.validateOverlayConfig(stored).ok, true);
  assert.deepEqual(
    browser.registrationIds(),
    stored.enabled ? [GLOBAL_REGISTRATION_ID] : []
  );
  assert.deepEqual(
    browser.grantedPatterns(),
    stored.enabled ? [...GLOBAL_PATTERNS].sort() : []
  );
});

// ---------------------------------------------------------------------------
// A017 — popup control states.
// ---------------------------------------------------------------------------

test("A017: control state covers unsupported, reconciling, enabled, disabled, denied", () => {
  const off = security.emptyOverlayConfig(1);
  const on = { version: 2, revision: 2, enabled: true };
  const httpsTab = "https://example.com/login";

  assert.equal(
    computeGlobalControlState({ tabUrl: "chrome://extensions", config: off }).state,
    "unsupported"
  );
  assert.equal(
    computeGlobalControlState({ tabUrl: "file:///tmp/a.html", config: off }).state,
    "unsupported"
  );
  assert.equal(computeGlobalControlState({ tabUrl: "", config: off }).state, "unsupported");
  // No tab NAMED at all is not the same as a tab that cannot host the overlay:
  // a caller that supplied nothing gets the plain global answer.
  assert.equal(computeGlobalControlState({ config: off }).state, "disabled");
  assert.equal(computeGlobalControlState({ tabUrl: null, config: off }).state, "disabled");
  assert.equal(
    computeGlobalControlState({ tabUrl: httpsTab, config: off, ready: false }).state,
    "reconciling"
  );
  assert.equal(computeGlobalControlState({ tabUrl: httpsTab, config: on }).state, "enabled");
  assert.equal(computeGlobalControlState({ tabUrl: httpsTab, config: off }).state, "disabled");
  assert.equal(
    computeGlobalControlState({ tabUrl: httpsTab, config: off, lastRequestDenied: true }).state,
    "denied"
  );
});

test("A017: the OFF switch is reachable from a page the overlay cannot run on", () => {
  // A permission the user cannot withdraw from where they are standing is a
  // permission they effectively cannot withdraw. `unsupported` must therefore
  // never mask an ON switch: the popup renders "Turn off" on a chrome:// page
  // exactly as it does on an http(s) one.
  const on = { version: 2, revision: 2, enabled: true };
  for (const tabUrl of ["chrome://extensions", "file:///tmp/a.html", "", null]) {
    assert.equal(
      computeGlobalControlState({ tabUrl, config: on }).state,
      "enabled",
      `${String(tabUrl)} must still offer the off switch`
    );
  }
});

test("A017: a declined prompt persists nothing", async () => {
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await worker.ready();

  // The popup never calls enable without a grant; if it ever did, the worker
  // still refuses, because the browser is the authority on the grant.
  const result = await worker.enable({ tabId: 1 });

  assert.deepEqual(result, { ok: false, error: "permission_missing" });
  assert.equal(browser.config().enabled, false);
  assert.deepEqual(browser.registrationIds(), []);
});

test("A017: siteState is global — the same answer whatever tab is open", async () => {
  // SLICE C REPLACEMENT for "siteState reports the committed origin, not the
  // requested one". There is no per-origin answer to report any more, and the
  // property worth pinning is the inverse: the tab must not be able to change
  // the reported state of a global switch.
  const browser = new FakeBrowser();
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 1);

  for (const tabUrl of [
    "https://example.com/x?y#z",
    "https://example.com:8443/x",
    "http://example.com/x",
    "https://unrelated.test/",
    "chrome://extensions",
    null,
  ]) {
    assert.equal(
      (await worker.siteState({ tabUrl })).state,
      "enabled",
      `${String(tabUrl)} must report the global state`
    );
  }
});

// ---------------------------------------------------------------------------
// Persistence hygiene.
// ---------------------------------------------------------------------------

test("no secret-shaped key is ever written to storage", async () => {
  const browser = new FakeBrowser({ tabs: [{ id: 1 }] });
  const worker = newWorker(browser);
  await grantAndEnable(browser, worker, 1);
  await worker.disable();

  const serialized = JSON.stringify(browser.store);
  for (const forbidden of security.FORBIDDEN_KEYS) {
    assert.equal(serialized.includes(`"${forbidden}"`), false, forbidden);
  }
  // The permission patterns are derived from a constant, never stored.
  assert.equal(serialized.includes("/*"), false);
  assert.deepEqual(Object.keys(browser.config()).sort(), [
    "enabled",
    "revision",
    "version",
  ]);
  // No origin is persisted at all any more — the durable value cannot leak
  // which sites the user visits, because it never knew.
  assert.equal(serialized.includes("example.com"), false);
});
