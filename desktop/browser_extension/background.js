const HOST_NAME = "dev.camillobucciarelli.keyvault_native_host";
const PROTOCOL_VERSION = 2;
const NATIVE_TIMEOUT_MS = 3000;

function createRequestId() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  const random = new Uint32Array(4);
  globalThis.crypto.getRandomValues(random);
  return Array.from(random, (part) => part.toString(16).padStart(8, "0")).join(
    "-"
  );
}

function normalizeError(error) {
  if (!error) {
    return { code: "unknown_error", message: "Unknown native host error." };
  }
  if (typeof error === "string") {
    return { code: "native_error", message: error };
  }
  return {
    code: error.code || "native_error",
    message: error.message || "Native host request failed.",
  };
}

function withTimeout(promise, timeoutMs) {
  let timeoutId;
  const timeout = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      reject(new Error("Native host response timed out."));
    }, timeoutMs);
  });

  return Promise.race([promise, timeout]).finally(() => clearTimeout(timeoutId));
}

async function sendNativeV2(type, payload = {}) {
  const request = {
    version: PROTOCOL_VERSION,
    id: createRequestId(),
    type,
    payload,
  };

  const nativeCall = new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, request, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) {
        reject(new Error(lastError.message));
        return;
      }
      if (!response) {
        reject(new Error("Native host returned an empty response."));
        return;
      }
      resolve(response);
    });
  });

  const response = await withTimeout(nativeCall, NATIVE_TIMEOUT_MS);
  if (response.version !== PROTOCOL_VERSION) {
    return {
      version: PROTOCOL_VERSION,
      type,
      ok: false,
      error: {
        code: "unsupported_version",
        message: "Native host returned an unsupported protocol version.",
      },
    };
  }
  if (response.id && response.id !== request.id) {
    return {
      version: PROTOCOL_VERSION,
      type,
      ok: false,
      error: {
        code: "invalid_response",
        message: "Native host response did not match the request.",
      },
    };
  }
  return response;
}

function requireExtensionSender(sender) {
  return sender?.id === chrome.runtime.id && !sender.tab;
}

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (!requireExtensionSender(sender)) {
    sendResponse({
      ok: false,
      error: { code: "forbidden", message: "Unsupported message sender." },
    });
    return false;
  }

  if (request?.type === "KEYVAULT_V2_STATUS") {
    sendNativeV2("status")
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          version: PROTOCOL_VERSION,
          type: "status",
          ok: false,
          error: normalizeError(error),
        });
      });
    return true;
  }

  if (request?.type === "KEYVAULT_V2_QUERY_CREDENTIALS") {
    sendNativeV2("queryCredentials", {
      url: request.url,
      title: request.title,
      limit: Number.isInteger(request.limit) ? request.limit : 5,
    })
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          version: PROTOCOL_VERSION,
          type: "queryCredentials",
          ok: false,
          error: normalizeError(error),
        });
      });
    return true;
  }

  if (request?.type === "KEYVAULT_V2_SEARCH_CREDENTIALS") {
    sendNativeV2("searchCredentials", {
      query: typeof request.query === "string" ? request.query : "",
      url: request.url,
      limit: Number.isInteger(request.limit) ? request.limit : 25,
    })
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          version: PROTOCOL_VERSION,
          type: "searchCredentials",
          ok: false,
          error: normalizeError(error),
        });
      });
    return true;
  }

  if (request?.type === "KEYVAULT_V2_CREATE_PENDING_ASSOCIATION") {
    sendNativeV2("createPendingAssociation", {
      entryId: request.entryId,
      url: request.url,
    })
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          version: PROTOCOL_VERSION,
          type: "createPendingAssociation",
          ok: false,
          error: normalizeError(error),
        });
      });
    return true;
  }

  if (request?.type === "KEYVAULT_V2_REVEAL_FOR_FILL") {
    sendNativeV2("revealForFill", {
      entryId: request.entryId,
      origin: request.origin,
    })
      .then(sendResponse)
      .catch((error) => {
        sendResponse({
          version: PROTOCOL_VERSION,
          type: "revealForFill",
          ok: false,
          error: normalizeError(error),
        });
      });
    return true;
  }

  return false;
});
