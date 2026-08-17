# 009 — Tasks

Order is mandatory: tests/security contract, native authorization, lifecycle,
behavior, accessibility, visuals. Slice B remains blocked until its app contracts
land.

## Slice A0 — baseline and automated security harness

- [ ] **A001** Record current baseline from
      `desktop/browser_extension/manifest.json`, `background.js`, `popup.js`,
      `tool/native_host_protocol.dart`, and reveal bridge. Confirm current protocol
      has no overlay/generation capability and current generator settings are
      dialog-local.
- [ ] **A002** Add `desktop/browser_extension/overlay_security.js` with pure,
      production-used canonical HTTP(S) origin, strict object-shape, and sender
      classification helpers. No dependency.
- [ ] **A003** Add Node built-in test harness under
      `desktop/browser_extension/test/`. Test extension-page sender path separately
      from content sender path; reject sender-path confusion, wrong runtime id,
      extension URL mismatch, missing tab/frame/sender URL, unknown keys, wrong
      types, and oversize values.
- [ ] **A004** Create shared
      `desktop/browser_extension/test/fixtures/origin_canonicalization_v1.json`
      with required IDs from `data-model.md`: IDNA Unicode/punycode, IPv6 compact/
      expanded, userinfo, trailing dot, default/non-default ports, canonical and
      odd/noncanonical IPv4, invalid schemes, and phishing suffix. Node tests load
      every fixture case, verify version/count/unique required IDs, and verify body
      origin equals normalized `sender.url`, not `sender.tab.url` or host.
- [ ] **A005** Test top-frame, same-origin child, permitted cross-origin child,
      disabled child origin, missing injection, sandboxed/opaque sender, and top
      URL/frame URL disagreement behavior.
- [ ] **A006** Test focus nonce/token bind, allowed entry id, sender tab/frame/
      document/origin, 30-second maximum expiry, one-shot consumption, permission
      revision, database id, cache generation, bridge generation, bounded eviction,
      worker-reset loss, and stale response after focus/navigation/disable. Test
      vault A → B with identical entry UUID + origin: A token and delayed A response
      return `stale_session` and cannot reveal B secret.
- [ ] **A007** Add shape assertions proving persisted config and all metadata
      messages reject `password`, `secret`, native payload dumps, username, and
      unknown fields. Tests must execute production validators, not copies.

**Gate A0**: `node --test desktop/browser_extension/test/*.test.js` passes before
overlay markup/CSS begins.

Enforced by CI, not by memory: the `extension-tests` job in
`.github/workflows/pr.yml` runs this command on every pull request to `main`, so
the gate holds across all later slices without anyone re-running it by hand. The
same job carries the `node --check` syntax gate for the extension sources that
exist today (`overlay_security.js`, `background.js`, `popup.js`). Any new runtime
JS file must be added to that job when it is created — the task that creates it
owns that obligation (see A028).

## Slice A1 — native exact-origin contract

- [ ] **A008** In `tool/native_host_protocol.dart`, define/advertise
      `overlayExactOriginV1` capability and strict overlay query policy (or a new
      request type if old-peer fail-closed behavior cannot be guaranteed). Add
      explicit non-secret `cacheGeneration` per metadata publish and
      `bridgeGeneration` per reveal-bridge start alongside database id.
- [ ] **A009** Add Dart tests first: exact URL origin matches; implicit/default
      port matches; scheme/non-default port/phishing suffix differs; domain-only
      identifier is possible metadata and cannot reveal. Include `www.`, `m.`,
      and `mobile.` label differences so current host-normalization prefix removal
      cannot become fill authorization. Dart tests consume same
      `origin_canonicalization_v1.json` and assert every case; no duplicated Dart
      expected-value table.
- [ ] **A010** Harden `queryCredentials` overlay mode to return bounded metadata
      only (`entryId`, `title`, `displayService`, exact/possible classification,
      fill eligibility) plus current database/cache/bridge binding. No username/
      password. Echo canonical target and strict policy so background can reject
      old-host downgrade. Snapshot tuple, then re-read/compare immediately before
      response; concurrent republish returns `stale_session`.
- [ ] **A011** Harden `revealForFill` origin-bound path in
      `tool/native_host_protocol.dart`: remove domain/host fallback, require exact
      normalized URL origin, exact entry/database/cacheGeneration/
      bridgeGeneration/policy, and current bridge. Add dedicated exact-origin
      helper; do not reuse current prefix-stripping host matcher. Any binding
      mismatch returns `stale_session` before app request.
