#!/usr/bin/env node
// Mutation runner — makes the hand-maintained mutation table executable.
//
// WHY THIS EXISTS
// ---------------
// The mutation tables for spec 009 lived in PR bodies and drifted twice:
// a stale kill count in #37, and a row in Slice A2 that claimed a property
// (registration-id injectivity) which no test actually held — it survived with
// ZERO kills for a full slice because the property was asserted in a code
// comment and the tests matched on names and rationales instead of behaviour.
//
// A survivor is the signal. Everything else here is bookkeeping.
//
// WHAT IT DOES
// ------------
// For each mutation defined in a JSON definitions file: apply the edits to a
// source file, run a test suite, diff the passing-test set against a clean
// baseline, restore the file, and verify the restore by hash.
//
// NON-NEGOTIABLES IMPLEMENTED HERE
// --------------------------------
//  1. Restore is guaranteed and *verified by hash*, not trusted to `finally`.
//     Signals, crashes, timeouts and unhandled rejections all restore. SIGKILL
//     cannot be caught, so an on-disk backup + manifest lets the NEXT run
//     recover before it does anything else.
//  2. An edit that matches nothing — or matches more times than declared — is a
//     hard error. A mutation that silently applies nothing would otherwise
//     report a perfect score for testing nothing at all.
//  3. Zero kills is a flagged failure, not an ordinary table row.
//  4. Mutations are versioned data, not code.
//  5. Deterministic, and reports the NAMES of killed tests — that is what
//     showed M1 and M5 have disjoint kill sets.
//
// No dependencies. Node's built-in test runner and `flutter test` are the two
// supported suites.

import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import process from "node:process";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_DEFINITIONS = path.join(REPO_ROOT, "tool", "mutations", "009_overlay_autofill.json");

const EXIT_OK = 0;
const EXIT_SURVIVOR = 1;
const EXIT_RESTORE_FAILED = 2;
const EXIT_BAD_DEFINITION = 3;

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");

// ---------------------------------------------------------------------------
// Requirement 1 — restore, and prove it.
//
// `active` holds every file currently mutated. Everything that can end this
// process restores from it. Restores are synchronous so they are legal inside
// an `exit` handler.
// ---------------------------------------------------------------------------

/** @type {Map<string, {absPath: string, original: Buffer, hash: string, backup: string}>} */
const active = new Map();

const RECOVERY_DIR = path.join(
  os.tmpdir(),
  `kv-mutation-runner-${sha256(REPO_ROOT).slice(0, 12)}`
);
const RECOVERY_MANIFEST = path.join(RECOVERY_DIR, "manifest.json");

function writeManifestSync() {
  fs.mkdirSync(RECOVERY_DIR, { recursive: true });
  const entries = [...active.values()].map((e) => ({
    absPath: e.absPath,
    hash: e.hash,
    backup: e.backup,
  }));
  if (entries.length === 0) {
    fs.rmSync(RECOVERY_MANIFEST, { force: true });
    return;
  }
  fs.writeFileSync(RECOVERY_MANIFEST, JSON.stringify(entries, null, 2));
}

/** Restore one file and verify by hash. Throws if the bytes do not match. */
function restoreSync(entry) {
  fs.writeFileSync(entry.absPath, entry.original);
  const actual = sha256(fs.readFileSync(entry.absPath));
  if (actual !== entry.hash) {
    throw new Error(
      `RESTORE VERIFICATION FAILED for ${entry.absPath}\n` +
        `  expected sha256 ${entry.hash}\n` +
        `  actual   sha256 ${actual}\n` +
        `  a backup of the original is at ${entry.backup}`
    );
  }
  active.delete(entry.absPath);
  fs.rmSync(entry.backup, { force: true });
  writeManifestSync();
}

function restoreAllSync() {
  let failure = null;
  for (const entry of [...active.values()]) {
    try {
      restoreSync(entry);
    } catch (error) {
      failure = error;
      console.error(`\n\u001b[41m\u001b[97m ${error.message} \u001b[0m`);
    }
  }
  return failure;
}

/**
 * SIGKILL and a hard power loss cannot be trapped, so a previous run may have
 * left a mutation on disk. Recover before doing anything else, and refuse to
 * continue if recovery is not clean — running a mutation suite on top of an
 * unknown tree would produce numbers nobody should trust.
 */
