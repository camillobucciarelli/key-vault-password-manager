// spec-008 T503 — the only place a merge field's transient values live.
//
// The widget invokes `LoadSyncMergeFieldDisplayUseCase` itself. The result
// never travels through the coordinator, the BLoC or the state: it is held
// in this State object alone and nulled on dispose, so a lock (which
// disposes the vault tree) or a session change leaves nothing behind.
import 'package:flutter/widgets.dart';

import '../../domain/models/merge_field_display.dart';
import '../../domain/models/sync_merge_models.dart';
import '../../domain/usecases/load_sync_merge_field_display_usecase.dart';

typedef SyncMergeFieldDisplayBuilder =
    Widget Function(BuildContext context, MergeFieldDisplay? display);

class SyncMergeFieldDisplayView extends StatefulWidget {
  const SyncMergeFieldDisplayView({
    super.key,
    required this.loadFieldDisplay,
    required this.sessionId,
    required this.decisionId,
    required this.builder,
  });

  final LoadSyncMergeFieldDisplayUseCase loadFieldDisplay;
  final MergeSessionId sessionId;
  final MergeDecisionId decisionId;

  /// Receives null while loading, after a failure, and never after dispose.
  final SyncMergeFieldDisplayBuilder builder;

  @override
  State<SyncMergeFieldDisplayView> createState() =>
      _SyncMergeFieldDisplayViewState();
}

class _SyncMergeFieldDisplayViewState extends State<SyncMergeFieldDisplayView> {
  MergeFieldDisplay? _display;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SyncMergeFieldDisplayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.decisionId != widget.decisionId) {
      _drop();
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _drop();
    super.dispose();
  }

  /// Disposes the plaintext so a read after unmount/lock throws instead of
  /// returning stale values, then forgets it.
  void _drop() {
    _display?.dispose();
    _display = null;
  }

  Future<void> _load() async {
    final request = ++_request;
    MergeFieldDisplay? loaded;
    try {
      loaded = await widget.loadFieldDisplay(
        sessionId: widget.sessionId,
        decisionId: widget.decisionId,
      );
    } on Object {
      loaded = null;
    }
    if (!mounted || request != _request) {
      loaded?.dispose();
      return;
    }
    setState(() {
      _drop();
      _display = loaded;
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _display);
}
