import '../../domain/repositories/database_sync_repository.dart';
import '../bloc/vault/vault_bloc.dart';
import '../bloc/vault/vault_event.dart';

enum GoogleDriveReconnectContinuation { resumeSync, reloadRemoteFiles }

class GoogleDriveReconnectCoordinator {
  GoogleDriveReconnectCoordinator({required this.databaseSyncRepository});

  final DatabaseSyncRepository databaseSyncRepository;
  final Map<Object, Future<void>> _ownerInFlight = {};
  Future<void>? _authInFlight;

  Future<void> reconnect({
    required Object owner,
    required VaultBloc bloc,
    required GoogleDriveReconnectContinuation continuation,
    required bool Function() isOwnerActive,
    String remoteFilesQuery = '',
  }) {
    final inFlight = _ownerInFlight[owner];
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> operation;
    operation =
        _run(
          bloc: bloc,
          continuation: continuation,
          isOwnerActive: isOwnerActive,
          remoteFilesQuery: remoteFilesQuery,
        ).whenComplete(() {
          if (identical(_ownerInFlight[owner], operation)) {
            _ownerInFlight.remove(owner);
          }
        });
    _ownerInFlight[owner] = operation;
    return operation;
  }

  Future<void> _authenticate() {
    final inFlight = _authInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> operation;
    operation = Future.sync(databaseSyncRepository.connect).whenComplete(() {
      if (identical(_authInFlight, operation)) {
        _authInFlight = null;
      }
    });
    _authInFlight = operation;
    return operation;
  }

  Future<void> _run({
    required VaultBloc bloc,
    required GoogleDriveReconnectContinuation continuation,
    required bool Function() isOwnerActive,
    required String remoteFilesQuery,
  }) async {
    if (!isOwnerActive() || bloc.isClosed) {
      return;
    }

    try {
      await _authenticate();
    } catch (error, stackTrace) {
      if (!isOwnerActive() || bloc.isClosed) {
        return;
      }
      bloc.add(
        GoogleDriveReconnectFailed(
          error: error,
          stackTrace: stackTrace,
          remoteFiles:
              continuation ==
              GoogleDriveReconnectContinuation.reloadRemoteFiles,
        ),
      );
      return;
    }

    if (!isOwnerActive() || bloc.isClosed) {
      return;
    }

    if (continuation == GoogleDriveReconnectContinuation.reloadRemoteFiles) {
      try {
        final files = await databaseSyncRepository.listRemoteFiles(
          query: remoteFilesQuery,
        );
        if (!isOwnerActive() || bloc.isClosed) {
          return;
        }
        bloc.add(GoogleDriveReconnectSucceeded(remoteFiles: files));
      } catch (error, stackTrace) {
        if (!isOwnerActive() || bloc.isClosed) {
          return;
        }
        bloc.add(
          GoogleDriveReconnectFailed(
            error: error,
            stackTrace: stackTrace,
            remoteFiles: true,
            duringRemoteLoad: true,
          ),
        );
        return;
      }
      return;
    }

    bloc
      ..add(const GoogleDriveReconnectSucceeded())
      ..add(const BackgroundDriveSync());
  }
}
