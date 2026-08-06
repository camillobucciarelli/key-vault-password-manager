import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../domain/models/sync_conflict.dart';
import '../../domain/models/vault_custom_field.dart';

sealed class VaultRouteResult extends Equatable {
  const VaultRouteResult();

  @override
  bool? get stringify => false;
}

final class EntryEditResult extends VaultRouteResult {
  const EntryEditResult({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    required this.otpUri,
    required this.customFields,
    required this.attachmentPaths,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String otpUri;
  final List<VaultCustomField> customFields;
  final List<String> attachmentPaths;

  @override
  List<Object?> get props => [
    title,
    username,
    const _RedactedRouteValue(),
    url,
    const _RedactedRouteValue(),
    const _RedactedRouteValue(),
    customFields,
    attachmentPaths,
  ];

  @override
  String toString() =>
      'EntryEditResult(title: $title, username: $username, password: <redacted>, '
      'url: $url, notes: <redacted>, otpUri: <redacted>, '
      'customFields: $customFields, attachmentPaths: $attachmentPaths)';
}

final class GeneratedPasswordResult extends VaultRouteResult {
  const GeneratedPasswordResult(this.password);

  final String password;

  @override
  List<Object?> get props => const [_RedactedRouteValue()];

  @override
  String toString() => 'GeneratedPasswordResult(password: <redacted>)';
}

final class OtpScanResult extends VaultRouteResult {
  const OtpScanResult(this.otpUri);

  final String otpUri;

  @override
  List<Object?> get props => const [_RedactedRouteValue()];

  @override
  String toString() => 'OtpScanResult(otpUri: <redacted>)';
}

final class GroupEditResult extends VaultRouteResult {
  const GroupEditResult(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

final class MoveTargetResult extends VaultRouteResult {
  const MoveTargetResult(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

sealed class DriveLinkResult extends VaultRouteResult {
  const DriveLinkResult();

  const factory DriveLinkResult.existing(String remoteFileId) =
      ExistingDriveLinkResult;
  const factory DriveLinkResult.newFile(String remoteFileName) =
      NewDriveLinkResult;
}

final class ExistingDriveLinkResult extends DriveLinkResult {
  const ExistingDriveLinkResult(this.remoteFileId);

  final String remoteFileId;

  @override
  List<Object?> get props => [remoteFileId];
}

final class NewDriveLinkResult extends DriveLinkResult {
  const NewDriveLinkResult(this.remoteFileName);

  final String remoteFileName;

  @override
  List<Object?> get props => [remoteFileName];
}

final class SyncConflictRouteResult extends VaultRouteResult {
  const SyncConflictRouteResult(this.resolution);

  final SyncConflictResolution resolution;

  @override
  List<Object?> get props => [resolution];
}

final class ConfirmDecision extends VaultRouteResult {
  const ConfirmDecision._(this.isConfirmed);

  static const confirm = ConfirmDecision._(true);
  static const cancel = ConfirmDecision._(false);

  final bool isConfirmed;

  @override
  List<Object?> get props => [isConfirmed];
}

final class VaultDone extends VaultRouteResult {
  const VaultDone();

  @override
  List<Object?> get props => const [];
}

final class DatabaseSettingsResult extends VaultRouteResult {
  const DatabaseSettingsResult({
    required this.fileName,
    required this.keyFilePath,
    required this.biometricProtectionEnabled,
    required this.changePassword,
    required this.inactivityLockTimeoutSeconds,
    required this.currentPassword,
    required this.newPassword,
  });

  final String fileName;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final bool changePassword;
  final int? inactivityLockTimeoutSeconds;
  final String currentPassword;
  final String newPassword;

  @override
  List<Object?> get props => [
    fileName,
    const _RedactedRouteValue(),
    biometricProtectionEnabled,
    changePassword,
    inactivityLockTimeoutSeconds,
    const _RedactedRouteValue(),
    const _RedactedRouteValue(),
  ];

  @override
  String toString() =>
      'DatabaseSettingsResult(fileName: $fileName, keyFilePath: <redacted>, '
      'biometricProtectionEnabled: $biometricProtectionEnabled, '
      'changePassword: $changePassword, '
      'inactivityLockTimeoutSeconds: $inactivityLockTimeoutSeconds, '
      'currentPassword: <redacted>, newPassword: <redacted>)';
}

final class CsvImportResult extends VaultRouteResult {
  const CsvImportResult({
    required this.filePath,
    required this.avoidDuplicates,
  });

  final String filePath;
  final bool avoidDuplicates;

  @override
  List<Object?> get props => [filePath, avoidDuplicates];
}

final class _RedactedRouteValue {
  const _RedactedRouteValue();

  @override
  bool operator ==(Object other) => other is _RedactedRouteValue;

  @override
  int get hashCode => 0;

  @override
  String toString() => '<redacted>';
}

@immutable
final class VaultOperationId {
  const VaultOperationId._(this._value);

  final int _value;

  @override
  bool operator ==(Object other) =>
      other is VaultOperationId && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'VaultOperationId(<redacted>)';
}

typedef VaultSurfaceBuilder = Widget Function(BuildContext context);

sealed class VaultSurface<R extends VaultRouteResult> {
  const VaultSurface({required this.builder});

  final VaultSurfaceBuilder builder;
}

final class EntrySurface<R extends VaultRouteResult> extends VaultSurface<R> {
  const EntrySurface({required super.builder});
}

final class OtpScannerSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const OtpScannerSurface({required super.builder});
}

final class PasswordGeneratorSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const PasswordGeneratorSurface({required super.builder});
}

final class GroupEditSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const GroupEditSurface({required super.builder});
}

final class MoveTargetSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const MoveTargetSurface({required super.builder});
}

final class AttachmentsSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const AttachmentsSurface({required super.builder});
}

final class RecycleBinSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const RecycleBinSurface({required super.builder});
}

