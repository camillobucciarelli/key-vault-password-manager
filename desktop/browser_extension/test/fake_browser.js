// Fake `chrome` for the Slice A2 lifecycle harness.
//
// This file models BROWSER state only: storage bytes, granted optional host
// patterns, registered dynamic scripts, open tabs. It contains no
// authorization logic, no canonicalization and no ordering rules, so a test
// can never pass against a policy that only the fake implements.
//
// Durable state lives on the fake, not on the lifecycle instance. "Restarting
// the worker" in these tests means constructing a new `OverlayLifecycle`
// against the *same* fake — exactly what an MV3 cold start does.

"use strict";

/**
 * Real Chrome (measured on 151) returns `chrome.storage.local.get` objects
 * with keys in ALPHABETICAL order, recursively — not insertion order:
 * `set {version, revision, enabledOrigins}` reads back as
 * `{enabledOrigins, revision, version}`. Reproducing that here keeps the
 * WHOLE suite sensitive to any key-order assumption on values that cross
 * storage. Array order is untouched, exactly as in Chrome.
 */
function sortKeysDeep(value) {
  if (Array.isArray(value)) return value.map(sortKeysDeep);
  if (value !== null && typeof value === "object") {
    const sorted = {};
    for (const key of Object.keys(value).sort()) {
      sorted[key] = sortKeysDeep(value[key]);
    }
    return sorted;
  }
  return value;
}

class FakeBrowser {
  constructor({ storage = {}, granted = [], tabs = [] } = {}) {
    this.store = { ...storage };
    /**
     * `chrome.storage.session` model. In-memory for the lifetime of THIS fake
     * instance — exactly Chrome's semantics (dies with the browser session,
     * survives worker restarts, which the tests model as a new
     * OverlayLifecycle against the same fake). Default access level is
     * TRUSTED_CONTEXTS: popup and worker both read/write it, content scripts
     * never do — the harness gives content-script code no handle to it.
     */
    this.sessionStore = {};
    this.granted = new Set(granted);
    this.registered = new Map();
    this.tabList = tabs.map((tab) => ({ ...tab }));
    /** Ordered log of every mutating browser call. Order assertions read this. */
    this.calls = [];
    /** Set to a message to make the next `storage.local.set` reject. */
    this.failNextSet = null;
    /**
     * Set to a message to make the next `storage.local.get` reject — a
     * TRANSIENT read failure, not corruption. The distinction matters: a failed
     * read tells the worker nothing about what is stored, so it must not be
     * mistaken for evidence that the stored value is low or absent.
     */
    this.failNextGet = null;
    /**
     * Set to a value to make the read that immediately follows the next write
     * return something else — i.e. a failed readback, not a failed read.
     */
    this.corruptNextReadback = null;
    this._lastOpWasSet = false;
    this.deliveredTeardowns = [];

    const self = this;

    this.storage = {
      local: {
        async get(key) {
          if (self.failNextGet !== null) {
            const message = self.failNextGet;
            self.failNextGet = null;
            throw new Error(message);
          }
          const keys = Array.isArray(key) ? key : [key];
          const result = {};
          for (const entry of keys) {
            if (Object.prototype.hasOwnProperty.call(self.store, entry)) {
              result[entry] = sortKeysDeep(
                JSON.parse(JSON.stringify(self.store[entry]))
              );
            }
          }
          if (self.corruptNextReadback !== null && self._lastOpWasSet) {
            const corrupt = self.corruptNextReadback;
            self.corruptNextReadback = null;
            result[keys[0]] = corrupt;
          }
          self._lastOpWasSet = false;
          return result;
        },
        async set(values) {
          if (self.failNextSet !== null) {
            const message = self.failNextSet;
            self.failNextSet = null;
            throw new Error(message);
          }
          self.calls.push("storage.set");
          self._lastOpWasSet = true;
          Object.assign(self.store, JSON.parse(JSON.stringify(values)));
        },
      },
      session: {
        async get(key) {
          const keys = Array.isArray(key) ? key : [key];
          const result = {};
          for (const entry of keys) {
            if (Object.prototype.hasOwnProperty.call(self.sessionStore, entry)) {
              result[entry] = sortKeysDeep(
                JSON.parse(JSON.stringify(self.sessionStore[entry]))
              );
            }
          }
          return result;
        },
        async set(values) {
          self.calls.push("storage.session.set");
          Object.assign(self.sessionStore, JSON.parse(JSON.stringify(values)));
        },
        async remove(key) {
          self.calls.push("storage.session.remove");
          const keys = Array.isArray(key) ? key : [key];
          for (const entry of keys) delete self.sessionStore[entry];
        },
      },
    };

    /**
     * Listeners for `permissions.onAdded`, dispatched by `request()` exactly
     * as Chrome does: after the grant lands, before the granting page's next
     * message can reach the worker. Dispatch results are collected in
     * `permissionEvents` so a test can await the listener-triggered work at
     * the point Chrome would have completed it. Pure browser behaviour — the
     * fake decides nothing about what a listener does.
     */
    this._onAddedListeners = [];
    this.permissionEvents = [];

    this.permissions = {
      onAdded: {
        addListener(listener) {
          self._onAddedListeners.push(listener);
        },
      },
      async getAll() {
        return { origins: [...self.granted], permissions: [] };
      },
      async contains({ origins = [] } = {}) {
        return origins.every((pattern) => self.granted.has(pattern));
      },
      async request({ origins = [] } = {}) {
        self.calls.push("permissions.request");
        for (const pattern of origins) self.granted.add(pattern);
        for (const listener of self._onAddedListeners) {
          self.permissionEvents.push(
            Promise.resolve().then(() => listener({ origins: [...origins] }))
          );
        }
        return true;
      },
      async remove({ origins = [] } = {}) {
        self.calls.push("permissions.remove");
        for (const pattern of origins) self.granted.delete(pattern);
        return true;
      },
    };

    this.scripting = {
      async getRegisteredContentScripts() {
        return [...self.registered.values()].map((script) => ({ ...script }));
      },
      async registerContentScripts(scripts) {
        self.calls.push("scripting.register");
        for (const script of scripts) {
          if (self.registered.has(script.id)) {
            throw new Error(`duplicate registration id ${script.id}`);
          }
          self.registered.set(script.id, { ...script });
        }
      },
      async unregisterContentScripts({ ids = [] } = {}) {
        self.calls.push("scripting.unregister");
        for (const id of ids) self.registered.delete(id);
      },
      async executeScript({ target, files } = {}) {
        self.calls.push("scripting.execute");
        return [{ frameId: 0, target, files }];
      },
    };

    this.tabs = {
      async query() {
        return self.tabList.map((tab) => ({ ...tab }));
      },
      async sendMessage(tabId, message) {
        self.calls.push("tabs.sendMessage");
        self.deliveredTeardowns.push({ tabId, message });
        return undefined;
      },
    };
  }

  /** Committed durable value, exactly as stored. */
  config(key = "overlayConfigV1") {
    return this.store[key];
  }

  registrationIds() {
    return [...this.registered.keys()].sort();
  }

  grantedPatterns() {
    return [...this.granted].sort();
  }

  callsMatching(prefix) {
    return this.calls.filter((call) => call.startsWith(prefix));
  }
}

module.exports = { FakeBrowser };