- [ ] **A012** Apply same exact-origin authorization in
      `desktop_browser_autofill_reveal_bridge_service.dart`; host check and app
      bridge check must both pass for expected database/cache/bridge binding. App
      checks under one session epoch before lookup and response, then echoes binding.
      Native host re-reads cache/descriptor after bridge response and verifies it.
      Add tests for host-only denial and stale binding before secret response.
- [ ] **A013** Preserve current framing limits, response id/version checks,
      2/3-second bridge/background timeouts, direct loopback, bearer auth, redacted
      errors, and clear-on-lock/database-change behavior. Add fake delayed bridge
      regression for vault A → B using same UUID/origin; old request/response must
      be `stale_session`. Add no secret logging.
- [ ] **A014** Update current popup fill result eligibility/labels if stricter
      origin semantics would otherwise present domain-only entries as fillable.

**Gate A1**: targeted native/reveal tests pass. Old host lacking capability must
produce `unsupported_capability`, never host-only fallback.

## Slice A2 — manifest, opt-in, registration, revocation

- [ ] **A015** Update `desktop/browser_extension/manifest.json` only as follows:
      add `storage`; add
      `"optional_host_permissions": ["http://*/*", "https://*/*"]`. Keep MV3,
      `activeTab`, `nativeMessaging`, `scripting`. Add no `host_permissions`,
      static `content_scripts`, `<all_urls>`, `tabs`, `webNavigation`, clipboard,
      or remote code.
- [ ] **A016** Implement `overlayConfigV1` from `data-model.md`: sorted unique
      exact origins + revision only. Off by default. Enforce limits and migrate
      invalid/missing state to disabled.
- [ ] **A017** Add popup **Show the overlay on this site** control. Compute exact
      active-tab HTTP(S) origin; request one derived optional host pattern only
      from explicit popup user gesture; persist only after grant. Show unsupported,
      denied, enabled, disabled, and reconciliation states.
- [ ] **A018** Register `content_overlay.js` dynamically in isolated world at
      `document_idle`, including frames where browser allows. Registration match
      is browser permission pattern; bootstrap exact-origin check keeps other
      ports inert. Registration affects future documents, so after grant also
      inject current tab with `chrome.scripting.executeScript({allFrames: true})`;
      make startup idempotent and attach listeners only after bootstrap approval.
- [ ] **A019** Implement crash-consistent disable exactly: first atomically replace
      durable `overlayConfigV1` with target origin removed and revision incremented;
      await successful write/readback. Only afterward clear grants, broadcast
      teardown, unregister unused dynamic script, then remove unused optional
      permission. No cleanup side effect starts if durable commit fails. Derive
      sharing from committed origins; test two ports sharing one pattern.
- [ ] **A020** Implement fail-closed reconciliation before serving messages on
      every worker cold start, plus install/startup, popup open, and permission
      changes: validate durable config (invalid/missing = zero enabled), start with
      no grants, then reconcile permissions, registrations, and live teardown.
      Already-injected instance remains inert until approved bootstrap.
- [ ] **A021** Add deterministic crash injection after each disable phase: durable
      commit, grant invalidation, active-frame teardown, script unregister, and
      permission removal. Restart worker after each fault and assert identical
      disabled terminal state. Also test shared-pattern retention and unreachable
      injected script: JS cannot be unloaded, but durable revision denies every
      request immediately and reconciliation completes cleanup.

**Gate A2**: fresh install grants/injects nothing; grant and revoke behavior is
automated where possible and manually checked in Chrome.

## Slice A3 — background trust paths and focus grants

- [ ] **A022** Refactor `background.js` into explicit extension-page and content
      route allowlists. Preserve current popup routes under extension-page sender
      validator. Unknown sender/type/shape fails deterministically.
- [ ] **A023** For content bootstrap/matches/fill, derive authoritative frame
      origin from `sender.url`; validate tab id, frame id, optional document id,
      top context, exact stored origin, permission, and revision before native I/O.
- [ ] **A024** Issue random short-lived fill token only after exact-origin metadata
      query succeeds. Bind per `data-model.md`; include fill-eligible entry ids
      and exact database/cache/bridge generation only; bound/evict worker map;
      never persist token or binding.
- [ ] **A025** Consume token on explicit fill before accepting replay. Revalidate
      sender, capability, and message/grant binding, then forward sender-derived
      exact origin plus expected database/cache/bridge values to native host.
      Validate echoed success binding before forwarding secret. Never forward body
      URL as origin authority.
- [ ] **A026** Map timeout, no host, app locked, unsupported capability, disabled,
      unsupported frame, invalid request, forbidden, and stale session to stable
      non-sensitive error codes. Do not log messages/native responses.
- [ ] **A027** Confirm MV3 worker restart invalidates grants and next request
      recovers through fresh metadata query; no reconnect loop or durable token.
      New status/query tuple eagerly clears older grants; vault/cache/bridge
      mismatch still fails natively if worker has not observed republish.

**Gate A3**: JS harness covers sender validation, message shape, stale response,
teardown, origin/port/scheme, and frame behavior before visual UI work.

## Slice A4 — metadata overlay and explicit fill

- [ ] **A028** Implement eligible field detection in `content_overlay.js`: visible,
      enabled, writable password input; username/email autocomplete input only
      with associated eligible password field. New focus tears down old session
      and creates cryptographic nonce.
      Because this task creates the file, it must also register it in the two
      places that enumerate runtime files explicitly, in the same commit:
      1. add `node --check desktop/browser_extension/content_overlay.js` to the
         `Syntax check extension sources` step of the `extension-tests` job in
         `.github/workflows/pr.yml`, where it is currently omitted on purpose
         because the file does not exist yet;
      2. add it to the `zip` allowlist in
         `desktop/browser_extension/package_extension.sh` (see A042).
      Neither is a glob, so neither fails on its own if this is forgotten.
- [ ] **A029** Render closed-shadow metadata overlay only after successful
      bootstrap/matches response for current nonce. Rows expose title + display
      service only. No username/password in text, attributes, dataset, comments,
      globals, style, accessible names, or state object.
- [ ] **A030** Implement states: loading, exact matches, possible/no fillable
      matches, no matches, locked, native host unavailable/timeout, unsupported
      frame, stale/retry. Slice A Generate is absent/disabled with honest app text.
- [ ] **A031** Implement explicit fill. Verify current focus/nonce/token/origin/
      entry response; use local username/password only; best-effort blank mutable
      response fields; set native input values; dispatch bubbling `input` and
      `change`; never submit; clear references and teardown.
- [ ] **A032** Add executable secret-lifetime tests: match shapes and overlay DOM/
      attributes/storage/log capture/globals contain no password; fill input does;
      no test claims GC, heap erasure, performance-timeline invisibility, or
      inaccessible page value.
- [ ] **A033** Teardown on Escape, focus replacement/outside blur, pagehide,
      visibility hidden, navigation/unload, anchor disconnect, timeout, disable,
      permission removal, and stale revision. Abort listeners/observers/timers/
      animation frames, remove host, restore ARIA, null local references.
- [ ] **A034** Document/test Shadow DOM honestly: `host.shadowRoot === null` is
      style/collision isolation evidence only. Page observation of host layout,
      value, and events remains expected.

## Slice A5 — iframe, accessibility, behavior, visuals

- [ ] **A035** Implement frame policy exactly: top and injected same-origin frames
      supported; cross-origin frame only with child origin separately enabled,
      permitted, injected, and sender-validated; otherwise fail closed. Where
      detectable show unsupported state directing manual copy from KeyVault app.
      Add no extension clipboard path.
- [ ] **A036** Add `role=listbox`, `role=option`, `aria-selected`, stable option
      ids, `aria-activedescendant`, anchor combobox expanded state, and
      `role=status aria-live=polite` fallback. Restore original anchor ARIA on
      teardown.
- [ ] **A037** Keyboard: arrows move selection; Enter fills current eligible row
      and prevents only that action's default/propagation; Escape dismisses current
      focus session; Tab tears down and passes through. Closed overlay captures no
      page keys.
- [ ] **A038** Resolve click-vs-blur race: pointer-down inside overlay preserves
      anchor focus and marks pending action; deferred outside blur cannot remove
      row before click. Controls are `type=button`, outside page forms, and produce
      zero submit events.
- [ ] **A039** Test plain and framework-controlled input event delivery, no submit,
      no hidden/read-only fill, anchor removal, scroll/resize, viewport flip/clamp,
      zoom, forced colors, reduced motion, and light/dark mode. Required named DOM
      assertions: `renders every state with metadata-only DOM`, `anchors below,
      flips above, and clamps viewport`, `applies light/dark/forced-colors
      contract`, `exposes listbox/options/live state and restores ARIA`, and
      `teardown removes host/listeners and never submits`.
- [ ] **A040** Manual accessibility checks: keyboard-only; Chrome + NVDA on
      Windows; Chrome + VoiceOver on macOS where available. Record closed-shadow
      active-descendant limitation and verify live announcement fallback.
- [ ] **A041** Only after Gates A0–A3 and tasks A028–A040 pass, capture real
      unpacked-extension browser screenshots because Flutter goldens/widget tests
      do not render this DOM.
      Canonical acceptance uses one Linux x86_64 OCI digest and exact Chrome for
      Testing build pinned by `visual_environment_v1.json`, including browser/
      archive hashes, locale/timezone, OS/font hashes, color/rendering flags.
      Commit approved PNGs under `screenshots/expected/` and hashes in
      `visual_baselines_v1.sha256`; deterministic recapture writes `actual/` and
      compares decoded pixels + approved hashes. Add inventory test asserting 18
      exact basenames only as supplemental check. Reject mutable/mismatched env and
      unapproved baseline updates. Noncanonical Edge/Windows/macOS rely on A039 DOM/
      geometry assertions plus A040/manual smoke. Security wins over pixel parity.

## Slice A6 — packaging, README, release checks

- [ ] **A042** Update `desktop/browser_extension/package_extension.sh` explicit
      allowlist with `overlay_security.js` and `content_overlay.js` (plus any other
      actual runtime file). Keep `test/`, origin fixture, screenshots, debug hooks,
      visual environment/hash manifests, source maps, and secrets out of ZIP.
      Package listing test rejects them.
      The script lists every packaged file by name in the `zip` invocation; it is
      an allowlist, not a glob. A runtime file that is never added is silently
      left out of the ZIP — `zip` exits 0, the build is green, and the omission
      surfaces only at runtime in the installed extension as a missing script.
      Standing rule for the rest of this feature and after it: any task that adds
      a runtime file to `desktop/browser_extension/` updates this allowlist in the
      same commit. The packaging assertion below must therefore also assert that
      each expected runtime file is *present*, not only that excluded paths are
      absent.
- [ ] **A043** Update `desktop/browser_extension/README.md`: permissions and store
      justification; exact-origin opt-in/revoke; port-granularity caveat; dynamic
      injection/teardown; frame/restricted-page limits; worker cold-start recovery;
      exact-origin native capability; secret policy; Chrome/Edge native host setup;
      automated/manual commands; canonical visual environment/baseline verification
      and approval; package contents.
- [ ] **A044** Confirm native host templates/installers still contain one exact
      `chrome-extension://<id>/` in `allowed_origins`. Protocol capability does not
      require broader native host registration. Reinstall/restart only when host
      binary/extension id changed.
- [ ] **A045** Run the targeted checks that CI does **not** already run. The
      `extension-tests` job in `.github/workflows/pr.yml` runs Gate A0
      (`node --test desktop/browser_extension/test/*.test.js`) and `node --check`
      on every extension source — including `content_overlay.js` once A028 adds it
      — on each pull request, so repeating them here would add noise, not
      coverage. They are omitted below for that reason only.

      Not covered by any CI job:

      ```bash
      python3 -m json.tool desktop/browser_extension/manifest.json >/dev/null
      ./desktop/browser_extension/test/run_visual_baselines.sh --verify
      ./desktop/browser_extension/package_extension.sh
      unzip -l desktop/browser_extension/dist/keyvault-browser-extension.zip
      ```

      Covered only partially, so kept:

      ```bash
      # The `analyze` job runs `flutter analyze` across the whole project, which
      # includes `tool/`. Kept as the fast local form: CI reports it only after
      # a PR exists, and this narrows the output to the native host code.
      dart analyze tool

      # The `test` job runs the full suite minus goldens, so these files do
      # execute in CI. Kept because this is the targeted local form and because
      # it names the exact set a reviewer must see pass for this feature; the
      # whole-suite run does not make that set visible.
      flutter test test/tool/native_host_test.dart \
        test/features/password_manager/data/services/desktop_browser_autofill_cache_test.dart \
        test/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service_test.dart \
        test/features/password_manager/presentation/coordinators/desktop_browser_autofill_coordinator_test.dart
      ```

- [ ] **A046** Manual Chrome/Edge matrix: fresh install, grant/deny, scheme/port
      variants, exact/domain-only match, top/same/cross-origin frames, restricted
      page, app lock, host absent/timeout, worker termination, disable while open,
      crash/restart after every disable phase, navigation/stale native response,
      vault A → B stale token/response with same UUID/origin, keyboard/pointer/AT,
      package reload, and canonical baseline comparison. Edge smoke is not pixel
      authority.

