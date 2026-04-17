import 'dart:io';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/vault_attachment.dart';
import '../../domain/models/vault_custom_field.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/models/vault_group.dart';
import '../../domain/models/vault_snapshot.dart';

class VaultKdbxService {
  static const maxAttachmentBytes = 20 * 1024 * 1024;
  static final _notesKey = KdbxKey('Notes');
  static final _standardEntryKeys = {
    KdbxKeyCommon.TITLE.key.toLowerCase(),
    KdbxKeyCommon.USER_NAME.key.toLowerCase(),
    KdbxKeyCommon.PASSWORD.key.toLowerCase(),
    KdbxKeyCommon.URL.key.toLowerCase(),
    _notesKey.key.toLowerCase(),
  };

  Future<String?> getRecycleBinGroupId({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );
    return file.recycleBin?.uuid.uuid;
  }

  Future<VaultSnapshot> loadVault({
    required String databasePath,
    required String password,
    String? keyFilePath,
    String? currentGroupId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final rootGroup = file.body.rootGroup;
    final groups = rootGroup.getAllGroups();

    final resolvedCurrentGroup = currentGroupId == null
        ? rootGroup
        : _findGroupByIdOrNull(groups, currentGroupId) ?? rootGroup;

    final groupModels = groups
        .map(
          (group) => VaultGroup(
            id: group.uuid.uuid,
            name: group.name.get() ?? 'Untitled Group',
            parentId: group.parent?.uuid.uuid,
            isRecycleBin: file.recycleBin?.uuid == group.uuid,
          ),
        )
        .toList(growable: false);

    final entryModels = resolvedCurrentGroup.entries
        .map((entry) => _mapEntry(resolvedCurrentGroup.uuid.uuid, entry))
        .toList(growable: false);

    final allEntryModels = rootGroup
        .getAllEntries()
        .map(
          (entry) =>
              _mapEntry(entry.parent?.uuid.uuid ?? rootGroup.uuid.uuid, entry),
        )
        .toList(growable: false);

    return VaultSnapshot(
      rootGroupId: rootGroup.uuid.uuid,
      currentGroupId: resolvedCurrentGroup.uuid.uuid,
      groups: groupModels,
      entries: entryModels,
      allEntries: allEntryModels,
    );
  }

  Future<List<VaultEntry>> loadRecycleBinEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final recycleBin = file.recycleBin;
    if (recycleBin == null) {
      return const [];
    }

    final entries = recycleBin.getAllEntries()
      ..sort((a, b) {
        final left = a.getString(KdbxKeyCommon.TITLE)?.getText() ?? '';
        final right = b.getString(KdbxKeyCommon.TITLE)?.getText() ?? '';
        return left.toLowerCase().compareTo(right.toLowerCase());
      });

    return entries
        .map(
          (entry) =>
              _mapEntry(entry.parent?.uuid.uuid ?? recycleBin.uuid.uuid, entry),
        )
        .toList(growable: false);
  }

  Future<List<VaultEntry>> loadAllEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final recycleBinUuid = file.recycleBin?.uuid.uuid;
    final entries = file.body.rootGroup
        .getAllEntries()
        .where((entry) {
          if (recycleBinUuid == null) return true;
          // Walk up the parent chain to check if entry is inside the recycle bin.
          KdbxGroup? group = entry.parent;
          while (group != null) {
            if (group.uuid.uuid == recycleBinUuid) return false;
            group = group.parent;
          }
          return true;
        })
        .toList()
      ..sort((a, b) {
        final left = a.getString(KdbxKeyCommon.TITLE)?.getText() ?? '';
        final right = b.getString(KdbxKeyCommon.TITLE)?.getText() ?? '';
        return left.toLowerCase().compareTo(right.toLowerCase());
      });

