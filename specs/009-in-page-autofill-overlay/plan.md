# 009 — Implementation plan

## Delivery rule

Ship Slice A alone. Start Slice B only after app-owned settings, generation, and
pending-new-entry contracts exist. Security/protocol tests precede overlay visual
work.

## Current code to extend

| Path | Current responsibility | Required direction |
| --- | --- | --- |
| `desktop/browser_extension/manifest.json` | MV3; `activeTab`, `nativeMessaging`, `scripting` only | add `storage` and optional HTTP(S) hosts; no static content script/always-on hosts |
| `desktop/browser_extension/background.js` | extension-page sender check; native v2 timeout/forwarding | split sender trust paths, exact-origin validation, focus grants, lifecycle reconciliation |
| `desktop/browser_extension/popup.{html,js,css}` | metadata search and explicit popup fill | exact-origin opt-in controls and capability state |
| `desktop/browser_extension/package_extension.sh` | explicit runtime ZIP allowlist | add overlay runtime files; continue excluding tests/debug files |
| `desktop/browser_extension/README.md` | current popup/native host setup | document new permissions, per-origin opt-in/revoke, frame limits, tests, package contents |
| `tool/native_host_protocol.dart` | v2 parser, metadata query, pending association, reveal | exact-origin query/reveal authorization; later generation type only in Slice B |
| `tool/native_host.dart` | framed stdio loop | no architectural change; retain redacted stderr and bounded messages |
| `desktop/native_host/manifests/{chrome,edge}/*.json` | exact extension `allowed_origins` | no permission widening; description/version update only if protocol capability changes |
| `lib/.../desktop_browser_autofill_cache.dart` | metadata, existing-entry pending associations, bridge descriptor | Slice A exact-origin helpers plus cache/bridge generations; Slice B keeps separate pending-new-entry model |
| `lib/.../desktop_browser_autofill_reveal_bridge_service.dart` | authenticated loopback `/status` + `/reveal` | exact origin and database/cache/bridge binding; Slice B endpoint only after contract tests |
| `lib/.../desktop_browser_autofill_coordinator.dart` | publish/start and lock/database cleanup | ensure new Slice B pending generation clears through same lifecycle |
| `lib/.../password_generator_service.dart` | secure generation from supplied options | reuse in Slice B; do not move generation into extension/native host |
| `lib/.../vault_dialog_password.part.dart` | dialog-local options reset to defaults | evidence current shared settings contract is absent; Slice B must define ownership first |
| `test/tool/native_host_test.dart` | v2 framing and protocol security | exact-origin and later generation capability tests |

`web/manifest.json` and `web/index.html` are Flutter web/PWA files, not browser
extension manifests. This feature does not modify them.

## Proposed extension files

Keep file count small and security logic testable:

| Path | Purpose |
| --- | --- |
| `desktop/browser_extension/overlay_security.js` | pure origin normalization, strict shape checks, sender classification/binding helpers; usable by worker and Node harness |
| `desktop/browser_extension/content_overlay.js` | isolated-world focus session, metadata UI, explicit fill, ARIA, teardown |
| `desktop/browser_extension/test/fixtures/origin_canonicalization_v1.json` | one canonical origin corpus consumed unchanged by Node and Dart tests |
| `desktop/browser_extension/test/overlay_security.test.js` | Node built-in `node:test` harness with fake MessageSender/chrome state |
| `desktop/browser_extension/test/content_overlay.test.js` | small DOM/fake-port harness for stale response, teardown, keys, no submit, frame states |
| `desktop/browser_extension/test/visual_inventory.test.js` | asserts exact 18 screenshot basenames from `spec.md` |
| `desktop/browser_extension/test/visual_environment_v1.json` | immutable canonical OS/browser/font/rendering lock |
| `desktop/browser_extension/test/visual_baselines_v1.sha256` | approved expected PNG hashes |
| `desktop/browser_extension/test/run_visual_baselines.sh` | verify lock, deterministic capture, pixel/hash comparison |
| `lib/features/password_manager/domain/repositories/password_generator_settings_repository.dart` | Slice B global app settings contract |
| `lib/features/password_manager/data/repositories/shared_preferences_password_generator_settings_repository.dart` | Slice B versioned non-secret persistence |

No CSS generator or new dependency. Keep overlay CSS as a static template inside
`content_overlay.js` unless size proves unmanageable. Reuse current popup colors
where practical. Tests use Node standard library; DOM behavior may use a minimal
local fake rather than adding npm infrastructure.

## Slice A stages

### A0 — executable security contract

