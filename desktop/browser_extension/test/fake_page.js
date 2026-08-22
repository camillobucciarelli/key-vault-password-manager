// One isolated world for one document, for driving `content_overlay.js`.
//
// `content_overlay.js` is the only extension file that runs inside a hostile
// page, and it is an IIFE with no exports: there is nothing to `require()`.
// So this harness does what Chromium does — evaluate the shipped
// `overlay_security.js` and the shipped `content_overlay.js`, in that order,
// in one fresh isolated-world global — and then observes what the script is
// allowed to touch: the messages it sends, the listeners it attaches, and
// (since Slice A4) the DOM it renders.
//
// The context models the DOCUMENT and nothing more. It holds no authorization
// logic, so a test can never pass against a policy the fake invented.
// Answering a `bootstrap` is delegated to `respond`, which the end-to-end
// tests wire straight into a real `OverlayLifecycle` / `OverlayRouter`.
//
// FIDELITY RULES (the smoke lessons — model the REAL behaviour, not the
// convenient one):
//
//   * Structured clone. The real `chrome.runtime.sendMessage` structured-
//     clones BOTH directions across the isolated-world boundary. Requests are
//     JSON round-tripped into the Node realm; responses (and delivered
//     runtime messages) are JSON round-tripped INTO THE VM REALM, so the
//     content script receives objects whose prototype is the vm realm's
//     `Object.prototype` — exactly what its own `isPlainObject` requires.
//     Handing it Node-realm objects would make the shipped validators reject
//     everything and the tests would "fix" it by weakening production.
//   * Focus. `mousedown` moves focus as its default action; `preventDefault`
//     on the mousedown — and nothing else — keeps focus where it is. That is
//     the real click-vs-blur hazard the overlay must survive. `focusout`
//     fires at the old element before `focusin` fires at the new one.
//   * Closed shadow root. `host.shadowRoot` reads `null`, exactly like the
//     platform. The harness keeps its own registry of created roots — the
//     same x-ray DevTools has — so the secret-lifetime tests can scan shadow
//     content without pretending the page could.
//   * Visibility of an element follows `display:none`/`[hidden]` up the
//     ancestor chain, which is what `getClientRects().length` reflects in a
//     real layout.
//   * Events bubble target → ancestors → document → window. COMPOSED events
//     (what Chrome stamps on UA-generated mousedown/mouseup/click/keydown/
//     focusin/focusout) cross the shadow boundary and are RETARGETED: outside
//     the shadow tree, `event.target` reads as the shadow HOST, exactly as in
//     Chrome. Non-composed events (the overlay's own `input`/`change`
//     constructor events, page-synthesized events without `composed`) stop at
//     the shadow root. Without this, "a closed overlay captures no page keys"
//     (A037) would be unfalsifiable: no keydown would ever reach a document
//     listener in the first place.
//   * `value` is an accessor on the element PROTOTYPE (like
//     `HTMLInputElement.prototype.value`), so the framework-controlled-input
//     contract — fill through the native prototype setter, bypassing an
//     instance-level override — is testable against the real mechanism.

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

// ---------------------------------------------------------------------------
// Minimal-but-real DOM.
// ---------------------------------------------------------------------------

class FakeEvent {
  constructor(type, init = {}) {
    this.type = type;
    this.bubbles = init.bubbles === true;
    this.cancelable = init.cancelable === true;
    this.composed = init.composed === true;
    // Chrome fidelity: ONLY user-agent-generated events are trusted. A
    // constructor-created event (page-synthetic dispatchEvent, or the
    // overlay's own input/change events) reads isTrusted false. The harness
    // sets `isTrusted: true` exactly where it plays the UA: `click()`,
    // `pressKey()`, and the focus transitions in `_moveFocus`. A test that
    // hand-builds an event models PAGE code by default — the adversarial
    // case — and must opt in to `isTrusted: true` to model a real gesture.
    this.isTrusted = init.isTrusted === true;
    this.key = init.key;
    this.relatedTarget = init.relatedTarget ?? null;
    this.target = null;
    this.defaultPrevented = false;
    this._propagationStopped = false;
  }