**Slice A done**: all automated security/protocol checks pass before visual signoff;
no broad always-on permission; explicit exact-origin fill only.

## Slice B0 — app contracts (blocked until Slice A done; no extension Generate yet)

- [ ] **B001** After Slice A acceptance, define global non-secret
      `GeneratorSettingsSnapshot` schema v1/revision and app-owned
      `PasswordGeneratorSettingsRepository`; implement with existing
      `SharedPreferences` under `password_generator_settings_v1`, registered in
      `password_manager_data_di.dart`. First install persists length 16 and all
      four sets enabled. Extension never receives/persists settings. Reuse
      `PasswordGeneratorService`; dialog-local defaults are migration baseline only.
- [ ] **B002** Implement/test repository and app UI semantics: read/save/watch;
      atomic validated Apply/Save; Cancel no-op; explicit Reset commits defaults;
      known-version migration; missing first-install; corrupt JSON/type/range/no-set
      fallback to persisted defaults with redacted code; unknown future version
      defaults in memory without overwrite until explicit reset; failed write keeps
      last snapshot/no event; global UI consumers update once; generation snapshots
      latest committed revision. Clean open UI follows updates; dirty drafts retain
      edits and stale-revision Apply is rejected until reload/reapply. Test no
      native/extension settings override.
- [ ] **B003** Define separate in-memory `PendingGeneratedEntry` with app/database/
      cache/bridge generation, settings revision, exact-origin ownership, opaque
      id, created/expiry (`<= 5 minutes`), and pending/consumed/rejected/expired
      transitions. Do not reuse disk-backed `DesktopBrowserAutofillPendingAssociation`.
- [ ] **B004** Add tests first for generate, consume, reject, expiry, bounded
      pending set, clear-on-lock, database switch, vault close, reveal bridge stop,
      and app exit. Assert no generated secret reaches cache, descriptor, pending
      association file, or logs. Verify reference/record removal without claiming
      deterministic zeroization or garbage-collection timing.
- [ ] **B005** Connect pending record to normal app new-entry/save confirmation.
      App owns vault mutation; page/extension cannot auto-save.

**Gate B0**: Slice A is complete; settings repository/UI and pending-generation
lifecycle are explicit and tested in app. Otherwise stop; Generate remains
unavailable. Run:

```bash
flutter test \
  test/features/password_manager/data/repositories/shared_preferences_password_generator_settings_repository_test.dart \
  test/features/password_manager/data/services/desktop_browser_pending_generation_service_test.dart \
  test/features/password_manager/presentation/screens/vault/password_generator_settings_test.dart
```

## Slice B1 — native generation capability

- [ ] **B006** Add authenticated app bridge `/generate-pending` only after B0.
      Validate loopback bearer, database, unlock state, exact origin, bounds/rate,
      expected cache/bridge generation, and latest committed app settings. Return
      password + pending id + expiry + echoed binding/settings revision once.
- [ ] **B007** Add native protocol `generatePendingEntry` and advertise
      `generatePendingEntryV1` only when app endpoint/contract is available. Old
      peer returns unsupported capability.
- [ ] **B008** Add native tests for malformed request/response, origin scheme/port,
      locked/database mismatch, timeout, response size, capability negotiation,
      cache/bridge generation mismatch (`stale_session`), settings ownership/
      revision, expiry metadata, and no native-host persistence/logging.
- [ ] **B009** Ensure coordinator lock/database/close paths stop endpoint and clear
      pending generated secrets before descriptor removal completes.

## Slice B2 — explicit Generate UI

- [ ] **B010** Add Generate row only when capability exists. Request requires
      current sender-bound focus nonce/token and exact origin; no settings payload.
- [ ] **B011** On explicit click/Enter, nonce-check response, fill generated secret
      once, best-effort clear extension references, store neither password nor
      pending id, never submit, teardown.
- [ ] **B012** Test stale/late/replayed generation, disable/navigation during
      request, lock/expiry, no extension storage/DOM/log/global secret, and app
      pending ownership/cleanup.
- [ ] **B013** Update package README/UI copy to state app ownership, expiry, and
      save confirmation. Do not claim extension saves or remembers generated
      password.

**Slice B done**: B0/B1/B2 gates pass. No fallback generation in extension,
native host, or default settings.