final class DuplicatesSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const DuplicatesSurface({required super.builder});
}

final class SyncLinkSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const SyncLinkSurface({required super.builder});
}

final class SyncConflictSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const SyncConflictSurface({required super.builder});
}

final class DatabaseSettingsSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const DatabaseSettingsSurface({required super.builder});
}

final class KeyFileManagerSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const KeyFileManagerSurface({required super.builder});
}

final class ConfirmationSurface<R extends VaultRouteResult>
    extends VaultSurface<R> {
  const ConfirmationSurface({required super.builder});
}

sealed class VaultSurfacePresentation {
  const VaultSurfacePresentation();
}

final class VaultRoutePresentation extends VaultSurfacePresentation {
  const VaultRoutePresentation();
}

final class VaultSheetPresentation extends VaultSurfacePresentation {
  const VaultSheetPresentation();
}

final class VaultPanePresentation extends VaultSurfacePresentation {
  const VaultPanePresentation();
}

VaultSurfacePresentation presentationFor<R extends VaultRouteResult>(
  VaultSurface<R> surface,
  double width,
) {
  final mobile = width < 600;
  return switch (surface) {
    EntrySurface() ||
    OtpScannerSurface() ||
    AttachmentsSurface() ||
    RecycleBinSurface() ||
    DuplicatesSurface() ||
    SyncLinkSurface() ||
    DatabaseSettingsSurface() =>
      mobile ? const VaultRoutePresentation() : const VaultPanePresentation(),
    PasswordGeneratorSurface() ||
    GroupEditSurface() ||
    MoveTargetSurface() ||
    SyncConflictSurface() =>
      mobile ? const VaultSheetPresentation() : const VaultPanePresentation(),
    KeyFileManagerSurface() ||
    ConfirmationSurface() => const VaultSheetPresentation(),
  };
}

typedef VaultOperationIdFactory = VaultOperationId Function();
typedef VaultPaneChanged = void Function(Widget? pane);
typedef VaultModalHost =
    Future<void> Function(
      BuildContext context,
      WidgetBuilder builder,
      void Function(VoidCallback dismiss) mounted,
    );

final class VaultShellRouter {
  VaultShellRouter({
    VaultPaneChanged? onPaneChanged,
    VaultOperationIdFactory? operationIdFactory,
    VaultModalHost? routeHost,
    VaultModalHost? sheetHost,
  }) : _onPaneChanged = onPaneChanged,
       _operationIdFactory = operationIdFactory,
       _routeHost = routeHost,
       _sheetHost = sheetHost;

  final VaultPaneChanged? _onPaneChanged;
  final VaultOperationIdFactory? _operationIdFactory;
  final VaultModalHost? _routeHost;
  final VaultModalHost? _sheetHost;
  final Map<VaultOperationId, _VaultOperationSession> _sessions = {};
  final Set<VaultOperationId> _issuedIds = {};
  int _nextId = 0;
  int _nextSequence = 0;
  bool _disposed = false;

  @visibleForTesting
  int get debugLiveSessionCount => _sessions.length;

  @visibleForTesting
  bool debugRetainsOperation(VaultOperationId id) => _sessions.containsKey(id);

  Future<R?> open<R extends VaultRouteResult>({
    required BuildContext context,
    required VaultSurface<R> surface,
    double? width,
  }) {
    if (_disposed) {
      return Future<R?>.value();
    }

    final id = _newId();
    final parentId = VaultOperationScope.maybeOf(context)?.operationId;
    final presentation = presentationFor(
      surface,
      width ?? MediaQuery.sizeOf(context).width,
    );
    final session = _TypedVaultOperationSession<R>(
      id: id,
      parentId: parentId,
      sequence: _nextSequence++,
      presentation: presentation,
      surface: surface,
    );
    _sessions[id] = session;

    switch (presentation) {
      case VaultRoutePresentation():
        unawaited(_hostRoute(context, session));
      case VaultSheetPresentation():
        unawaited(_hostSheet(context, session));
      case VaultPanePresentation():
        _hostPane(session);
    }

    return session.future;
  }

