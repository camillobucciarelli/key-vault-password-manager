// spec-019 — a `VaultBloc` with fake edges, for the folder tests.
//
// The bloc's constructor takes eight collaborators; the folder work concerns
// exactly one of them (none). Everything here exists so a test can say "a vault
// shaped like this" and then assert about `visibleEntries`, without a `.kdbx`
// file, a Drive account or a keychain.
//
// The fakes answer only what the paths under test call and `noSuchMethod` the
// rest, so an unrelated method arriving here fails loudly as an unimplemented
// call instead of quietly returning a plausible empty value.
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_duplicate_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_group.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_snapshot.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/services/vault_health_service.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/vault/vault_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testDatabasePath = '/vault.kdbx';

VaultEntry testEntry({
  required String id,
  required String groupId,
  String? title,
  String? username,
  String url = '',
  String notes = '',
}) => VaultEntry(
  id: id,
  groupId: groupId,
  title: title ?? 'Entry $id',
  username: username ?? 'user-$id',
  password: 'p-$id',
  url: url,
  notes: notes,
);

VaultBloc buildTestVaultBloc({
  required VaultSnapshot snapshot,
  List<VaultEntry> recycleBinEntries = const [],
  VaultDuplicateService? duplicateService,
  VaultHealthService? healthService,
  AppleAutofillV2CoordinatorContract? autofill,
  FakeVaultKdbxService? kdbx,
  SharedPreferences? folderExpansionPreferences,
  String databasePath = testDatabasePath,
}) {
  return VaultBloc(
    databasePath: databasePath,
    getSelectedKeyFilePath: () async => null,
    sessionSecretHolder: SessionSecretHolder()..set('secret'),
    vaultKdbxService:
        kdbx ??
        FakeVaultKdbxService(
          snapshot: snapshot,
          recycleBinEntries: recycleBinEntries,
        ),
    vaultCsvImportService: VaultCsvImportService(),
    vaultDuplicateService: duplicateService ?? VaultDuplicateService(),
    databaseSyncRepository: FakeSyncRepository(),
    appleAutofillV2Coordinator: autofill ?? const NoopAppleAutofillV2Coordinator(),
    vaultHealthService: healthService ?? const VaultHealthService(),
    folderExpansionPreferences: folderExpansionPreferences,
  );
}

class FakeVaultKdbxService implements VaultKdbxService {
  FakeVaultKdbxService({
    required this.snapshot,
    this.recycleBinEntries = const [],
  });

  VaultSnapshot snapshot;
  List<VaultEntry> recycleBinEntries;
  final List<String> createdInGroupIds = <String>[];

  @override
  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    // The real service echoes back the group it was asked to open, and the
    // bloc reads the selection out of the snapshot, so a fake that ignored
    // this would silently reset the folder on every reload.
    final wanted = currentGroupId ?? snapshot.currentGroupId;
    return VaultSnapshot(
      rootGroupId: snapshot.rootGroupId,
      currentGroupId: wanted,
      groups: snapshot.groups,
      entries: snapshot.entries,
      allEntries: snapshot.allEntries,
    );
  }

  @override
  Future<List<VaultEntry>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async => recycleBinEntries;

  @override
  Future<String> createEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    required String title,
    required String username,
    required String entryPassword,
    required String url,
    required String notes,
    List<VaultCustomField> customFields = const [],
  }) async {
    createdInGroupIds.add(groupId);
    final created = VaultEntry(
      id: 'created-${createdInGroupIds.length}',
      groupId: groupId,
      title: title,
      username: username,
      password: entryPassword,
      url: url,
      notes: notes,
    );
    final all = [...snapshot.allEntries, created];
    snapshot = VaultSnapshot(
      rootGroupId: snapshot.rootGroupId,
      currentGroupId: snapshot.currentGroupId,
      groups: snapshot.groups,
      entries: all,
      allEntries: all,
    );
    return created.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeSyncRepository implements DatabaseSyncRepository {
  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async => null;

  @override
  Future<bool> isConnected() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class RecordingAutofillCoordinator
    implements AppleAutofillV2CoordinatorContract {
  final List<List<VaultEntry>> published = [];

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async => published.add(List<VaultEntry>.of(entries));

  @override
  Future<void> clearCredentials({String? databasePath}) async {}

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async => const [];

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {}
}

/// A vault with a root, two top-level folders and one nested folder:
///
///     Vault (root)      e-root
///     ├── Work          e-work
///     │   └── Clients   e-client
///     └── Personal      e-personal
VaultSnapshot nestedSnapshot({String currentGroupId = 'root'}) {
  final entries = <VaultEntry>[
    testEntry(id: 'e-root', groupId: 'root', title: 'Aurora', username: 'ada'),
    testEntry(id: 'e-work', groupId: 'work', title: 'Borealis', username: 'ben'),
    testEntry(
      id: 'e-client',
      groupId: 'clients',
      title: 'Cirrus',
      username: 'cy',
    ),
    testEntry(
      id: 'e-personal',
      groupId: 'personal',
      title: 'Delta',
      username: 'dee',
    ),
  ];
  return VaultSnapshot(
    rootGroupId: 'root',
    currentGroupId: currentGroupId,
    groups: const [
      VaultGroup(id: 'root', name: 'Vault', parentId: null),
      VaultGroup(id: 'work', name: 'Work', parentId: 'root'),
      VaultGroup(id: 'clients', name: 'Clients', parentId: 'work'),
      VaultGroup(id: 'personal', name: 'Personal', parentId: 'root'),
      VaultGroup(id: 'bin', name: 'Recycle Bin', parentId: 'root', isRecycleBin: true),
    ],
    entries: entries,
    allEntries: entries,
  );
}
