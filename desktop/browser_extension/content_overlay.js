// 009 Slice A2 — content-script bootstrap ONLY.
//
// There is no overlay UI in this file yet, and that is deliberate. Slice A4
// (task A028 onward) owns eligible-field detection, the closed-shadow overlay,
// its states, keyboard/ARIA behaviour and explicit fill. What exists here is
// the minimum A018/A020 require: the guarded, idempotent bootstrap handshake
// that must be *approved* before any listener is attached. Until A4 lands the
// approved state does nothing except answer teardown, which is exactly the
// "already-injected instance remains inert" case SR-8 describes.
//
// This file is registered together with `overlay_security.js`
// (see CONTENT_SCRIPT_FILES in overlay_lifecycle.js) so the SR-2 canonical
// origin rule is the shipped one, not a second copy living in the page world.

"use strict";

(() => {
  const security = globalThis.KeyVaultOverlaySecurity;
  if (!security) return;

  // Idempotent startup: the browser can run the registered script and an
  // explicit `executeScript` injection against the same document (that is the
  // normal case right after a grant). The guard lives in the isolated world,
  // is non-secret, and is cleared on teardown so a later valid enable can
  // bootstrap again.
  const GUARD = "__keyVaultOverlayBootstrapV1";
  if (globalThis[GUARD] === true) return;
  globalThis[GUARD] = true;

  const clearGuard = () => {
    globalThis[GUARD] = false;
  };

  // Exact-origin check. A Chromium host-permission pattern cannot express a
  // port, so `https://example.com:8443` gets injected whenever
  // `https://example.com` is enabled. Both this check and the background
  // authorization below keep that other port inert.
  const origin = security.canonicalOriginOrNull(location.href);
  if (origin === null) {
    clearGuard();
    return;
  }

  const bootstrap = {
    channel: security.CHANNEL,
    version: security.MESSAGE_VERSION,
    type: "bootstrap",
    origin,
  };

  chrome.runtime.sendMessage(bootstrap, (response) => {
    // Reading lastError is what suppresses the "unchecked runtime.lastError"
    // console noise when the worker is gone.
    if (chrome.runtime.lastError || response?.ok !== true || response.enabled !== true) {
      clearGuard();
      return;
    }

    // Approved. Listeners are attached only here, never before.
    // ponytail: teardown is the only listener Slice A2 has anything to tear
    // down. A033 extends this handler with the real session teardown.
    const onMessage = (message) => {
      if (message?.channel !== security.CHANNEL || message.type !== "teardown") return;

      // The broadcast deliberately does NOT name the disabled origin. It is
      // delivered to every injected document, so naming it would tell a
      // document on enabled origin A which origin B the user just turned off —
      // a free cross-origin disclosure. The message is only a "revalidate now"
      // nudge; this document re-derives authorization for its OWN exact origin
      // from the background, which is the single authority anyway. Anything
      // other than an explicit approval — including a dead worker — tears this
      // instance down.
      chrome.runtime.sendMessage(bootstrap, (response) => {
        if (
          chrome.runtime.lastError ||
          response?.ok !== true ||
          response.enabled !== true
        ) {
          chrome.runtime.onMessage.removeListener(onMessage);
          clearGuard();
        }
      });
    };
    chrome.runtime.onMessage.addListener(onMessage);
  });
})();