function recoverStaleMutations() {
  if (!fs.existsSync(RECOVERY_MANIFEST)) return;
  let entries;
  try {
    entries = JSON.parse(fs.readFileSync(RECOVERY_MANIFEST, "utf8"));
  } catch {
    console.error(`unreadable recovery manifest at ${RECOVERY_MANIFEST}; delete it manually`);
    process.exit(EXIT_RESTORE_FAILED);
  }
  console.error(
    `\u001b[33m! a previous run left ${entries.length} mutated file(s) on disk; recovering\u001b[0m`
  );
  for (const entry of entries) {
    const original = fs.readFileSync(entry.backup);
    if (sha256(original) !== entry.hash) {
      console.error(`  backup for ${entry.absPath} is itself corrupt; restore it from git`);
      process.exit(EXIT_RESTORE_FAILED);
    }
    fs.writeFileSync(entry.absPath, original);
    if (sha256(fs.readFileSync(entry.absPath)) !== entry.hash) {
      console.error(`  could not restore ${entry.absPath}`);
      process.exit(EXIT_RESTORE_FAILED);
    }
    fs.rmSync(entry.backup, { force: true });
    console.error(`  restored ${path.relative(REPO_ROOT, entry.absPath)}`);
  }
  fs.rmSync(RECOVERY_MANIFEST, { force: true });
}

// ---------------------------------------------------------------------------
// Exclusive lock.
//
// Two runners against one checkout interleave their mutations: the second
// snapshots a file the first has already mutated, and "restoring" then writes
// the mutated text back permanently. That defeats the whole restore guarantee
// and silently corrupts the working tree, so it is refused rather than raced.
// ---------------------------------------------------------------------------

const LOCK_PATH = path.join(RECOVERY_DIR, "runner.lock");
let lockHeld = false;

function releaseLockSync() {
  if (!lockHeld) return;
  lockHeld = false;
  fs.rmSync(LOCK_PATH, { force: true });
}

function acquireLock() {
  fs.mkdirSync(RECOVERY_DIR, { recursive: true });
  try {
    fs.writeFileSync(LOCK_PATH, String(process.pid), { flag: "wx" });
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    const owner = Number(fs.readFileSync(LOCK_PATH, "utf8").trim());
    // A lock whose owner is not a real pid is a wreck, not a live run. SIGKILL
    // between the `wx` create and the write leaves the file EMPTY, and
    // Number("") is 0 — which `process.kill(0, 0)` reports as alive, because
    // signalling pid 0 targets the caller's OWN process group. Probing it
    // therefore always succeeds and wedges every later run behind a lock that
    // nobody holds, in a tmpdir nobody thinks to look in.
    let alive = Number.isInteger(owner) && owner > 0;
    if (alive) {
      try {
        process.kill(owner, 0);
      } catch {
        alive = false;
      }
    }
    if (alive) {
      throw new Error(
        `another mutation run (pid ${owner}) already holds this checkout.\n` +
          `Two concurrent runs would mutate the same files and restore each other's\n` +
          `mutated text permanently. Wait for it, or kill it and re-run.`
      );
    }
    fs.writeFileSync(LOCK_PATH, String(process.pid));
  }
  lockHeld = true;
}

let guardsInstalled = false;
function installGuards() {
  if (guardsInstalled) return;
  guardsInstalled = true;
  process.on("exit", () => {
    restoreAllSync();
    releaseLockSync();
  });
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP", "SIGQUIT"]) {
    process.on(signal, () => {
      console.error(`\n${signal} received — restoring source files before exit.`);
      const failure = restoreAllSync();
      releaseLockSync();
      process.exit(failure ? EXIT_RESTORE_FAILED : 130);
    });
  }
  for (const event of ["uncaughtException", "unhandledRejection"]) {
    process.on(event, (error) => {
      console.error(`\n${event}:`, error);
      const failure = restoreAllSync();
      releaseLockSync();
      process.exit(failure ? EXIT_RESTORE_FAILED : EXIT_SURVIVOR);
    });
  }
}

// ---------------------------------------------------------------------------
// Requirement 2 — applying nothing is an error.
// ---------------------------------------------------------------------------

