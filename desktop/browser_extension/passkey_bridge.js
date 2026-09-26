// spec 023 T503 — isolated-world relay between the page's wrapped
// `navigator.credentials.get` and the service worker.
//
// This world can talk to the worker; the page's world cannot. Everything it
// receives over `postMessage` comes from the page and is treated as such:
// shapes and sizes are checked here, and every decision that matters — which
// origin is asking, which passkey may answer, whether the user agreed — is
// made by the worker and the app from `sender.url`, never from what this
// message claims.
(() => {
  "use strict";

  if (window.__keyvaultPasskeyBridgeInstalled) return;
  window.__keyvaultPasskeyBridgeInstalled = true;

  const CHANNEL = "keyvault-passkey";
  const MAX_RP_ID = 253;
  const MAX_CHALLENGE = 2048;
  const MAX_CREDENTIAL_ID = 512;
  const MAX_ALLOW_CREDENTIALS = 32;

  function refuse(requestId) {
    window.postMessage(
      { channel: CHANNEL, kind: "passkey-get-result", requestId, ok: false },
      window.location.origin
    );
  }

  function boundedString(value, maxLength) {
    return typeof value === "string" && value.length > 0 && value.length <= maxLength
      ? value
      : null;
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.channel !== CHANNEL || data.kind !== "passkey-get") return;
    const requestId = data.requestId;
    if (typeof requestId !== "number") return;

    const rpId = boundedString(data.rpId, MAX_RP_ID);
    const challenge = boundedString(data.challenge, MAX_CHALLENGE);
    if (!rpId || !challenge) {
      refuse(requestId);
      return;
    }
    const allowCredentials = Array.isArray(data.allowCredentials)
      ? data.allowCredentials
          .slice(0, MAX_ALLOW_CREDENTIALS)
          .map((value) => boundedString(value, MAX_CREDENTIAL_ID))
          .filter((value) => value !== null)
      : [];

    // No origin is sent: the worker reads it from `sender.url`, so a page
    // cannot ask for a passkey belonging to another site by claiming to be
    // it. The same reason `_requestMatches` forwards the authority rather
    // than the claim (A024).
    chrome.runtime.sendMessage(
      { type: "passkeyGet", rpId, challenge, allowCredentials },
      (response) => {
        // A worker that never answered, a disconnected extension, a refusal:
        // all one thing to the page world, which falls back to the browser.
        if (chrome.runtime.lastError || response?.ok !== true) {
          refuse(requestId);
          return;
        }
        window.postMessage(
          {
            channel: CHANNEL,
            kind: "passkey-get-result",
            requestId,
            ok: true,
            credentialId: response.credentialId,
            authenticatorData: response.authenticatorData,
            signature: response.signature,
            clientDataJSON: response.clientDataJSON,
            userHandle: response.userHandle ?? null,
          },
          window.location.origin
        );
      }
    );
  });
})();
