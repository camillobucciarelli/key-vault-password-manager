// Shared scaffolding for the content-overlay SESSION tests (Slices A4/A5).
//
// Builds inputs only: a FakePage holding one login form, plus canned worker
// responses shaped exactly like the production `matchesResult`/`fillResult`
// messages. The shipped `validateMatchesResult` runs INSIDE the content
// script against them, so a response the real worker could not have produced
// is rejected by production code, never accepted by a lenient fake.

"use strict";

const assert = require("node:assert/strict");

const { FakePage } = require("./fake_page.js");
const { bindingA } = require("./helpers.js");

const ORIGIN = "https://example.com";
const PAGE_URL = "https://example.com/login";

// Mirrors the real `bootstrapResult` the worker sends (SR-7 `frameSupport`
// included: an approval is not an approval unless the frame is supported).
const APPROVED = Object.freeze({
  ok: true,
  type: "bootstrapResult",
  enabled: true,
  frameSupport: "top",
  revision: 3,
});

function item(overrides = {}) {
  return {
    entryId: "entry-1",
    title: "Example",
    displayService: "example.com",
    matchType: "exact-origin",
    fillEligible: true,
    ...overrides,
  };
}

/** A `matchesResult` echoing the request, shaped like the production worker. */
function matchesResult(
  message,
  {
    items = [item()],
    fillToken = "token-1",
    expiresInMs = 25000,
    generateAvailable,
    generateToken,
  } = {}
) {
  const result = {
    ok: true,
    type: "matchesResult",
    origin: message.origin,
    focusNonce: message.focusNonce,
    revision: 3,
    sessionBinding: bindingA(),
    items,
  };
  const fillable = items.some((entry) => entry.fillEligible === true);
  if (fillable && typeof fillToken === "string") {
    result.fillToken = fillToken;
    result.expiresAtEpochMs = Date.now() + expiresInMs;
  }
  // B010 — mirror the production worker: capability flag plus one-shot token.
  if (generateAvailable !== undefined) result.generateAvailable = generateAvailable;
  if (generateAvailable === true) {
    result.generateToken =
      typeof generateToken === "string" ? generateToken : "gen-token-1";
  }
  return result;
}

/** A `fillResult` echoing the request, shaped like the production worker. */
function fillResult(message, { username = "alice", password, ...overrides } = {}) {
  return {
    ok: true,
    type: "fillResult",
    origin: message.origin,
    focusNonce: message.focusNonce,
    entryId: message.entryId,
    sessionBinding: bindingA(),
    // Callers pass their own runtime-assembled canary; a default is provided
    // the same way (never a credential-shaped source literal — GitGuardian).
    data: { username, password: password ?? ["canary", "alpha"].join("-") },
    ...overrides,
  };
}

/** A `generateResult` echoing the request, shaped like the production worker. */
function generateResult(message, { generated, ...overrides } = {}) {
  return {
    ok: true,
    type: "generateResult",
    origin: message.origin,
    focusNonce: message.focusNonce,
    sessionBinding: bindingA(),
    // Runtime-assembled default; never a credential-shaped source literal.
    data: { password: generated ?? ["canary", "generated"].join("-") },
    ...overrides,
  };
}

function errorResult(type, code, message) {
  return {
    ok: false,
    type,
    focusNonce: message?.focusNonce,
    error: { code, message: "test" },
  };
}

/**
 * An approved page holding one login form. `handlers.matches` / `handlers.fill`
 * may be swapped at any point; both receive the structured-cloned request.
 */
async function loginPage({
  url = PAGE_URL,
  withUsername = true,
  bootstrap = APPROVED,
} = {}) {
  const handlers = {
    matches: (message) => matchesResult(message),
    fill: (message) => fillResult(message),
    generate: (message) => generateResult(message),
  };
  const page = new FakePage({
    url,
    respond: async (message) => {
      if (message.type === "bootstrap") return bootstrap;
      if (message.type === "requestMatches") return handlers.matches(message);
      if (message.type === "fill") return handlers.fill(message);
      if (message.type === "generate") return handlers.generate(message);
      throw new Error(`unexpected message type ${message.type}`);
    },
  });
  const doc = page.document;
  const form = doc.createElement("form");
  const password = doc.createElement("input");
  password.setAttribute("type", "password");
  form.appendChild(password);
  let username = null;
  if (withUsername) {
    username = doc.createElement("input");
    username.setAttribute("type", "text");
    username.setAttribute("autocomplete", "username");
    form.appendChild(username);
  }
  doc.body.appendChild(form);
  await page.inject();
  assert.equal(page.listenerCount, 1, "bootstrap should have been approved");
  return { page, form, password, username, handlers };
}

function statusText(page) {
  const status = page.allElements().find((el) => el.id === "kv-status");
  return status ? status.textContent : null;
}

/** The SHADOW metadata rows (A029). Excludes the A040 light fallback. */
function optionRows(page) {
  return page
    .allElements()
    .filter(
      (el) =>
        el.getAttribute("role") === "option" && el.id.startsWith("kv-option-")
    );
}

/** The SHADOW listbox (`#kv-list`). Excludes the A040 light fallback. */
function listboxEl(page) {
  return page.allElements().find((el) => el.id === "kv-list");
}

/** A040 — the light-DOM fallback listbox, or undefined. */
function lightListboxEl(page) {
  return page.allElements().find((el) => el.id === "kv-light-listbox");
}

/** A040 — the GENERIC light options, in DOM order. */
function lightOptions(page) {
  const listbox = lightListboxEl(page);
  return listbox ? [...listbox.childNodes] : [];
}

function overlayCount(page) {
  return page.overlayHosts().length;
}

module.exports = {
  ORIGIN,
  PAGE_URL,
  APPROVED,
  item,
  matchesResult,
  fillResult,
  generateResult,
  errorResult,
  loginPage,
  statusText,
  optionRows,
  listboxEl,
  lightListboxEl,
  lightOptions,
  overlayCount,
};