function countOccurrences(haystack, needle) {
  if (needle.length === 0) throw new Error("empty `find` string");
  let count = 0;
  let index = haystack.indexOf(needle);
  while (index !== -1) {
    count += 1;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

/**
 * Applies every edit of a mutation, or throws without touching the file.
 * Literal string matching, never regex: a definition must be unambiguous on
 * sight, and a regex that quietly matches a second site is the same silent
 * failure this tool exists to catch.
 */
function applyMutation(mutation) {
  const absPath = path.join(REPO_ROOT, mutation.file);
  if (!fs.existsSync(absPath)) {
    throw new Error(`${mutation.id}: file not found: ${mutation.file}`);
  }
  const original = fs.readFileSync(absPath);
  let text = original.toString("utf8");

  for (const [index, edit] of mutation.edits.entries()) {
    const expected = edit.expect ?? 1;
    const found = countOccurrences(text, edit.find);
    if (found !== expected) {
      throw new Error(
        `${mutation.id}: edit ${index + 1} matched ${found} time(s), expected ${expected}, ` +
          `in ${mutation.file}\n` +
          `  find: ${JSON.stringify(edit.find.slice(0, 120))}` +
          (found === 0
            ? "\n  the source moved out from under this definition — fix the definition, " +
              "do not weaken it"
            : "")
      );
    }
    text = text.split(edit.find).join(edit.replace);
  }

  const backup = path.join(RECOVERY_DIR, `${sha256(absPath).slice(0, 16)}.bak`);
  fs.mkdirSync(RECOVERY_DIR, { recursive: true });
  fs.writeFileSync(backup, original);
  const entry = { absPath, original, hash: sha256(original), backup };
  active.set(absPath, entry);
  writeManifestSync();

  fs.writeFileSync(absPath, text);
  return entry;
}

// ---------------------------------------------------------------------------
// Suites.
// ---------------------------------------------------------------------------

function runProcess(command, args, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: REPO_ROOT,
      env: { ...process.env, NO_COLOR: "1", FORCE_COLOR: "0" },
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, timeoutMs);
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ stdout, stderr: stderr + String(error), code: -1, timedOut });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ stdout, stderr, code, timedOut });
    });
  });
}

/**
 * node --test, TAP reporter.
 *
 * Nested subtests are counted, not just top-level ones: the crash-injection
 * cases (`crash after D1` ... `crash after D5`) are subtests, and they are the
 * only tests that observe the SR-8 commit-ordering property. Dropping them
 * silently under-reports every Slice A2 kill count.
 *
 * Subtest numbering restarts inside each parent, so names are qualified by
 * their ancestors ("parent > child") to stay unique across the whole run.
 */
