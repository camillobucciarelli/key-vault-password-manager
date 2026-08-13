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

// ---------------------------------------------------------------------------
// T14 — badge state machine (plan.md "Badge state machine" / ICONS.md §1).
//
// MV3 kills this service worker aggressively and unpredictably (plan.md
// risk: "MV3 worker restart loses badge state"). Nothing here is trusted
// from a module-level JS variable across an event: every derivation reads
// chrome.storage.local first, then does a fresh native-host ping. There is
// no persistent connection to the native host (sendNativeMessage is
// one-shot), so "host connect/disconnect" and "app lock/unlock" are not
// pushed events — they are inferred by re-pinging on every wake, exactly
// as plan.md's mitigation describes ("re-derive from storage + a fresh
// host ping on every wake").
// ---------------------------------------------------------------------------

const BADGE_STATE_KEY = "kv_badge_state_v1";

// Copied verbatim from desktop/browser_extension/tokens.css (which is
// itself generated from specs/_design/tokens.css) — chrome.action's badge
// APIs need literal colour strings, not CSS custom properties, so these
// three constants are the one place colour hex values are duplicated
// outside CSS. Keep them in sync with tokens.css by hand if the tokens
// ever change; nothing enforces that automatically here.
const BADGE_COLOR_HOST_MISSING = "#f6a06b"; // --color-accent-400
const BADGE_COLOR_APP_LOCKED = "#a19786"; // --color-neutral-500
const BADGE_COLOR_MATCHES = "#aebf92"; // --color-accent-2-400
const BADGE_TEXT_COLOR_MATCHES = "#272e1b"; // --color-accent-2-900
const BADGE_DIM_OPACITY = 0.45;
const ICON_SIZES = [16, 32, 48];

async function loadBadgeState() {
  const stored = await chrome.storage.local.get(BADGE_STATE_KEY);
  return (
    stored[BADGE_STATE_KEY] || {
      hostReachable: false,
      appUnlocked: false,
      tabMatchCounts: {},
    }
  );
}

async function saveBadgeState(state) {
  await chrome.storage.local.set({ [BADGE_STATE_KEY]: state });
}

async function pingHostForBadge() {
  try {
    const response = await sendNativeV2("status");
    return {
      hostReachable: response?.ok === true,
      appUnlocked: response?.ok === true && response.data?.vault?.connected === true,
    };
  } catch (_) {
    return { hostReachable: false, appUnlocked: false };
  }
}

let dimIconImageDataCache = null; // pure perf cache; losing it on worker
// restart only costs one re-fetch+redraw of the *existing* PNGs below,
// never a correctness issue — the cache holds no state used for the
// hostReachable/appUnlocked/matchCount derivation itself.

async function dimmedIconImageData() {
  if (dimIconImageDataCache) return dimIconImageDataCache;
  const result = {};
  for (const size of ICON_SIZES) {
    const url = chrome.runtime.getURL(`icons/icon-${size}.png`);
    const response = await fetch(url);
    const blob = await response.blob();
    const bitmap = await createImageBitmap(blob);
    const canvas = new OffscreenCanvas(size, size);
    const ctx = canvas.getContext("2d");
    ctx.globalAlpha = BADGE_DIM_OPACITY;
    ctx.drawImage(bitmap, 0, 0, size, size);
    result[size] = ctx.getImageData(0, 0, size, size);
  }
  dimIconImageDataCache = result;
  return result;
}

// ponytail: spec 007 owns real pre-rendered per-state icon PNGs
// (icons/state/*.png per plan.md); those do not exist in this repo yet
// and T10-T14 scope forbids generating new binary icon assets. Until
// spec 007 ships them, the "45% opacity" badge states are produced at
// runtime by alpha-compositing the *existing* icon-16/32/48.png (never
// creating a new file on disk). Swap dimmedIconImageData() for
// chrome.action.setIcon({tabId, path: {...}}) against real dimmed PNGs
// once spec 007 lands.
async function applyIconForTab(tabId, dim) {
  if (!dim) {
    await chrome.action.setIcon({
      tabId,
      path: { 16: "icons/icon-16.png", 32: "icons/icon-32.png", 48: "icons/icon-48.png" },
    });
    return;
  }
  const imageData = await dimmedIconImageData();
  await chrome.action.setIcon({ tabId, imageData });
}

