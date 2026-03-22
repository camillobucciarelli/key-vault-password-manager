#!/usr/bin/env bash
# install_mac.sh - Installs the Native Messaging Host for Chrome/Edge/Brave on macOS

set -euo pipefail

# Find the absolute path to the directory containing this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Target directories for Chrome, Brave and Edge
CHROME_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
BRAVE_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
EDGE_DIR="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"

# Host name and manifest filename
HOST_NAME="com.cbucciarelli.keyvault"
MANIFEST_NAME="$HOST_NAME.json"

# Update the path in the JSON file to point to the actual bash script location
# So we don't have to hardcode /Applications/... while developing
TEMP_MANIFEST="/tmp/${MANIFEST_NAME}"
cp "${DIR}/${MANIFEST_NAME}" "${TEMP_MANIFEST}"
sed -i '' "s|/Applications/KeyVault.app/Contents/Resources/native_host/keyvault_native_host.sh|${DIR}/keyvault_native_host.sh|g" "${TEMP_MANIFEST}"

echo "[KeyVault] Installing Native Messaging Host for Google Chrome..."
mkdir -p "$CHROME_DIR"
cp "$TEMP_MANIFEST" "$CHROME_DIR/$MANIFEST_NAME"
# Set proper permissions
chmod o+r "$CHROME_DIR/$MANIFEST_NAME"

echo "[KeyVault] Installing Native Messaging Host for Brave..."
mkdir -p "$BRAVE_DIR"
cp "$TEMP_MANIFEST" "$BRAVE_DIR/$MANIFEST_NAME"
chmod o+r "$BRAVE_DIR/$MANIFEST_NAME"

echo "[KeyVault] Installing Native Messaging Host for Microsoft Edge..."
mkdir -p "$EDGE_DIR"
cp "$TEMP_MANIFEST" "$EDGE_DIR/$MANIFEST_NAME"
chmod o+r "$EDGE_DIR/$MANIFEST_NAME"

echo "[KeyVault] Installation complete!"
echo "[KeyVault] Make sure your Chrome Extension ID is updated in $DIR/$MANIFEST_NAME"
