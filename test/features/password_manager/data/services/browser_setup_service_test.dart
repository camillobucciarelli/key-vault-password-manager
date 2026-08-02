import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/browser_setup_service.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BrowserSetupService', () {
    const validExtensionId = 'abcdefghijklmnopabcdefghijklmnop';

    test('validates extension IDs safely', () {
      expect(BrowserSetupService.isValidExtensionId(validExtensionId), isTrue);
      expect(
        BrowserSetupService.isValidExtensionId(' $validExtensionId\n'),
        isTrue,
      );
      expect(
        BrowserSetupService.isValidExtensionId(
          'abcdefghijklmnopabcdefghijklmno',
        ),
        isFalse,
      );
      expect(
        BrowserSetupService.isValidExtensionId(
          'abcdefghijklmnopabcdefghijklmnoq',
        ),
        isFalse,
      );
      expect(
        BrowserSetupService.isValidExtensionId(
          'ABCDEFGHIJKLMNOPABCDEFGHIJKLMNOP',
        ),
        isFalse,
      );
      expect(
        BrowserSetupService.isValidExtensionId(
          'abcd;rm -rf /;abcdefghijklmnop',
        ),
        isFalse,
      );
    });

    test('generates macOS Chrome installer command', () async {
      final root = await _fakeProjectRoot(scriptName: 'install_host_macos.sh');
      addTearDown(() => root.delete(recursive: true));

      final service = BrowserSetupService(
        projectRoot: root,
        platformOverride: BrowserSetupHostPlatform.macOS,
      );

      final command = service.nativeHostInstallCommand(
        browser: NativeHostBrowser.chrome,
        extensionId: validExtensionId,
      );

      expect(command, isNotNull);
      expect(command!.executable, '/bin/bash');
      expect(command.arguments, [
        p.join(root.path, 'desktop', 'native_host', 'install_host_macos.sh'),
        'chrome',
        validExtensionId,
      ]);
      expect(
        command.displayCommand,
        './desktop/native_host/install_host_macos.sh chrome $validExtensionId',
      );
    });

    test('generates Linux Chromium installer command', () async {
      final root = await _fakeProjectRoot(scriptName: 'install_host_linux.sh');
      addTearDown(() => root.delete(recursive: true));

      final service = BrowserSetupService(
        projectRoot: root,
        platformOverride: BrowserSetupHostPlatform.linux,
      );

      final command = service.nativeHostInstallCommand(
        browser: NativeHostBrowser.chromium,
        extensionId: validExtensionId,
      );

      expect(command, isNotNull);
      expect(command!.executable, '/bin/bash');
      expect(command.arguments, [
        p.join(root.path, 'desktop', 'native_host', 'install_host_linux.sh'),
        '--browser',
        'chromium',
        validExtensionId,
      ]);
      expect(
        command.displayCommand,
        './desktop/native_host/install_host_linux.sh --browser chromium $validExtensionId',
      );
    });

    test('generates Windows Edge installer command', () async {
      final root = await _fakeProjectRoot(
        scriptName: 'install_host_windows.ps1',
      );
      addTearDown(() => root.delete(recursive: true));

      final service = BrowserSetupService(
        projectRoot: root,
        platformOverride: BrowserSetupHostPlatform.windows,
      );

      final command = service.nativeHostInstallCommand(
        browser: NativeHostBrowser.edge,
        extensionId: validExtensionId,
      );

      expect(command, isNotNull);
      expect(command!.executable, 'powershell.exe');
      expect(command.arguments, [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join(root.path, 'desktop', 'native_host', 'install_host_windows.ps1'),
        '-Browser',
        'Edge',
        '-ExtensionId',
        validExtensionId,
      ]);
      expect(
        command.displayCommand,
        r'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\desktop\native_host\install_host_windows.ps1 -Browser Edge -ExtensionId '
        '$validExtensionId',
      );
    });

    test('does not run installer for invalid extension IDs', () async {
      final root = await _fakeProjectRoot(scriptName: 'install_host_macos.sh');
      addTearDown(() => root.delete(recursive: true));
      var ranProcess = false;

      final service = BrowserSetupService(
        projectRoot: root,
        platformOverride: BrowserSetupHostPlatform.macOS,
        processRunner: (executable, arguments) async {
          ranProcess = true;
          return ProcessResult(1, 0, '', '');
        },
      );

      final result = await service.registerNativeHost(
        browser: NativeHostBrowser.chrome,
        extensionId: 'invalid;id',
      );

      expect(result, NativeHostInstallResult.invalidExtensionId);
      expect(ranProcess, isFalse);
    });

    test('returns success when installer exits zero', () async {
      final root = await _fakeProjectRoot(scriptName: 'install_host_macos.sh');
      addTearDown(() => root.delete(recursive: true));
      String? executableSeen;
      List<String>? argumentsSeen;

      final service = BrowserSetupService(
        projectRoot: root,
        platformOverride: BrowserSetupHostPlatform.macOS,
        processRunner: (executable, arguments) async {
          executableSeen = executable;
          argumentsSeen = arguments;
          return ProcessResult(1, 0, '', '');
        },
      );

      final result = await service.registerNativeHost(
        browser: NativeHostBrowser.edge,
        extensionId: validExtensionId,
      );

      expect(result, NativeHostInstallResult.success);
      expect(executableSeen, '/bin/bash');
      expect(argumentsSeen, [
        p.join(root.path, 'desktop', 'native_host', 'install_host_macos.sh'),
        'edge',
        validExtensionId,
      ]);
    });

    test('returns failed when installer exits nonzero', () async {
      final root = await _fakeProjectRoot(scriptName: 'install_host_macos.sh');
      addTearDown(() => root.delete(recursive: true));
      String? executableSeen;
      List<String>? argumentsSeen;

      final service = BrowserSetupService(
        projectRoot: root,
        platformOverride: BrowserSetupHostPlatform.macOS,
        processRunner: (executable, arguments) async {
          executableSeen = executable;
          argumentsSeen = arguments;
          return ProcessResult(1, 42, '', 'installer failed');
        },
      );

      final result = await service.registerNativeHost(
        browser: NativeHostBrowser.edge,
        extensionId: validExtensionId,
      );

      expect(result, NativeHostInstallResult.failed);
      expect(executableSeen, '/bin/bash');
      expect(argumentsSeen, [
        p.join(root.path, 'desktop', 'native_host', 'install_host_macos.sh'),
        'edge',
        validExtensionId,
      ]);
    });

    test('rejects descriptor with dead bridge port', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-browser-setup-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final service = BrowserSetupService(
        cacheStore: store,
        platformOverride: BrowserSetupHostPlatform.macOS,
      );

      expect(await service.checkBridgeConnection(), BridgeCheckResult.noConfig);
      await _writeCache(store, databaseId: 'db-1');
      expect(
        await service.checkBridgeConnection(),
        BridgeCheckResult.v2AppBridgeUnavailable,
      );

      final deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = deadServer.port;
      await deadServer.close();
      await _writeDescriptor(store, port: deadPort);

      expect(
        await service.checkBridgeConnection(),
        BridgeCheckResult.v2AppBridgeUnavailable,
      );
    });

    test('connects only to live authenticated bridge', () async {
      final directory = await Directory.systemTemp.createTemp(
        'kv-browser-setup-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = DesktopBrowserAutofillCacheStore(directory: directory);
      final bridge = DesktopBrowserAutofillRevealBridgeService(
        store: store,
        mapper: const DesktopBrowserAutofillMetadataMapper(),
      );
      addTearDown(bridge.stop);
      await bridge.start(
        databasePath: '/vaults/example.kdbx',
        entries: const [],
      );
      final descriptor = (await store.readBridgeDescriptor())!;
      await _writeCache(store, databaseId: descriptor.databaseId);
      final service = BrowserSetupService(
        cacheStore: store,
        platformOverride: BrowserSetupHostPlatform.macOS,
      );

      expect(
        await service.checkBridgeConnection(),
        BridgeCheckResult.connected,
      );

      await store.writeBridgeDescriptor(
        DesktopBrowserAutofillBridgeDescriptor(
          version: descriptor.version,
          port: descriptor.port,
          token: 'wrong-token-wrong-token-wrong-token-wrong-token',
          databaseId: descriptor.databaseId,
          createdAtEpochMs: descriptor.createdAtEpochMs,
        ),
      );
      expect(
        await service.checkBridgeConnection(),
        BridgeCheckResult.v2AppBridgeUnavailable,
      );
    });
  });
}

Future<void> _writeCache(
  DesktopBrowserAutofillCacheStore store, {
  required String databaseId,
}) {
  return store.writeMetadataCache(
    DesktopBrowserAutofillMetadataCache(
      version: desktopBrowserAutofillCacheVersion,
      databaseId: databaseId,
      generatedAtEpochMs: 1,
      entries: const [],
    ),
  );
}

Future<void> _writeDescriptor(
  DesktopBrowserAutofillCacheStore store, {
  required int port,
}) {
  return store.writeBridgeDescriptor(
    DesktopBrowserAutofillBridgeDescriptor(
      version: desktopBrowserAutofillBridgeDescriptorVersion,
      port: port,
      token: 'test-token-test-token-test-token-test-token',
      databaseId: 'db-1',
      createdAtEpochMs: 1,
    ),
  );
}

Future<Directory> _fakeProjectRoot({required String scriptName}) async {
  final root = await Directory.systemTemp.createTemp('kv-browser-setup-');
  await Directory(
    p.join(root.path, 'desktop', 'browser_extension'),
  ).create(recursive: true);
  final script = File(p.join(root.path, 'desktop', 'native_host', scriptName));
  await script.create(recursive: true);
  return root;
}
