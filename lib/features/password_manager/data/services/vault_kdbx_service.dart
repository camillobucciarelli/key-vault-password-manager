import 'dart:io';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/vault_attachment.dart';
import '../../domain/models/vault_custom_field.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/models/vault_group.dart';
import '../../domain/models/vault_snapshot.dart';
import 'database_file_hash_recorder.dart';
import 'database_path_mutex.dart';
import 'safe_vault_file_writer.dart';

class KdbxCredentialChange {
  const KdbxCredentialChange({
    required this.databasePath,
    required this.backupPath,
  });

  final String databasePath;
  final String backupPath;
}

class VaultKdbxService {
  VaultKdbxService({
    this.credentialTempWriter,
    DatabasePathMutex? mutex,
    SafeVaultFileWriter? safeWriter,
    DatabaseFileHashRecorder? fileHashRecorder,
  }) : _mutex = mutex ?? DatabasePathMutex(),
       _safeWriter = safeWriter ?? SafeVaultFileWriter(),
       _fileHashRecorder = fileHashRecorder;

  /// spec 008 T105: every mutation below runs inside this lock so vault
  /// edits, sync replacement, import commits and renames on the same file
  /// serialize. NOT reentrant: no method may call another locked method
  /// from inside its action ([changeCredentials] composes sequentially).
  final DatabasePathMutex _mutex;

  final Future<void> Function(File file, Uint8List bytes)? credentialTempWriter;

  /// spec 008 T109: lock-free safe writer used INSIDE the mutex actions for
  /// every database byte write (temp + fsync + verify + atomic rename).
  final SafeVaultFileWriter _safeWriter;

  /// Invalidate/complete/rollback hash protocol (P1-4) around vault save
  /// and credential-change install/rollback. `null` in callers/tests that
  /// do not need registry hash tracking.
  final DatabaseFileHashRecorder? _fileHashRecorder;

  Future<T> _trackDatabaseWrite<T>({
    required String databasePath,
    required Uint8List bytes,
    required Future<T> Function() write,
  }) {
    final recorder = _fileHashRecorder;
    if (recorder == null) {
      return write();
    }
    return recorder.trackWrite(
      databasePath: databasePath,
      bytes: bytes,
      write: write,
    );
  }

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