    return entries
        .map(
          (entry) => _mapEntry(
            entry.parent?.uuid.uuid ?? file.body.rootGroup.uuid.uuid,
            entry,
          ),
        )
        .toList(growable: false);
  }

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
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );
    final rootGroup = file.body.rootGroup;
    final group = _findGroupById(rootGroup.getAllGroups(), groupId);

    final entry = KdbxEntry.create(file, group);
    entry.setString(KdbxKeyCommon.TITLE, PlainValue(title));
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue(username));
    entry.setString(
      KdbxKeyCommon.PASSWORD,
      ProtectedValue.fromString(entryPassword),
    );
    entry.setString(KdbxKeyCommon.URL, PlainValue(url));
    entry.setString(_notesKey, PlainValue(notes));
    _setCustomFields(entry, customFields);
    group.addEntry(entry);

    await _save(databasePath, file);
    return entry.uuid.uuid;
  }

  Future<void> updateEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String title,
    required String username,
    required String entryPassword,
    required String url,
    required String notes,
    List<VaultCustomField> customFields = const [],
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    entry.setString(KdbxKeyCommon.TITLE, PlainValue(title));
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue(username));
    entry.setString(
      KdbxKeyCommon.PASSWORD,
      ProtectedValue.fromString(entryPassword),
    );
    entry.setString(KdbxKeyCommon.URL, PlainValue(url));
    entry.setString(_notesKey, PlainValue(notes));
    _setCustomFields(entry, customFields);

    await _save(databasePath, file);
  }

  Future<void> mergeEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String primaryId,
    required String secondaryId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final allEntries = file.body.rootGroup.getAllEntries();
    final primary = _findEntryById(allEntries, primaryId);
    final secondary = _findEntryById(allEntries, secondaryId);

    // Copy notes if primary notes is empty.
    final primaryNotes = primary.getString(_notesKey)?.getText() ?? '';
    final secondaryNotes = secondary.getString(_notesKey)?.getText() ?? '';
    if (primaryNotes.trim().isEmpty && secondaryNotes.trim().isNotEmpty) {
      primary.setString(_notesKey, PlainValue(secondaryNotes));
    }

    // Copy custom fields present in secondary but absent in primary.
    final primaryStringKeys = primary.stringEntries
        .map((e) => e.key.key.toLowerCase())
        .toSet();
    for (final stringEntry in secondary.stringEntries) {
      final key = stringEntry.key.key;
      if (_standardEntryKeys.contains(key.toLowerCase())) continue;
      if (!primaryStringKeys.contains(key.toLowerCase())) {
        primary.setString(KdbxKey(key), stringEntry.value ?? PlainValue(''));
      }
    }

    // Copy attachments present in secondary but absent in primary.
    final primaryAttachmentKeys =
        primary.binaryEntries.map((e) => e.key.key).toSet();
    for (final binaryEntry in secondary.binaryEntries) {
      final key = binaryEntry.key.key;
      if (!primaryAttachmentKeys.contains(key)) {
        primary.createBinary(
          isProtected: false,
          name: key,
          bytes: binaryEntry.value.value,
        );
      }
    }

    // Move secondary to recycle bin.
    file.deleteEntry(secondary);

    await _save(databasePath, file);
  }

  Future<void> changeMasterPassword({
    required String databasePath,
    required String currentPassword,
    String? keyFilePath,
    required String newPassword,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: currentPassword,
      keyFilePath: keyFilePath,
    );

    Uint8List? keyFileBytes;
    if (keyFilePath != null && keyFilePath.trim().isNotEmpty) {
      final keyFile = File(keyFilePath);
      if (!await keyFile.exists()) {
        throw Exception('Key file not found.');
      }
      keyFileBytes = await keyFile.readAsBytes();
    }

    file.credentials = Credentials.composite(
      ProtectedValue.fromString(newPassword),
      keyFileBytes,
    );
    await _save(databasePath, file);
  }

  Future<void> addAttachment({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String filePath,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final source = File(filePath);
    if (!await source.exists()) {
      throw Exception('Attachment source file not found.');
    }

    final bytes = await source.readAsBytes();
    if (bytes.length > maxAttachmentBytes) {
      throw Exception('Attachment exceeds 20 MB limit.');
    }

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    entry.createBinary(
      isProtected: false,
      name: p.basename(filePath),
      bytes: bytes,
    );
    await _save(databasePath, file);
  }

  Future<void> removeAttachment({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String attachmentKey,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    entry.removeBinary(KdbxKey(attachmentKey));
    await _save(databasePath, file);
  }

  Future<String> exportAttachment({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String attachmentKey,
    required String destinationDirectory,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    final binary = entry.getBinary(KdbxKey(attachmentKey));
    if (binary == null) {
      throw Exception('Attachment not found.');
    }

    final destination = File(p.join(destinationDirectory, attachmentKey));
    await destination.writeAsBytes(binary.value, flush: true);
    return destination.path;
  }

  Future<void> deleteEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    bool permanently = false,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);

    if (permanently) {
      file.deletePermanently(entry);
    } else {
      file.deleteEntry(entry);
    }

    await _save(databasePath, file);
  }

  Future<void> moveEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String targetGroupId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final groups = file.body.rootGroup.getAllGroups();
    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    final targetGroup = _findGroupById(groups, targetGroupId);
    file.move(entry, targetGroup);

    await _save(databasePath, file);
  }

  Future<void> createGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String parentGroupId,
    required String name,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final parentGroup = _findGroupById(
      file.body.rootGroup.getAllGroups(),
      parentGroupId,
    );
    file.createGroup(parent: parentGroup, name: name);

    await _save(databasePath, file);
  }

  Future<void> renameGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    required String newName,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final group = _findGroupById(file.body.rootGroup.getAllGroups(), groupId);
    group.name.set(newName);

    await _save(databasePath, file);
  }

  Future<void> deleteGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    bool permanently = false,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final group = _findGroupById(file.body.rootGroup.getAllGroups(), groupId);
    if (group.parent == null) {
      throw Exception('Root group cannot be deleted.');
    }

    if (permanently) {
      file.deletePermanently(group);
    } else {
      file.deleteGroup(group);
    }

    await _save(databasePath, file);
  }

  Future<bool> isGroupEmpty({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final group = _findGroupById(file.body.rootGroup.getAllGroups(), groupId);
    if (group.parent == null) {
      throw Exception('Root group cannot be deleted.');
    }

    return group.entries.isEmpty && group.groups.isEmpty;
  }

  Future<void> moveGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    required String targetGroupId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final groups = file.body.rootGroup.getAllGroups();
    final group = _findGroupById(groups, groupId);
    final targetGroup = _findGroupById(groups, targetGroupId);

    if (group.parent == null) {
      throw Exception('Root group cannot be moved.');
    }
    if (group.uuid == targetGroup.uuid) {
      throw Exception('Group cannot be moved into itself.');
    }
    if (targetGroup.isInGroup(group)) {
      throw Exception('Group cannot be moved into a descendant.');
    }

    file.move(group, targetGroup);
    await _save(databasePath, file);
  }

  Future<void> restoreEntryFromRecycleBin({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    if (!entry.isInRecycleBin()) {
      throw Exception('Entry is not in recycle bin.');
    }

    final targetGroup = _resolveRestoreTargetGroup(file, entry);
    file.move(entry, targetGroup);
    await _save(databasePath, file);
  }

  Future<void> restoreGroupFromRecycleBin({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final groups = file.body.rootGroup.getAllGroups();
    final group = _findGroupById(groups, groupId);
    if (!group.isInRecycleBin()) {
      throw Exception('Group is not in recycle bin.');
    }

    final targetGroup = _resolveRestoreTargetGroup(file, group);
    if (targetGroup == group || targetGroup.isInGroup(group)) {
      throw Exception('Invalid restore target group.');
    }

    file.move(group, targetGroup);
    await _save(databasePath, file);
  }

  Future<void> deleteEntryPermanently({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final entry = _findEntryById(file.body.rootGroup.getAllEntries(), entryId);
    if (!entry.isInRecycleBin()) {
      throw Exception('Only recycle bin entries can be permanently deleted.');
    }

    file.deletePermanently(entry);
    await _save(databasePath, file);
  }

  Future<void> deleteGroupPermanently({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final group = _findGroupById(file.body.rootGroup.getAllGroups(), groupId);
    if (!group.isInRecycleBin()) {
      throw Exception('Only recycle bin groups can be permanently deleted.');
    }
    if (group == file.recycleBin) {
      throw Exception('Recycle bin group cannot be permanently deleted.');
    }

    file.deletePermanently(group);
    await _save(databasePath, file);
  }

  Future<void> emptyRecycleBin({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final file = await _openFile(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    final recycleBin = file.recycleBin;
    if (recycleBin == null) {
      return;
    }

    final entries = recycleBin.getAllEntries();
    for (final entry in entries) {
      if (entry.parent != null) {
        file.deletePermanently(entry);
      }
    }

    final groups =
        recycleBin.getAllGroups().where((group) => group != recycleBin).toList()
          ..sort(
            (a, b) => b.breadcrumbs.length.compareTo(a.breadcrumbs.length),
          );

    for (final group in groups) {
      if (group.parent != null) {
        file.deletePermanently(group);
      }
    }

    await _save(databasePath, file);
  }

  Future<KdbxFile> _openFile({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) async {
    final dbFile = File(databasePath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found.');
    }

    Uint8List? keyFileBytes;
    if (keyFilePath != null && keyFilePath.trim().isNotEmpty) {
      final keyFile = File(keyFilePath);
      if (!await keyFile.exists()) {
        throw Exception('Key file not found.');
      }
      keyFileBytes = await keyFile.readAsBytes();
    }

    final credentials = Credentials.composite(
      ProtectedValue.fromString(password),
      keyFileBytes,
    );
    final dbBytes = await dbFile.readAsBytes();
    return KdbxFormat().read(dbBytes, credentials);
  }

  Future<void> _save(String databasePath, KdbxFile file) async {
    final bytes = await file.save();
    await File(databasePath).writeAsBytes(bytes, flush: true);
  }

  KdbxGroup _findGroupById(List<KdbxGroup> groups, String id) {
    return groups.firstWhere(
      (group) => group.uuid.uuid == id,
      orElse: () => throw Exception('Group not found.'),
    );
  }

  KdbxGroup? _findGroupByIdOrNull(List<KdbxGroup> groups, String id) {
    for (final group in groups) {
      if (group.uuid.uuid == id) {
        return group;
      }
    }
    return null;
  }

  KdbxEntry _findEntryById(List<KdbxEntry> entries, String id) {
    return entries.firstWhere(
      (entry) => entry.uuid.uuid == id,
      orElse: () => throw Exception('Entry not found.'),
    );
  }

  VaultEntry _mapEntry(String groupId, KdbxEntry entry) {
    final customFields = <VaultCustomField>[];
    for (final stringEntry in entry.stringEntries) {
      final key = stringEntry.key.key;
      if (_standardEntryKeys.contains(key.toLowerCase())) {
        continue;
      }
      customFields.add(
        VaultCustomField(key: key, value: stringEntry.value?.getText() ?? ''),
      );
    }

    final attachments = entry.binaryEntries
        .map(
          (binaryEntry) => VaultAttachment(
            key: binaryEntry.key.key,
            name: binaryEntry.key.key,
            size: binaryEntry.value.value.length,
          ),
        )
        .toList(growable: false);

    final otpUri = _resolveOtpUri(customFields);
    final createdAt = entry.times.creationTime.get()?.toLocal();
    final updatedAt = entry.times.lastModificationTime.get()?.toLocal();

    return VaultEntry(
      id: entry.uuid.uuid,
      groupId: groupId,
      title: entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '',
      username: entry.getString(KdbxKeyCommon.USER_NAME)?.getText() ?? '',
      password: entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '',
      url: entry.getString(KdbxKeyCommon.URL)?.getText() ?? '',
      notes: entry.getString(_notesKey)?.getText() ?? '',
      customFields: customFields,
      attachments: attachments,
      otpUri: otpUri,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastPasswordChangedAt: _resolveLastPasswordChangedAt(
        entry,
        fallbackCreatedAt: createdAt,
      ),
    );
  }

  DateTime? _resolveLastPasswordChangedAt(
    KdbxEntry entry, {
    DateTime? fallbackCreatedAt,
  }) {
    final revisions = <KdbxEntry>[...entry.history, entry]
      ..sort((left, right) {
        final leftTime =
            left.times.lastModificationTime.get() ??
            left.times.creationTime.get() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final rightTime =
            right.times.lastModificationTime.get() ??
            right.times.creationTime.get() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        return leftTime.compareTo(rightTime);
      });

    if (revisions.isEmpty) {
      return fallbackCreatedAt;
    }

    var previousPassword = _passwordOf(revisions.first);
    DateTime? lastChangedUtc;

    for (var i = 1; i < revisions.length; i++) {
      final current = revisions[i];
      final currentPassword = _passwordOf(current);
      if (currentPassword != previousPassword) {
        lastChangedUtc =
            current.times.lastModificationTime.get() ??
            current.times.creationTime.get();
      }
      previousPassword = currentPassword;
    }

    if (lastChangedUtc != null) {
      return lastChangedUtc.toLocal();
    }

    return fallbackCreatedAt ??
        revisions.first.times.creationTime.get()?.toLocal();
  }

  String _passwordOf(KdbxEntry entry) {
    return entry.getString(KdbxKeyCommon.PASSWORD)?.getText() ?? '';
  }

  String? _resolveOtpUri(List<VaultCustomField> customFields) {
    for (final field in customFields) {
      final key = field.key.toLowerCase().trim();
      final value = field.value.trim();
      final looksLikeOtpField =
          key == 'otp' ||
          key == 'totp' ||
          key == 'otpauth' ||
          key.contains('otp');
      if (looksLikeOtpField && value.startsWith('otpauth://')) {
        return value;
      }
    }
    return null;
  }

  void _setCustomFields(KdbxEntry entry, List<VaultCustomField> customFields) {
    final keysToRemove = entry.stringEntries
        .map((entry) => entry.key)
        .where((key) => !_standardEntryKeys.contains(key.key.toLowerCase()))
        .toList(growable: false);

    for (final key in keysToRemove) {
      entry.removeString(key);
    }

    for (final field in customFields) {
      final normalizedKey = field.key.trim();
      if (normalizedKey.isEmpty) {
        continue;
      }
      entry.setString(KdbxKey(normalizedKey), PlainValue(field.value));
    }
  }

  KdbxGroup _resolveRestoreTargetGroup(KdbxFile file, KdbxObject object) {
    final previousParentUuid = object.previousParentGroup.get();
    if (previousParentUuid != null) {
      try {
        final previousParent = file.findGroupByUuid(previousParentUuid);
        if (!previousParent.isInRecycleBin()) {
          return previousParent;
        }
      } catch (_) {
        // Ignore and fallback to root group.
      }
    }
    return file.body.rootGroup;
  }
}
