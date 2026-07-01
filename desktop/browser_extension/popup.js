const hostStatusElement = document.getElementById("hostStatus");
const appStatusElement = document.getElementById("appStatus");
const statusButton = document.getElementById("statusButton");
const queryButton = document.getElementById("queryButton");
const searchButton = document.getElementById("searchButton");
const searchInput = document.getElementById("searchInput");
const statusElement = document.getElementById("status");
const resultsElement = document.getElementById("results");

let inFlight = false;
let currentTargetOrigin = null;

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

function fillCredentialInPage(username, password) {
  function isVisible(element) {
    const style = globalThis.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return (
      style.visibility !== "hidden" &&
      style.display !== "none" &&
      rect.width > 0 &&
      rect.height > 0
    );
  }

  function canFillInput(element) {
    return (
      element instanceof HTMLInputElement &&
      !element.disabled &&
      !element.readOnly &&
      isVisible(element)
    );
  }

  function setNativeValue(element, value) {
    const prototype = Object.getPrototypeOf(element);
    const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
    if (descriptor?.set) {
      descriptor.set.call(element, value);
    } else {
      element.value = value;
    }
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function textScore(element, passwordField) {
    const haystack = [
      element.autocomplete,
      element.name,
      element.id,
      element.getAttribute("aria-label"),
      element.placeholder,
    ]
      .join(" ")
      .toLowerCase();
    let score = 0;
    if (/username|user-name|email|e-mail|login|account/.test(haystack)) {
      score += 20;
    }
    if (element.type === "email") {
      score += 10;
    }
    if (element.compareDocumentPosition(passwordField) & Node.DOCUMENT_POSITION_FOLLOWING) {
      score += 4;
    }
    return score;
  }

  const passwordFields = Array.from(document.querySelectorAll('input[type="password"]'))
    .filter(canFillInput);
  if (passwordFields.length === 0) {
    return { filled: false, reason: "no_password_field" };
  }

  const passwordField = passwordFields[0];
  const scope = passwordField.form || document;
  const usernameCandidates = Array.from(
    scope.querySelectorAll('input:not([type]), input[type="text"], input[type="email"], input[type="search"], input[type="tel"], input[type="url"]')
  ).filter((element) => canFillInput(element) && element !== passwordField);
  usernameCandidates.sort(
    (left, right) => textScore(right, passwordField) - textScore(left, passwordField)
  );

  const usernameField = usernameCandidates[0] || null;
  if (usernameField && username) {
    setNativeValue(usernameField, username);
  }
  setNativeValue(passwordField, password);
  passwordField.focus();
  return {
    filled: true,
    usernameFilled: Boolean(usernameField && username),
    passwordFilled: true,
  };
}

async function executeFill(tabId, username, password) {
  return new Promise((resolve) => {
    chrome.scripting.executeScript(
      {
        target: { tabId },
        func: fillCredentialInPage,
        args: [username, password],
      },
      (results) => {
        const lastError = chrome.runtime.lastError;
        if (lastError) {
          resolve({ ok: false, error: lastError.message });
          return;
        }
        resolve({ ok: true, result: results?.[0]?.result || null });
      }
    );
  });
}

function renderMessage(title, body) {
  resultsElement.textContent = "";
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
      bridgeStatus === "metadata_cache_available"
        ? "Metadata ready"
        : bridgeStatus === "available"
          ? "Connected"
          : "Not connected";
    return;
  }

  hostStatusElement.textContent = "Unavailable";
  appStatusElement.textContent = "Not connected";
}

function resultTitle(result) {
  const title = (result.title || "").trim();
  const service = (result.displayService || "").trim();
  if (title && service) {
    return `${title} · ${service}`;
  }
  return title || service || "Untitled entry";
}

function resultBody(result, label) {
  return label;
}

function renderResultCard(result, label, canCreatePending, canFill = false) {
  const wrapper = document.createElement("article");
  wrapper.className = "result-card";

  const badge = document.createElement("span");
  badge.className = `badge ${result.matchType === "strong" ? "badge-strong" : "badge-possible"}`;
  badge.textContent = label;

  const heading = document.createElement("div");
  heading.className = "result-title";
  heading.textContent = resultTitle(result);

  const text = document.createElement("div");
  text.className = "result-body";
  text.textContent = resultBody(result, label);

  wrapper.appendChild(badge);
  wrapper.appendChild(heading);
  wrapper.appendChild(text);

  if (canFill) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Fill on this page";
    button.addEventListener("click", () => fillCredential(result.entryId));
    wrapper.appendChild(button);
  }

  if (canCreatePending) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "secondary-button";
    button.textContent = "Request link in app";
    button.addEventListener("click", () => createPendingAssociation(result.entryId));
    wrapper.appendChild(button);
  }

  return wrapper;
}

function renderQueryResults(response) {
  resultsElement.textContent = "";
  const strong = response.data?.strongMatches || [];
  const possible = response.data?.possibleMatches || [];
  const fillAvailable = response.data?.fillAvailable === true;

  if (strong.length === 0 && possible.length === 0) {
    renderMessage(
      "No site match",
      "Use global search below. Selecting a result creates a pending association for app confirmation."
    );
    return;
  }

  for (const result of strong) {
    resultsElement.appendChild(
      renderResultCard(result, "Strong exact host match", false, fillAvailable)
    );
  }
  for (const result of possible) {
    resultsElement.appendChild(renderResultCard(result, "Possible match", true));
  }
}

