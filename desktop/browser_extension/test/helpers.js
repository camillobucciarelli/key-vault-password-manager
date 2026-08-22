// Shared test scaffolding for the spec 009 Slice A0 harness.
//
// This file builds INPUTS and loads FIXTURES only. It contains no
// canonicalization, no shape checking, and no sender classification: every
// assertion in every test file runs the shipped
// `desktop/browser_extension/overlay_security.js`, so a test can never pass
// against a copy that the extension does not actually load.

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const security = require("../overlay_security.js");

const RUNTIME_ID = "abcdefghijklmnopabcdefghijklmnop";
const OTHER_RUNTIME_ID = "ponmlkjihgfedcbaponmlkjihgfedcba";

const FIXTURE_PATH = path.join(
  __dirname,
  "fixtures",
  "origin_canonicalization_v1.json"
);

function loadOriginFixture() {
  return JSON.parse(fs.readFileSync(FIXTURE_PATH, "utf8"));
}

function fixtureCaseById(fixture, id) {
  const found = fixture.cases.find((entry) => entry.id === id);
  if (!found) throw new Error(`fixture case "${id}" is missing`);
  return found;
}

/** A well-formed extension-page sender (popup). */
function extensionPageSender(overrides = {}) {
  return {
    id: RUNTIME_ID,
    url: `chrome-extension://${RUNTIME_ID}/popup.html`,
    origin: `chrome-extension://${RUNTIME_ID}`,
    ...overrides,
  };
}

/** A well-formed content-script sender. Defaults to the top frame. */
function contentScriptSender(overrides = {}) {
  const {
    frameUrl = "https://example.com/login",
    topUrl = frameUrl,
    frameId = 0,
    tabId = 42,
    ...rest
  } = overrides;
  return {
    id: RUNTIME_ID,
    url: frameUrl,
    frameId,
    tab: { id: tabId, url: topUrl },
    ...rest,
  };
}

function overlayMessage(type, fields = {}) {
  return {
    channel: security.CHANNEL,
    version: security.MESSAGE_VERSION,
    type,
    ...fields,
  };
}

function bootstrapMessage(origin = "https://example.com") {
  return overlayMessage("bootstrap", { origin });
}

function requestMatchesMessage(overrides = {}) {
  return overlayMessage("requestMatches", {
    origin: "https://example.com",
    focusNonce: "nonce-1",
    fieldKind: "password",
    ...overrides,
  });
}

function fillMessage(overrides = {}) {
  const { sessionBinding = bindingA(), ...rest } = overrides;
  return overlayMessage("fill", {
    origin: "https://example.com",
    focusNonce: "nonce-1",
    fillToken: "token-1",
    entryId: "entry-1",
    sessionBinding,
    ...rest,
  });
}

function getSiteStateMessage(overrides = {}) {
  return overlayMessage("getSiteState", {
    tabId: 42,
    tabUrl: "https://example.com/login",
    ...overrides,
  });
}

function setSiteStateMessage(overrides = {}) {
  return overlayMessage("setSiteState", {
    tabId: 42,
    enabled: true,
    ...overrides,
  });
}

function bindingA() {
  return {
    databaseId: "db-a",
    cacheGeneration: "cache-a1",
    bridgeGeneration: "bridge-a1",
  };
}

/**
 * Vault B. Deliberately reuses nothing from vault A: switching databases
 * changes the database id and mints fresh cache/bridge generations, which is
 * exactly what makes an A grant unusable against B (SR-4).
 */
function bindingB() {
  return {
    databaseId: "db-b",
    cacheGeneration: "cache-b1",
    bridgeGeneration: "bridge-b1",
  };
}

/** Committed `overlayConfigV2`. Slice C: one global switch, no origin list. */
function overlayConfig(enabled = true, revision = 17) {
  return { version: 2, revision, enabled };
}

/**
 * A Slice A2 `overlayConfigV1` value, for the migration tests ONLY.
 *
 * Built here rather than by the shipped code on purpose: this build has no
 * v1 writer any more, so the fixture has to be spelled out to prove that a
 * value written by the PREVIOUS build cannot be read as an opt-in by this one.
 */
function legacyConfigV1(origins, revision = 17) {
  return { version: 1, revision, enabledOrigins: [...origins].sort() };
}

/** Authorization context for `validateContentScriptRequest`. */
function contextFor(overrides = {}) {
  return {
    enabled: true,
    revision: 17,
    grantedPatterns: [...security.GLOBAL_PERMISSION_PATTERNS],
    ...overrides,
  };
}

module.exports = {
  security,
  RUNTIME_ID,
  OTHER_RUNTIME_ID,
  FIXTURE_PATH,
  loadOriginFixture,
  fixtureCaseById,
  extensionPageSender,
  contentScriptSender,
  overlayMessage,
  bootstrapMessage,
  requestMatchesMessage,
  fillMessage,
  getSiteStateMessage,
  setSiteStateMessage,
  bindingA,
  bindingB,
  overlayConfig,
  legacyConfigV1,
  contextFor,
};
