# KDBX Vault Manager Chrome/Edge extension (Native Messaging v2)

Current scope: safe metadata search, pending-association requests, and explicit
popup-triggered fill for exact strong matches. The extension/native host do
**not** read `.kdbx`, request the master password, cache plaintext passwords, or
fill pages silently.

Production setup:

1. Install KDBX Vault Manager from Chrome Web Store.
2. Open **Desktop browser extension** in KDBX Vault Manager.
3. On Windows/Linux, click **Configure Chrome**. On macOS, download and run the
   signed **KeyVault Chrome Support** package offered by the app.
4. Restart Chrome, unlock the vault, then open the extension popup.

The published extension ID is `ogjmlkogmogijgpflnjifiobdmnmommh`. Users never
need to copy this ID, enable Developer mode, install Dart, or run terminal
commands.

Development install:

1. Open `chrome://extensions` or `edge://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked**.
4. Select `desktop/browser_extension`.
5. Copy the extension ID and register the native messaging host as described in `../../docs/desktop_browser_autofill.md`.

Windows helper from the repository root:

```powershell
.\desktop\native_host\install_host_windows.ps1 -Browser Chrome -ExtensionId <EXTENSION_ID>
```

Linux Chrome quick setup from the repository root:

```bash
./desktop/native_host/install_host_linux.sh <EXTENSION_ID>
```

Use `--browser chromium` only when testing with Chromium instead of Google Chrome.
Use the macOS helper with `edge` for Microsoft Edge.

The extension expects this Native Messaging v2 host name:

```text
dev.camillobucciarelli.keyvault_native_host
```

Optional packaging from repository root:

```bash
./desktop/browser_extension/package_extension.sh
```

The ZIP contains only `manifest.json`, `background.js`, popup files, this
README, and the four declared extension icons. Upload that ZIP to Chrome Web
Store for beta/unlisted/private review.

Firefox is not implemented in this MV3 service-worker extension. A separate
Firefox manifest/background implementation is required before advertising
Firefox support.

Do not put vault passwords, key file paths, database paths, credentials, or other
secrets in extension files, console logs, DOM nodes, or browser storage.

Permissions are intentionally small: `nativeMessaging` talks to the registered
host, `activeTab` lets the popup inspect the current tab after a click,
`scripting` injects the one-shot fill function only after the user clicks
Fill, and `storage` holds only the toolbar badge state (host reachable / app
unlocked / per-tab match *count*, never any credential data) so it survives
the MV3 service worker being killed and restarted. No host permissions or
content scripts are used.

The popup checks native-host status automatically when opened. Manual **Check
host status** remains a refresh button. No fill runs until the user clicks
**Fill on this page** on an exact strong match.

Flow:

1. Unlock KDBX Vault Manager desktop. The app publishes a metadata-only cache for the
   native host.
2. Popup **Find current site** sends only active tab origin + title.
3. Exact normalized host matches are labeled strong. If the app reveal bridge is
   active, strong matches show **Fill on this page**.
4. Global search shows metadata results. Selecting a possible/manual result
   creates a pending association for app confirmation.
5. Fill calls `revealForFill` with the current tab origin and entry id; the
   native host re-checks the strong match and asks the running unlocked app over
   a loopback token bridge. The popup injects once, then drops the plaintext
   variables.
