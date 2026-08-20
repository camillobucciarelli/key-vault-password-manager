# KeyVault Chrome/Edge extension (Native Messaging v2)

MV3 extension for Chrome and Chromium-based Edge. Current scope: safe metadata
search, pending-association requests, explicit popup-triggered fill for exact
strong matches, and an opt-in in-page overlay on origins the user enables one
by one. The extension and native host do **not** read `.kdbx`, request the
master password, cache plaintext passwords, or fill pages silently.

Firefox is not supported: this is an MV3 service-worker extension and a
separate Firefox implementation would be required before advertising support.

## Permissions and store justification

Declared in `manifest.json`, intentionally minimal:

| Permission | Why |
|---|---|
| `nativeMessaging` | Talk to the locally registered KeyVault native host. All credential flow goes through it; the extension holds no vault data. |
| `activeTab` | Let the popup read the current tab's origin and title after an explicit toolbar click. No `tabs` permission, no background tab access. |
| `scripting` | Register the overlay content script per enabled origin, and inject the one-shot fill function only after an explicit user action. |
| `storage` | Persist the overlay's enabled-origin config and the toolbar badge state (host reachable / app unlocked / per-tab match *count*). Never credential data. Survives MV3 worker termination. |
| `optional_host_permissions` (`http://*/*`, `https://*/*`) | Ceiling for per-origin opt-in requests. Nothing is granted at install time; each origin is requested individually when the user enables it. |

Not present, by design: `host_permissions`, static `content_scripts`,
`tabs`, `webNavigation`, `clipboardRead`, `clipboardWrite`, `<all_urls>`.
The test suite asserts their absence.

## Exact-origin opt-in and revoke

- The overlay is **off by default everywhere**. The user enables it per exact
  canonical origin (scheme + host + port) from the popup. Enabling requests
  the matching optional host permission in the same user gesture.
- Disabling from the popup removes the origin from config, unregisters its
  content script, and revokes the optional permission.
- Revoking the permission from `chrome://extensions` (outside the popup) is
  also honored: the worker reconciles on cold start, popup open, permission
  removal, and disable, and tears the origin down.

### Port-granularity caveat

Chromium host-permission patterns have no port component: enabling
`https://example.com:8443` requests the pattern `https://example.com/*`,
which also covers other ports on that host. **Authorization does not widen
with it**: the extension's own config stores the exact origin including port,
and every overlay request is checked against that exact origin. The permission
pattern is a browser-side ceiling; the exact-origin check is the gate.

## Dynamic injection and teardown

No static content scripts. `content_overlay.js` is registered via
`scripting.registerContentScripts` only for enabled origins (`document_idle`,
`allFrames: true`) and unregistered on disable/revoke. The in-page overlay is
a closed-shadow host that renders **metadata only** (title + display service),
and tears down on Escape, focus loss, navigation, page hide, visibility
change, timeout, disable, permission removal, and stale config revision —
removing the host, aborting listeners/observers/timers, and restoring ARIA.

## Frame and restricted-page limits

- Supported: top frame and same-origin frames of an enabled origin.
- Cross-origin frames only when the child frame's origin is itself enabled,
  permitted, injected, and sender-validated; otherwise the overlay fails
  closed. Authorization follows the frame origin, never the top document.
- Restricted pages (`chrome://`, the Web Store, other extensions' pages,
  `file://` without explicit permission) cannot be injected. Where a limit is
  detectable the overlay shows an unsupported state directing the user to copy
  manually from the KeyVault app. The extension has **no clipboard path**.

## Worker cold-start recovery

MV3 terminates the service worker at will. All durable state (overlay config,
badge state) lives in `chrome.storage`; on cold start the worker reconciles
registered content scripts and granted permissions against committed config,
sweeps orphans, and rebuilds the badge. A worker restart costs a re-read and
redraw, never a lost authorization and never a widened one.

## Native host capability (exact origin)

The native messaging host manifest lists exactly **one**
`chrome-extension://<id>/` entry in `allowed_origins`. The v2 protocol
(metadata search, pending association, explicit reveal-for-fill) requires no
broader registration. Reinstall/re-register the host only when the host binary
path or the extension ID changes; a Chrome restart picks up manifest changes.

## Secret policy

- Overlay and popup DOM, attributes, datasets, logs, globals, and storage are
  metadata-only. No username or password appears anywhere in them.
- Plaintext is revealed only on an explicit fill action: the native host
  re-validates the strong match and asks the running unlocked app over a
  loopback token bridge; the injected function writes the values into the page
  inputs, dispatches `input`/`change`, never submits, then drops every
  reference.
- Never via clipboard. Never persisted. Never logged.
- Do not put vault passwords, key file paths, database paths, or other secrets
  in extension files, console output, DOM nodes, or browser storage.

## Production setup

1. Install KeyVault from Chrome Web Store. Published extension ID:
   `ogjmlkogmogijgpflnjifiobdmnmommh`.
2. Open **Desktop browser extension** in the KeyVault app.
3. On Windows/Linux, click **Configure Chrome**. On macOS, download and run
   the signed **KeyVault Chrome Support** package offered by the app.
4. Restart the browser, unlock the vault, then open the extension popup.

Users never need to copy the ID, enable Developer mode, install Dart, or run
terminal commands.

