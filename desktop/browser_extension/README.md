# KeyVault Chrome extension

Development install:

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked**.
4. Select `desktop/browser_extension`.
5. Copy the extension ID and register the native messaging host as described in `../../docs/desktop_browser_autofill.md`.

Windows Chrome helper from the repository root:

```powershell
.\desktop\native_host\install_host_windows.ps1 -ExtensionId <EXTENSION_ID>
```

Linux Chrome quick setup from the repository root:

```bash
./desktop/native_host/install_host_linux.sh <EXTENSION_ID>
```

Use `--browser chromium` only when testing with Chromium instead of Google Chrome.

The extension expects this native messaging host name:

```text
dev.camillobucciarelli.kdbxKeyVault_native_host
```

Optional packaging from repository root:

```bash
./desktop/browser_extension/package_extension.sh
```

Do not put vault passwords or secrets in extension files, console logs, or browser storage.
