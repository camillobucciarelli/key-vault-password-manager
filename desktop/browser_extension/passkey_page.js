// spec 023 T503 — MAIN-world wrapper for `navigator.credentials.get`.
//
// This file runs in the PAGE's world, which is the only world where patching
// `navigator.credentials` is visible to the site. That is also why it holds
// no secret, no token and no policy: everything here is readable and
// spoofable by the page. It is a courier between the site's promise and the
// isolated world, and nothing more.
//
// The security rules it does NOT enforce, deliberately, because the page
// could defeat them here: which origin is asking (the worker derives that
// from `sender.url`), which relying party a passkey may answer for (the app
// checks rpId against that origin), and whether the user agreed (the app
// asks them). A page that forges a message to the isolated world gains
// nothing it could not get by calling `navigator.credentials.get` honestly.
(() => {
  "use strict";

  // One wrapper per world. A second injection — a re-registration, an
  // `executeScript` against the same document — must not wrap the wrapper,
  // or each layer would add another round trip and the innermost would call
  // a `get` that is itself already wrapped.
  if (window.__keyvaultPasskeyWrapped) return;
  const credentials = navigator.credentials;
  if (!credentials || typeof credentials.get !== "function") return;
  window.__keyvaultPasskeyWrapped = true;

  const CHANNEL = "keyvault-passkey";
  const originalGet = credentials.get.bind(credentials);

  // Correlates one request with its answer. Not a secret — the page can read
  // it — just a way to keep two concurrent sign-ins apart.
  let nextRequestId = 1;
  const pending = new Map();

  window.addEventListener("message", (event) => {
    // Only this frame talks to its own bridge. A message from an iframe or
    // an opener is not an answer to anything asked here.
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.channel !== CHANNEL || data.kind !== "passkey-get-result") {
      return;
    }
    const resolve = pending.get(data.requestId);
    if (!resolve) return;
    pending.delete(data.requestId);
    resolve(data);
  });

  function base64UrlFromBuffer(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function bufferFromBase64Url(value) {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/");
    const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes.buffer;
  }

  function askExtension(request) {
    return new Promise((resolve) => {
      const requestId = nextRequestId++;
      pending.set(requestId, resolve);
      window.postMessage(
        { channel: CHANNEL, kind: "passkey-get", requestId, ...request },
        window.location.origin
      );
    });
  }

  /**
   * The shape a relying party's own JS reads off the resolved promise.
   *
   * Not a real `PublicKeyCredential`: the constructor is not callable from
   * here, and a site that checks `instanceof` will reject this. That is the
   * documented limit of the desktop path (research R12) — sites that only
   * read the fields, which is the common case, work.
   */
  function toCredential(result) {
    const rawId = bufferFromBase64Url(result.credentialId);
    return {
      id: result.credentialId,
      rawId,
      type: "public-key",
      authenticatorAttachment: "cross-platform",
      response: {
        clientDataJSON: bufferFromBase64Url(result.clientDataJSON),
        authenticatorData: bufferFromBase64Url(result.authenticatorData),
        signature: bufferFromBase64Url(result.signature),
        userHandle: result.userHandle ? bufferFromBase64Url(result.userHandle) : null,
      },
      getClientExtensionResults: () => ({}),
    };
  }

  credentials.get = async function get(options) {
    const publicKey = options?.publicKey;
    // Anything that is not a WebAuthn sign-in — a federated or password
    // credential, a `create`-shaped call — goes straight to the browser.
    if (!publicKey || !publicKey.challenge) {
      return originalGet(options);
    }

    // An abort the site already fired, or fires while we are asking, belongs
    // to the site's own promise: pass it through untouched rather than
    // resolving with a credential nobody is waiting for any more.
    if (options?.signal?.aborted) return originalGet(options);

    let request;
    try {
      request = {
        rpId: publicKey.rpId || window.location.hostname,
        challenge: base64UrlFromBuffer(publicKey.challenge),
        allowCredentials: Array.isArray(publicKey.allowCredentials)
          ? publicKey.allowCredentials
              .map((entry) => (entry?.id ? base64UrlFromBuffer(entry.id) : null))
              .filter((value) => typeof value === "string")
          : [],
      };
    } catch {
      // A challenge that is not a buffer is the site's bug, not ours: let
      // the browser raise the error it would have raised anyway.
      return originalGet(options);
    }

    const result = await askExtension(request);
    // Every refusal — no passkey here, the user declined, the app is locked,
    // the extension never answered — falls through to the browser's own
    // authenticator. KeyVault having nothing to offer must never stop a
    // security key or a platform passkey from working.
    if (!result || result.ok !== true) {
      return originalGet(options);
    }
    try {
      return toCredential(result);
    } catch {
      return originalGet(options);
    }
  };
})();
