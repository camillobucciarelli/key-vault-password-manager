# KeyVault Chrome/Edge extension (Native Messaging v2)

Current scope: safe metadata search, pending-association requests, and explicit
popup-triggered fill for exact strong matches. The extension/native host do
**not** read `.kdbx`, request the master password, cache plaintext passwords, or
fill pages silently.

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

Firefox is not implemented in this MV3 service-worker extension. A separate
Firefox manifest/background implementation is required before advertising
Firefox support.

Do not put vault passwords, key file paths, database paths, credentials, or other
secrets in extension files, console logs, DOM nodes, or browser storage.

Permissions are intentionally small: `nativeMessaging` talks to the registered
host, `activeTab` lets the popup inspect the current tab after a click, and
`scripting` injects the one-shot fill function only after the user clicks Fill.
No host permissions, content scripts, or extension storage are used.

Flow:

1. Unlock KeyVault desktop. The app publishes a metadata-only cache for the
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
