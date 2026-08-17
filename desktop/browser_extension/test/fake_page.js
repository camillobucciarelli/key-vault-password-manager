// One isolated world for one document, for driving `content_overlay.js`.
//
// `content_overlay.js` is the only extension file that runs inside a hostile
// page, and it is an IIFE with no exports: there is nothing to `require()`.
// So this harness does what Chromium does — evaluate the shipped
// `overlay_security.js` and the shipped `content_overlay.js`, in that order,
// in one fresh isolated-world global — and then observes the two things the
// bootstrap is allowed to touch: the messages it sends and the listeners it
// attaches.
//
// The context models the DOCUMENT only: `location`, `chrome.runtime`. It holds
// no authorization logic, so a test can never pass against a policy the fake
// invented. Answering a `bootstrap` is delegated to `respond`, which the
// end-to-end tests wire straight into a real `OverlayLifecycle`.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const EXT_DIR = path.join(__dirname, "..");

function extensionSource(file) {
  return fs.readFileSync(path.join(EXT_DIR, file), "utf8");
}

/** The guard `content_overlay.js` uses. Named here so tests can read it. */
const BOOTSTRAP_GUARD = "__keyVaultOverlayBootstrapV1";

class FakePage {
  /**
   * @param {object} options
   * @param {string} options.url        Document URL. `location.href` reads it.
   * @param {Function} [options.respond] `async (message) => response` for
   *        `chrome.runtime.sendMessage`. Throwing models a dead worker:
   *        `chrome.runtime.lastError` is set for that callback only.
   * @param {boolean} [options.loadSecurity] Set false to model the isolated
   *        world where `overlay_security.js` never ran.
   */
  constructor({ url, respond, loadSecurity = true } = {}) {
    this.url = url;
    this.respond = respond ?? (async () => ({ ok: true, enabled: true, revision: 1 }));
    /** Every payload passed to `chrome.runtime.sendMessage`, deep-copied. */
    this.sent = [];
    /** Live `chrome.runtime.onMessage` listeners. */
    this.listeners = [];

    this._pending = [];
    this._activeLastError = undefined;

    const self = this;
    const chrome = {
      runtime: {
        get lastError() {
          return self._activeLastError;
        },
        sendMessage(message, callback) {
          // The real API structured-clones across the isolated-world boundary,
          // so the worker never sees the page realm's object. Copying here is
          // not a shortcut: without it the receiver would be handed an object
          // whose prototype belongs to the vm realm, and the shape validator
          // rejects exotic prototypes by design.
          const delivered = JSON.parse(JSON.stringify(message));
          self.sent.push(delivered);
          self._pending.push(
            (async () => {
              let response;
              let failure = null;
              try {
                response = await self.respond(delivered);
              } catch (error) {
                failure = error;
              }
              // `lastError` exists only for the duration of the callback, the
              // way the real API scopes it.
              self._activeLastError = failure
                ? { message: String(failure?.message ?? failure) }
                : undefined;
              try {
                if (typeof callback === "function") callback(response);
              } finally {
                self._activeLastError = undefined;
              }
            })()
          );
        },
        onMessage: {
          addListener(fn) {
            self.listeners.push(fn);
          },
          removeListener(fn) {
            const at = self.listeners.indexOf(fn);
            if (at !== -1) self.listeners.splice(at, 1);
          },
          hasListener(fn) {
            return self.listeners.includes(fn);
          },
        },
      },
    };

    this.context = vm.createContext({
      URL,
      crypto,
      Buffer,
      console,
      chrome,
      location: {
        get href() {
          return self.url;
        },
      },
    });

    if (loadSecurity) this.evaluate("overlay_security.js");
  }

  /** Evaluate a shipped extension file in this world, as the browser does. */
  evaluate(file) {
    vm.runInContext(extensionSource(file), this.context, { filename: file });
  }

  /**
   * Run the content-script bootstrap and settle its round trips. Calling this
   * twice is exactly the registered-script + `executeScript` double injection.
   */
  async inject() {
    this.evaluate("content_overlay.js");
    await this.settle();
  }

  /** Await every in-flight `sendMessage` callback, including nested ones. */
  async settle() {
    while (this._pending.length > 0) {
      const inflight = this._pending;
      this._pending = [];
      await Promise.all(inflight);
    }
  }

  /** Deliver a runtime message to every live listener, then settle. */
  async deliver(message) {
    for (const listener of [...this.listeners]) {
      listener(message, { id: "kv" }, () => {});
    }
    await this.settle();
  }

  /** True while the idempotence guard is held. */
  get guarded() {
    return this.context[BOOTSTRAP_GUARD] === true;
  }

  get listenerCount() {
    return this.listeners.length;
  }

  /** Payloads of a given `type`. */
  sentOfType(type) {
    return this.sent.filter((message) => message?.type === type);
  }
}

module.exports = { FakePage, BOOTSTRAP_GUARD };
