# 016 — Device evidence

Hardware observations for the tasks that cannot be proven any other way. Fill a
row in, state `pass` or `fail` explicitly, and record the versions: a verdict
without the IME or browser version is not evidence.

Nothing here is filled in by an agent. Every line is something someone watched
happen on a device.

## Devices used

| Label | Model | Android | API | Screen lock | Biometric enrolled |
|-------|-------|---------|-----|-------------|--------------------|
| D1    | Pixel 11 Pro | 17 | 37 | yes | yes |
| D2    | *(API 29 device still needed)* | | | | |

## T001 — inline suggestions on real IMEs (gates Phase 4 and T102)

Emulator IMEs do not advertise what real ones do. This needs a physical API 30+
device.

Observed on D1 (2026-08-28) against the real implementation rather than a
throwaway probe: the service was built with `supportsInlineSuggestions="true"`
and inline datasets, then the advertisement was read back from the live request.

| IME | Version | Renders inline? | maxSuggestionCount | Style spec | Verdict |
|-----|---------|-----------------|--------------------|------------|---------|
| Gboard | *(record)* | yes | 9 | `androidx.autofill.inline.ui.version:v1`, min 89x126, max 630x126 | `pass` |
| (third-party) | | | | | **not run — no second IME installed on D1** |

Traced line, verbatim:

```
D KeyVaultAutofill: fill: entries=468 targets=[AndroidAutofillServiceIdentifier(type=AndroidPackage, value=it.lene.lene)]
strongMatches=0 usernameFields=1 passwordFields=1 inlineRequested=true maxSuggestionCount=9 specs=9
styleV1=[androidx.autofill.inline.ui.version:v1] minSize=89x126 maxSize=630x126
```

Framework side of the same request:

```
mSupportInlinePresentations=true
datasets=[ hasInlinePresentation x3, hasPresentation (picker) ]
autoFill(): requestId=878; datasetIdx=2
```

Observed by hand: suggestions appear on the strip showing title and username
only, never a password; tapping one raises the biometric prompt and fills
without opening the picker.

**Gboard nuance worth keeping**: on its *password* keyboard layout Gboard reports
`supportsInlineSuggestion=false`, so the strip appears on the username field and
not on the password field. That is Gboard's behaviour, not ours.

**Verdict**: `pass` on Gboard. **T001 is not closed**: it requires a second, real
IME, which D1 does not have installed.

> `fail` means Phase 4 is not built and `androidx.autofill` is not added. Say so
> here rather than leaving the phase silently open.

## T002 — compatibility mode exposes a web domain (gates Phase 6 verification)

`<compatibility-package>` is already declared for both browsers.

| Browser | Version | Login page | Observed webDomain | Verdict |
|---------|---------|-----------|--------------------|---------|
| Chrome  | *(record)* | *(record)* | *(record)* | partial — see below |
| Firefox | | | | not run |

The declaration is live on the device:

```
Compat packages: {com.android.chrome=1000000000000, org.mozilla.firefox=1000000000000}
```

**Prerequisite discovered on D1**: Chrome does not delegate to an Android autofill
service until the user turns it on in Chrome (Settings → Autofill services →
use another service). Until then the framework opens no session at all
(`notifyValueChanged: ignoring on state UNKNOWN`, no `startSession`), which reads
as "our service is broken" and is not. This belongs in the quickstart, and
possibly in user-facing setup guidance.

After enabling it, Chrome produced a fill request and our service answered with a
dataset (`mTotalDatasetsProvided=1`).

**Verdict**: not yet — needs the three-domain run on both browsers, with the
webDomain recorded and the "never matches the browser package" check.

If a version has to be excluded, record it and narrow `maxLongVersionCode` in
`android/app/src/main/res/xml/keyvault_autofill_service.xml`.

## T003 — biometric prompt across the API split (gates Phase 3)

| Device | API | Fingerprint enrolled | Prompt shown | Device-credential fallback | Verdict |
|--------|-----|----------------------|--------------|----------------------------|---------|
| | 29 | yes | | | |
| | 29 | no | | | |
| | 31+ | yes | | | |
| | 31+ | no | | | |

**Verdict**: `pass` / `fail` —

## T004 — device with no secure lock (gates Phase 3)

Remove the screen lock, attempt a fill, restore the lock afterwards.

- `BiometricManager.canAuthenticate` returned (verbatim constant):
- Refusal reachable and message shown:

**Verdict**: `pass` / `fail` —

## Quickstart runs

| Section | D1 | D2 | Notes |
|---------|----|----|-------|
| A — authentication gate | | | |
| B — inline suggestions | | | |
| C — save capture | | | |
| D — browsers | | | |
| E — accessibility | | | |
| F — redaction | | | |

## T802 — redaction sweep

Command run and its output (a hit is a failed gate, not a note):

```
adb logcat -d | grep -i -E "password|secret" | grep -v "redacted"
```

```
<paste output, including "no matches">
```

Also checked: nothing under `files/autofill_v2` holds a plaintext password.

## T803 — sign-off

- Sections A–F pass on API 29:
- Sections A–F pass on API 33+:
- Deviations, with device / OS / IME / browser:
