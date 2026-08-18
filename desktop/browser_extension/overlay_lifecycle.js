// 009 Slice A2 — durable opt-in, dynamic registration, crash-consistent revoke.
//
// This file is PRODUCTION code. `background.js` loads it with
// `importScripts("overlay_security.js", "overlay_lifecycle.js")` and the Node
// harness under `test/` loads the very same file through `require()` against a
// fake browser. There is one implementation of every rule below.
//
// Every validation rule this file needs already exists in `overlay_security.js`
// (SR-2 canonical origin, permission-pattern derivation, `overlayConfigV1`
// shape, focus-grant store). Nothing is re-implemented here: this file owns
// only the *lifecycle* — when the durable value is written, in which order the
// revocation side effects run, and how a cold worker reconciles browser state
// back to the committed config.
//
// No `chrome.*` global is referenced. The browser API arrives as one injected
// object so the crash-injection harness can drive it deterministically.

"use strict";

// MV3 `importScripts` shares one global scope across worker files: every
// top-level binding lives inside this IIFE so it cannot collide with
// `overlay_security.js` / `overlay_routes.js` (`require()` in the Node harness
// would never show the collision). See `test/worker_global_scope.test.js`.
(() => {

const securityModule =
  typeof require === "function" &&
  typeof module !== "undefined" &&
  typeof module.exports === "object"
    ? require("./overlay_security.js")
    : globalThis.KeyVaultOverlaySecurity;

// ---------------------------------------------------------------------------
// Registration identity.
//
// data-model.md: "Registration ids are derived from a stable hash/encoding of
// permission pattern; do not persist duplicate registration truth in storage."
// Hex encoding is used rather than a hash because it is injective: two distinct
// patterns can never collide onto one registration id, and a collision here
// would silently unregister a still-authorized site.
// ---------------------------------------------------------------------------

const REGISTRATION_PREFIX = "kv-overlay-";

function registrationIdForPattern(pattern) {
  let hex = "";
  for (let index = 0; index < pattern.length; index += 1) {
    hex += pattern.charCodeAt(index).toString(16).padStart(4, "0");
  }
  return REGISTRATION_PREFIX + hex;
}

function isOverlayRegistrationId(id) {
  return typeof id === "string" && id.startsWith(REGISTRATION_PREFIX);
}

/**
 * The browser permission patterns the committed config justifies.
 *
 * Derived, never persisted (data-model.md). Two enabled origins that differ
 * only by port collapse onto one pattern, which is precisely why disabling one
 * of them must not remove the permission the other still needs.
 */
function desiredPatterns(config) {
  const patterns = new Set();
  for (const origin of config.enabledOrigins) {
    const pattern = securityModule.permissionPatternForOrigin(origin);
    if (pattern !== null) patterns.add(pattern);
  }
  return patterns;
}

// Registration and injection both target the isolated world at document_idle,
// in every frame the browser is willing to inject. `overlay_security.js` is
// listed first so the content script can reuse the shipped canonicalization
// instead of carrying a second copy of the SR-2 rule.
const CONTENT_SCRIPT_FILES = Object.freeze([
  "overlay_security.js",
  "content_overlay.js",
]);

function registrationForPattern(pattern) {
  return {
    id: registrationIdForPattern(pattern),
    matches: [pattern],
    js: [...CONTENT_SCRIPT_FILES],
    runAt: "document_idle",
    allFrames: true,
    world: "ISOLATED",
    persistAcrossSessions: true,
  };
}

// ---------------------------------------------------------------------------
// A017 — popup control state.
//
// Pure so the popup renders a state it did not compute itself. `denied` is not
// derivable from durable state: it is the transient answer to one declined
// `permissions.request`, so the popup passes it in.
// ---------------------------------------------------------------------------

function computeSiteControlState({
  tabUrl,
  config,
  ready = true,
  lastRequestDenied = false,
}) {
  const origin = securityModule.canonicalOriginOrNull(tabUrl);
  if (origin === null) {
    return { state: "unsupported", origin: null, pattern: null };
  }
  const pattern = securityModule.permissionPatternForOrigin(origin);
  if (!ready) return { state: "reconciling", origin, pattern };
  if (config.enabledOrigins.includes(origin)) {
    return { state: "enabled", origin, pattern };
  }
  if (lastRequestDenied) return { state: "denied", origin, pattern };
  return { state: "disabled", origin, pattern };
}

// ---------------------------------------------------------------------------

const DISABLE_PHASES = Object.freeze(["D1", "D2", "D3", "D4", "D5"]);

/**
 * Canonical JSON with object keys sorted recursively. Array order is
 * preserved — `enabledOrigins` is sorted by contract, so a reordered array IS
 * a different value and must still mismatch.
 *
 * Exists because real Chrome (measured on 151) returns
 * `chrome.storage.local.get` objects with keys in ALPHABETICAL order, not
 * insertion order: `set {version, revision, enabledOrigins}` reads back as
 * `{enabledOrigins, revision, version}`. A readback compared through plain
 * `JSON.stringify` therefore mismatches on EVERY commit in production while
 * comparing equal in any harness that preserves insertion order. The readback
 * guard's intent is value identity, not byte identity of one serialization.
 */
function canonicalJson(value) {
  if (Array.isArray(value)) {
    return "[" + value.map(canonicalJson).join(",") + "]";
  }
  if (value !== null && typeof value === "object") {
    return (
      "{" +
      Object.keys(value)
        .sort()
        .map((key) => JSON.stringify(key) + ":" + canonicalJson(value[key]))
        .join(",") +
      "}"
    );
  }
  // `undefined` serializes as undefined, which can never equal an object's
  // canonical string — a missing readback still mismatches.
  return JSON.stringify(value);
}

class OverlayLifecycle {
  /**
   * @param {object} options
   * @param {object} options.browser   `chrome`-shaped API (promise flavour).
   * @param {object} [options.grants]  Focus-grant store; anything with clear().
   * @param {Function} [options.onFault] Crash injection hook (A021). Called
   *        with each completed disable phase; throwing simulates the worker
   *        dying at that exact point.
   */
  constructor({ browser, grants, onFault } = {}) {
    this._browser = browser;
    this._grants = grants ?? new securityModule.FocusGrantStore();
    this._onFault = onFault ?? null;
    // Serializes every config mutation inside one worker instance, so two
    // concurrent enable/disable calls cannot interleave read-modify-write.
    this._queue = Promise.resolve();
    this._reconciled = null;
  }

  get grants() {
    return this._grants;
  }

  // -------------------------------------------------------------------------
  // Durable config.
  // -------------------------------------------------------------------------

  /**
   * A023 — the durable monotonic revision floor.
   *
   * CLOSES the "KNOWN GAP" Slice A2 left here. In A2 a total corruption of
   * `overlayConfigV1` (an unreadable revision, `null`, a missing key, a
   * negative revision) salvaged 0 and the next commit restarted the counter at
   * revision 1. That was harmless while nothing was authorized. In A3 it is
   * not: a focus grant carries `configRevision`, and `FocusGrantStore.consume`
   * accepts a grant only when that number equals the committed one. A rewound
   * counter that climbs back to an already-used revision would make a stale
   * grant compare as current.
   *
   * Two independent mechanisms, because each covers the other's blind spot:
   *
   *   PREVENTION — this floor. Written in the SAME `storage.local.set` as the
   *   config (one operation, so D1 stays a single atomic commit) but under its
   *   own key, so corruption of `overlayConfigV1` does not destroy it. Every
   *   commit raises it, every read raises the recovered revision to it, and a
   *   config whose revision is BELOW it is treated as corrupt — that is what a
   *   rollback to an older-but-well-formed value looks like.
   *
   *   CONTAINMENT — `_readConfig` clears every in-memory grant the moment it
   *   observes an invalid config, and the authorization paths refuse to serve
   *   until reconciliation has rebuilt a valid value. This holds even if the
   *   floor key itself is unreadable, which prevention alone cannot cover.
   */
  async _readConfig() {
    const key = securityModule.OVERLAY_CONFIG_KEY;
    const floorKey = securityModule.OVERLAY_REVISION_FLOOR_KEY;
    let stored;
    try {
      stored = await this._browser.storage.local.get([key, floorKey]);
    } catch (_) {
      // A failed read is not evidence that anything is authorized.
      this._grants.clear();
      return { ...securityModule.emptyOverlayConfig(0), __invalid: true };
    }
    const raw = stored?.[key];
    const floor = securityModule.revisionFloorOrZero(stored?.[floorKey]);
    const valid = securityModule.validateOverlayConfig(raw).ok;

    // A well-formed value whose revision sits below the floor is a rollback,
    // not a valid config: it would re-authorize origins from a revision that
    // has already been superseded.
    if (!valid || raw.revision < floor) {
      const plausible =
        Number.isInteger(raw?.revision) && raw.revision >= 0 ? raw.revision : 0;
      // Containment: no grant minted against the pre-corruption revision may
      // outlive the moment corruption is observed.
      this._grants.clear();
      return {
        ...securityModule.emptyOverlayConfig(Math.max(floor, plausible)),
        __invalid: true,
      };
    }
    return {
      version: 1,
      revision: raw.revision,
      enabledOrigins: [...raw.enabledOrigins],
    };
  }

  /**
   * Committed authorization state. Anything invalid or missing reads as zero
   * enabled origins; this method never writes, so a read path can never grant.
   */
  async readCommittedConfig() {
    return this._readConfig();
  }

  /**
   * D1. One `storage.local.set` carrying the config and the raised floor, then
   * a readback that must match exactly. A rejected write or a mismatched
   * readback throws, and the caller is contractually forbidden from running any
   * later phase.
   *
   * Both keys travel in ONE `set` on purpose: SR-8 requires the durable
   * authorization commit to be a single operation, and a floor written in a
   * second call could be lost while the config it protects survives.
   */
  async _commitConfig(next) {
    const key = securityModule.OVERLAY_CONFIG_KEY;
    const floorKey = securityModule.OVERLAY_REVISION_FLOOR_KEY;
    const shape = securityModule.validateOverlayConfig(next);
    if (!shape.ok) {
      throw new Error(`overlay_config_invalid:${shape.error}`);
    }
    // The floor is a HIGH-WATER MARK: a commit may raise it, nothing may lower
    // it. `next.revision` alone is not that value. The revision being committed
    // is derived from whatever `_readConfig` managed to see, and `_readConfig`
    // reports revision 0 when the read itself FAILED — a transient
    // `storage.local.get` error is not evidence that the floor is low, only
    // that it is unknown. Writing `next.revision` unconditionally would take a
    // floor of 9 down to 1 on the next commit, silently disarming the
    // prevention half of A023 and leaving containment as the only surviving
    // defence of two that are documented as independent.
    //
    // Read separately from `_readConfig` on purpose: that call may have failed,
    // and its salvaged revision is not a floor. If THIS read throws the commit
    // aborts, which is the correct answer when the floor cannot be established.
    const priorFloor = securityModule.revisionFloorOrZero(
      (await this._browser.storage.local.get([floorKey]))?.[floorKey]
    );
    const floor = Math.max(priorFloor, next.revision);

    // Still ONE `set` carrying both keys: SR-8/D1 requires the durable
    // authorization commit to be a single operation. The read above is a read.
    await this._browser.storage.local.set({ [key]: next, [floorKey]: floor });
    const stored = await this._browser.storage.local.get([key, floorKey]);
    const readback = stored?.[key];
    // Key-order-insensitive on purpose: Chrome's `get` returns keys sorted
    // alphabetically (see `canonicalJson`). Any truncated, altered, extra or
    // reordered-array value still throws.
    if (canonicalJson(readback) !== canonicalJson(next)) {
      throw new Error("overlay_config_readback_mismatch");
    }
    if (securityModule.revisionFloorOrZero(stored?.[floorKey]) < floor) {
      throw new Error("overlay_revision_floor_readback_mismatch");
    }
    return next;
  }

  _nextConfig(config, enabledOrigins) {
    return {
      version: 1,
      revision: config.revision + 1,
      enabledOrigins: [...enabledOrigins].sort(),
    };
  }

  async _fault(phase) {
    if (this._onFault !== null) await this._onFault(phase);
  }

  _withLock(work) {
    const run = this._queue.then(work, work);
    // Keep the chain alive after a rejection so one failed transaction does not
    // wedge every later one.
    this._queue = run.then(
      () => undefined,
      () => undefined
    );
    return run;
  }

  // -------------------------------------------------------------------------
  // Browser state derivation.
  // -------------------------------------------------------------------------

  async _grantedPatterns() {
    try {
      const granted = await this._browser.permissions.getAll();
      return Array.isArray(granted?.origins) ? granted.origins : [];
    } catch (_) {
      return [];
    }
  }

  async _hasPattern(pattern) {
    if (pattern === null) return false;
    try {
      return (await this._browser.permissions.contains({ origins: [pattern] })) === true;
    } catch (_) {
      return false;
    }
  }

  async _registeredOverlayScripts() {
    try {
      const registered = await this._browser.scripting.getRegisteredContentScripts();
      return (Array.isArray(registered) ? registered : []).filter((script) =>
        isOverlayRegistrationId(script?.id)
      );
    } catch (_) {
      return [];
    }
  }

  /** D4. Registrations converge on exactly the patterns the config justifies. */
  async _reconcileRegistrations(config) {
    const desired = desiredPatterns(config);
    const desiredIds = new Set([...desired].map(registrationIdForPattern));
    const registered = await this._registeredOverlayScripts();
    const registeredIds = new Set(registered.map((script) => script.id));

    const orphans = registered
      .map((script) => script.id)
      .filter((id) => !desiredIds.has(id));
    if (orphans.length > 0) {
      await this._browser.scripting.unregisterContentScripts({ ids: orphans });
    }

    const missing = [...desired]
      .filter((pattern) => !registeredIds.has(registrationIdForPattern(pattern)))
      .map(registrationForPattern);
    if (missing.length > 0) {
      await this._browser.scripting.registerContentScripts(missing);
    }
  }

  /**
   * D5. Optional host permissions converge on the patterns the config
   * justifies. A pattern shared by another still-enabled origin is retained;
   * that check reads committed origins, never the caller's intent.
   */
  async _reconcilePermissions(config) {
    const desired = desiredPatterns(config);
    const granted = await this._grantedPatterns();
    const orphans = granted.filter((pattern) => !desired.has(pattern));
    if (orphans.length > 0) {
      try {
        await this._browser.permissions.remove({ origins: orphans });
      } catch (_) {
        // Retried by the next reconciliation. Authorization is already revoked.
      }
    }
  }

  /**
   * D3. Teardown is advisory: authorization is already gone after D1.
   *
   * The message names NO origin. Without the `tabs` permission the worker
   * cannot read `tab.url`, so this is necessarily a broadcast to every
   * injected document; putting the disabled origin in it would tell a document
   * on still-enabled origin A which origin B the user just turned off. The
   * revision is a global counter that leaks nothing about which site changed.
   * Each receiver revalidates its own exact origin against `authorizeBootstrap`
   * and tears itself down only if that answer is no.
   */
  async _broadcastTeardown(revision) {
    let tabs = [];
    try {
      tabs = await this._browser.tabs.query({});
    } catch (_) {
      return;
    }
    const message = {
      channel: securityModule.CHANNEL,
      version: securityModule.MESSAGE_VERSION,
      type: "teardown",
      revision,
    };
    for (const tab of tabs) {
      if (typeof tab?.id !== "number") continue;
      try {
        await this._browser.tabs.sendMessage(tab.id, message);
      } catch (_) {
        // No injected receiver in that tab, or the tab is gone. Both fine.
      }
    }
  }

  // -------------------------------------------------------------------------
  // A020 — fail-closed reconciliation.
  // -------------------------------------------------------------------------

  /**
   * Runs at most once per worker instance and gates every message. Callers
   * await this before answering anything, so a cold worker can never serve a
   * request against unreconciled browser state.
   */
  async ready() {
    if (this._reconciled === null) {
      this._reconciled = this.reconcile().catch((error) => {
        // Failing closed means retrying, not caching a broken "ready".
        this._reconciled = null;
        throw error;
      });
    }
    return this._reconciled;
  }

  /**
   * @param {object} [options]
   * @param {boolean} [options.prunePermissions=true]
   *
   * `prunePermissions: false` exists for exactly one caller: the
   * `permissions.onAdded` listener in `background.js`. Chrome fires that event
   * the instant the user accepts the popup's `permissions.request`, BEFORE the
   * popup's `setSiteState` message reaches this worker — so at that moment the
   * freshly granted pattern is not yet justified by committed config and a
   * full reconcile would classify it as an orphan and revoke it, making the
   * enable fail (`enableOrigin` re-checks `permissions.contains`).
   *
   * Deferring the orphan sweep on that one trigger is safe because the
   * DURABLE CONFIG, never the browser permission alone, is the authorization
   * source of truth: bootstrap and every content route verify config +
   * revision, so a granted-but-unconfigured permission is inert. Removing
   * orphan permissions is hygiene, not revocation of authorization, and the
   * sweep still runs on every other trigger — cold start / `ready()`, popup
   * open (`siteState`), `permissions.onRemoved`, and the disable flow (D5).
   *
   * TOCTOU variant (full reconcile computes orphans, `enableOrigin` commits,
   * reconcile then removes): impossible by construction inside one worker.
   * Both `reconcile()` and `enableOrigin()` run their ENTIRE body — config
   * read, orphan computation, `permissions.remove` — inside `_withLock`, one
   * FIFO promise queue per lifecycle instance, and `background.js` constructs
   * exactly one instance per worker. So a full reconcile either finishes
   * before the enable's commit (and never saw the new pattern as granted-and-
   * unjustified past the commit) or starts after it (and sees the config that
   * justifies the pattern).
   */
  async reconcile({ prunePermissions = true } = {}) {
    return this._withLock(async () => {
      let config = await this.readCommittedConfig();

      // Invalid or missing durable state becomes zero enabled origins, written
      // back as one valid revisioned config, before any registration exists.
      if (config.__invalid === true) {
        config = await this._commitConfig(
          securityModule.emptyOverlayConfig(config.revision + 1)
        );
      }

      // In-memory grants never survive a cold start, and are dropped again here
      // so a reconciliation triggered by a permission change also clears them.
      this._grants.clear();

      // A permission revoked outside the popup (chrome://extensions) durably
      // disables the affected origins in one revisioned write.
      const survivors = [];
      for (const origin of config.enabledOrigins) {
        const pattern = securityModule.permissionPatternForOrigin(origin);
        if (await this._hasPattern(pattern)) survivors.push(origin);
      }
      if (survivors.length !== config.enabledOrigins.length) {
        config = await this._commitConfig(this._nextConfig(config, survivors));
        // One broadcast regardless of how many origins were dropped: the
        // message carries only the new revision, so per-origin fan-out would
        // add round trips without adding information.
        await this._broadcastTeardown(config.revision);
      }

      await this._reconcileRegistrations(config);
      if (prunePermissions) await this._reconcilePermissions(config);
      return config;
    });
  }

  // -------------------------------------------------------------------------
  // A017/A018 — enable.
  // -------------------------------------------------------------------------

  /**
   * Persists an opt-in. The permission grant is the popup's job (it needs the
   * user gesture); this method refuses to persist unless the browser confirms
   * the derived pattern is actually held, so a declined or revoked grant can
   * never leave an enabled origin behind.
   */
  async enableOrigin({ origin, tabId } = {}) {
    return this._withLock(async () => {
      const canonical = securityModule.canonicalOriginOrNull(origin);
      if (canonical === null) return { ok: false, error: "unsupported_origin" };

      const pattern = securityModule.permissionPatternForOrigin(canonical);
      if (!(await this._hasPattern(pattern))) {
        return { ok: false, error: "permission_missing" };
      }

      let config = await this.readCommittedConfig();
      if (config.__invalid === true) {
        // Same salvage as `disableOrigin`: the recovered value is in-memory
        // only and is never committed on its own, so the single write below
        // advances the revision by exactly one either way.
        config = securityModule.emptyOverlayConfig(config.revision);
      }
      if (!config.enabledOrigins.includes(canonical)) {
        if (config.enabledOrigins.length >= securityModule.LIMITS.ENABLED_ORIGINS) {
          return { ok: false, error: "too_many_origins" };
        }
        config = await this._commitConfig(
          this._nextConfig(config, [...config.enabledOrigins, canonical])
        );
      }

      await this._reconcileRegistrations(config);
      // Registration only affects documents loaded from now on, so the tab the
      // user is looking at is injected explicitly. Failure is not fatal: a
      // reload picks the registration up.
      if (typeof tabId === "number") {
        try {
          await this._browser.scripting.executeScript({
            target: { tabId, allFrames: true },
            files: [...CONTENT_SCRIPT_FILES],
          });
        } catch (_) {
          // Restricted page or no injectable frame. Fails closed by doing
          // nothing; SR-7 forbids claiming injection happened.
        }
      }
      return { ok: true, revision: config.revision, origin: canonical };
    });
  }

  // -------------------------------------------------------------------------
  // A019/SR-8 — crash-consistent disable.
  // -------------------------------------------------------------------------

  /**
   * ORDER IS THE SECURITY PROPERTY, not an implementation detail.
   *
   * D1 is the durable commit. It is the only fallible step whose failure
   * aborts the transaction, and it happens before every side effect, because
   * the durable config — not the permission, not the registration, not the
   * injected script — is the authorization source of truth. After D1 every
   * authorization check sees the origin as disabled even if this worker dies
   * on the very next line. D2–D5 are idempotent cleanup that any later worker
   * finishes through `reconcile()`.
   *
   * Moving `_commitConfig` after any of D2–D5 reintroduces a window where a
   * crash leaves the browser cleaned up but the origin still durably
   * authorized. `test/overlay_lifecycle.test.js` and
   * `test/overlay_crash_consistency.test.js` both fail if that order changes.
   */
  async disableOrigin({ origin } = {}) {
    return this._withLock(async () => {
      const canonical = securityModule.canonicalOriginOrNull(origin);
      if (canonical === null) return { ok: false, error: "unsupported_origin" };

      let config = await this.readCommittedConfig();
      if (config.__invalid === true) {
        config = securityModule.emptyOverlayConfig(config.revision);
      }

      // D1 — durable commit. Throws on write or readback failure; nothing below
      // this line runs in that case.
      const committed = await this._commitConfig(
        this._nextConfig(
          config,
          config.enabledOrigins.filter((entry) => entry !== canonical)
        )
      );
      await this._fault("D1");

      // D2 — worker grants for the old revision are worthless now.
      this._grants.clear();
      await this._fault("D2");

      // D3 — advisory teardown for documents that still hold an injected script.
      await this._broadcastTeardown(committed.revision);
      await this._fault("D3");

      // D4 — drop the registration only if no committed origin still needs the
      // pattern (two ports of one host share it).
      await this._reconcileRegistrations(committed);
      await this._fault("D4");

      // D5 — same sharing rule for the optional host permission.
      await this._reconcilePermissions(committed);
      await this._fault("D5");

      return { ok: true, revision: committed.revision, origin: canonical };
    });
  }

  // -------------------------------------------------------------------------
  // A017/A018 — read paths.
  // -------------------------------------------------------------------------

  /** Popup control state for one tab. Reconciles first, then reports. */
  async siteState({ tabUrl, lastRequestDenied = false } = {}) {
    await this.ready();
    const config = await this.readCommittedConfig();
    return {
      ...computeSiteControlState({ tabUrl, config, lastRequestDenied }),
      revision: config.revision,
    };
  }

  /**
   * A023 — the single authorization gate for EVERY content-script request
   * (bootstrap, requestMatches, fill). It runs before any native I/O and it is
   * the only place the frame's authoritative origin is established.
   *
   * The authoritative origin comes from `sender.url` inside
   * `validateContentScriptSender`; `message.origin` is compared against it and
   * is never promoted to authority. Tab id, frame id, optional document id and
   * the top-frame agreement rule are all enforced there too. What this method
   * adds is the state only the worker owns: the committed config, the
   * permission the browser still reports, the revision, and the frame support
   * classification.
   *
   * @returns {{ok: true, sender: object, config: object, frameSupport: string}
   *          |{ok: false, error: string}}
   */
  async authorizeContentRequest({ message, sender, runtimeId } = {}) {
    await this.ready();
    const config = await this.readCommittedConfig();
    if (config.__invalid === true) {
      // Refuse to serve until reconciliation has rebuilt a valid durable value.
      // Grants were already dropped by the read itself.
      //
      // `ready()` resolves once per worker, so corruption appearing AFTER it
      // resolved would otherwise wedge this worker into permanent refusal.
      // Dropping the memo makes the NEXT request reconcile and rebuild, while
      // this one still fails closed.
      this._reconciled = null;
      return { ok: false, error: "stale_session" };
    }
    const grantedPatterns = await this._grantedPatterns();
    const result = securityModule.validateContentScriptRequest(
      message,
      sender,
      runtimeId,
      {
        enabledOrigins: config.enabledOrigins,
        revision: config.revision,
        grantedPatterns,
      }
    );
    if (!result.ok) return { ok: false, error: result.error };

    const frameSupport = securityModule.computeFrameSupport({
      frameId: result.sender.frameId,
      frameOrigin: result.sender.origin,
      topOrigin: result.sender.topOrigin,
      enabledOrigins: config.enabledOrigins,
    });
    return { ok: true, sender: result.sender, config, frameSupport };
  }

  /**
   * A018/A020 — an already-injected content script stays inert until this
   * approves it. Authorization is re-derived from committed config every time;
   * the script's own claim about its origin is only ever a mismatch detector.
   */
  async authorizeBootstrap({ message, sender, runtimeId } = {}) {
    const auth = await this.authorizeContentRequest({ message, sender, runtimeId });
    if (!auth.ok) {
      return { ok: false, error: { code: auth.error } };
    }
    return {
      ok: true,
      type: "bootstrapResult",
      // SR-7: `enabled` is the durable opt-in for THIS frame's exact origin.
      // An unsupported frame keeps `enabled: true` and is refused by
      // `frameSupport`, so the content script can render the honest
      // "unsupported frame" state instead of a misleading "disabled" one.
      enabled: true,
      origin: auth.sender.origin,
      topOrigin: auth.sender.topOrigin,
      frameId: auth.sender.frameId,
      frameSupport: auth.frameSupport,
      revision: auth.config.revision,
    };
  }
}

const API = {
  OverlayLifecycle,
  CONTENT_SCRIPT_FILES,
  DISABLE_PHASES,
  REGISTRATION_PREFIX,
  registrationIdForPattern,
  isOverlayRegistrationId,
  registrationForPattern,
  desiredPatterns,
  computeSiteControlState,
};

if (typeof module !== "undefined" && typeof module.exports === "object") {
  module.exports = API;
} else {
  globalThis.KeyVaultOverlayLifecycle = API;
}

})();
