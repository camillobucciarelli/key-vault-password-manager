# 006 — Tasks

- [x] **T0** Snapshot the Italian labels of `browser_setup_screen.dart` and the
      settings/master-password strings into `test/fixtures/strings_006_before.txt`.

## Flutter — settings & security

- [ ] **T1** `vault_settings.part.dart`: two groups with `labelUpper` labels and
      16 section gap. Database — file name, Biometric protection `KvSwitch`,
      Lock on inactivity, Change master password, Key file. App — Appearance,
      Autofill & browsers, Backups & import. Plus "Close database" as a
      `KvPillButton.secondary` with `linkText` text.
- [x] **T2** Theme selector: three equal pills, padding 9, radius 999, selected
      `actionFill`/`actionText`, mapped 1:1 to the three `ThemeCubit` values.
- [x] **T3** Change-master-password screen: the three existing fields unchanged,
      then a `Confirm security changes` → `Confirm and apply` `KvBottomSheet`
      listing what changes and what stays (key file, biometrics, Drive link,
      entries). Write a dated local copy before the re-key (constitution §VII) —
      add it if it does not exist yet.
- [x] **T4** `vault_lock_overlay.part.dart`: dark full screen, mark 76 r 24,
      "locked for <duration>", three actions — Face ID, master password, close
      database. Keeps the existing inactivity timer + 30 s background rule.
- [x] **T5** Privacy overlay: same dark ground, mark only, **zero text nodes**.

## Flutter — autofill

- [ ] **T6** `autofill_enablement_screen.dart` (iOS): the three system steps plus
      the "what is shared" statement — titles, usernames, sites; **not**
      passwords.
- [x] **T7** `Link AutoFill credential?` `KvBottomSheet`: Target / Entry /
      Username rows, Reject / Link actions, wired to the existing pending
      association flow unchanged.
- [x] **T8** `browser_setup_screen.dart`: three step cards radius 24 padding 16 —
      done `positiveTint` + 40 square check, active `surface` + numbered 40 square
      `actionFill`, pending 60 % opacity. Command block radius 18 padding 12/14,
      `neutral900` bg, mono 11.5 `neutral100`, 30 px copy button. **Italian labels
      byte-identical.**
- [x] **T9** Host-not-found diagnostic naming
      `dev.camillobucciarelli.keyvault_native_host` and the three likely causes.

## Extension

- [x] **T10** `desktop/browser_extension/tokens.css`: the token subset the popup
      uses, generated from `specs/_design/tokens.css` (same hex values, no
      hand-typed colours).
- [x] **T11** `popup.html` structure: header 38 (mark 22 r 7, title 12.5/600,
      beta tag right); body padding 14 gap 12; two status cards (Native host,
      App-vault bridge) flex-1 radius 14 padding 10/12 with a 10 px uppercase
      micro label + 13/600 value; current-tab row radius 14 padding 10/12 with a
      26 square; match list; search field h 34 r 999; footer note 11.
- [x] **T12** `popup.css`: the above geometry on the tokens, width 400,
      `--shadow-md`, plus a `prefers-color-scheme: dark` block using the dark
      mapping.
- [x] **T13** `popup.js`: the four states — matches (rows radius 14 padding 11/12,
      title 13/600, meta 11, `strong` **text** label, Fill button padding 7/12
      radius 999 `accent-300`), app locked, host not found ("Show me how" /
      "Check again"), possible-only (action "Ask app" → pending association).
- [ ] **T14** `background.js`: the badge state machine from plan §Badge state
      machine, re-derived on `tabs.onActivated`, `tabs.onUpdated`, host
      connect/disconnect and app lock/unlock. Uses `chrome.action.setIcon` with
      the pre-rendered state PNGs + `setBadgeText`/`setBadgeBackgroundColor`.
      No state kept only in worker memory.

## Verify

- [x] **T15** Tests:
      - string diff vs `strings_006_before.txt` empty (Italian labels intact);
      - privacy overlay renders zero `Text` widgets;
      - theme selector exposes exactly three options;
      - the iOS "what is shared" list equals the payload keys actually published
        by the autofill coordinator.
- [ ] **T16** Goldens for screens 1–9; manual screenshots for popup states 10–13
      in light and dark.
- [ ] **T17** Greyscale check: `strong` vs `possible` still distinguishable.
- [x] **T18** `rg -n '#[0-9a-fA-F]{6}' desktop/browser_extension/popup.css` — every
      hit must exist in `tokens.css`.
- [ ] **T19** Load the unpacked extension and verify all four badge states,
      including after forcing a service-worker restart.
- [x] **T20** `flutter analyze` clean, `flutter test` green.