Write failing automated JS tests before UI:

- classify extension page versus content script;
- reject missing/extra/wrong-typed message fields;
- derive frame origin from `sender.url`, top origin from `sender.tab.url`;
- consume shared `origin_canonicalization_v1.json` and distinguish scheme, host,
  effective port, IDNA, IPv6, userinfo, trailing dot, canonical/noncanonical IPv4,
  invalid schemes, and phishing suffixes;
- enforce stored exact-origin enable plus actual permission;
- bind/revoke/expire focus token;
- bind grant/response to database id + cache/bridge generation and reject vault
  A → B reuse with same entry UUID/origin;
- reject stale async response after focus change, navigation simulation, and
  disable;
- cover top, same-origin frame, permitted cross-origin frame, and uninjected/
  unsupported cross-origin behavior;
- assert match message and persisted state shapes cannot carry password.

Use production validators directly in harness. Do not create a separate test-only
security implementation. Node test must iterate every shared fixture case and
assert fixture version/count/unique ids so silent case omission fails.

### A1 — native exact-origin authorization

Harden existing native v2 path before content UI can call it:

1. Canonicalize full HTTP(S) origin with scheme, host, and effective port.
   Use a new exact-origin helper; current
   `DesktopBrowserAutofillMetadataMapper.normalizedHost/normalizedOrigin` strips
   `www.`, `m.`, and `mobile.` prefixes and is not an authorization primitive.
2. `queryCredentials` overlay mode returns only metadata and marks which entries
   have exact `url` origin match. Domain/host results remain possible only.
   Response also returns current non-secret database id, cache generation, and
   bridge generation.
3. `revealForFill` requires exact origin at both
   `tool/native_host_protocol.dart` and app loopback reveal bridge. Remove
   `domain`/host fallback from origin-bound authorization.
4. Native host rechecks entry id, database id, exact origin, response id/version,
   expected cache/bridge generations, byte bounds, timeout, and app unlock. App
   bridge independently validates same expected tuple under current session epoch
   before credential lookup and before response. Native host re-reads current
   cache/descriptor after bridge response; query also confirms captured generation
   unchanged before return.
5. `hello` advertises exact-origin overlay capability. Background fails closed if
   old host/app does not advertise it.

Prefer a backward-compatible capability/strict policy field within protocol v2 if
old peers fail closed. If that cannot be guaranteed, add a new request type rather
than interpreting old host-only “strong” results as safe. Do not bump protocol
version without migration need.

Target tests live in `test/tool/native_host_test.dart` and
`test/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service_test.dart`.
Both Dart suites load same
`desktop/browser_extension/test/fixtures/origin_canonicalization_v1.json`; no
second Dart-only expected-value table is allowed.
Add delayed-response regression: issue grant on vault A, republish vault B with
identical entry UUID/origin, then prove old token/request/response returns
`stale_session` and cannot expose B secret.

### A2 — permissions and registration lifecycle

1. Add manifest `storage` and `optional_host_permissions` for HTTP(S).
2. Popup computes active tab exact origin. Enable requests only corresponding
   browser match pattern, then writes exact origin after permission succeeds.
3. Dynamic content script registration uses isolated world, `document_idle`, and
   frame injection. Browser match pattern may span ports; content bootstrap and
   background authorization still require exact stored origin.
   Registration covers future documents. After a successful grant, also use
   `chrome.scripting.executeScript` on current tab with `allFrames: true`; browser
   injects only permitted frames. Content startup must be idempotent.
4. Disable first atomically replaces durable `overlayConfigV1` with origin removed
   and revision incremented. Only after successful write/readback: invalidate
   grants, teardown frames, unregister unused script, remove unused permission.
   Derive shared permission use from committed enabled origins; do not persist
   mutable reference counts. Cleanup steps are idempotent.
5. Add deterministic crash hooks in test harness after durable commit, grant
   invalidation, frame teardown, script unregister, and permission removal. After
   each injected worker termination/restart, cold-start reconciliation must finish
   same disabled fail-closed state.
6. Reconcile storage, permission, registration, and live document state on every
   worker cold start/startup/install/permission change/popup open. Invalid/missing
   config means zero enabled origins; clear grants before other processing.
7. Every injected instance starts inert, sends bootstrap, and attaches page
   listeners only after background confirms exact origin remains enabled.

Do not rely on service-worker globals for durable enablement. Use globals only for
short-lived focus grants; cold start intentionally invalidates them.

### A3 — message routing and native timeout behavior

Refactor `background.js` around explicit route tables:

- extension-page route: status/query/search/current popup functions plus overlay
  enable/disable/state;
- content route: bootstrap, matches, fill only;
- unknown route/sender/shape: deterministic `forbidden` or `invalid_request`;
- no request-body URL forwarded until replaced by sender-derived exact origin;
- no fill forwarded until token's database/cache/bridge binding matches message;
- native reveal receives all expected binding fields and every success echo is
  verified before secret forwarding;
- map timeout/host/app lock/stale token/unsupported capability to stable codes;
- never log request/response payloads.

Continue one-shot `chrome.runtime.sendNativeMessage` with bounded timeout. No
long-lived native port or reconnect loop is needed. On timeout, close current
overlay state; next focus/user retry starts a fresh request. Worker cold start
rebuilds permission state but never reconstructs fill grants.

### A4 — metadata overlay and explicit fill

`content_overlay.js` responsibilities:

- eligible field detection without scanning hidden/disabled/read-only fields;
- one random focus nonce per focus session;
- current non-secret database/cache/bridge binding retained only in focus scope;
- ignore mismatched/stale nonce responses;
- closed shadow root for style isolation only;
- metadata rows: title + display service, never password or username;
- explicit click/Enter fill only;
- local secret handling, native value setter, bubbling `input` and `change`;
- no form submission;
- teardown on focus change, blur, Escape, pagehide, navigation/unload,
  visibility-hidden, permission disable message, anchor removal, timeout;
- best-effort reference clearing, no GC/performance claims.

Do not cache page prototypes as a security claim. Isolated world helps avoid page
JS monkey patches, but filled values/events remain observable by page.

### A5 — iframe and accessibility pass

- Validate frame sender independently from top tab.
- Support only frames with actual permission, registration, and injection.
- Show unsupported state where cross-origin frame focus is detectable; otherwise
  no overlay. Popup tells user to copy manually from app.
- Add listbox/option semantics, active descendant, polite live region, selected
  text, Escape/Tab/arrow/Enter behavior, and restoration of anchor ARIA state.
- Resolve pointer-down/blur/click race while preserving input focus.
- Ensure overlay buttons are not form-associated and Enter fill consumes exactly
  that action without submit.
- Test zoom, viewport clamp, scroll/resize, forced colors, reduced motion,
  light/dark mode after security tests pass.
- Capture and verify real browser screenshots because Flutter goldens do not own
  this DOM. Canonical authority is one Linux x86_64 OCI image by digest with exact
  Chrome for Testing version/revision/archive+binary SHA-256, OS/font hashes,
  locale/timezone/color/rendering flags in `visual_environment_v1.json`.
  Deterministic runner refuses mutable/mismatched environment, captures exact
  18-file inventory, compares decoded pixels and approved SHA-256 against
  `screenshots/expected/`, and rejects missing/extra files. Baseline changes need
  explicit human design approval. Windows/macOS/Edge use DOM/geometry/AT assertions
  and manual smoke, not independent pixel authority.

Closed-shadow active-descendant support varies by browser/accessibility stack.
Live-region announcement is required fallback; manual NVDA/Chrome and
VoiceOver/Chrome checks remain release gates.

### A6 — packaging and operator docs

Update `desktop/browser_extension/package_extension.sh` explicit ZIP allowlist to
include every new runtime JS file and nothing under `test/`. Update
`desktop/browser_extension/README.md` with:

- why `storage` and optional hosts are required;
- default-off exact-origin enable/revoke behavior;
- Chromium port-granularity limitation and runtime exact-origin check;
- frame/restricted-page limits;
- native host capability/registration compatibility;
- targeted test, syntax-check, package, and manual verification commands;
- no secret in extension storage/DOM/log policy.

No `web/` or unrelated docs change belongs to this spec implementation.

## Slice B stages — blocked

### B0 — app contracts and tests

Start B0 only after Slice A acceptance is complete. Before any Slice B protocol or
extension UI work, define app-side interfaces/models:

1. `GeneratorSettingsSnapshot`: global non-secret settings owned/persisted by app
   through `PasswordGeneratorSettingsRepository` and existing
   `SharedPreferences`; current dialog-local defaults do not count as contract.
   First install persists length 16 + all four sets. Schema v1/revision, migration,
   explicit reset, corruption/future-version fallback, failed-write behavior, and
   app Apply/Cancel/watch/stale-draft semantics follow `data-model.md`.
2. `PendingGeneratedEntry`: id, database id, exact origin, created/expiry times,
   state (`pending`, `consumed`, `rejected`, `expired`), and generated secret held
   only in unlocked app memory.