### macOS signing/TCC notes

- The host is a Dart AOT binary. The Apple hardened runtime blocks Dart AOT's
  snapshot mapping, so signing with `--options runtime` requires the
  `com.apple.security.cs.allow-unsigned-executable-memory` entitlement — a
  hardened-runtime-signed host without it dies on launch (SIGKILL) and the
  extension only sees "host unavailable". The packaging script
  (`tool/package_native_host_macos.sh`) keeps the hardened runtime (required
  for notarization) and signs with `tool/native_host_macos.entitlements`.
- On macOS Sequoia, the host reads the app's Group Container
  (`group.dev.camillobucciarelli.kdbxKeyVault`) for the metadata cache; TCC
  may show a one-time access prompt for it. Denying it leaves the host
  reachable but with no matches.

## Development install

1. Open `chrome://extensions` or `edge://extensions`, enable **Developer
   mode**, click **Load unpacked**, select `desktop/browser_extension`.
2. Copy the extension ID and register the native host as described in
   `../../docs/desktop_browser_autofill.md`.

Host registration helpers from the repository root:

```powershell
.\desktop\native_host\install_host_windows.ps1 -Browser Chrome -ExtensionId <EXTENSION_ID>
```

```bash
./desktop/native_host/install_host_linux.sh <EXTENSION_ID>   # --browser chromium for Chromium
./desktop/native_host/install_host_macos.sh <EXTENSION_ID>   # pass `edge` for Microsoft Edge
```

Expected Native Messaging host name:

```text
dev.camillobucciarelli.keyvault_native_host
```

## Automated and manual checks

Automated (CI runs the first two on every PR):

```bash
node --test desktop/browser_extension/test/*.test.js   # Gate A0 harness
node --check desktop/browser_extension/<each runtime .js>
node tool/mutation_runner.mjs --check                  # mutation gate
python3 -m json.tool desktop/browser_extension/manifest.json
./desktop/browser_extension/package_extension.sh
```

Manual: keyboard-only navigation, screen reader smoke (NVDA/VoiceOver), and
the Chrome/Edge install/grant/revoke matrix (spec 009 A046).

### Visual baselines

Pixel acceptance for the overlay runs in ONE canonical environment: a Linux
x86_64 OCI image pinned by immutable digest plus an exact Chrome for Testing
build (version, archive SHA-256, and binary SHA-256), all locked in
`test/visual_environment_v1.json` together with timezone, locale, the
installed font-set hash, and the full rendering flag list. Any mismatch —
image contents, Chrome hash, fonts, timezone — fails loudly before capture;
there is no skip path and no mutable-tag fallback.

```bash
# Recapture into test/screenshots/actual/ and compare decoded pixels + the
# approved sha256 per baseline against test/screenshots/expected/. Never
# rewrites expected/. Exit 0 = all 18 baselines match.
./desktop/browser_extension/test/run_visual_baselines.sh --verify

# Regenerate expected/ + visual_baselines_v1.sha256. ONLY after human design
# review; commit both together or the inventory test and --verify reject the
# unapproved edit.
./desktop/browser_extension/test/run_visual_baselines.sh --approve
```

Requires `podman`. On Apple Silicon the amd64 image must run under a
Rosetta-enabled podman machine (qemu TCG cannot run Chrome — the run then
fails on CDP timeouts, never silently):

```bash
printf '[machine]\nprovider = "applehv"\nrosetta = true\n' > /tmp/kv-machine.conf
CONTAINERS_CONF_OVERRIDE=/tmp/kv-machine.conf podman machine init kv-visual-amd64
CONTAINERS_CONF_OVERRIDE=/tmp/kv-machine.conf podman machine start kv-visual-amd64
KEYVAULT_VISUAL_PODMAN_CONNECTION=kv-visual-amd64 \
  ./desktop/browser_extension/test/run_visual_baselines.sh --verify
```

Every run captures the 18 scenarios TWICE with fresh browser profiles and
requires the two passes to be byte-identical (determinism proof re-established
on every run). The capture drives the UNMODIFIED production
`overlay_security.js` + `content_overlay.js` loaded as an unpacked extension in
Chrome for Testing; scenario states come from a test-only background stub under
`test/visual/harness/` that is never packaged. The supplemental inventory test
(`test/visual_inventory.test.js`, runs in the normal Gate A0 suite) asserts the
exact 18 basenames and that every committed expected PNG still matches its
approved hash. Windows/macOS/Edge remain DOM/geometry/manual-smoke
environments, never pixel authorities.

## Package contents

`./desktop/browser_extension/package_extension.sh` builds
`dist/keyvault-browser-extension.zip` from an explicit allowlist:
`manifest.json`, `background.js`, `overlay_security.js`,
`overlay_lifecycle.js`, `overlay_routes.js`, `content_overlay.js`,
`popup.html`, `popup.js`, `popup.css`, `tokens.css`, this README, the four
declared icons, and the AGPL license files. Nothing under `test/` (including
the `session_helpers.js` harness), no fixtures, screenshots, source maps,
visual manifests, or environment files. The test suite asserts both the
presence of every runtime file and the absence of the excluded ones; any task
that adds a runtime file updates the allowlist in the same commit.