function renderSearchResults(response) {
  resultsElement.textContent = "";
  const results = response.data?.results || [];
  if (results.length === 0) {
    renderMessage("No metadata result", "Try another search term.");
    return;
  }
  for (const result of results) {
    resultsElement.appendChild(renderResultCard(result, "Manual search result", Boolean(currentTargetOrigin)));
  }
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
      "Desktop metadata mode",
      response.data?.message || "Unlock KeyVault to publish browser metadata."
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
  currentTargetOrigin = origin;
  if (!origin) {
    setStatus("Open an http(s) page before querying KeyVault.", true);
    return;
  }

  inFlight = true;
  setStatus("Searching metadata for current site…");

  try {
    const response = await sendExtensionMessage({
      type: "KEYVAULT_V2_QUERY_CREDENTIALS",
      url: origin,
      title: tab?.title || "",
      limit: 10,
    });
    updateStatusCards(response);

    if (!response?.ok) {
      setStatus(errorText(response, "Credential metadata query unavailable."), true);
      renderMessage(
        "Vault metadata unavailable",
        "Open and unlock KeyVault desktop. The extension sends only the active site origin and page title."
      );
      return;
    }

    setStatus("Metadata query completed. No password was requested.");
    renderQueryResults(response);
  } finally {
    inFlight = false;
  }
}

async function searchMetadata() {
  if (inFlight) {
    return;
  }

  const tab = await getActiveTab();
  currentTargetOrigin = activeTabOrigin(tab?.url || "");
  inFlight = true;
  setStatus("Searching KeyVault metadata…");

  try {
    const response = await sendExtensionMessage({
      type: "KEYVAULT_V2_SEARCH_CREDENTIALS",
      query: searchInput.value || "",
      url: currentTargetOrigin,
      limit: 25,
    });
    updateStatusCards(response);
    if (!response?.ok) {
      setStatus(errorText(response, "Global metadata search unavailable."), true);
      renderMessage(
        "Search unavailable",
        "Open and unlock KeyVault desktop, then retry. No credentials were requested."
      );
      return;
    }

    setStatus("Search completed. Results are metadata only.");
    renderSearchResults(response);
  } finally {
    inFlight = false;
  }
}

async function createPendingAssociation(entryId) {
  if (!currentTargetOrigin) {
    setStatus("Open an http(s) page before creating an association.", true);
    return;
  }
  if (inFlight) {
    return;
  }

  inFlight = true;
  setStatus("Creating pending association…");

  try {
    const response = await sendExtensionMessage({
      type: "KEYVAULT_V2_CREATE_PENDING_ASSOCIATION",
      entryId,
      url: currentTargetOrigin,
    });
    updateStatusCards(response);
    if (!response?.ok) {
      setStatus(errorText(response, "Unable to create pending association."), true);
      return;
    }
    setStatus("Pending association saved. Confirm it in KeyVault desktop.");
    renderMessage(
      "Association pending",
      "KeyVault will update the vault only after you confirm in the desktop app. No password was stored in the browser."
    );
  } finally {
    inFlight = false;
  }
}

async function fillCredential(entryId) {
  if (inFlight) {
    return;
  }

  const tab = await getActiveTab();
  const origin = activeTabOrigin(tab?.url || "");
  if (!tab?.id || !origin) {
    setStatus("Open an http(s) page before filling.", true);
    return;
  }

  inFlight = true;
  setStatus("Requesting one-shot fill…");

  let username = null;
  let password = null;
  let response = null;
  try {
    response = await sendExtensionMessage({
      type: "KEYVAULT_V2_REVEAL_FOR_FILL",
      entryId,
      origin,
    });
    if (!response?.ok) {
      setStatus(errorText(response, "Unable to reveal credential for this site."), true);
      return;
    }

    username = typeof response.data?.username === "string" ? response.data.username : "";
    password = typeof response.data?.password === "string" ? response.data.password : "";
    if (!password) {
      setStatus("Credential did not include a fillable password.", true);
      return;
    }

    const fillResult = await executeFill(tab.id, username, password);
    if (!fillResult.ok) {
      setStatus("Unable to inject fill script into this page.", true);
      return;
    }
    if (!fillResult.result?.filled) {
      setStatus("No visible password field found on this page.", true);
      return;
    }
    setStatus("Filled current page. Password was not stored by the extension.");
  } finally {
    if (response?.data) {
      response.data.username = "";
      response.data.password = "";
    }
    username = null;
    password = null;
    response = null;
    inFlight = false;
  }
}

statusButton.addEventListener("click", checkHostStatus);
queryButton.addEventListener("click", queryCurrentSite);
searchButton.addEventListener("click", searchMetadata);
searchInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    searchMetadata();
  }
});

setStatus("Click Find current site or search KeyVault metadata.");
renderMessage(
  "No password cache",
  "This popup reads metadata. Exact strong matches show a Fill button after KeyVault desktop starts the local reveal bridge."
);