  preventDefault() {
    if (this.cancelable) this.defaultPrevented = true;
  }

  stopPropagation() {
    this._propagationStopped = true;
  }
}

class FakeEventTarget {
  constructor() {
    this._listeners = [];
  }

  addEventListener(type, fn, options = {}) {
    const signal = options && options.signal;
    if (signal) {
      if (signal.aborted) return;
      signal.addEventListener("abort", () => this.removeEventListener(type, fn), {
        once: true,
      });
    }
    this._listeners.push({ type, fn });
  }

  removeEventListener(type, fn) {
    const at = this._listeners.findIndex(
      (entry) => entry.type === type && entry.fn === fn
    );
    if (at !== -1) this._listeners.splice(at, 1);
  }

  _invoke(event) {
    for (const entry of [...this._listeners]) {
      if (entry.type === event.type) entry.fn.call(this, event);
    }
  }

  get listenerTypes() {
    return this._listeners.map((entry) => entry.type);
  }
}

class FakeShadowRoot extends FakeEventTarget {
  constructor(host) {
    super();
    this.host = host;
    this.childNodes = [];
    this.parentNode = null; // A shadow root is a tree boundary.
  }

  appendChild(child) {
    if (child.parentNode) child.remove();
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }

  get firstChild() {
    return this.childNodes[0] ?? null;
  }
}

const FOCUSABLE_TAGS = new Set(["INPUT", "BUTTON", "SELECT", "TEXTAREA", "IFRAME"]);

class FakeElement extends FakeEventTarget {
  constructor(doc, tagName) {
    super();
    this._doc = doc;
    this.tagName = String(tagName).toUpperCase();
    this._attributes = new Map();
    this.dataset = {};
    this.style = {};
    this.childNodes = [];
    this.parentNode = null;
    this._text = "";
    this.id = "";
    this._value = "";
    this.type = this.tagName === "INPUT" ? "text" : "";
    this.disabled = false;
    this.readOnly = false;
    this._shadow = null;
    this._shadowMode = null;
    this._rect = null;
  }

  // -- attributes -----------------------------------------------------------

  setAttribute(name, value) {
    this._attributes.set(String(name), String(value));
    if (name === "id") this.id = String(value);
    if (name === "type" && this.tagName === "INPUT") this.type = String(value);
  }

  getAttribute(name) {
    return this._attributes.has(name) ? this._attributes.get(name) : null;
  }

  hasAttribute(name) {
    return this._attributes.has(name);
  }

  removeAttribute(name) {
    this._attributes.delete(name);
  }

  // -- tree -----------------------------------------------------------------

  appendChild(child) {
    if (child.parentNode) child.remove();
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }

  remove() {
    if (this.parentNode) {
      const siblings = this.parentNode.childNodes;
      const at = siblings.indexOf(this);
      if (at !== -1) siblings.splice(at, 1);
    }
    this.parentNode = null;
  }

  get firstChild() {
    return this.childNodes[0] ?? null;
  }

  get isConnected() {
    let node = this;
    while (node) {
      if (node === this._doc) return true;
      node = node.parentNode ?? (node instanceof FakeShadowRoot ? node.host : null);
    }
    return false;
  }

  get textContent() {
    return (
      this._text + this.childNodes.map((child) => child.textContent ?? "").join("")
    );
  }

  set textContent(value) {
    for (const child of this.childNodes) child.parentNode = null;
    this.childNodes = [];
    this._text = String(value);
  }

  // -- forms ----------------------------------------------------------------

  /** Real `HTMLInputElement.form`: the nearest FORM ancestor. */
  get form() {
    let node = this.parentNode;
    while (node) {
      if (node.tagName === "FORM") return node;
      node = node.parentNode ?? null;
    }
    return null;
  }

  /** Real `HTMLFormElement.elements`, as an array of listed descendants. */
  get elements() {
    if (this.tagName !== "FORM") return undefined;
    const found = [];
    const walk = (node) => {
      for (const child of node.childNodes ?? []) {
        if (child instanceof FakeElement) {
          if (FOCUSABLE_TAGS.has(child.tagName)) found.push(child);
          walk(child);
        }
      }
    };
    walk(this);
    return found;
  }