function parseTap(stdout) {
  const passed = new Set();
  const failed = new Set();
  /** @type {Map<number, string>} indent width -> most recent subtest name */
  const stack = new Map();

  for (const line of stdout.split("\n")) {
    const subtest = /^(\s*)# Subtest: (.*)$/.exec(line);
    if (subtest) {
      const indent = subtest[1].length;
      for (const key of [...stack.keys()]) if (key > indent) stack.delete(key);
      stack.set(indent, subtest[2].trim());
      continue;
    }
    const match = /^(\s*)(ok|not ok) \d+ - (.*)$/.exec(line);
    if (!match) continue;
    const indent = match[1].length;
    const raw = match[3];
    if (/#\s*(SKIP|TODO)\b/i.test(raw)) continue;
    const name = raw.replace(/\s+#\s*(SKIP|TODO).*$/i, "").trim();
    const ancestors = [...stack.keys()]
      .filter((key) => key < indent)
      .sort((a, b) => a - b)
      .map((key) => stack.get(key));
    const qualified = [...ancestors, name].join(" > ");
    (match[2] === "ok" ? passed : failed).add(qualified);
  }
  return { passed, failed };
}

/** flutter test --reporter json, newline-delimited events. */
function parseFlutterJson(stdout) {
  const names = new Map();
  const passed = new Set();
  const failed = new Set();
  for (const line of stdout.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("{")) continue;
    let event;
    try {
      event = JSON.parse(trimmed);
    } catch {
      continue;
    }
    if (event.type === "testStart" && event.test) {
      if (typeof event.test.name === "string" && !event.test.name.startsWith("loading ")) {
        names.set(event.test.id, event.test.name);
      }
    } else if (event.type === "testDone" && event.hidden !== true) {
      const name = names.get(event.testID);
      if (name === undefined) continue;
      (event.result === "success" ? passed : failed).add(name);
    }
  }
  return { passed, failed };
}

const PARSERS = { tap: parseTap, "flutter-json": parseFlutterJson };

async function runSuite(suite) {
  const result = await runProcess(suite.command[0], suite.command.slice(1), suite.timeoutMs ?? 600000);
  const parser = PARSERS[suite.parser];
  if (!parser) throw new Error(`unknown parser: ${suite.parser}`);
  const parsed = parser(result.stdout);
  return { ...parsed, timedOut: result.timedOut, code: result.code, stderr: result.stderr };
}

// ---------------------------------------------------------------------------
// CLI.
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const options = {
    definitions: DEFAULT_DEFINITIONS,
    slices: null,
    ids: null,
    check: false,
    json: false,
    names: false,
    dryRun: false,
    list: false,
  };
  for (const arg of argv) {
    if (arg === "--check") options.check = true;
    else if (arg === "--json") options.json = true;
    else if (arg === "--names") options.names = true;
    else if (arg === "--dry-run") options.dryRun = true;
    else if (arg === "--list") options.list = true;
    else if (arg.startsWith("--definitions=")) options.definitions = path.resolve(arg.slice(14));
    else if (arg.startsWith("--slice=")) options.slices = arg.slice(8).split(",");
    else if (arg.startsWith("--id=")) options.ids = arg.slice(5).split(",");
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  return options;
}

const USAGE = `
Usage: node tool/mutation_runner.mjs [options]

  --slice=A0,A2      only mutations from these slices
  --id=M1,M5         only these mutation ids
  --dry-run          apply + restore every mutation, run no tests
                     (proves the definitions still match the sources)
  --check            exit non-zero on a survivor or on a drifted kill count
  --names            print the killed-test names for every mutation
  --json             emit machine-readable results instead of the table
  --list             list the mutations and exit
  --definitions=P    use another definitions file
`.trim();

function formatMarkdownTable(rows, definitions) {
  const lines = [];
  const bySlice = new Map();
  for (const row of rows) {
    if (!bySlice.has(row.slice)) bySlice.set(row.slice, []);
    bySlice.get(row.slice).push(row);
  }
  for (const [slice, sliceRows] of bySlice) {
    const meta = definitions.slices?.[slice];
    lines.push(`### ${slice}${meta ? ` — ${meta}` : ""}`);
    lines.push("");
    lines.push("| id | mutation | file | kills | expected | |");
    lines.push("|---|---|---|---|---|---|");
    for (const row of sliceRows) {
      const flag =
        row.kills === 0 && !row.equivalent
          ? "**SURVIVED**"
          : row.equivalent && row.kills === 0
            ? "equivalent"
            : row.drift || (row.equivalent && row.kills !== 0)
              ? `drift (expected ${row.expectedKills})`
              : row.suiteError
                ? "suite error"
                : "";
      lines.push(
        `| ${row.id} | ${row.title} | \`${path.basename(row.file)}\` | ` +
          `${row.kills === 0 ? `**0**` : row.kills} | ` +
          `${row.expectedKills ?? "—"} | ${flag} |`
      );
    }
    lines.push("");
  }
  return lines.join("\n");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(USAGE);
    return EXIT_OK;
  }

  const definitions = JSON.parse(fs.readFileSync(options.definitions, "utf8"));
  let mutations = definitions.mutations;
  if (options.slices) mutations = mutations.filter((m) => options.slices.includes(m.slice));
  if (options.ids) mutations = mutations.filter((m) => options.ids.includes(m.id));

  if (mutations.length === 0) throw new Error("no mutations selected");

  // Before anything else, including --list: if a previous run was SIGKILLed the
  // tree still holds a mutation, and every later command would be reading
  // mutated source without knowing it.
  recoverStaleMutations();

  if (options.list) {
    for (const mutation of mutations) {
      console.log(`${mutation.slice}/${mutation.id}\t${mutation.file}\t${mutation.title}`);
    }
    return EXIT_OK;
  }

  installGuards();
  acquireLock();

  // ---- dry run: requirement 2 without paying for any test run. -------------
  if (options.dryRun) {
    for (const mutation of mutations) {
      const entry = applyMutation(mutation);
      restoreSync(entry);
      console.log(`ok   ${mutation.id}  applies cleanly and restores byte-identical`);
    }
    console.log(`\n${mutations.length} mutation(s) verified against the current sources.`);
    return EXIT_OK;
  }

  // ---- baselines ----------------------------------------------------------
  const neededSuites = [...new Set(mutations.map((m) => m.suite))];
  const baselines = new Map();
  for (const name of neededSuites) {
    const suite = definitions.suites[name];
    if (!suite) throw new Error(`mutation references unknown suite: ${name}`);
    process.stderr.write(`baseline ${name} ... `);
    const started = Date.now();
    const result = await runSuite(suite);
    const elapsed = Date.now() - started;
    if (result.failed.size > 0 || result.passed.size === 0) {
      throw new Error(
        `baseline for suite "${name}" is not green ` +
          `(${result.passed.size} pass, ${result.failed.size} fail). ` +
          `Mutation numbers are meaningless against a red baseline.\n${result.stderr.slice(-2000)}`
      );
    }
    process.stderr.write(`${result.passed.size} pass (${(elapsed / 1000).toFixed(1)}s)\n`);
    baselines.set(name, { passed: result.passed, ms: elapsed });
  }

  // ---- mutations ----------------------------------------------------------
  const rows = [];
  for (const mutation of mutations) {
    const suite = definitions.suites[mutation.suite];
    const baseline = baselines.get(mutation.suite);
    process.stderr.write(`${mutation.id} ... `);

    const entry = applyMutation(mutation);
    let result;
    try {
      result = await runSuite(suite);
    } finally {
      restoreSync(entry);
    }

    // A test counts as killed when it passed clean and does not pass now —
    // including when it vanished because the suite aborted.
    const killedNames = [...baseline.passed].filter((name) => !result.passed.has(name)).sort();
    const suiteError = result.timedOut || (result.passed.size === 0 && result.failed.size === 0);

    const row = {
      id: mutation.id,
      slice: mutation.slice,
      title: mutation.title,
      property: mutation.property ?? null,
      file: mutation.file,
      suite: mutation.suite,
      kills: killedNames.length,
      killedTests: killedNames,
      expectedKills: mutation.expectedKills ?? null,
      drift:
        mutation.expectedKills !== undefined && mutation.expectedKills !== killedNames.length,
      // An equivalent mutant cannot be killed because it does not change
      // observable behaviour for any reachable input. Declaring one pins the
      // reachability argument: if the argument ever stops holding, the mutation
      // starts killing and is reported as drift rather than passing silently.
      equivalent: mutation.equivalent === true,
      equivalentReason: mutation.equivalentReason ?? null,
      suiteError,
      disjointFrom: mutation.disjointFrom ?? null,
    };
    rows.push(row);
    process.stderr.write(
      row.kills === 0 && !row.equivalent
        ? `\u001b[41m\u001b[97m SURVIVED — 0 kills \u001b[0m\n`
        : row.equivalent && row.kills === 0
          ? `0 kills (declared equivalent)\n`
          : `${row.kills} kills${row.drift ? ` \u001b[33m(expected ${row.expectedKills})\u001b[0m` : ""}\n`
    );
  }

  // ---- declared invariants between mutations ------------------------------
  const byId = new Map(rows.map((row) => [row.id, row]));
  const disjointFailures = [];
  for (const row of rows) {
    if (!row.disjointFrom) continue;
    for (const otherId of row.disjointFrom) {
      const other = byId.get(otherId);
      if (!other) continue;
      const overlap = row.killedTests.filter((name) => other.killedTests.includes(name));
      if (overlap.length > 0) {
        disjointFailures.push({ a: row.id, b: otherId, overlap });
      } else {
        process.stderr.write(`invariant ok: ${row.id} \u2229 ${otherId} = \u2205\n`);
      }
    }
  }

  // ---- report -------------------------------------------------------------
  const survivors = rows.filter((row) => row.kills === 0 && !row.equivalent);
  // A declared-equivalent mutant that suddenly kills is drift too: the
  // reachability argument that justified it no longer holds.
  const drifted = rows.filter((row) => row.drift || (row.equivalent && row.kills !== 0));

  if (options.json) {
    console.log(JSON.stringify({ rows, survivors: survivors.map((r) => r.id), disjointFailures }, null, 2));
  } else {
    console.log("");
    console.log(formatMarkdownTable(rows, definitions));
    if (options.names) {
      for (const row of rows) {
        console.log(`\n#### ${row.id} — ${row.kills} killed`);
        for (const name of row.killedTests) console.log(`  - ${name}`);
      }
    }
    for (const failure of disjointFailures) {
      console.log(
        `\nINVARIANT VIOLATED: ${failure.a} and ${failure.b} were declared to have ` +
          `disjoint kill sets but share ${failure.overlap.length}:\n  ` +
          failure.overlap.join("\n  ")
      );
    }
    for (const row of drifted) {
      console.log(
        `\nDRIFT: ${row.id} killed ${row.kills}, definition says ${row.expectedKills}. ` +
          `Re-measure and update the definition — this is exactly the drift the table had before.`
      );
    }
    if (survivors.length > 0) {
      console.log("");
      for (const row of survivors) {
        console.log(
          `\u001b[41m\u001b[97m SURVIVOR \u001b[0m ${row.id} — ${row.title}\n` +
            `  No test observes this. The property is claimed${row.property ? `: ${row.property}` : ""}\n` +
            `  but nothing holds it. Write the test, do not delete the row.`
        );
      }
    }
  }

  if (options.check && (survivors.length > 0 || drifted.length > 0 || disjointFailures.length > 0)) {
    return EXIT_SURVIVOR;
  }
  return EXIT_OK;
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error(`\n${error.message ?? error}`);
    const failure = restoreAllSync();
    releaseLockSync();
    process.exit(failure ? EXIT_RESTORE_FAILED : EXIT_BAD_DEFINITION);
  });
