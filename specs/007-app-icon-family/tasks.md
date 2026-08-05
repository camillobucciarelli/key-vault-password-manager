# 007 — Tasks

- [ ] **T1** Create `icons/`; copy `specs/_design/keyvault-mark.svg` and
      `keyvault-mark-foreground.svg` into it. Verify the geometry against
      `specs/_design/ICONS.md` §1 element by element (ring r 31 stroke 10, hand
      M50 50→74 26 stroke 10 round, hub r 14, four notches r 5 at N/E/S/W, group
      `scale(.75)` about the centre, draw order background → ring → hand → hub →
      notches).
- [ ] **T2** Derive `icons/keyvault-mark-monochrome.svg`: every `stroke`/`fill`
      hex → `#ffffff`, `fill="none"` preserved, no background rect.
- [ ] **T3** `tool/build_icons.sh`: render the three SVGs at 4× and downsample to
      the nine PNGs of spec FR-2 (1024/1024/1024/512/192/128/48/32/16). No extra
      padding, no rounding. Make it idempotent and runnable from the repo root.
- [ ] **T4** Run it; verify each PNG's exact pixel size and that
      `keyvault-source-1024.png` has **no alpha channel**.
- [ ] **T5** Badged extension variants: `icons/state/ext-{16,32,48}-locked.png`
      (icon 45 %, solid `#a19786` badge) and `-nohost.png` (icon 45 %, solid
      `#f6a06b`). Badge diameter 28 % of the icon, 2 px ring in the toolbar
      background. The N-matches badge is drawn at runtime by `chrome.action`
      (spec 006 T14) — no asset needed.
- [ ] **T6** `pubspec.yaml`: apply the `flutter_launcher_icons` block from spec
      FR-3 verbatim, including `adaptive_icon_background: "#FFE1D0"`. Update
      `flutter: assets:` to the new in-app mark. **Do not touch `version:`.**
- [ ] **T7** `flutter pub run flutter_launcher_icons`; confirm Android, iOS,
      macOS, Windows and web assets regenerate.
- [ ] **T8** Copy `ext-{16,32,48,128}.png` into
      `desktop/browser_extension/icons/icon-{16,32,48,128}.png`. Leave
      `manifest.json` unchanged — the paths already match.
- [ ] **T9** Visual check on Android: circle, squircle and rounded-square masks —
      ink stays inside the safe zone, nothing clipped.
- [ ] **T10** Visual check at 16 px in the Chrome toolbar: hub, hand and ring
      remain distinguishable.
- [ ] **T11** Sweep `rg -n 'keyvault-source\.png|keyvault-monochrome\.png' . -g '!specs/**'`;
      fix any hit, then delete `assets/logo/keyvault-source.png` and
      `assets/logo/keyvault-monochrome.png`.
- [ ] **T12** `flutter analyze` clean, `flutter test` green, app builds and
      launches with the new launcher icon.