  Future<ConfirmDecision?> confirm({
    required BuildContext context,
    required String title,
    required String body,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
  }) {
    return open<ConfirmDecision>(
      context: context,
      surface: ConfirmationSurface<ConfirmDecision>(
        builder: (surfaceContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => VaultOperationScope.of(
                surfaceContext,
              ).complete(ConfirmDecision.cancel),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => VaultOperationScope.of(
                surfaceContext,
              ).complete(ConfirmDecision.confirm),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  void complete<R extends VaultRouteResult>(VaultOperationId id, R result) {
    final session = _sessions[id];
    if (session == null || !session.accepts(result)) {
      return;
    }
    _finish(id, result);
  }

  void cancel(VaultOperationId id) => _finish(id, null);

  Future<bool> requestCancel(VaultOperationId id) async {
    final session = _sessions[id];
    if (session == null) {
      return true;
    }
    final guard = session.discardGuard;
    if (guard != null && !await guard()) {
      return false;
    }
    cancel(id);
    return true;
  }

  Future<bool> cancelForDestinationChange() async {
    if (_sessions.isEmpty) {
      return true;
    }
    final latest = _sessions.values.reduce(
      (left, right) => left.sequence > right.sequence ? left : right,
    );
    final guard = latest.discardGuard;
    if (guard != null && !await guard()) {
      return false;
    }
    _cancelAll();
    return true;
  }

  Future<bool> requestCancelCurrentPane() async {
    final panes = _sessions.values
        .where((session) => session.presentation is VaultPanePresentation)
        .toList(growable: false);
    if (panes.isEmpty) {
      return false;
    }
    panes.sort((left, right) => right.sequence.compareTo(left.sequence));
    return requestCancel(panes.first.id);
  }

  void registerDiscardGuard(
    VaultOperationId id,
    Future<bool> Function()? guard,
  ) {
    _sessions[id]?.discardGuard = guard;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelAll();
  }

  VaultOperationId _newId() {
    final id = _operationIdFactory?.call() ?? VaultOperationId._(_nextId++);
    if (!_issuedIds.add(id)) {
      throw StateError('Vault operation IDs must never be reused.');
    }
    return id;
  }

  Widget _buildScoped(_VaultOperationSession session) {
    return Builder(
      builder: (context) {
        if (!_sessions.containsKey(session.id)) {
          return const SizedBox.shrink();
        }
        try {
          final child = session.build(context);
          return VaultOperationScope(
            operationId: session.id,
            completeOperation: (result) => complete(session.id, result),
            cancelOperation: () => requestCancel(session.id),
            registerDiscardGuard: (guard) =>
                registerDiscardGuard(session.id, guard),
            child: PopScope(
              canPop: session.allowHostRemoval,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  unawaited(requestCancel(session.id));
                }
              },
              child: child,
            ),
          );
        } catch (_) {
          cancel(session.id);
          return const SizedBox.shrink();
        }
      },
    );
  }

  Future<void> _hostRoute(
    BuildContext context,
    _VaultOperationSession session,
  ) async {
    try {
      await (_routeHost ?? _defaultRouteHost)(
        context,
        (_) => _buildScoped(session),
        (dismiss) => session.dismissHost = dismiss,
      );
    } finally {
      cancel(session.id);
    }
  }

  Future<void> _hostSheet(
    BuildContext context,
    _VaultOperationSession session,
  ) async {
    try {
      await (_sheetHost ?? _defaultSheetHost)(
        context,
        (_) => _buildScoped(session),
        (dismiss) => session.dismissHost = dismiss,
      );
    } finally {
      cancel(session.id);
    }
  }

  void _hostPane(_VaultOperationSession session) {
    session.hostedWidget = KeyedSubtree(
      key: ValueKey(session.id),
      child: _buildScoped(session),
    );
    _publishTopPane();
  }

  Future<void> _defaultRouteHost(
    BuildContext context,
    WidgetBuilder builder,
    void Function(VoidCallback dismiss) mounted,
  ) async {
    final navigator = Navigator.of(context);
    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      builder: (routeContext) => Scaffold(body: builder(routeContext)),
    );
    mounted(() {
      if (route.isActive) {
        navigator.removeRoute(route);
      }
    });
    await navigator.push<void>(route);
  }

  Future<void> _defaultSheetHost(
    BuildContext context,
    WidgetBuilder builder,
    void Function(VoidCallback dismiss) mounted,
  ) async {
    final width = MediaQuery.sizeOf(context).width;
    BuildContext? sheetContext;
    mounted(() {
      final current = sheetContext;
      if (current != null && Navigator.of(current).canPop()) {
        Navigator.of(current).pop();
      }
    });
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      constraints: width < 600 ? null : const BoxConstraints(maxWidth: 560),
      builder: (modalContext) {
        sheetContext = modalContext;
        return SafeArea(child: builder(modalContext));
      },
    );
  }

