const HOST_NAME = "dev.camillobucciarelli.password_manager_native_host";

async function sendNativeMessage(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, message, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) {
        reject(new Error(lastError.message));
        return;
      }
      resolve(response);
    });
  });
}

async function sendFillToTab(tabId, credential) {
  return new Promise((resolve) => {
    chrome.tabs.sendMessage(
      tabId,
      {
        type: "KEYVAULT_FILL_ACTIVE_CREDENTIAL",
        payload: credential,
      },
      (response) => {
        const lastError = chrome.runtime.lastError;
        if (lastError) {
          resolve({ ok: false, error: lastError.message });
          return;
        }
        resolve(response || { ok: false, error: "No response from page." });
      }
    );
  });
}

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request?.type === "KEYVAULT_FIND_CREDENTIALS") {
    sendNativeMessage({
      type: "findCredentials",
      url: request.url,
      databasePath: request.databasePath,
      masterPassword: request.masterPassword,
      keyFilePath: request.keyFilePath,
      limit: request.limit || 5,
    })
      .then((response) => {
        sendResponse(response || { ok: false, error: "Empty host response." });
      })
      .catch((error) => {
        sendResponse({ ok: false, error: error.message });
      });
    return true;
  }

  if (request?.type === "KEYVAULT_FILL_CREDENTIAL") {
    sendFillToTab(request.tabId, request.credential).then((response) => {
      sendResponse(response);
    });
    return true;
  }

  return false;
});
