// spec-002 T1-T3: VaultShellRouter contract tests.
//
// Tests the real, concrete `VaultShellRouter` through a widget harness (per
// plan.md: "no VaultShellRouterContract, mock subclass or second
// implementation"). Uses the existing sealed `VaultSurface`/`VaultRouteResult`
// subtypes since both hierarchies are sealed to their declaring library.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/navigation/vault_shell_router.dart';

Widget _noop(BuildContext context) =>
    const SizedBox.shrink(key: ValueKey('surface-child'));

void main() {
  group('presentationFor — FR-6 exhaustive dispatch at 390 and 1024', () {
    const mobileWidth = 390.0;
    const railWidth = 1024.0;

    void expectRouteThenPane(VaultSurface<VaultDone> surface) {
      expect(
        presentationFor(surface, mobileWidth),
        isA<VaultRoutePresentation>(),
      );
      expect(presentationFor(surface, railWidth), isA<VaultPanePresentation>());
    }

    void expectSheetThenPane(VaultSurface<VaultDone> surface) {
      expect(
        presentationFor(surface, mobileWidth),
        isA<VaultSheetPresentation>(),
      );
      expect(presentationFor(surface, railWidth), isA<VaultPanePresentation>());
    }

    void expectAlwaysSheet(VaultSurface<VaultDone> surface) {
      expect(
        presentationFor(surface, mobileWidth),
        isA<VaultSheetPresentation>(),
      );
      expect(
        presentationFor(surface, railWidth),
        isA<VaultSheetPresentation>(),
      );
    }

    test('Entry detail/editor: route / pane', () {
      expectRouteThenPane(EntrySurface<VaultDone>(builder: _noop));
    });
    test('OTP QR scanner: route / pane', () {
      expectRouteThenPane(OtpScannerSurface<VaultDone>(builder: _noop));
    });
    test('Attachments: route / pane', () {
      expectRouteThenPane(AttachmentsSurface<VaultDone>(builder: _noop));
    });
    test('Recycle bin: route / pane', () {
      expectRouteThenPane(RecycleBinSurface<VaultDone>(builder: _noop));
    });
    test('Duplicates/merge preview: route / pane', () {
      expectRouteThenPane(DuplicatesSurface<VaultDone>(builder: _noop));
    });
    test('Sync link/remote picker: route / pane', () {
      expectRouteThenPane(SyncLinkSurface<VaultDone>(builder: _noop));
    });
    test('Database settings/CSV import: route / pane', () {
      expectRouteThenPane(DatabaseSettingsSurface<VaultDone>(builder: _noop));
    });
    test('Password generator: sheet / pane', () {
      expectSheetThenPane(PasswordGeneratorSurface<VaultDone>(builder: _noop));
    });
    test('Group create/rename: sheet / pane', () {
      expectSheetThenPane(GroupEditSurface<VaultDone>(builder: _noop));
    });
    test('Move target: sheet / pane', () {
      expectSheetThenPane(MoveTargetSurface<VaultDone>(builder: _noop));
    });
    test('Sync conflict: sheet / pane', () {
      expectSheetThenPane(SyncConflictSurface<VaultDone>(builder: _noop));
    });
    test('Key-file manager: sheet / sheet', () {
      expectAlwaysSheet(KeyFileManagerSurface<VaultDone>(builder: _noop));
    });
    test('Confirmations: sheet / sheet over root window', () {
      expectAlwaysSheet(ConfirmationSurface<VaultDone>(builder: _noop));
    });
  });

  group('Redacted DTO diagnostics', () {
    test('EntryEditResult redacts secret fields', () {
      const result = EntryEditResult(
        title: 't',
        username: 'u',
        password: 'super-secret',
        url: 'https://example.com',
        notes: 'private-note-body',
        otpUri: 'otpauth://x',
        customFields: [],
        attachmentPaths: [],
      );
      expect(result.toString(), isNot(contains('super-secret')));
      expect(result.toString(), isNot(contains('private-note-body')));
      expect(result.toString(), isNot(contains('otpauth://x')));
      expect(result.props, isNot(contains('super-secret')));
    });

    test('GeneratedPasswordResult redacts the password', () {
      const result = GeneratedPasswordResult('super-secret');
      expect(result.toString(), isNot(contains('super-secret')));
      expect(result.props, isNot(contains('super-secret')));
    });

    test('DatabaseSettingsResult redacts credentials', () {
      const result = DatabaseSettingsResult(
        fileName: 'db.kdbx',
        keyFilePath: '/keys/a.key',
        biometricProtectionEnabled: true,
        changePassword: true,
        inactivityLockTimeoutSeconds: 30,
        currentPassword: 'old-secret',
        newPassword: 'new-secret',
      );
      expect(result.toString(), isNot(contains('old-secret')));
      expect(result.toString(), isNot(contains('new-secret')));
      expect(result.toString(), isNot(contains('/keys/a.key')));
    });
  });

  group('router mechanics via widget harness', () {
    testWidgets('open()/complete() resolves the exact typed result once', (
      tester,
    ) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final future = router.open<VaultDone>(
        context: ctx,
        width: 1024, // pane presentation: hosted synchronously, no Navigator
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();

      expect(router.debugLiveSessionCount, 1);
      final scope = _findOperationScope(tester);
      scope.complete(const VaultDone());
      await tester.pump();

      expect(await future, const VaultDone());
      expect(router.debugLiveSessionCount, 0);
    });

    testWidgets('duplicate/stale completion after terminal is a no-op', (
      tester,
    ) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final future = router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();
      final scope = _findOperationScope(tester);
      final id = scope.operationId;

      router.complete(id, const VaultDone());
      await tester.pump();
      expect(await future, const VaultDone());

      // Stale/duplicate completion on the now-terminal id must be a no-op:
      // no exception, no change, and it must not resolve a later operation.
      expect(() => router.complete(id, const VaultDone()), returnsNormally);
      expect(router.debugRetainsOperation(id), isFalse);
    });

    testWidgets('cancel()/back resolves null exactly once', (tester) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final future = router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();
      final scope = _findOperationScope(tester);
      final id = scope.operationId;

      router.cancel(id);
      await tester.pump();

      expect(await future, isNull);
      expect(router.debugRetainsOperation(id), isFalse);
    });

    testWidgets('sequential opens issue distinct, never-reused ids', (
      tester,
    ) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final firstFuture = router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();
      final firstId = _findOperationScope(tester).operationId;
      router.cancel(firstId);
      await firstFuture;
      await tester.pump();

      final secondFuture = router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();
      final secondId = _findOperationScope(tester).operationId;

      expect(secondId, isNot(equals(firstId)));
      router.cancel(secondId);
      await secondFuture;
    });

    testWidgets('nested confirmation gets its own id and does not replace '
        'the parent session', (tester) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final parentFuture = router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();
      final parentScope = _findOperationScope(tester);
      final parentId = parentScope.operationId;

      final childFuture = router.confirm(
        context: tester.element(find.byKey(const ValueKey('surface-child'))),
        title: 'Nested?',
        body: 'body',
      );
      await tester.pump();

      expect(router.debugLiveSessionCount, 2);
      expect(router.debugRetainsOperation(parentId), isTrue);

      // Closing the parent terminally cancels the still-open child.
      router.cancel(parentId);
      await tester.pump();

      expect(await parentFuture, isNull);
      expect(await childFuture, isNull);
      expect(router.debugLiveSessionCount, 0);
    });

    testWidgets('router dispose() cancels every live operation', (
      tester,
    ) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final future = router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      await tester.pump();
      expect(router.debugLiveSessionCount, 1);

      router.dispose();
      await tester.pump();

      expect(await future, isNull);
      expect(router.debugLiveSessionCount, 0);

      // A disposed router refuses new operations rather than throwing.
      final afterDispose = await router.open<VaultDone>(
        context: ctx,
        width: 1024,
        surface: EntrySurface<VaultDone>(builder: _noop),
      );
      expect(afterDispose, isNull);
    });

    testWidgets('confirm() drives the ConfirmDecision contract', (
      tester,
    ) async {
      late VaultShellRouter router;
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: _RouterHarness(onReady: (r, c) => (router = r, ctx = c)),
        ),
      );
      await tester.pump();

      final future = router.confirm(
        context: ctx,
        title: 'Confirm delete',
        body: 'Delete this entry?',
      );
      await tester.pump();

      expect(find.text('Confirm delete'), findsOneWidget);
      expect(find.text('Delete this entry?'), findsOneWidget);

      final scope = VaultOperationScope.of(
        tester.element(find.byType(AlertDialog)),
      );
      scope.complete(ConfirmDecision.confirm);
      await tester.pump();

      expect(await future, ConfirmDecision.confirm);
    });
  });
}

VaultOperationScope _findOperationScope(WidgetTester tester) {
  // 'surface-child' is the leaf built by the surface's own builder, i.e. a
  // genuine descendant of the VaultOperationScope the router installs.
  return VaultOperationScope.of(
    tester.element(find.byKey(const ValueKey('surface-child'))),
  );
}

class _RouterHarness extends StatefulWidget {
  const _RouterHarness({required this.onReady});

  final void Function(VaultShellRouter router, BuildContext context) onReady;

  @override
  State<_RouterHarness> createState() => _RouterHarnessState();
}

class _RouterHarnessState extends State<_RouterHarness> {
  late final VaultShellRouter router;
  Widget? pane;

  @override
  void initState() {
    super.initState();
    router = VaultShellRouter(
      onPaneChanged: (p) {
        if (mounted) setState(() => pane = p);
      },
    );
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VaultShellRouterScope(
      router: router,
      child: Scaffold(
        body: Column(
          children: [
            Builder(
              builder: (innerContext) {
                widget.onReady(router, innerContext);
                return const SizedBox.shrink();
              },
            ),
            if (pane != null)
              Expanded(
                child: KeyedSubtree(
                  key: const ValueKey('pane-host'),
                  child: pane!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
