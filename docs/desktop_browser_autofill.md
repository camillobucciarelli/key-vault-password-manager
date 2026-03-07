# Desktop Browser Autofill (Chrome/Edge/Firefox + Safari adapter)

This project now includes a desktop autofill MVP based on:
- Browser extension (`desktop/browser_extension/`)
- Native messaging host (`desktop/native_host/`)
- Dart host runtime (`tool/native_host.dart`)
- Local bridge exposed by running desktop app session

## What it does

1. You open a login page in a supported browser.
2. Open the extension popup.
3. If the KeyVault app is open and unlocked, just click **Find credentials**.
4. Optional fallback mode: enter database path and password/key file in popup.
5. Click **Find credentials**.
5. The extension asks the local native host for matches on current domain.
6. You choose a match and click **Fill this account**.

## Setup (macOS)

### 1) Load extension unpacked

1. Open `chrome://extensions`, `edge://extensions`, or `about:debugging#/runtime/this-firefox`.
2. Enable **Developer mode**.
3. Click **Load unpacked** and select `desktop/browser_extension`.
4. Copy extension ID (Chrome/Edge) or add-on ID (Firefox, from manifest gecko id).

Safari uses a converted Xcode project (see Safari section below).

### 2) Register native messaging host

Run from repository root:

```bash
./desktop/native_host/install_host_macos.sh chrome <EXTENSION_ID>
```

For Edge:

```bash
./desktop/native_host/install_host_macos.sh edge <EXTENSION_ID>
```

For Firefox:

```bash
./desktop/native_host/install_host_macos.sh firefox keyvault-autofill@camillobucciarelli.dev
```

This creates:
- Chrome manifest in `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- Edge manifest in `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/`
- Firefox manifest in `~/Library/Application Support/Mozilla/NativeMessagingHosts/`

### 3) Package extension zip (optional)

```bash
./desktop/browser_extension/package_extension.sh
```

### 4) Safari adapter (experimental)

Use converter script:

```bash
./desktop/safari/convert_extension_to_safari.sh
```

Then follow `desktop/safari/README.md`.

## Usage

### Recommended mode (running app session)

1. Start KeyVault desktop app and unlock your vault.
2. Visit a page with login form.
3. Click extension icon and press **Find credentials**.
4. Keep **Auto refresh when tab/page changes** enabled (default) to refresh automatically.
5. Choose an entry and click **Fill this account**.

### Fallback mode (direct vault access)

If the app is not running, fill these fields in popup:
- `Database path`
- `Master password` or `Key file path`
- `Max results`

Then click **Find credentials**.

## Security notes

- In recommended mode, popup does not need master password.
- The popup keeps database path/key file path in extension local storage for fallback mode.
- In fallback mode, master password is not persisted by this code; it is sent per-request to host.
- Communication browser <-> host uses local native messaging (stdio).
- Communication host <-> app bridge uses local loopback and a random bearer token in bridge config.
- Bridge token expires automatically every 20 minutes and is rotated.
- Returned credentials are filtered with strict domain matching (same host or direct subdomain relationship).

## Current limitations

- Safari adapter is present but still marked experimental.

## Troubleshooting

- **"Native host has exited"**
  - Run `dart --version` and confirm Dart SDK is available in shell.
  - Confirm scripts are executable:
    - `desktop/native_host/keyvault_native_host.sh`
    - `desktop/native_host/install_host_macos.sh`
- **"Specified native messaging host not found"**
  - Re-run install script with correct browser and extension/add-on ID.
  - Verify the manifest JSON exists in the browser path above.
- **"Running app session unavailable"**
  - Ensure KeyVault desktop app is open.
  - Unlock the vault in app first.
  - Verify bridge file exists:
    - macOS/Linux: `~/.keyvault_autofill/bridge.json`
    - Windows: `%APPDATA%\\KeyVaultAutofill\\bridge.json`
- **No fields filled**
  - Click in password field first, then run fill again.
  - Some custom login pages need site-specific selectors (to be added iteratively).