async function applyBadgeForTab(tabId, { text, color, textColor }) {
  await chrome.action.setBadgeText({ tabId, text: text || "" });
  if (text) {
    await chrome.action.setBadgeBackgroundColor({ tabId, color });
    // setBadgeTextColor is Chrome 110+; feature-detect, never required.
    if (textColor && typeof chrome.action.setBadgeTextColor === "function") {
      await chrome.action.setBadgeTextColor({ tabId, color: textColor });
    }
  }
}

// derive(state) from: hostReachable, appUnlocked, matchCount(activeTab)
//   !hostReachable → icon 45%, badge solid accent-400
//   !appUnlocked   → icon 45%, badge solid neutral-500
//   matchCount > 0 → icon 100%, badge accent-2-400 with the count
//   otherwise      → icon 100%, no badge
async function refreshBadgeForTab(tabId) {
  if (typeof tabId !== "number") return;

  const ping = await pingHostForBadge();
  const state = await loadBadgeState();
  state.hostReachable = ping.hostReachable;
  state.appUnlocked = ping.appUnlocked;
  await saveBadgeState(state);

  if (!state.hostReachable) {
    await applyIconForTab(tabId, true);
    await applyBadgeForTab(tabId, { text: " ", color: BADGE_COLOR_HOST_MISSING });
    return;
  }
  if (!state.appUnlocked) {
    await applyIconForTab(tabId, true);
    await applyBadgeForTab(tabId, { text: " ", color: BADGE_COLOR_APP_LOCKED });
    return;
  }

  const matchCount = state.tabMatchCounts?.[tabId];
  if (typeof matchCount === "number" && matchCount > 0) {
    await applyIconForTab(tabId, false);
    await applyBadgeForTab(tabId, {
      text: String(Math.min(matchCount, 99)),
      color: BADGE_COLOR_MATCHES,
      textColor: BADGE_TEXT_COLOR_MATCHES,
    });
    return;
  }

  await applyIconForTab(tabId, false);
  await applyBadgeForTab(tabId, { text: "" });
}

async function setTabMatchCount(tabId, count) {
  if (typeof tabId !== "number") return;
  const state = await loadBadgeState();
  state.tabMatchCounts = state.tabMatchCounts || {};
  state.tabMatchCounts[tabId] = count;
  await saveBadgeState(state);
  await refreshBadgeForTab(tabId);
}

async function clearTabMatchCount(tabId) {
  const state = await loadBadgeState();
  if (state.tabMatchCounts) delete state.tabMatchCounts[tabId];
  await saveBadgeState(state);
}

async function currentActiveTabId() {
  return new Promise((resolve) => {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      resolve(tabs[0]?.id ?? null);
    });
  });
}

async function refreshActiveTabBadge() {
  const tabId = await currentActiveTabId();
  if (tabId !== null) await refreshBadgeForTab(tabId);
}

// Re-derived on tab activation, tab navigation, extension (re)start — the
// events plan.md names. No "tabs" host permission is requested: these
// listeners fire without it (only sensitive fields like tab.url would be
// filtered, and this file never reads tab.url — it only ever uses tabId).
chrome.tabs.onActivated.addListener(({ tabId }) => {
  void refreshBadgeForTab(tabId).catch(() => {});
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading") {
    // Navigation invalidates any cached match count for this tab — show
    // the safe "unknown" (no-badge) state rather than a stale count.
    void clearTabMatchCount(tabId)
      .then(() => refreshBadgeForTab(tabId))
      .catch(() => {});
  } else if (changeInfo.status === "complete") {
    void refreshBadgeForTab(tabId).catch(() => {});
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  void clearTabMatchCount(tabId).catch(() => {});
});

chrome.runtime.onStartup.addListener(() =>
  void refreshActiveTabBadge().catch(() => {})
);
chrome.runtime.onInstalled.addListener(() =>
  void refreshActiveTabBadge().catch(() => {})
);

// ---------------------------------------------------------------------------

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

  // Internal extension message (not part of the native-messaging
  // protocol): the popup reports how many matches it rendered for a tab
  // so the badge can be re-derived and persisted (T14). Fire-and-forget
  // from the popup's perspective; still acknowledged so sendMessage
  // never logs an unchecked lastError.
  if (request?.type === "KEYVAULT_V2_REPORT_MATCH_COUNT") {
    const count = Number.isInteger(request.count) ? request.count : 0;
    setTabMatchCount(request.tabId, count)
      .then(() => sendResponse({ ok: true }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }

  return false;
});
