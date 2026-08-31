// spec-008 T503 — the field widget is the only holder of the transient
// display, loads it itself, and disposes it on unmount.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/merge_field_display.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:password_manager/features/password_manager/domain/repositories/sync_merge_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/load_sync_merge_field_display_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/widgets/sync_merge_field_display_view.dart';

final _session = MergeSessionId('ms-${'a' * 32}');
final _decision = MergeDecisionId('md-${'b' * 32}');
final _otherDecision = MergeDecisionId('md-${'c' * 32}');

void main() {
  testWidgets('loads through the use case, hands the display to the builder, '
      'and disposes it on unmount', (tester) async {
    final port = _Port();
    MergeFieldDisplay? seen;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SyncMergeFieldDisplayView(
          loadFieldDisplay: LoadSyncMergeFieldDisplayUseCase(port),
          sessionId: _session,
          decisionId: _decision,
          builder: (context, display) {
            seen = display;
            return Text(display?.local.value ?? 'loading');
          },
        ),
      ),
    );
    expect(find.text('loading'), findsOneWidget);
    await tester.pump();

    expect(find.text('local-plaintext'), findsOneWidget);
    expect(port.loads, [(_session, _decision)]);
    final held = seen!;
    expect(held.isDisposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(held.isDisposed, isTrue);
    expect(() => held.local.value, throwsStateError);
  });

  testWidgets('a new decision id disposes the previous display and reloads', (
    tester,
  ) async {
    final port = _Port();
    final displays = <MergeFieldDisplay>{};
    Widget build(MergeDecisionId decisionId) => Directionality(
      textDirection: TextDirection.ltr,
      child: SyncMergeFieldDisplayView(
        loadFieldDisplay: LoadSyncMergeFieldDisplayUseCase(port),
        sessionId: _session,
        decisionId: decisionId,
        builder: (context, display) {
          if (display != null) displays.add(display);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(build(_decision));
    await tester.pump();
    await tester.pumpWidget(build(_otherDecision));
    await tester.pump();

    expect(port.loads.map((l) => l.$2), [_decision, _otherDecision]);
    expect(displays, hasLength(2));
    expect(displays.first.isDisposed, isTrue);
    expect(displays.last.isDisposed, isFalse);
  });

  testWidgets('a load failure yields null, not an exception', (tester) async {
    final port = _Port()
      ..error = const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SyncMergeFieldDisplayView(
          loadFieldDisplay: LoadSyncMergeFieldDisplayUseCase(port),
          sessionId: _session,
          decisionId: _decision,
          builder: (context, display) =>
              Text(display == null ? 'none' : 'some'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('none'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Port implements SyncMergeRepository {
  final List<(MergeSessionId, MergeDecisionId)> loads = [];
  Object? error;

  @override
  Future<MergeFieldDisplay> loadFieldDisplay({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  }) async {
    loads.add((sessionId, decisionId));
    final e = error;
    if (e != null) throw e;
    return MergeFieldDisplay(
      label: 'Custom_Field',
      local: MergeDisplaySide.present('local-plaintext'),
      remote: MergeDisplaySide.missing(),
      protected: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