  /** The real method never fires a `submit` event; it still submits. */
  submit() {
    this._doc._page.submitCount += 1;
  }

  requestSubmit() {
    this._doc._page.submitCount += 1;
  }

  // -- layout ---------------------------------------------------------------

  _isRendered() {
    let node = this;
    while (node) {
      if (node instanceof FakeElement) {
        if (node.hasAttribute("hidden") || node.style.display === "none") {
          return false;
        }
      }
      node = node.parentNode ?? (node instanceof FakeShadowRoot ? node.host : null);
    }
    return true;
  }

  getClientRects() {
    return this._isRendered() ? [this.getBoundingClientRect()] : [];
  }

  getBoundingClientRect() {
    return (
      this._rect ?? {
        x: 0,
        y: 0,
        top: 0,
        left: 0,
        bottom: 0,
        right: 0,
        width: 0,
        height: 0,
      }
    );
  }

  // -- value ----------------------------------------------------------------

  /**
   * Accessor on the PROTOTYPE, like `HTMLInputElement.prototype.value`: an
   * instance-level override (what a framework installs) shadows it, and the
   * fill path must reach this one through the prototype descriptor.
   */
  get value() {
    return this._value;
  }

  set value(next) {
    this._value = String(next);
  }

  // -- shadow ---------------------------------------------------------------

  attachShadow({ mode } = {}) {
    if (this._shadow) throw new Error("Shadow root cannot be created twice");
    this._shadow = new FakeShadowRoot(this);
    this._shadowMode = mode;
    this._doc._page._shadowRoots.push(this._shadow);
    return this._shadow;
  }

  /** Closed mode reads null — exactly the platform behaviour (SR-6/A034). */
  get shadowRoot() {
    return this._shadowMode === "open" ? this._shadow : null;
  }

  // -- focus and events -----------------------------------------------------

  get _focusable() {
    return FOCUSABLE_TAGS.has(this.tagName) && this.disabled !== true;
  }

  focus() {
    if (!this._focusable) return;
    this._doc._page._moveFocus(this);
  }

  blur() {
    if (this._doc.activeElement === this) {
      this._doc._page._moveFocus(this._doc.body);
    }
  }

  dispatchEvent(event) {
    this._doc._page._propagate(this, event);
    return !event.defaultPrevented;
  }
}

class FakeDocument extends FakeEventTarget {
  constructor(page) {
    super();
    this._page = page;
    this.documentElement = new FakeElement(this, "html");
    this.documentElement.parentNode = this;
    this.body = new FakeElement(this, "body");
    this.documentElement.appendChild(this.body);
    this.activeElement = this.body;
    this._visibilityState = "visible";
    /**
     * `document.title` is SHARED DOM state: the isolated world and the page
     * write and read the very same value (Chrome shares the DOM between
     * worlds, only the JS globals are isolated), and it further leaks into
     * history and the OS task switcher. It is therefore an observable surface
     * the secret scan must cover — see `captureObservableState`.
     *
     * Element EXPANDOS (`el.someProp = x`) are deliberately NOT such a
     * surface: a plain JS property set in the isolated world lives on that
     * world's wrapper object and is invisible to page code, so the fake does
     * not model them as observable. Attributes/dataset ARE shared DOM and are
     * scanned.
     */
    this.title = "";
  }

  createElement(tagName) {
    return new FakeElement(this, tagName);
  }

  get visibilityState() {
    return this._visibilityState;
  }

  dispatchEvent(event) {
    this._page._propagate(this, event);
    return !event.defaultPrevented;
  }
}