  void _finish(VaultOperationId id, VaultRouteResult? result) {
    final session = _sessions.remove(id);
    if (session == null) {
      return;
    }

    final childIds = _sessions.values
        .where((candidate) => candidate.parentId == id)
        .map((candidate) => candidate.id)
        .toList(growable: false);
    for (final childId in childIds) {
      cancel(childId);
    }

    try {
      session.pendingResult = result;
      session.complete(result);
      session.allowHostRemoval = true;
      session.dismissHost?.call();
    } finally {
      session.clear();
      _publishTopPane();
    }
  }

  void _cancelAll() {
    final ids = _sessions.keys.toList(growable: false).reversed;
    for (final id in ids) {
      cancel(id);
    }
  }

  void _publishTopPane() {
    if (_onPaneChanged == null) {
      return;
    }
    final panes = _sessions.values
        .where(
          (session) =>
              session.presentation is VaultPanePresentation &&
              session.hostedWidget != null,
        )
        .toList(growable: false);
    if (panes.isEmpty) {
      _onPaneChanged(null);
      return;
    }
    panes.sort((left, right) => right.sequence.compareTo(left.sequence));
    _onPaneChanged(panes.first.hostedWidget);
  }
}

abstract class _VaultOperationSession {
  _VaultOperationSession({
    required this.id,
    required this.parentId,
    required this.sequence,
    required this.presentation,
  });

  final VaultOperationId id;
  final VaultOperationId? parentId;
  final int sequence;
  final VaultSurfacePresentation presentation;
  Widget? hostedWidget;
  VoidCallback? dismissHost;
  Future<bool> Function()? discardGuard;
  VaultRouteResult? pendingResult;
  bool allowHostRemoval = false;

  Future<VaultRouteResult?> get future;
  bool accepts(VaultRouteResult result);
  Widget build(BuildContext context);
  void complete(VaultRouteResult? result);

  void clear() {
    hostedWidget = null;
    dismissHost = null;
    discardGuard = null;
    pendingResult = null;
    clearSurface();
  }

  void clearSurface();
}

final class _TypedVaultOperationSession<R extends VaultRouteResult>
    extends _VaultOperationSession {
  _TypedVaultOperationSession({
    required super.id,
    required super.parentId,
    required super.sequence,
    required super.presentation,
    required VaultSurface<R> surface,
  }) : _surface = surface;

  final Completer<R?> _completer = Completer<R?>();
  VaultSurface<R>? _surface;

  @override
  Future<R?> get future => _completer.future;

  @override
  bool accepts(VaultRouteResult result) => result is R;

  @override
  Widget build(BuildContext context) => _surface!.builder(context);

  @override
  void complete(VaultRouteResult? result) {
    if (!_completer.isCompleted) {
      _completer.complete(result as R?);
    }
  }

  @override
  void clearSurface() => _surface = null;
}

final class VaultOperationScope extends InheritedWidget {
  const VaultOperationScope({
    super.key,
    required this.operationId,
    required this.completeOperation,
    required this.cancelOperation,
    required this.registerDiscardGuard,
    required super.child,
  });

  final VaultOperationId operationId;
  final ValueChanged<VaultRouteResult> completeOperation;
  final Future<void> Function() cancelOperation;
  final ValueChanged<Future<bool> Function()?> registerDiscardGuard;

  void complete<R extends VaultRouteResult>(R result) =>
      completeOperation(result);

  Future<void> cancel() => cancelOperation();

  static VaultOperationScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No VaultOperationScope found in context.');
    return scope!;
  }

  static VaultOperationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VaultOperationScope>();

  @override
  bool updateShouldNotify(VaultOperationScope oldWidget) =>
      operationId != oldWidget.operationId;
}

final class VaultShellRouterScope extends InheritedWidget {
  const VaultShellRouterScope({
    super.key,
    required this.router,
    required super.child,
  });

  final VaultShellRouter router;

  static VaultShellRouter of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<VaultShellRouterScope>();
    assert(scope != null, 'No VaultShellRouterScope found in context.');
    return scope!.router;
  }

  @override
  bool updateShouldNotify(VaultShellRouterScope oldWidget) =>
      router != oldWidget.router;
}