3. `generatePendingEntry(origin)`: app reads its settings, generates via existing
   `PasswordGeneratorService`, snapshots current settings revision and vault/cache/
   bridge tuple, owns pending record, returns one response.
4. Lock/database change/bridge stop/app exit clears all generated secrets and
   invalidates ids. Maximum expiry: five minutes.
5. Save consumes pending record into normal app new-entry flow; reject/expiry
   clears it. Extension never owns vault mutation.

Existing disk-backed `DesktopBrowserAutofillPendingAssociation` remains for
linking existing entries and must not be overloaded with generated plaintext.
Cleanup drops all reachable references best-effort; immutable Dart strings cannot
promise deterministic zeroization or GC timing.
Extension never receives/persists generator settings and cannot override them in a
generation request.

B0 targeted checks include:

```bash
flutter test \
  test/features/password_manager/data/repositories/shared_preferences_password_generator_settings_repository_test.dart \
  test/features/password_manager/data/services/desktop_browser_pending_generation_service_test.dart \
  test/features/password_manager/presentation/screens/vault/password_generator_settings_test.dart
```

### B1 — native capability and bridge

Add protocol request only after B0 passes. Suggested capability and type names:

- capability: `generatePendingEntryV1`;
- native request: `generatePendingEntry` with exact origin only;
- app bridge endpoint: `/generate-pending` authenticated by current bearer token;
- response: pending id, expiry, password; no settings echo and no persistence.

Validate ids, exact origin, response size, database binding, lock state, timeout,
cache/bridge generations, and capability. Native host must not cache response or
write it to files/logs. Binding mismatch is `stale_session`.

### B2 — extension Generate action

Show action only when capability negotiation succeeds and current focus grant is
valid. Explicit activation sends exact sender origin and focus token. Response is
nonce-checked, filled once, then references clear and overlay tears down.
Extension stores neither password nor pending id. Stale/late response is discarded
and app operation is rejected/expired through app contract.

## Browser/install risks

| Risk | Plan |
| --- | --- |
| Chromium host match patterns do not isolate ports | store exact origins; validate effective port on every message; disclose permission UI granularity |
| MV3 worker sleeps/restarts | persistent storage/registrations reconcile; focus grants fail closed and refresh |
| Already-injected JS cannot be unloaded | immediate teardown message plus server-side revision/token revocation |
| Worker crashes during disable | durable origin removal/revision commits first; idempotent cold-start reconciliation completes later phases; crash test after every phase |
| Restricted pages/frames reject injection | fail closed; show unsupported where detectable; manual app copy |
| Chrome/Edge API/version differences | test current stable Chrome and Edge; do not claim Firefox/Safari support |
| Closed Shadow DOM ARIA relation differences | live-region fallback plus NVDA/VoiceOver manual gate |
| Native host extension ID mismatch | keep exact single `allowed_origins`; reinstall/restart browser after ID/package change |
| Old native host lacks exact-origin/generation capability | capability negotiation disables affected action; never downgrade to host-only reveal |
| Vault switch/cache republish reuses entry UUID/origin | grant/reveal bind database + cache/bridge generations; every layer returns `stale_session` on mismatch |
| Pixel drift across OS/browser/font stacks | one immutable canonical Chrome/Linux lock owns expected pixels; other environments use DOM/geometry/AT assertions |

## Verification commands for implementation

Run from repository root:

```bash
python3 -m json.tool desktop/browser_extension/manifest.json >/dev/null
node --test desktop/browser_extension/test/*.test.js
node --check desktop/browser_extension/overlay_security.js
node --check desktop/browser_extension/content_overlay.js
node --check desktop/browser_extension/background.js
node --check desktop/browser_extension/popup.js
dart analyze tool
flutter test test/tool/native_host_test.dart \
  test/features/password_manager/data/services/desktop_browser_autofill_cache_test.dart \
  test/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service_test.dart \
  test/features/password_manager/presentation/coordinators/desktop_browser_autofill_coordinator_test.dart
./desktop/browser_extension/test/run_visual_baselines.sh --verify
./desktop/browser_extension/package_extension.sh
unzip -l desktop/browser_extension/dist/keyvault-browser-extension.zip
```

Then manually test unpacked extension in stable Chrome and Edge with registered
native host: fresh install, grant, exact scheme/port, frame cases, lock, worker
termination, disable while overlay open, navigation, pointer/keyboard/AT, and
package reload. Full Flutter suite is not required for this feature's docs or
targeted implementation validation.
