import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'desktop_browser_autofill_cache.dart';

/// Result of installing the native messaging host on macOS.
enum NativeHostInstallResult { success, scriptNotFound, failed }

/// Result of verifying desktop browser autofill connectivity.
enum BridgeCheckResult {
  connected,
  notRunning,
  noConfig,
  v2AppBridgeUnavailable,
}

class BrowserSetupService {
  // ---------------------------------------------------------------------------
  // Bridge connectivity check
  // ---------------------------------------------------------------------------

  /// Returns whether the Flutter desktop app bridge is running and reachable.
  Future<BridgeCheckResult> checkBridgeConnection() async {
    if (!_isDesktop) return BridgeCheckResult.notRunning;
    final status = await DesktopBrowserAutofillCacheStore().status();
    return status.cacheAvailable
        ? BridgeCheckResult.connected
        : BridgeCheckResult.v2AppBridgeUnavailable;
  }

  // ---------------------------------------------------------------------------
  // Native host installation
  // ---------------------------------------------------------------------------

  /// Legacy automatic install is disabled because the v2 native host manifest
  /// must include the browser-generated extension ID. Use the explicit
  /// `install_host_macos.sh <chrome|edge> <EXTENSION_ID>` flow instead.
  Future<NativeHostInstallResult> installNativeHost() async {
    debugPrint(
      '[BrowserSetup] automatic v1 native-host install disabled; use install_host_macos.sh with the extension ID.',
    );
    return NativeHostInstallResult.failed;
  }

  // ---------------------------------------------------------------------------
  // Extension folder lookup
  // ---------------------------------------------------------------------------

  /// Absolute path to the browser extension folder inside the project root.
  ///
  /// Works during development (when the script lives in
  /// `.../desktop/native_host/`).  In a shipped `.app` this would need to
  /// resolve from the bundle, but for now dev-mode is enough.
  String? get extensionFolderPath {
    final script = _installScriptPath();
    if (script == null) return null;
    // native_host/ → desktop/ → project_root/desktop/browser_extension/
    final projectRoot = p.dirname(p.dirname(p.dirname(script)));
    final ext = p.join(projectRoot, 'desktop', 'browser_extension');
    return Directory(ext).existsSync() ? ext : null;
  }

  String get nativeHostName => 'dev.camillobucciarelli.keyvault_native_host';

  String get bridgeConfigPath =>
      DesktopBrowserAutofillCacheStore.defaultDirectory()?.path ??
      'Desktop browser Autofill cache directory unavailable';

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  bool get _isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Tries to locate `install_host_macos.sh` relative to the executable or the
  /// project source tree (dev mode).
  String? _installScriptPath() {
    // Dev mode: script sits next to keyvault_native_host.sh
    final exe = Platform.resolvedExecutable;
    // In Flutter dev: .../.dart_tool/... or .../build/macos/Build/...
    // Walk up to find desktop/native_host/
    var dir = p.dirname(exe);
    for (var i = 0; i < 10; i++) {
      final candidate = p.join(
        dir,
        'desktop',
        'native_host',
        'install_host_macos.sh',
      );
      if (File(candidate).existsSync()) return candidate;
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    debugPrint('[BrowserSetup] install_host_macos.sh not found near $exe');
    return null;
  }
}
