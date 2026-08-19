// 009 A041 — TEST-ONLY background service worker for visual baseline capture.
//
// NEVER PACKAGED. This file lives under test/ and is copied by
// capture_runner.mjs into a throwaway unpacked extension together with the
// UNMODIFIED production `overlay_security.js` + `content_overlay.js`. It
// replaces the production worker so the 18 overlay states can be driven
// deterministically without a native host. The production runtime files, the
// packaging allowlist, and the shipped ZIP are untouched.
//
// The scenario is selected by the test page's own URL query string
// (`?scenario=...`), which arrives here as `sender.url` — the same channel the
// production worker uses for origin authority, so no debug hook exists inside
// any runtime extension file.
//
// GitGuardian note: every string below is a neutral fixture label; the fill
// token is assembled with join() and no credential-shaped value exists.

"use strict";

const ERROR_SCENARIOS = Object.freeze({
  locked: "locked",
  "no-host": "no_host",
  timeout: "timeout",
  "stale-retry": "stale_session",
});

const FIXTURE_FILL_TOKEN = ["visual", "fixture", "fill", "token"].join("-");

const fixtureItems = (scenario) => {
  const possible = scenario === "possible";
  return [
    {
      entryId: "entry-1",
      title: "Personal login",
      displayService: "example.com",
      matchType: possible ? "possible" : "exact-origin",
      fillEligible: !possible,
    },
    {
      entryId: "entry-2",
      title: "Work login",
      displayService: "login.example.com",
      matchType: possible ? "possible" : "exact-origin",
      fillEligible: !possible,
    },
  ];
};

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const senderUrl = new URL(sender.url);
  const scenario = senderUrl.searchParams.get("scenario") ?? "";
  const origin = senderUrl.origin;

  if (message?.type === "bootstrap") {
    sendResponse({
      ok: true,
      enabled: true,
      frameSupport: scenario === "unsupported-frame" ? "unsupported" : "top",
    });
    return false;
  }

  if (message?.type === "requestMatches") {
    if (scenario === "loading") {
      // Deliberately never responds: the overlay stays in its loading state.
      return true;
    }
    const errorCode = ERROR_SCENARIOS[scenario];
    if (errorCode !== undefined) {
      sendResponse({ ok: false, error: { code: errorCode } });
      return false;
    }
    const base = {
      ok: true,
      type: "matchesResult",
      origin,
      focusNonce: message.focusNonce,
      revision: 1,
      sessionBinding: {
        databaseId: "db-visual-fixture",
        cacheGeneration: "cache-1",
        bridgeGeneration: "bridge-1",
      },
    };
    if (scenario === "no-matches") {
      sendResponse({ ...base, items: [] });
      return false;
    }
    const items = fixtureItems(scenario);
    if (scenario === "possible") {
      sendResponse({ ...base, items });
      return false;
    }
    sendResponse({ ...base, items, fillToken: FIXTURE_FILL_TOKEN });
    return false;
  }

  return false;
});
