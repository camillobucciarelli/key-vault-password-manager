const databasePathInput = document.getElementById("databasePath");
const masterPasswordInput = document.getElementById("masterPassword");
const keyFilePathInput = document.getElementById("keyFilePath");
const limitInput = document.getElementById("limit");
const autoRefreshInput = document.getElementById("autoRefresh");
const findButton = document.getElementById("findButton");
const statusElement = document.getElementById("status");
const resultsElement = document.getElementById("results");

let lastTabUrl = "";
let inFlight = false;

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.style.color = isError ? "#b42342" : "#5f4a83";
}

async function getActiveTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  return tabs[0];
}

async function saveSettings() {
  await chrome.storage.local.set({
    databasePath: databasePathInput.value.trim(),
    keyFilePath: keyFilePathInput.value.trim(),
    limit: Number.parseInt(limitInput.value, 10) || 5,
    autoRefresh: autoRefreshInput.checked,
  });
}

async function loadSettings() {
  const settings = await chrome.storage.local.get([
    "databasePath",
    "keyFilePath",
    "limit",
    "autoRefresh",
  ]);

  databasePathInput.value = settings.databasePath || "";
  keyFilePathInput.value = settings.keyFilePath || "";
  limitInput.value = String(settings.limit || 5);
  autoRefreshInput.checked = settings.autoRefresh !== false;
}

function renderResults(tabId, credentials) {
  resultsElement.innerHTML = "";
  if (!credentials.length) {
    resultsElement.textContent = "No matching credentials found.";
    return;
  }

  for (const credential of credentials) {
    const wrapper = document.createElement("article");
    wrapper.className = "credential";

    const title = document.createElement("div");
    title.className = "credential-title";
    title.textContent = credential.title || "Saved credential";

    const subtitle = document.createElement("div");
    subtitle.className = "credential-subtitle";
    subtitle.textContent = credential.username || "(no username)";

    const button = document.createElement("button");
    button.textContent = "Fill this account";
    button.addEventListener("click", async () => {
      const response = await chrome.runtime.sendMessage({
        type: "KEYVAULT_FILL_CREDENTIAL",
        tabId,
        credential,
      });

      if (!response?.ok) {
        setStatus(response?.error || "Failed to fill page.", true);
        return;
      }

      setStatus("Credential filled.");
    });

    wrapper.appendChild(title);
    wrapper.appendChild(subtitle);
    wrapper.appendChild(button);
    resultsElement.appendChild(wrapper);
  }
}

async function findCredentials({ force = false } = {}) {
  if (inFlight) {
    return;
  }

  const databasePath = databasePathInput.value.trim();
  const masterPassword = masterPasswordInput.value;
  const keyFilePath = keyFilePathInput.value.trim();
  const limit = Number.parseInt(limitInput.value, 10) || 5;

  const tab = await getActiveTab();
  if (!tab?.id || !tab.url) {
    setStatus("No active tab found.", true);
    return;
  }

  if (!force && autoRefreshInput.checked && tab.url === lastTabUrl) {
    return;
  }

  inFlight = true;
  setStatus("Searching...");
  resultsElement.innerHTML = "";

  await saveSettings();

  try {
    const response = await chrome.runtime.sendMessage({
      type: "KEYVAULT_FIND_CREDENTIALS",
      url: tab.url,
      databasePath,
      masterPassword,
      keyFilePath,
      limit,
    });

    if (!response?.ok) {
      const error = response?.details
        ? `${response.error} (${response.details})`
        : response?.error || "Failed to read credentials.";
      setStatus(error, true);
      return;
    }

    const credentials = Array.isArray(response.credentials)
      ? response.credentials
      : [];
    setStatus(`Found ${credentials.length} credential(s).`);
    renderResults(tab.id, credentials);
    lastTabUrl = tab.url;
  } finally {
    inFlight = false;
  }
}

let refreshTimer = null;

function scheduleAutoRefresh() {
  if (!autoRefreshInput.checked) {
    return;
  }

  if (refreshTimer) {
    clearTimeout(refreshTimer);
  }

  refreshTimer = setTimeout(() => {
    findCredentials();
  }, 220);
}

findButton.addEventListener("click", () => {
  findCredentials({ force: true });
});

autoRefreshInput.addEventListener("change", () => {
  saveSettings();
  if (autoRefreshInput.checked) {
    findCredentials({ force: true });
  }
});

chrome.tabs.onActivated.addListener(() => {
  scheduleAutoRefresh();
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status !== "complete") {
    return;
  }

  getActiveTab().then((activeTab) => {
    if (activeTab?.id === tabId) {
      scheduleAutoRefresh();
    }
  });
});

window.addEventListener("focus", () => {
  scheduleAutoRefresh();
});

loadSettings().then(() => {
  findCredentials({ force: true });
});
