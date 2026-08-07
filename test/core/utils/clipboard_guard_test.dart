// spec-004 T9/T23/AC6: ClipboardGuard behaviour.
//
// Uses `testWidgets` (not bare `test`) so the test body runs inside
// Flutter's `FakeAsync` zone: `tester.pump(duration)` deterministically
// elapses the guard's real `Timer`, no `fake_async` package needed.
// The platform clipboard channel is mocked in-memory so `Clipboard.setData`
// / `Clipboard.getData` never touch a real OS clipboard.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/clipboard_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? clipboardContent;

  setUp(() {
    clipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardContent = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return {'text': clipboardContent};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('copy writes the value to the clipboard immediately', (
    tester,
  ) async {
    final guard = ClipboardGuard();
    await guard.copy('s3cret');

    expect(clipboardContent, 's3cret');
    guard.dispose();
  });

  testWidgets('clears the clipboard 30s after copy if unchanged', (
    tester,
  ) async {
    final guard = ClipboardGuard();
    await guard.copy('s3cret');
    expect(clipboardContent, 's3cret');

    await tester.pump(const Duration(seconds: 29));
    expect(clipboardContent, 's3cret', reason: 'not cleared before 30s');

    await tester.pump(const Duration(seconds: 2));
    expect(clipboardContent, '', reason: 'cleared once 30s has elapsed');

    guard.dispose();
  });

  testWidgets(
    'does NOT clear the clipboard if the user changed it in the meantime',
    (tester) async {
      final guard = ClipboardGuard();
      await guard.copy('s3cret');

      await tester.pump(const Duration(seconds: 10));
      // Simulate the user copying something else outside the app.
      clipboardContent = 'user-typed-elsewhere';

      await tester.pump(const Duration(seconds: 25));

      expect(
        clipboardContent,
        'user-typed-elsewhere',
        reason:
            'guard must never clear a clipboard it did not write most '
            'recently',
      );

      guard.dispose();
    },
  );

  testWidgets('a second copy cancels and reschedules the previous timer', (
    tester,
  ) async {
    final guard = ClipboardGuard();
    await guard.copy('first');
    await tester.pump(const Duration(seconds: 25));

    await guard.copy('second');
    // First timer would have fired at t=30 (5s from now); make sure it did
    // not clear the second value.
    await tester.pump(const Duration(seconds: 6));
    expect(clipboardContent, 'second');

    await tester.pump(const Duration(seconds: 25));
    expect(clipboardContent, '', reason: 'second copy clears at its own 30s');

    guard.dispose();
  });

  testWidgets('dispose cancels the pending timer (no leak, no late clear)', (
    tester,
  ) async {
    final guard = ClipboardGuard();
    await guard.copy('s3cret');
    guard.dispose();

    await tester.pump(const Duration(seconds: 31));
    expect(clipboardContent, 's3cret', reason: 'disposed guard never fires');
  });
}
