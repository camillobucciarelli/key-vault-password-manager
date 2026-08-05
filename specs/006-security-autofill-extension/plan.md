# 006 — Plan

## Approach

Two disjoint surfaces, done in either order:

- **Flutter side** — settings destination, master-password flow, overlays,
  autofill enablement, browser setup. All re-layout on the `Kv*` kit; the only
  new logic is the pre-re-key backup (constitution §VII) if it does not exist yet.
- **Extension side** — `popup.css` gets the Organic tokens as CSS custom
  properties (copy `specs/_design/tokens.css` into it, trimmed to what the popup
  uses), `popup.html` is restructured to the design, `background.js` gains badge
  state management.

The extension is the one place where the design's HTML can be adapted rather than
re-implemented — but it is still a rewrite against the tokens, not a paste of the
`.dc.html`.

## Files

### New

| Path | Contents |
| --- | --- |
| `.../screens/vault/vault_settings.part.dart` (from 002) | FR-1 content |
| `.../screens/vault/vault_lock_overlay.part.dart` | FR-3 |
| `.../screens/autofill_enablement_screen.dart` | FR-4 |
| `desktop/browser_extension/tokens.css` | the popup's token subset |
| `desktop/browser_extension/icons/state/*.png` | pre-rendered badge-state icons (assets come from spec 007) |
| `test/features/.../settings_test.dart`, `lock_overlay_test.dart` | |
| `test/goldens/settings_*.png`, `lock_*.png`, `browsersetup_*.png` | |

### Modified

| Path | Change |
| --- | --- |
| `.../screens/vault/vault_navigation.part.dart` | settings surfaces already moved in 002; here they get their design |
| `.../screens/vault/vault_shell.part.dart` | lock + privacy overlay hookup |
| `.../screens/browser_setup_screen.dart` | 3 step cards + command block, Italian labels untouched |
| `desktop/browser_extension/popup.html` | new structure (header, status cards, tab row, matches, search, footer) |
| `desktop/browser_extension/popup.css` | tokens + component rules, `prefers-color-scheme` dark |
| `desktop/browser_extension/popup.js` | render the four states; `strong`/`possible` as text |
| `desktop/browser_extension/background.js` | badge state machine + `setIcon`/`setBadgeText` |

## Badge state machine

```
derive(state) from: hostReachable, appUnlocked, matchCount(activeTab)
  !hostReachable          → icon 45 %, badge solid #f6a06b
  !appUnlocked            → icon 45 %, badge solid #a19786
  matchCount > 0          → icon 100 %, badge #aebf92 with the count
  otherwise               → icon 100 %, no badge
```

Re-derived on `chrome.tabs.onActivated`, `onUpdated`, native-host connect/disconnect
and app lock/unlock messages — never cached only in worker memory, since MV3
service workers are killed aggressively.

## Sequencing

```
Flutter:  T1 settings ─ T2 theme selector ─ T3 master password + confirm sheet
          T4 lock overlay ─ T5 privacy overlay
          T6 iOS enablement ─ T7 link-credential sheet
          T8 browser setup ─ T9 host diagnostic
Extension: T10 tokens.css ─ T11 popup.html ─ T12 popup.css ─ T13 popup.js states
           T14 background badges
Verify:    T15 tests ─ T16 goldens/screenshots
```

## Risks

| Risk | Mitigation |
| --- | --- |
| The "not passwords" claim on the iOS screen drifts from reality | T15 asserts against the published payload keys; if a password field ever appears, the test fails |
| MV3 worker restart loses badge state | Re-derive from storage + a fresh host ping on every wake |
| Translating Italian labels by accident | Snapshot them first; the diff test is the guard |
| Popup dark mode diverging from the app | Both read the same token values; the popup's `tokens.css` is generated from `specs/_design/tokens.css`, not hand-typed |

## Verification

```bash
flutter analyze && flutter test
# extension
desktop/browser_extension/package_extension.sh
# load unpacked, then check: matches, locked, host-missing, possible-only
```
