import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Result of installing the native messaging host on macOS.
enum NativeHostInstallResult { success, scriptNotFound, failed }

/// Result of verifying that the desktop bridge HTTP server is reachable.
enum BridgeCheckResult { connected, notRunning, noConfig }

class BrowserSetupService {
  // ---------------------------------------------------------------------------
  // Bridge connectivity check
  // ---------------------------------------------------------------------------

  /// Returns whether the Flutter desktop app bridge is running and reachable.
  Future<BridgeCheckResult> checkBridgeConnection() async {
    if (!_isDesktop) return BridgeCheckResult.notRunning;

    final config = await _readBridgeConfig();
    if (config == null) return BridgeCheckResult.noConfig;

    try {
      final host = config['host'] as String?;
      final port = (config['port'] as num?)?.toInt();
      final token = config['token'] as String?;

      if (host == null || port == null || token == null) {
        return BridgeCheckResult.noConfig;
      }

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      try {
        final req = await client.get(host, port, '/health');
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        await resp.drain<void>();
        return resp.statusCode == HttpStatus.ok
            ? BridgeCheckResult.connected
            : BridgeCheckResult.notRunning;
      } finally {
        client.close();
      }
    } catch (_) {
      return BridgeCheckResult.notRunning;
    }
  }

  // ---------------------------------------------------------------------------
  // Native host installation
  // ---------------------------------------------------------------------------

  /// Runs `install_mac.sh` to register the native messaging host in all
  /// supported Chromium-based browsers.
  Future<NativeHostInstallResult> installNativeHost() async {
    if (!_isDesktop || !Platform.isMacOS) {
      return NativeHostInstallResult.failed;
    }

    final scriptPath = _installScriptPath();
    if (scriptPath == null) return NativeHostInstallResult.scriptNotFound;

    final script = File(scriptPath);
    if (!await script.exists()) return NativeHostInstallResult.scriptNotFound;

    // Ensure the script is executable
    await Process.run('chmod', ['+x', scriptPath]);

    try {
      final result = await Process.run(
        '/bin/bash',
        [scriptPath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        return NativeHostInstallResult.success;
      }
      debugPrint('[BrowserSetup] install_mac.sh stderr: ${result.stderr}');
      return NativeHostInstallResult.failed;
    } catch (e) {
      debugPrint('[BrowserSetup] install error: $e');
      return NativeHostInstallResult.failed;
    }
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

  String get nativeHostName =>
      'dev.camillobucciarelli.kdbxKeyVault_native_host';

  String get bridgeConfigPath => _bridgeFilePath();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  bool get _isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Tries to locate `install_mac.sh` relative to the executable or the
  /// project source tree (dev mode).
  String? _installScriptPath() {
    // Dev mode: script sits next to keyvault_native_host.sh
    final exe = Platform.resolvedExecutable;
    // In Flutter dev: .../.dart_tool/... or .../build/macos/Build/...
    // Walk up to find desktop/native_host/
    var dir = p.dirname(exe);
    for (var i = 0; i < 10; i++) {
      final candidate = p.join(dir, 'desktop', 'native_host', 'install_mac.sh');
      if (File(candidate).existsSync()) return candidate;
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    debugPrint('[BrowserSetup] install_mac.sh not found near $exe');
    return null;
  }

  Future<Map<String, Object?>?> _readBridgeConfig() async {
    final file = File(_bridgeFilePath());
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {}
    return null;
  }

  String _bridgeFilePath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'KeyVaultAutofill', 'bridge.json');
      }
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return p.join(home, '.keyvault_autofill', 'bridge.json');
  }
}