    final recycleBinUuid = file.recycleBin?.uuid.uuid;
    final allEntryModels = rootGroup
        .getAllEntries()
        .where((entry) => !_isInsideRecycleBin(entry, recycleBinUuid))
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
    final entries =
        file.body.rootGroup
            .getAllEntries()
            .where((entry) => !_isInsideRecycleBin(entry, recycleBinUuid))
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
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
    });
  }

  /// spec-019 C-04-05 — copy a record, whole, beside itself.
  ///
  /// Deliberately not built on [createEntry]: that path takes the fields the
  /// editor knows about, and a record is more than those. It carries protected
  /// strings whose plaintext the caller has no reason to hold, custom fields
  /// (which is where the TOTP secret lives), and file attachments that exist
  /// only as bytes inside the database — nothing a caller could pass back in
  /// through a list of file paths.
  ///
  /// So the copy is made here, where the source entry is already open: every
  /// string with its protection flag intact, every binary, into the source's
  /// own group. The plaintext of the password is never read, only re-set from
  /// the value object.
  ///
  /// Returns the new entry's id.
  Future<String> duplicateEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String titleSuffix,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final source = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
      final group = source.parent;
      if (group == null) {
        throw Exception('Record has no group to be duplicated into.');
      }

      final copy = KdbxEntry.create(file, group);
      for (final key in source.stringEntries) {
        final value = key.value;
        if (value == null) {
          continue;
        }
        copy.setString(key.key, value);
      }
      final sourceTitle =
          source.getString(KdbxKeyCommon.TITLE)?.getText() ?? '';
      copy.setString(
        KdbxKeyCommon.TITLE,
        PlainValue('$sourceTitle$titleSuffix'),
      );

      for (final binary in source.binaryEntries) {
        copy.createBinary(
          isProtected: binary.value.isProtected,
          name: binary.key.key,
          bytes: binary.value.value,
        );
      }

      group.addEntry(copy);
      await _save(databasePath, file);
      return copy.uuid.uuid;
    });
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
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
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
    });
  }

  Future<void> mergeEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String primaryId,
    required String secondaryId,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
      final primaryAttachmentKeys = primary.binaryEntries
          .map((e) => e.key.key)
          .toSet();
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
    });
  }

  Future<void> changeCredentials({
    required String databasePath,
    required String currentPassword,
    String? currentKeyFilePath,
    required String newPassword,
    String? newKeyFilePath,
  }) async {
    final change = await beginCredentialChange(
      databasePath: databasePath,
      currentPassword: currentPassword,
      currentKeyFilePath: currentKeyFilePath,
      newPassword: newPassword,
      newKeyFilePath: newKeyFilePath,
    );
    await finalizeCredentialChange(change);
  }

  Future<KdbxCredentialChange> beginCredentialChange({
    required String databasePath,
    required String currentPassword,
    String? currentKeyFilePath,
    required String newPassword,
    String? newKeyFilePath,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: currentPassword,
        keyFilePath: currentKeyFilePath,
      );

      Uint8List? keyFileBytes;
      if (newKeyFilePath != null && newKeyFilePath.trim().isNotEmpty) {
        final keyFile = File(newKeyFilePath);
        if (!await keyFile.exists()) {
          throw Exception('Key file not found.');
        }
        keyFileBytes = await keyFile.readAsBytes();
      }

      file.credentials = Credentials.composite(
        ProtectedValue.fromString(newPassword),
        keyFileBytes,
      );
      final bytes = await file.save();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final directory = p.dirname(databasePath);
      final name = p.basename(databasePath);
      final tempFile = File(
        p.join(directory, '.$name.credentials-$suffix.tmp'),
      );
      final backupFile = File(
        p.join(directory, '.$name.credentials-$suffix.bak'),
      );
      final databaseFile = File(databasePath);

      try {
        final writer = credentialTempWriter;
        if (writer == null) {
          // T109: fsync the temp before it is verified and renamed over the
          // database — a rename of an un-fsynced temp is the classic
          // post-crash corruption.
          await _safeWriter.write(
            targetPath: tempFile.path,
            bytes: bytes,
            operation: 'credential change temp',
          );
        } else {
          await writer(tempFile, bytes);
        }
        await _openFile(
          databasePath: tempFile.path,
          password: newPassword,
          keyFilePath: newKeyFilePath,
        );

        await _trackDatabaseWrite(
          databasePath: databasePath,
          bytes: bytes,
          write: () async {
            await databaseFile.rename(backupFile.path);
            try {
              await tempFile.rename(databasePath);
            } catch (_) {
              await backupFile.rename(databasePath);
              rethrow;
            }
          },
        );

        return KdbxCredentialChange(
          databasePath: databasePath,
          backupPath: backupFile.path,
        );
      } catch (_) {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }
    });
  }

  Future<void> finalizeCredentialChange(KdbxCredentialChange change) {
    return _mutex.withDatabaseLock([change.databasePath], () async {
      final backupFile = File(change.backupPath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    });
  }

  Future<void> rollbackCredentialChange(KdbxCredentialChange change) {
    return _mutex.withDatabaseLock([change.databasePath], () async {
      final backupFile = File(change.backupPath);
      if (!await backupFile.exists()) {
        throw StateError('Credential backup is unavailable.');
      }

      final databaseFile = File(change.databasePath);
      final failedFile = File(
        '${change.databasePath}.credentials-rollback-${DateTime.now().microsecondsSinceEpoch}',
      );
      final restoredBytes = await backupFile.readAsBytes();
      await _trackDatabaseWrite(
        databasePath: change.databasePath,
        bytes: restoredBytes,
        write: () async {
          if (await databaseFile.exists()) {
            await databaseFile.rename(failedFile.path);
          }
          try {
            await backupFile.rename(change.databasePath);
          } catch (_) {
            if (await failedFile.exists() && !await databaseFile.exists()) {
              await failedFile.rename(change.databasePath);
            }
            rethrow;
          }
        },
      );
      try {
        if (await failedFile.exists()) {
          await failedFile.delete();
        }
      } catch (error, stackTrace) {
        logWarning(
          'Unable to remove a credential rollback artifact.',
          error,
          stackTrace,
        );
      }
    });
  }

  Future<void> addAttachment({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String filePath,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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

      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
      entry.createBinary(
        isProtected: false,
        name: p.basename(filePath),
        bytes: bytes,
      );
      await _save(databasePath, file);
    });
  }

  Future<void> removeAttachment({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String attachmentKey,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
      entry.removeBinary(KdbxKey(attachmentKey));
      await _save(databasePath, file);
    });
  }

  Future<String> exportAttachment({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String attachmentKey,
    required String destinationDirectory,
  }) {
    return _mutex.withDatabaseLock(
      [databasePath, p.join(destinationDirectory, attachmentKey)],
      () async {
        final file = await _openFile(
          databasePath: databasePath,
          password: password,
          keyFilePath: keyFilePath,
        );

        final entry = _findEntryById(
          file.body.rootGroup.getAllEntries(),
          entryId,
        );
        final binary = entry.getBinary(KdbxKey(attachmentKey));
        if (binary == null) {
          throw Exception('Attachment not found.');
        }

        final destination = File(p.join(destinationDirectory, attachmentKey));
        await destination.writeAsBytes(binary.value, flush: true);
        return destination.path;
      },
    );
  }

  Future<void> deleteEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    bool permanently = false,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );

      if (permanently) {
        file.deletePermanently(entry);
      } else {
        file.deleteEntry(entry);
      }

      await _save(databasePath, file);
    });
  }

  Future<void> moveEntry({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String targetGroupId,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final groups = file.body.rootGroup.getAllGroups();
      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
      final targetGroup = _findGroupById(groups, targetGroupId);
      file.move(entry, targetGroup);

      await _save(databasePath, file);
    });
  }

  Future<void> createGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String parentGroupId,
    required String name,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
    });
  }

  Future<void> renameGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    required String newName,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final group = _findGroupById(file.body.rootGroup.getAllGroups(), groupId);
      group.name.set(newName);

      await _save(databasePath, file);
    });
  }

  Future<void> deleteGroup({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
    bool permanently = false,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
    });
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
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
    });
  }

  Future<void> restoreEntryFromRecycleBin({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
      if (!entry.isInRecycleBin()) {
        throw Exception('Entry is not in recycle bin.');
      }

      final targetGroup = _resolveRestoreTargetGroup(file, entry);
      file.move(entry, targetGroup);
      await _save(databasePath, file);
    });
  }

  Future<void> restoreGroupFromRecycleBin({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
    });
  }

  Future<void> deleteEntryPermanently({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
      final file = await _openFile(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final entry = _findEntryById(
        file.body.rootGroup.getAllEntries(),
        entryId,
      );
      if (!entry.isInRecycleBin()) {
        throw Exception('Only recycle bin entries can be permanently deleted.');
      }

      file.deletePermanently(entry);
      await _save(databasePath, file);
    });
  }

  Future<void> deleteGroupPermanently({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String groupId,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
    });
  }

  Future<void> emptyRecycleBin({
    required String databasePath,
    required String password,
    String? keyFilePath,
  }) {
    return _mutex.withDatabaseLock([databasePath], () async {
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
          recycleBin
              .getAllGroups()
              .where((group) => group != recycleBin)
              .toList()
            ..sort(
              (a, b) => b.breadcrumbs.length.compareTo(a.breadcrumbs.length),
            );

      for (final group in groups) {
        if (group.parent != null) {
          file.deletePermanently(group);
        }
      }

      await _save(databasePath, file);
    });
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
    // T109: same-directory temp + fsync + verify + atomic rename. No backup
    // here: routine saves never produced one (user behaviour unchanged); the
    // old bytes stay intact until the atomic replace.
    await _trackDatabaseWrite(
      databasePath: databasePath,
      bytes: bytes,
      write: () => _safeWriter.write(
        targetPath: databasePath,
        bytes: bytes,
        operation: 'vault save',
      ),
    );
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

  bool _isInsideRecycleBin(KdbxEntry entry, String? recycleBinUuid) {
    if (recycleBinUuid == null) return false;

    KdbxGroup? group = entry.parent;
    while (group != null) {
      if (group.uuid.uuid == recycleBinUuid) return true;
      group = group.parent;
    }
    return false;
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
