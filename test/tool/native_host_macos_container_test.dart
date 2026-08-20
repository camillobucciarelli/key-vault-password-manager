import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_browser_autofill_cache.dart';

import '../../tool/native_host_macos_container.dart';

void main() {
  group('ensureMacosGroupContainerRegistered', () {
    test('returns the group container path on macOS, null elsewhere', () {
      final path = ensureMacosGroupContainerRegistered();

      if (!Platform.isMacOS) {
        expect(path, isNull);
        return;
      }
      // On macOS the Foundation call must actually run and report the
      // container of the browser-store group. The test binary is unsigned,
      // which for a non-sandboxed process still yields the conventional
      // ~/Library/Group Containers/<group> location.
      expect(path, isNotNull);
      expect(
        path,
        endsWith('/Library/Group Containers/$macosBrowserStoreAppGroup'),
      );
    });

    test('API container is the parent of the derived store directory', () {
      if (!Platform.isMacOS) return;

      // Sanity pairing: the app writes the store at the derived path and the
      // host reads there too; the API result is only the TCC side effect. If
      // Apple ever moved the API's answer away from the conventional
      // location this fails loudly instead of the host silently reading an
      // empty store.
      final containerPath = ensureMacosGroupContainerRegistered();
      final derived = DesktopBrowserAutofillCacheStore.defaultDirectory();

      expect(derived, isNotNull);
      expect(derived!.path, '$containerPath/browser_v2');
    });

    test('is idempotent and stable across calls', () {
      final first = ensureMacosGroupContainerRegistered();
      final second = ensureMacosGroupContainerRegistered();

      expect(second, first);
    });
  });
}
