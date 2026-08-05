# 007 — App icon family "Combinatore" (journey 13)

**Status**: Draft · **Kind**: Restyle · **Depends on**: —
**Design source**: `13 Icona app & estensione.dc.html`,
`specs/_design/ICONS.md` §1, `specs/_design/keyvault-mark.svg`,
`specs/_design/keyvault-mark-foreground.svg`.

## Why

The current mark (`assets/logo/keyvault-source.png`) is superseded. Direction
**3d "Combinatore"** was chosen: a peach dial ring with a dark hub and hand and
four sage notches — readable at 16 px in a browser toolbar and safe inside
Android's adaptive mask. This spec is independent of the restyle and can ship
first.

## Functional requirements

### FR-1 · Geometry (exact)

Canvas 100 × 100 units, square, full bleed. All ink inside
`transform="translate(50,50) scale(.75) translate(-50,-50)"`.

| Element | Geometry | Paint |
| --- | --- | --- |
| Background | `rect 0,0 100×100` | `#ffe1d0` |
| Dial ring | `circle cx 50 cy 50 r 31` | stroke `#f6a06b` width 10, no fill |
| Hand | `path M50 50 74 26` | stroke `#402310` width 10, cap round |
| Hub | `circle cx 50 cy 50 r 14` | fill `#402310` |
| Notch N | `circle cx 50 cy 19 r 5` | `#ccdbb2` |
| Notch E | `circle cx 81 cy 50 r 5` | `#ccdbb2` |
| Notch S | `circle cx 50 cy 81 r 5` | `#ccdbb2` |
| Notch W | `circle cx 19 cy 50 r 5` | `#ccdbb2` |

Draw order: background → ring → hand → hub → notches. The hand is drawn **before**
the hub so the hub covers its inner end. No gradient, no shadow, no rounded
corners on the artwork — the OS applies the mask.

After the 0.75 scale the ink box is x 26.5→73.5, y 23→77 — inside Android's safe
band 19.4→80.6 (66/108).

### FR-2 · Exports

| File | Size | Background | Target |
| --- | --- | --- | --- |
| `icons/keyvault-source-1024.png` | 1024 | `#ffe1d0` | `image_path`, iOS dark/tinted |
| `icons/keyvault-adaptive-foreground-1024.png` | 1024 | transparent | `adaptive_icon_foreground` |
| `icons/keyvault-monochrome-1024.png` | 1024 | transparent, white ink | `adaptive_icon_monochrome` |
| `icons/app-512.png` | 512 | `#ffe1d0` | `web/icons/Icon-512.png`, `Icon-maskable-512.png` |
| `icons/app-192.png` | 192 | `#ffe1d0` | `web/icons/Icon-192.png`, `Icon-maskable-192.png` |
| `icons/ext-128.png` | 128 | `#ffe1d0` | extension `icons/icon-128.png` |
| `icons/ext-48.png` | 48 | `#ffe1d0` | extension `icons/icon-48.png` |
| `icons/ext-32.png` | 32 | `#ffe1d0` | extension `icons/icon-32.png` |
| `icons/ext-16.png` | 16 | `#ffe1d0` | extension `icons/icon-16.png` |

Render at 4× and downsample. No extra padding, no rounding.
Monochrome = the foreground SVG with every `stroke` and `fill` set to `#ffffff`.

### FR-3 · `pubspec.yaml`

Only the paths and one value change. **Never touch `version:`** — the release
workflow owns it.

```yaml
flutter_launcher_icons:
  image_path: icons/keyvault-source-1024.png            # was assets/logo/keyvault-source.png
  android: true
  ios: true
  remove_alpha_ios: true
  adaptive_icon_background: "#FFE1D0"                   # was "#FFFFFF"
  adaptive_icon_foreground: icons/keyvault-adaptive-foreground-1024.png
  adaptive_icon_monochrome: icons/keyvault-monochrome-1024.png
  image_path_ios_dark_transparent: icons/keyvault-adaptive-foreground-1024.png
  image_path_ios_tinted_grayscale: icons/keyvault-monochrome-1024.png
  desaturate_tinted_to_grayscale_ios: true
  web: { generate: true }
  windows: { generate: true }
  macos: { generate: true }
```

Add the in-UI mark files under `flutter: assets:` — the mark is rendered inside
the app (unlock, lock overlay, database list header, tablet rail).

### FR-4 · In-app usage

| Where | Size | Radius |
| --- | --- | --- |
| Tablet/desktop rail | 38 | 13 |
| Database list header | 40 | 14 |
| Welcome screen | 88 | 26 |
| Lock overlay | 76 | 24 |
| Extension popup header | 22 | 7 |
| In-page overlay header | 18 | 6 |

### FR-5 · Extension state badges

Assets only in this spec (the logic is spec 006 T14): pre-render the three badged
variants at 16/32/48. Badge diameter 28 % of the icon, 2 px ring in the toolbar
background colour.

| State | Icon opacity | Badge |
| --- | --- | --- |
| Ready, no matches | 100 % | none |
| App locked | 45 % | solid `#a19786` |
| Native host missing | 45 % | solid `#f6a06b` |
| N matches | 100 % | `#aebf92` pill, count `#272e1b` 10 px bold (drawn at runtime) |

### FR-6 · Retire the old marks

`assets/logo/keyvault-source.png` and `keyvault-monochrome.png` are superseded.
Remove them from `pubspec.yaml` assets and delete once no reference remains.

## Acceptance criteria

1. `icons/` contains all nine PNGs at the exact stated sizes.
2. `flutter pub run flutter_launcher_icons` succeeds on all six platforms.
3. Android: the adaptive foreground's ink stays inside the safe zone at
   circle, squircle and rounded-square masks (visual check on one device/emulator).
4. iOS: no alpha in the source icon (`remove_alpha_ios` satisfied).
5. Web `Icon-192/512` and their maskable twins are regenerated.
6. Extension `icons/icon-{16,32,48,128}.png` replaced; the manifest is unchanged
   (same four paths).
7. `rg -n 'keyvault-source\.png|keyvault-monochrome\.png' .` returns nothing
   outside `specs/`.
8. The 16 px extension icon is still legible — hub, hand and ring distinguishable.

## Out of scope

- Badge rendering logic and `chrome.action` wiring — spec 006.
- Any splash-screen or notification icon (not in the design package).
