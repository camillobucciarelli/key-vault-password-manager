// 009 A041 — supplemental visual-baseline inventory test.
//
// The authority for visual acceptance is the canonical container run
// (run_visual_baselines.sh --verify): decoded-pixel equality plus approved
// sha256 per baseline in the pinned environment. THIS test is the cheap,
// CI-runnable supplement the spec requires: the committed inventory is
// exactly the 18 basenames from spec.md — no missing, no extra — and every
// committed expected PNG still matches its approved hash (so a baseline
// cannot be silently edited without touching visual_baselines_v1.sha256).

"use strict";

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const TEST_DIR = __dirname;
const EXPECTED_DIR = path.join(TEST_DIR, "screenshots", "expected");
const BASELINE_HASH_PATH = path.join(TEST_DIR, "visual_baselines_v1.sha256");

// The exact inventory from specs/009-in-page-autofill-overlay/spec.md,
// "Visual inventory — Slice A". Exactly 18, by contract.
const EXPECTED_BASENAMES = Object.freeze([
  "overlay-chrome-1440x900-dpr1-light-matches.png",
  "overlay-chrome-1440x900-dpr1-dark-matches.png",
  "overlay-chrome-1440x900-dpr1-light-possible.png",
  "overlay-chrome-1440x900-dpr1-dark-possible.png",
  "overlay-chrome-1440x900-dpr1-light-no-matches.png",
  "overlay-chrome-1440x900-dpr1-dark-no-matches.png",
  "overlay-chrome-1440x900-dpr1-light-locked.png",
  "overlay-chrome-1440x900-dpr1-dark-locked.png",
  "overlay-chrome-1440x900-dpr1-light-no-host.png",
  "overlay-chrome-1440x900-dpr1-dark-no-host.png",
  "overlay-chrome-1440x900-dpr1-light-unsupported-frame.png",
  "overlay-chrome-1440x900-dpr1-dark-unsupported-frame.png",
  "overlay-chrome-390x844-dpr2-light-matches-below.png",
  "overlay-chrome-390x844-dpr2-dark-matches-below.png",
  "overlay-chrome-1024x768-dpr1-light-matches-flipped.png",
  "overlay-chrome-1440x900-dpr1-light-loading.png",
  "overlay-chrome-1440x900-dpr1-dark-stale-retry.png",
  "overlay-chrome-1440x900-dpr1-light-timeout.png",
]);

test("A041: the visual inventory is exactly the 18 spec basenames", () => {
  assert.equal(EXPECTED_BASENAMES.length, 18);
  assert.equal(new Set(EXPECTED_BASENAMES).size, 18, "basenames must be unique");
  for (const name of EXPECTED_BASENAMES) {
    assert.match(name, /^overlay-chrome-\d+x\d+-dpr\d-(light|dark)-[a-z-]+\.png$/);
  }
});

test("A041: screenshots/expected/ holds exactly the 18 approved PNGs", () => {
  const onDisk = fs.readdirSync(EXPECTED_DIR).sort();
  assert.deepEqual(onDisk, [...EXPECTED_BASENAMES].sort());
});

test("A041: every approved hash row matches its committed expected PNG", () => {
  const rows = fs
    .readFileSync(BASELINE_HASH_PATH, "utf8")
    .split("\n")
    .filter((line) => line.trim().length > 0);
  assert.equal(rows.length, 18, "visual_baselines_v1.sha256 must have exactly 18 rows");
  const byName = new Map();
  for (const row of rows) {
    const match = /^([0-9a-f]{64})  (\S+)$/.exec(row);
    assert.notEqual(match, null, `malformed hash row: "${row}"`);
    byName.set(match[2], match[1]);
  }
  assert.deepEqual([...byName.keys()].sort(), [...EXPECTED_BASENAMES].sort());
  for (const name of EXPECTED_BASENAMES) {
    const digest = createHash("sha256")
      .update(fs.readFileSync(path.join(EXPECTED_DIR, name)))
      .digest("hex");
    assert.equal(
      digest,
      byName.get(name),
      `${name}: committed PNG does not match its approved sha256 — unapproved baseline edit`
    );
  }
});
