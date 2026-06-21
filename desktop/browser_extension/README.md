# KeyVault Chrome/Edge extension (Native Messaging v2 MVP)

Current scope: safe status/query protocol only. The extension does **not** read,
request, reveal, store, or fill vault credentials yet.

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