// ---------------------------------------------------------------------------

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
    /** Every shadow root ever attached — the harness x-ray (see header). */
    this._shadowRoots = [];
    /** `console.*` output from the content world, line per call. */
    this.consoleLines = [];
    /** Form submissions of any kind. The overlay contract keeps this at 0. */
    this.submitCount = 0;

    this._pending = [];
    this._activeLastError = undefined;
    this._intervals = new Map();
    this._timeouts = new Map();
    this._timerId = 0;
    this._timeOffsetMs = 0;

    this.document = new FakeDocument(this);
    this.window = new FakeEventTarget();
    // Viewport, controllable per test (`setViewport`). Real defaults.
    this.window.innerWidth = 1024;
    this.window.innerHeight = 768;

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
                if (typeof callback === "function") {
                  // Clone INTO the vm realm — see the fidelity rules above.
                  callback(self._toRealm(response));
                }
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

    const RealDate = Date;
    /** `Date.now()` honours `advanceTime`, everything else is the real Date. */
    class ControlledDate extends RealDate {
      static now() {
        return RealDate.now() + self._timeOffsetMs;
      }
    }

    this.context = vm.createContext({
      URL,
      crypto,
      Buffer,
      console: this._recordingConsole(),
      chrome,
      AbortController,
      Event: FakeEvent,
      Date: ControlledDate,
      document: this.document,
      window: this.window,
      setInterval: (fn, _ms) => {
        this._timerId += 1;
        this._intervals.set(this._timerId, fn);
        return this._timerId;
      },
      clearInterval: (id) => {
        this._intervals.delete(id);
      },
      // Zero-delay task queue, drained deterministically by `settle()` AFTER
      // the current event/response cascade — which is exactly the "after the
      // current pointer task" semantics the deferred-blur teardown relies on.
      setTimeout: (fn, _ms) => {
        this._timerId += 1;
        this._timeouts.set(this._timerId, fn);
        return this._timerId;
      },
      clearTimeout: (id) => {
        this._timeouts.delete(id);
      },
      location: {
        get href() {
          return self.url;
        },
      },
    });

    this._vmParse = vm.runInContext("(s) => JSON.parse(s)", this.context);

    if (loadSecurity) this.evaluate("overlay_security.js");
  }

  _recordingConsole() {
    const record = (...args) => {
      this.consoleLines.push(args.map(String).join(" "));
    };
    return { log: record, info: record, warn: record, error: record, debug: record };
  }

  /** JSON round trip into the vm realm; `undefined` stays `undefined`. */
  _toRealm(value) {
    if (value === undefined) return undefined;
    return this._vmParse(JSON.stringify(value));
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

  /**
   * Await every in-flight `sendMessage` callback (including nested ones),
   * then drain due zero-delay timeouts, honouring `clearTimeout` calls made
   * by earlier callbacks in the same drain.
   */
  async settle() {
    for (;;) {
      while (this._pending.length > 0) {
        const inflight = this._pending;
        this._pending = [];
        await Promise.all(inflight);
      }
      if (this._timeouts.size === 0) return;
      const next = this._timeouts.entries().next().value;
      this._timeouts.delete(next[0]);
      next[1]();
    }
  }

  /**
   * Run every due zero-delay timeout WITHOUT awaiting in-flight sendMessage
   * responses — the observation point between "scheduled" and "announced"
   * that the M13 live-region tests (and any gated-response test) need, since
   * `settle()` would block on a deliberately gated response.
   */
  flushTimers() {
    while (this._timeouts.size > 0) {
      const next = this._timeouts.entries().next().value;
      this._timeouts.delete(next[0]);
      next[1]();
    }
  }

  /** Deliver a runtime message to every live listener, then settle. */
  async deliver(message) {
    const delivered = this._toRealm(
      message === undefined ? undefined : JSON.parse(JSON.stringify(message ?? null))
    );
    for (const listener of [...this.listeners]) {
      listener(delivered, { id: "kv" }, () => {});
    }
    await this.settle();
  }

  // -- DOM driving ----------------------------------------------------------

  /**
   * `focusout` at the old element, then `focusin` at the new one.
   *
   * IFRAME FIDELITY (M7 — 6th fake/real divergence, measured live in real
   * Chrome): focus entering a child browsing context delivers NO `focusin`
   * to the parent document. The parent observes only (a) `focusout`/blur at
   * the previously focused element with a null relatedTarget, (b) a window
   * `blur` event, and (c) `document.activeElement` reading the iframe
   * ELEMENT. The old fake delivered `focusin` at the iframe element — the
   * convenient behaviour, not the real one — which made the cross-origin
   * hint pass against a mechanism Chrome never fires.
   */
  _moveFocus(next) {
    const prev = this.document.activeElement;
    if (prev === next) return;
    this.document.activeElement = next;
    const intoFrame = next != null && next.tagName === "IFRAME";
    if (prev && prev !== this.document.body) {
      this._propagate(
        prev,
        new FakeEvent("focusout", {
          bubbles: true,
          composed: true,
          isTrusted: true,
          relatedTarget: intoFrame ? null : next,
        })
      );
    }
    if (intoFrame) {
      // Parent loses focus to the child browsing context: window blur, no
      // focusin anywhere in this document.
      this.window._invoke(new FakeEvent("blur", { bubbles: false }));
      return;
    }
    if (next && next !== this.document.body) {
      this._propagate(
        next,
        new FakeEvent("focusin", {
          bubbles: true,
          composed: true,
          isTrusted: true,
          relatedTarget: prev,
        })
      );
    }
  }

  /**
   * target → ancestors → document → window. A composed event crosses a
   * shadow root and is RETARGETED to the host for every node outside the
   * shadow tree (Chrome semantics); a non-composed event stops at the root.
   */
  _propagate(target, event) {
    if (event.target === null) event.target = target;
    if (event.type === "submit") this.submitCount += 1;
    let node = target;
    while (node) {
      node._invoke(event);
      if (!event.bubbles || event._propagationStopped) return;
      if (node === this.window) return;
      if (node === this.document) {
        node = this.window;
        continue;
      }
      if (node instanceof FakeShadowRoot) {
        if (!event.composed) return;
        event.target = node.host; // retargeting at the boundary
        node = node.host;
        continue;
      }
      node = node.parentNode ?? null;
    }
  }

  /** Focus an element the way a user click/tab would, then settle. */
  async focus(el) {
    el.focus();
    await this.settle();
  }

  /**
   * A real pointer press: `mousedown` (whose DEFAULT ACTION moves focus,
   * unless prevented), then `click`. This is what makes the click-vs-blur
   * hazard reproducible instead of assumed away.
   */
  async click(el) {
    const mousedown = new FakeEvent("mousedown", {
      bubbles: true,
      cancelable: true,
      composed: true,
      isTrusted: true,
    });
    this._propagate(el, mousedown);
    if (!mousedown.defaultPrevented) {
      if (el._focusable) el.focus();
      else this._moveFocus(this.document.body);
    }
    this._propagate(
      el,
      new FakeEvent("mouseup", {
        bubbles: true,
        cancelable: true,
        composed: true,
        isTrusted: true,
      })
    );
    this._propagate(
      el,
      new FakeEvent("click", {
        bubbles: true,
        cancelable: true,
        composed: true,
        isTrusted: true,
      })
    );
    await this.settle();
  }

  /**
   * Key press delivered at the focused element, bubbling (composed, like a
   * real UA keydown) to the document. Returns the event so callers can assert
   * on `defaultPrevented`/propagation — the A037 "prevent ONLY the fill
   * action" contract.
   */
  async pressKey(key) {
    const target = this.document.activeElement ?? this.document.body;
    const event = new FakeEvent("keydown", {
      bubbles: true,
      cancelable: true,
      composed: true,
      isTrusted: true,
      key,
    });
    this._propagate(target, event);
    await this.settle();
    return event;
  }

  /** Resize the viewport and fire `resize` at the window, then settle. */
  async setViewport(width, height) {
    this.window.innerWidth = width;
    this.window.innerHeight = height;
    this.window._invoke(new FakeEvent("resize", { bubbles: false }));
    await this.settle();
  }

  /** Fire a scroll at the document (capture-phase listeners see it), settle. */
  async fireScroll() {
    this._propagate(this.document, new FakeEvent("scroll", { bubbles: false }));
    await this.settle();
  }

  async setVisibility(state) {
    this.document._visibilityState = state;
    this._propagate(this.document, new FakeEvent("visibilitychange", { bubbles: false }));
    await this.settle();
  }

  async firePagehide() {
    this.window._invoke(new FakeEvent("pagehide", { bubbles: false }));
    await this.settle();
  }

  /** Shift the content world's `Date.now()` without waiting. */
  advanceTime(ms) {
    this._timeOffsetMs += ms;
  }

  /** Run every live interval callback once (the overlay watchdog). */
  async tick() {
    for (const fn of [...this._intervals.values()]) fn();
    await this.settle();
  }

  // -- observation ----------------------------------------------------------

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

  /** Every element in the page tree AND in every shadow root ever created. */
  allElements() {
    const found = new Set();
    const walk = (node) => {
      for (const child of node.childNodes ?? []) {
        if (child instanceof FakeElement && !found.has(child)) {
          found.add(child);
          if (child._shadow) walk(child._shadow);
          walk(child);
        }
      }
    };
    found.add(this.document.documentElement);
    walk(this.document.documentElement);
    // Detached hosts too: a removed overlay must still be scannable.
    for (const root of this._shadowRoots) walk(root);
    return [...found];
  }

  /** The overlay hosts currently attached to the page tree. */
  overlayHosts() {
    return this._shadowRoots
      .map((root) => root.host)
      .filter((host) => host.isConnected);
  }

  /**
   * A032 — every observable surface EXCEPT input values, as one string:
   * tag names, ids, attributes, dataset, inline style, text (page tree and
   * all shadow roots, attached or not), the content world's globals, and its
   * console output. Input values are excluded because the filled input is
   * the single allowed secret sink; callers assert on it separately via
   * `inputValues()`.
   */
  captureObservableState() {
    const chunks = [];
    // Shared-DOM document state that the generic walks below cannot reach:
    // `document` itself is cyclic (its JSON.stringify in the globals loop
    // throws and is skipped), so its scannable string leaves are named here
    // explicitly. `title` is the one a content script can write.
    chunks.push(this.document.title);
    for (const el of this.allElements()) {
      chunks.push(el.tagName, el.id, el._text);
      for (const [name, value] of el._attributes) chunks.push(name, value);
      for (const [name, value] of Object.entries(el.dataset)) {
        chunks.push(name, String(value));
      }
      for (const [name, value] of Object.entries(el.style)) {
        chunks.push(name, String(value));
      }
    }
    for (const key of Object.keys(this.context)) {
      chunks.push(key);
      const value = this.context[key];
      if (["string", "number", "boolean"].includes(typeof value)) {
        chunks.push(String(value));
      } else {
        try {
          const json = JSON.stringify(value);
          if (typeof json === "string") chunks.push(json);
        } catch (_) {
          // Cyclic/exotic global (document, chrome): structure is not
          // serializable, but its own enumerable string leaves are what a
          // secret would live in, and those are covered by the DOM walk.
        }
      }
    }
    chunks.push(...this.consoleLines);
    return chunks.join("\n");
  }

  /**
   * A040 — every observable surface of the LIGHT DOM ONLY: the page tree
   * (tags, ids, attributes, dataset, inline style, text) with every shadow
   * root EXCLUDED, plus `document.title`. This is exactly what page code can
   * read without shadow access; the extended A032 scan asserts that entry
   * TITLES (not only secrets) never appear here — the light fallback listbox
   * may carry indices and static labels only.
   */
  captureLightDomState() {
    const chunks = [this.document.title];
    const walk = (node) => {
      for (const child of node.childNodes ?? []) {
        if (child instanceof FakeElement) {
          chunks.push(child.tagName, child.id, child._text);
          for (const [name, value] of child._attributes) chunks.push(name, value);
          for (const [name, value] of Object.entries(child.dataset)) {
            chunks.push(name, String(value));
          }
          for (const [name, value] of Object.entries(child.style)) {
            chunks.push(name, String(value));
          }
          walk(child); // NEVER descends into child._shadow — light DOM only.
        }
      }
    };
    walk(this.document.documentElement);
    return chunks.join("\n");
  }

  /** Values of every input in the page tree. */
  inputValues() {
    return this.allElements()
      .filter((el) => el.tagName === "INPUT")
      .map((el) => el.value);
  }
}

module.exports = { FakePage, FakeEvent, BOOTSTRAP_GUARD };
