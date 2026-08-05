# 006 — Security, autofill, extension (journeys 10–12)

**Status**: Draft · **Kind**: Restyle · **Depends on**: 001, 002
**Design source**: `10-12 Sicurezza, autofill, estensione.dc.html`,
`specs/_design/PIXEL_SPEC.md` §4 (Settings, Browser setup, Extension popup),
`14 Dark mode.dc.html` (settings, extension popup).

> The in-page autofill overlay shown in the same design file is **spec 009**.
> This spec restyles the popup and its four states; 009 adds a content script.

## Why

Settings is currently reachable only through `vault_navigation.part.dart`'s
dialogs; the lock overlay has no design; and the extension popup is the only
HTML surface in the product, so it needs the tokens ported to CSS rather than
Flutter.

## Screens

| # | Screen | Surface | Golden |
| --- | --- | --- | --- |
| 1 | Settings destination | Flutter | 390×844 L+D, 1024×768 L |
| 2 | Change master password | Flutter screen | 390×844 L |
| 3 | Confirm security changes | Flutter sheet | 390×844 L |
| 4 | Lock overlay | Flutter overlay | 390×844 |
| 5 | Privacy overlay | Flutter overlay | 390×844 |
| 6 | iOS autofill enablement | Flutter screen | 390×844 L |
| 7 | Link AutoFill credential | Flutter sheet | 390×844 L |
| 8 | Browser setup, 3 steps | Flutter screen | 1024×768 L |
| 9 | Host-not-found diagnostic | Flutter screen | 1024×768 L |
| 10 | Popup — matches | HTML 400 px | screenshot L+D |
| 11 | Popup — app locked | HTML 400 px | screenshot L |
| 12 | Popup — host not found | HTML 400 px | screenshot L |
| 13 | Popup — possible-only matches | HTML 400 px | screenshot L |

## Functional requirements

### FR-1 · Settings destination

Two groups, `labelUpper` group labels, standard rows, 16 section gap:

**Database** — file name, Biometric protection (`KvSwitch`), Lock on inactivity,
Change master password, Key file.
**App** — Appearance, Autofill & browsers, Backups & import.

Plus **"Close database"** as a secondary pill with `linkText` (accent-800) text.

Theme selector (Appearance): three equal pills, padding 9, radius 999, selected
`actionFill` / `actionText`. Values map 1:1 to the three `ThemeCubit` values —
Light / Dark / System. No new state.

### FR-2 · Change master password

The three real fields, unchanged. Then a `Confirm security changes` →
`Confirm and apply` sheet that lists explicitly **what changes** and **what
stays** (key file, biometrics, Drive link, entries). Per the constitution, a
dated local copy is written before the re-key.

### FR-3 · Lock and privacy overlays

- **Lock overlay**: dark full screen; states how long the vault has been locked;
  offers Face ID, master password, or closing the database. App mark 76 radius 24.
- **Privacy overlay** (app backgrounded): the same dark ground with the mark
  only — **no text**, so nothing leaks into the OS app switcher.

Auto-lock keeps the existing inactivity timer plus the 30 s background rule.

### FR-4 · iOS autofill enablement

The three system steps, plus an explicit statement of what is shared with the
system credential store: **titles, usernames and sites — not passwords**.
That statement is a security claim; it must match what
`AppleAutofillV2Coordinator` / `SharedAutofillStore` actually publish. If the
implementation ever publishes more, this screen changes with it.

### FR-5 · Link AutoFill credential sheet

`Target` / `Entry` / `Username` rows with **Reject** / **Link** actions. Drives
the existing pending-association flow, unchanged.

### FR-6 · Desktop browser setup

`browser_setup_screen.dart` in three steps, keeping its **Italian** labels
verbatim — "Carica l'estensione beta", "Registra Native Messaging Host",
"Ho fatto", "Estensione caricata ✓", "Incolla" — with the copyable install
command.

Step cards radius 24 padding 16: done card `positiveTint` with a 40 square check;
active card `surface` with a numbered 40 square `actionFill`; pending card at
60 % opacity. Command block radius 18 padding 12/14, background `neutral900`,
mono 11.5 `neutral100`, 30 px copy button.

Host-not-found diagnostic names `dev.camillobucciarelli.keyvault_native_host`
and the three likely causes.

### FR-7 · Extension popup (HTML/CSS)

Width **400**. Header 38 tall on `neutral-200`, mark 22 radius 7, title 12.5/600,
beta tag right. Body padding 14, gap 12.

- Two status cards, flex-1, radius 14, padding 10/12, micro label 10 uppercase +
  value 13/600: **Native host** and **App-vault bridge**.
- Current-tab row radius 14 padding 10/12 with a 26 square — the tab is detected
  automatically.
- Match rows radius 14 padding 11/12, title 13/600, meta 11, `strong` **text**
  label (never colour-only), Fill button padding 7/12 radius 999 `accent-300`.
- Global search field height 34 radius 999.
- Footer privacy note 11 `neutral-600`, line-height 1.5.

States:
- **app locked** — the popup says so and offers to focus the app;
- **host not found** — "Show me how" / "Check again";
- **possible-only matches** — the action is **"Ask app"**, which creates a
  pending association rather than filling.

Dark mode via `prefers-color-scheme`, using the dark token mapping.

### FR-8 · Extension toolbar badges

Per `specs/_design/ICONS.md` §1: badge diameter 28 % of the icon, 2 px ring in the
toolbar background.

| State | Icon | Badge |
| --- | --- | --- |
| Ready, no matches | 100 % | none |
| App locked | 45 % | solid `#a19786` |
| Native host missing | 45 % | solid `#f6a06b` |
| N matches | 100 % | `#aebf92` pill, count in `#272e1b`, 10 px bold |

`chrome.action.setIcon` with pre-rendered PNGs + `setBadgeText` /
`setBadgeBackgroundColor`.

## Acceptance criteria

1. All 13 screens match their golden/screenshot.
2. The Italian browser-setup labels are byte-identical (string diff).
3. Privacy overlay renders **no text nodes** (assert zero `Text` widgets).
4. Theme selector maps exactly to the three `ThemeCubit` values; no fourth option.
5. `strong` / `possible` in the popup are text labels; a greyscale screenshot
   still distinguishes them.
6. Popup CSS carries no colour literal that is not in `specs/_design/tokens.css`.
7. Badge state changes are driven by the background service worker and survive a
   worker restart (state re-derived, not cached in memory only).
8. The iOS enablement screen's "what is shared" list matches the fields actually
   published by the autofill coordinator — verified by a test that reads the
   published payload keys.

## Out of scope

- The in-page overlay and its content script — **spec 009**.
- Any change to the native-messaging protocol.
- Regenerating the extension icon PNGs — **spec 007**.
