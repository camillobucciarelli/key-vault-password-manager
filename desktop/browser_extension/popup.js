const hostStatusElement = document.getElementById("hostStatus");
const appStatusElement = document.getElementById("appStatus");
const statusButton = document.getElementById("statusButton");
const queryButton = document.getElementById("queryButton");
const statusElement = document.getElementById("status");
const resultsElement = document.getElementById("results");

let inFlight = false;

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.style.color = isError ? "#b42342" : "#5f4a83";
}

function errorText(response, fallback) {
  if (!response?.error) {
    return fallback;
  }
  if (typeof response.error === "string") {
    return response.error;
  }
  return response.error.message || response.error.code || fallback;
}

async function getActiveTab() {
  return new Promise((resolve) => {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) {
        resolve(null);
        return;
      }
      resolve(tabs[0] || null);
    });
  });
}

async function sendExtensionMessage(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) {
        resolve({
          ok: false,
          error: {
            code: "extension_message_failed",
            message: lastError.message,
          },
        });
        return;
      }
      resolve(response);
    });
  });
}

function activeTabOrigin(tabUrl) {
  try {
    const url = new URL(tabUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    return url.origin;
  } catch (_) {
    return null;
  }
}

function renderMessage(title, body) {
  resultsElement.innerHTML = "";
  const wrapper = document.createElement("article");
  wrapper.className = "result-card";

  const heading = document.createElement("div");
  heading.className = "result-title";
  heading.textContent = title;

  const text = document.createElement("div");
  text.className = "result-body";
  text.textContent = body;

  wrapper.appendChild(heading);
  wrapper.appendChild(text);
  resultsElement.appendChild(wrapper);
}

function updateStatusCards(response) {
  if (response?.ok) {
    hostStatusElement.textContent = "Available";
    const bridgeStatus = response.data?.appBridge?.status || "unavailable";
    appStatusElement.textContent =
      bridgeStatus === "available" ? "Connected" : "Not connected";
    return;
  }

  hostStatusElement.textContent = "Unavailable";
  appStatusElement.textContent = "Not connected";
}

async function checkHostStatus() {
  if (inFlight) {
    return;
  }

  inFlight = true;
  setStatus("Checking native host…");

  try {
    const response = await sendExtensionMessage({
      type: "KEYVAULT_V2_STATUS",
    });
    updateStatusCards(response);
    if (!response?.ok) {
      setStatus(errorText(response, "Native host unavailable."), true);
      renderMessage(
        "Host check failed",
        "Verify the native messaging manifest name, allowed origin and launcher path."
      );
      return;
    }

    setStatus("Native host v2 is reachable.");
    renderMessage(
      "Safe mode active",
      response.data?.message || "v2 is not yet connected to the KeyVault vault."
    );
  } finally {
    inFlight = false;
  }
}

async function queryCurrentSite() {
  if (inFlight) {
    return;
  }

  const tab = await getActiveTab();
  const origin = activeTabOrigin(tab?.url || "");
  if (!origin) {
    setStatus("Open an http(s) page before querying KeyVault.", true);
    return;
  }

  inFlight = true;
  setStatus("Sending v2 query…");

  try {
    const response = await sendExtensionMessage({
      type: "KEYVAULT_V2_QUERY_CREDENTIALS",
      url: origin,
      limit: 5,
    });
    updateStatusCards(response);

    if (!response?.ok) {
      setStatus(errorText(response, "Credential query unavailable."), true);
      renderMessage(
        "Vault bridge not connected",
        "The extension sent only the active site origin to the v2 host. No credentials or vault secrets were requested or returned."
      );
      return;
    }

    setStatus("Query completed.");
    renderMessage(
      "No fill performed",
      "Credential reveal/fill remains disabled until the app bridge milestone."
    );
  } finally {
    inFlight = false;
  }
}

statusButton.addEventListener("click", checkHostStatus);
queryButton.addEventListener("click", queryCurrentSite);

setStatus("Click Check host status to verify the v2 native host.");
renderMessage(
  "Not connected to vault",
  "This MVP intentionally cannot read, reveal, fill or store credentials."
);
