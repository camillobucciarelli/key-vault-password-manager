// spec 008 Gate 1 T111 — the platform harness itself.
//
// Gate 0 pinned WHAT an artifact must contain (`safety_evidence_schema.dart`)
// and left the runner unbuilt, which is why five checklist items could not
// start. This is that runner's body.
//
// It is a plain library, not a test, on purpose: the exact same eight cases
// must run in two places or the device evidence means nothing.
//
//   * `test/tool/safe_vault_writer_harness_test.dart` runs them on the CI
//     host on every PR, so a regression in the harness is caught by the
//     ordinary suite rather than discovered on a device six months later;
//   * `integration_test/safe_vault_writer_harness_test.dart` runs them on a
//     real target device and emits the artifact.
//
// WHAT THIS MEASURES THAT THE T110 HOST TESTS DO NOT. T110 asserts the
// writer's control flow with a faked filesystem. Everything here runs against
// the real filesystem of the real target, so the four capability booleans in
// the artifact are *measurements*, not assumptions:
//
//   * `atomicReplaceOverExisting` — does `rename(2)`/`MoveFileEx` really
//     replace an existing file on this filesystem? Windows and exFAT are the
//     reasons this is a question at all.
//   * `backupNoOverwrite` — does `create(exclusive: true)` really refuse an
//     existing name here? On a filesystem that does not honour `O_EXCL` the
//     writer's entire no-overwrite guarantee evaporates silently.
//   * `flushSupported` — is there a real fsync behind `RandomAccessFile.flush`?
//   * `directorySyncSupported` — does the post-rename directory sync work?
//
// The failure-injection cases keep using a fault seam because a real
// disk-full or a real mid-rename power cut cannot be summoned on demand; what
// changes is that everything *around* the injected fault is the real device.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:password_manager/features/password_manager/data/services/safe_vault_file_writer.dart';
import 'package:path/path.dart' as p;

import 'safety_evidence_schema.dart';

/// Bytes of the vault as it exists before a save.
final _oldBytes = Uint8List.fromList(
  List<int>.generate(4096, (i) => (i * 31 + 7) & 0xFF),
);

/// Bytes of the save being attempted. A different LENGTH as well as different
/// content, so a half-applied write is detectable by size alone.
final _newBytes = Uint8List.fromList(
  List<int>.generate(6144, (i) => (i * 17 + 3) & 0xFF),
);

/// A stable, non-cryptographic digest. `crypto` is not a dependency of this
/// layer and the artifact only needs to prove "these two byte strings are the
/// same or are not" — collisions here are not an attacker's tool, they are a
/// harness reading its own scratch files.
String digest(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'fnv1a32:${h.toRadixString(16).padLeft(8, '0')}:${bytes.length}';
}

/// One executed harness case, in the artifact's `cases[]` shape.
class HarnessCase {
  HarnessCase({
    required this.name,
    required this.injectedFailurePhase,
    required this.targetState,
    required this.passed,
    required this.finalChecksum,
    this.backupChecksum,
    this.detail,
  });

  final String name;
  final String injectedFailurePhase;

  /// `old` or `new` — never anything else when the case passed. A target that
  /// is missing, truncated or mixed is the whole failure this gate exists to
  /// detect, and it is reported here verbatim so the schema rejects it.
  final String targetState;
  final bool passed;
  final String finalChecksum;
  final String? backupChecksum;

  /// Why the case failed, in a form that names no path. `null` when it passed.
  final String? detail;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'injectedFailurePhase': injectedFailurePhase,
    'oldChecksum': digest(_oldBytes),
    'candidateChecksum': digest(_newBytes),
    'finalChecksum': finalChecksum,
    'backupChecksum': backupChecksum,
    'targetState': targetState,
    'passed': passed,
    if (detail != null) 'detail': detail,
  };
}

/// What the real filesystem under test turned out to support.
class HarnessCapabilities {
  const HarnessCapabilities({
    required this.flushSupported,
    required this.directorySyncSupported,
    required this.atomicReplaceOverExisting,
    required this.backupNoOverwrite,
  });

  final bool flushSupported;
  final bool directorySyncSupported;
  final bool atomicReplaceOverExisting;
  final bool backupNoOverwrite;
}

/// Result of one full harness run, before it is stamped with provenance.
class HarnessRun {
  const HarnessRun({required this.cases, required this.capabilities});

  final List<HarnessCase> cases;
  final HarnessCapabilities capabilities;

  bool get allPassed => cases.every((c) => c.passed);
}

// =============================================================================
// Fault seam.
//
// Deliberately a near-copy of `_FaultyIo` in the T110 unit test rather than a
// shared base class. The two exist to disagree: if a future refactor changes
// the writer's seam, the unit test and this harness must fail INDEPENDENTLY,
// because a shared fake that is quietly wrong would make both go green
// together on a writer that no longer holds its contract.
// =============================================================================

enum Fault {
  none,
  backupCreate,
  backupWrite,
  backupFlush,
  backupVerify,
  targetShortWrite,
  targetFlush,
  targetRename,
  directorySync,
}

class HarnessIo extends SafeVaultFileIo {
  HarnessIo(this.fault);

  final Fault fault;
  final _writeTargets = <RandomAccessFile, String>{};

  /// Set when [syncDirectory] was reached, i.e. the replace boundary was
  /// crossed. The post-boundary half of
  /// `interruption_before_and_after_replace_dispatch` reads this.
  bool reachedDirectorySync = false;

  static bool _isBackup(String path) => path.endsWith('.bak');

  @override
  Future<void> createExclusive(String path) {
    if (fault == Fault.backupCreate && _isBackup(path)) {
      throw const FileSystemException('injected: backup create failure');
    }
    return super.createExclusive(path);
  }

  @override
  Future<RandomAccessFile> openWrite(String path) async {
    final raf = await super.openWrite(path);
    _writeTargets[raf] = path;
    return raf;
  }

  @override
  Future<void> writeFull(RandomAccessFile file, Uint8List bytes) {
    final path = _writeTargets[file] ?? '';
    if (fault == Fault.backupWrite && _isBackup(path)) {
      throw const FileSystemException('injected: backup write failure');
    }
    if (fault == Fault.targetShortWrite && !_isBackup(path)) {
      // Disk-full: only part of the payload reaches the temp.
      return super.writeFull(
        file,
        Uint8List.sublistView(bytes, 0, bytes.length ~/ 2),
      );
    }
    return super.writeFull(file, bytes);
  }

  @override
  Future<void> flush(RandomAccessFile file) {
    final path = _writeTargets[file] ?? '';
    if (fault == Fault.backupFlush && _isBackup(path)) {
      throw const FileSystemException('injected: backup flush failure');
    }
    if (fault == Fault.targetFlush && !_isBackup(path)) {
      throw const FileSystemException('injected: disk full on flush');
    }
    return super.flush(file);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    final bytes = await super.readBytes(path);
    if (fault == Fault.backupVerify && _isBackup(path)) {
      return Uint8List.fromList(const [0xDE, 0xAD]);
    }
    return bytes;
  }

  @override
  Future<void> rename(String from, String to) {
    if (fault == Fault.targetRename && !_isBackup(to)) {
      throw const FileSystemException('injected: rename failure');
    }
    return super.rename(from, to);
  }

  @override
  Future<void> syncDirectory(String path) {
    reachedDirectorySync = true;
    if (fault == Fault.directorySync) {
      throw const FileSystemException('injected: directory sync failure');
    }
    return super.syncDirectory(path);
  }
}

// =============================================================================
// The eight required cases.
// =============================================================================

/// Runs every case in [requiredHarnessCases] inside [workspace], which must be
/// a real directory on the filesystem under test.
///
/// Never throws for a case failure: a case that blows up is recorded as
/// `passed: false` with a path-free [HarnessCase.detail], because a harness
/// that dies on the first bad platform reports nothing about the other seven
/// cases — and "no artifact" and "artifact says the platform is unsafe" are
/// exactly the two outcomes the gate must be able to tell apart.
Future<HarnessRun> runHarness(
  Directory workspace, {
  void Function(String key, Object? value)? report,
}) async {
  final say = report ?? (_, _) {};
  final cases = <HarnessCase>[];

  Future<void> record(
    String name,
    Future<HarnessCase> Function(Directory dir) body,
  ) async {
    final dir = Directory(p.join(workspace.path, name));
    await dir.create(recursive: true);
    HarnessCase result;
    try {
      result = await body(dir);
    } catch (error) {
      result = HarnessCase(
        name: name,
        injectedFailurePhase: name,
        targetState: 'unknown',
        passed: false,
        finalChecksum: 'n/a',
        detail: 'harness case threw: ${error.runtimeType}',
      );
    }
    say('CASE', '${result.name}=${result.passed ? "pass" : "FAIL"}');
    if (result.detail != null) {
      say('CASE_DETAIL', '${result.name}: ${result.detail}');
    }
    cases.add(result);
  }

  await record('backup_same_microsecond_collision', _sameMicrosecondCollision);
  await record('backup_preexisting_name_collision', _preexistingNameCollision);
  await record(
    'backup_create_failure',
    (d) => _abortsBeforeTarget(d, 'backup_create_failure', Fault.backupCreate),
  );
  await record('backup_write_flush_verify_failure', _backupWriteFlushVerify);
  await record(
    'target_short_write_failure',
    (d) => _abortsBeforeTarget(
      d,
      'target_short_write_failure',
      Fault.targetShortWrite,
      expectNoTempResidue: true,
    ),
  );
  await record(
    'target_flush_failure',
    (d) => _abortsBeforeTarget(
      d,
      'target_flush_failure',
      Fault.targetFlush,
      expectNoTempResidue: true,
    ),
  );
  await record(
    'target_rename_failure',
    (d) => _abortsBeforeTarget(
      d,
      'target_rename_failure',
      Fault.targetRename,
      expectRetainedBackup: true,
    ),
  );
  await record(
    'interruption_before_and_after_replace_dispatch',
    _interruptionAroundReplace,
  );

  final capabilities = await _measureCapabilities(workspace, cases, say);
  return HarnessRun(cases: cases, capabilities: capabilities);
}

Future<File> _seedTarget(Directory dir) async {
  final target = File(p.join(dir.path, 'vault.kdbx'));
  await target.writeAsBytes(_oldBytes, flush: true);
  return target;
}

/// The target must be byte-identical to the pre-write vault.
Future<String> _finalChecksum(File target) async {
  if (!await target.exists()) {
    return 'MISSING';
  }
  return digest(await target.readAsBytes());
}

List<File> _backupsIn(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.bak'))
    .toList();

List<File> _tempsIn(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.tmp'))
    .toList();

/// FR-9 steps 2/3, half one: a frozen clock must not be able to make two
/// backups collide into one file.
///
/// This is the case that would silently destroy the previous backup on a
/// filesystem that does not honour exclusive create — the writer asks for the
/// same `<target>.<micros>-<suffix>.bak` stem twice within one microsecond and
/// only the random suffix plus `O_EXCL` keep them apart.
Future<HarnessCase> _sameMicrosecondCollision(Directory dir) async {
  final target = await _seedTarget(dir);
  final frozen = DateTime.utc(2026, 1, 1);
  final writer = SafeVaultFileWriter(clock: () => frozen);

  final first = await writer.createBackup(target.path, operation: 'harness');
  final second = await writer.createBackup(target.path, operation: 'harness');

  final backups = _backupsIn(dir);
  final distinct = first != second;
  final both = backups.length == 2;
  final firstIntact = digest(await File(first).readAsBytes()) ==
      digest(_oldBytes);
  final secondIntact = digest(await File(second).readAsBytes()) ==
      digest(_oldBytes);
  final finalSum = await _finalChecksum(target);
  final targetUntouched = finalSum == digest(_oldBytes);
  final passed =
      distinct && both && firstIntact && secondIntact && targetUntouched;

  return HarnessCase(
    name: 'backup_same_microsecond_collision',
    injectedFailurePhase: 'frozen_clock_two_backups',
    targetState: targetUntouched ? 'old' : 'unknown',
    passed: passed,
    finalChecksum: finalSum,
    backupChecksum: firstIntact ? digest(_oldBytes) : 'CORRUPT',
    detail: passed
        ? null
        : 'distinct=$distinct count=${backups.length} '
              'firstIntact=$firstIntact secondIntact=$secondIntact '
              'targetUntouched=$targetUntouched',
  );
}

/// FR-9 steps 2/3, half two: a backup name that is ALREADY taken must be
/// retried onto a fresh name, never overwritten.
///
/// The exact first candidate is precomputed from the same frozen clock and the
/// same seeded [Random] the writer is handed, then pre-created holding a
/// sentinel. A writer that overwrote it would destroy a real backup.
Future<HarnessCase> _preexistingNameCollision(Directory dir) async {
  final target = await _seedTarget(dir);
  final frozen = DateTime.utc(2026, 1, 1);
  const seed = 20260101;

  // Same derivation as `SafeVaultFileWriter._claimFreshName`.
  final predictedSuffix = Random(
    seed,
  ).nextInt(0x100000).toRadixString(16).padLeft(5, '0');
  final squatted = File(
    '${target.path}.${frozen.microsecondsSinceEpoch}-$predictedSuffix.bak',
  );
  final sentinel = Uint8List.fromList(const [0xC0, 0xFF, 0xEE]);
  await squatted.writeAsBytes(sentinel, flush: true);

  final writer = SafeVaultFileWriter(
    clock: () => frozen,
    random: Random(seed),
  );
  final backup = await writer.createBackup(target.path, operation: 'harness');

  final squattedIntact =
      digest(await squatted.readAsBytes()) == digest(sentinel);
  final wroteElsewhere = backup != squatted.path;
  final backupContent = digest(await File(backup).readAsBytes());
  final backupCorrect = backupContent == digest(_oldBytes);
  final finalSum = await _finalChecksum(target);
  final targetUntouched = finalSum == digest(_oldBytes);
  final passed =
      squattedIntact && wroteElsewhere && backupCorrect && targetUntouched;

  return HarnessCase(
    name: 'backup_preexisting_name_collision',
    injectedFailurePhase: 'preexisting_backup_name',
    targetState: targetUntouched ? 'old' : 'unknown',
    passed: passed,
    finalChecksum: finalSum,
    backupChecksum: backupContent,
    detail: passed
        ? null
        : 'sentinelIntact=$squattedIntact wroteElsewhere=$wroteElsewhere '
              'backupCorrect=$backupCorrect targetUntouched=$targetUntouched',
  );
}

/// The shared shape of every "a fault before the replace leaves the old vault
/// exactly as it was" case.
Future<HarnessCase> _abortsBeforeTarget(
  Directory dir,
  String name,
  Fault fault, {
  bool expectNoTempResidue = false,
  bool expectRetainedBackup = false,
}) async {
  final target = await _seedTarget(dir);
  final io = HarnessIo(fault);
  final writer = SafeVaultFileWriter(io: io);

  var threw = false;
  try {
    await writer.write(
      targetPath: target.path,
      bytes: _newBytes,
      backupExistingTarget: true,
      operation: 'harness $name',
    );
  } catch (_) {
    threw = true;
  }

  final finalSum = await _finalChecksum(target);
  final targetIsOld = finalSum == digest(_oldBytes);
  final temps = _tempsIn(dir);
  final backups = _backupsIn(dir);
  final tempResidueOk = !expectNoTempResidue || temps.isEmpty;

  var backupOk = true;
  String? backupSum;
  if (expectRetainedBackup) {
    backupOk = backups.length == 1;
    if (backupOk) {
      backupSum = digest(await backups.single.readAsBytes());
      backupOk = backupSum == digest(_oldBytes);
    }
  }

  final passed = threw && targetIsOld && tempResidueOk && backupOk;
  return HarnessCase(
    name: name,
    injectedFailurePhase: fault.name,
    targetState: targetIsOld ? 'old' : 'unknown',
    passed: passed,
    finalChecksum: finalSum,
    backupChecksum: backupSum,
    detail: passed
        ? null
        : 'threw=$threw targetIsOld=$targetIsOld '
              'tempResidue=${temps.length} backups=${backups.length} '
              'backupOk=$backupOk',
  );
}

/// FR-9 steps 1/4 as one case, because the schema names them as one: a backup
/// that cannot be written, flushed OR verified must stop the save before the
/// target is touched, and must not leave a partial backup behind.
Future<HarnessCase> _backupWriteFlushVerify(Directory dir) async {
  final phases = <Fault>[Fault.backupWrite, Fault.backupFlush, Fault.backupVerify];
  final failures = <String>[];
  var finalSum = digest(_oldBytes);

  for (final fault in phases) {
    final sub = Directory(p.join(dir.path, fault.name));
    await sub.create(recursive: true);
    final target = await _seedTarget(sub);
    final writer = SafeVaultFileWriter(io: HarnessIo(fault));

    var threw = false;
    try {
      await writer.write(
        targetPath: target.path,
        bytes: _newBytes,
        backupExistingTarget: true,
        operation: 'harness backup_write_flush_verify_failure',
      );
    } catch (_) {
      threw = true;
    }

    finalSum = await _finalChecksum(target);
    final targetIsOld = finalSum == digest(_oldBytes);
    // A partial backup must be cleaned up: a `.bak` that is NOT a faithful
    // copy is worse than none, because recovery would trust it.
    final leftovers = _backupsIn(sub);
    final residueOk = leftovers.isEmpty;
    if (!threw || !targetIsOld || !residueOk) {
      failures.add(
        '${fault.name}(threw=$threw old=$targetIsOld '
        'residue=${leftovers.length})',
      );
    }
  }

  final passed = failures.isEmpty;
  return HarnessCase(
    name: 'backup_write_flush_verify_failure',
    injectedFailurePhase: 'backup_write|backup_flush|backup_verify',
    targetState: passed ? 'old' : 'unknown',
    passed: passed,
    finalChecksum: finalSum,
    detail: passed ? null : failures.join(' '),
  );
}

/// FR-8: the replace is a boundary. Before it the save may abort and the vault
/// must be entirely old; after it the save has happened and the vault must be
/// entirely new even if the bookkeeping that follows fails.
///
/// The "after" half is what makes this more than a duplicate of
/// `target_rename_failure`: a post-boundary failure must NOT be allowed to
/// roll the target back or to report the save as lost.
Future<HarnessCase> _interruptionAroundReplace(Directory dir) async {
  // --- before the boundary ---
  final beforeDir = Directory(p.join(dir.path, 'before'))
    ..createSync(recursive: true);
  final beforeTarget = await _seedTarget(beforeDir);
  final beforeIo = HarnessIo(Fault.targetRename);
  var beforeThrew = false;
  try {
    await SafeVaultFileWriter(io: beforeIo).write(
      targetPath: beforeTarget.path,
      bytes: _newBytes,
      backupExistingTarget: true,
      operation: 'harness interruption before replace',
    );
  } catch (_) {
    beforeThrew = true;
  }
  final beforeSum = await _finalChecksum(beforeTarget);
  final beforeIsOld = beforeSum == digest(_oldBytes);
  final beforeStoppedShort = !beforeIo.reachedDirectorySync;

  // --- after the boundary ---
  final afterDir = Directory(p.join(dir.path, 'after'))
    ..createSync(recursive: true);
  final afterTarget = await _seedTarget(afterDir);
  final afterIo = HarnessIo(Fault.directorySync);
  var afterSucceeded = false;
  try {
    await SafeVaultFileWriter(io: afterIo).write(
      targetPath: afterTarget.path,
      bytes: _newBytes,
      backupExistingTarget: true,
      operation: 'harness interruption after replace',
    );
    afterSucceeded = true;
  } catch (_) {
    afterSucceeded = false;
  }
  final afterSum = await _finalChecksum(afterTarget);
  final afterIsNew = afterSum == digest(_newBytes);
  final afterCrossed = afterIo.reachedDirectorySync;

  final passed = beforeThrew &&
      beforeIsOld &&
      beforeStoppedShort &&
      afterSucceeded &&
      afterIsNew &&
      afterCrossed;

  return HarnessCase(
    name: 'interruption_before_and_after_replace_dispatch',
    injectedFailurePhase: 'rename_boundary',
    // The case ends on the post-boundary half, whose defined outcome is a
    // fully-new target.
    targetState: afterIsNew ? 'new' : 'unknown',
    passed: passed,
    finalChecksum: afterSum,
    detail: passed
        ? null
        : 'beforeThrew=$beforeThrew beforeIsOld=$beforeIsOld '
              'beforeStoppedShort=$beforeStoppedShort '
              'afterSucceeded=$afterSucceeded afterIsNew=$afterIsNew '
              'afterCrossed=$afterCrossed',
  );
}

// =============================================================================
// Capability measurement — the part a faked filesystem cannot answer.
// =============================================================================

Future<HarnessCapabilities> _measureCapabilities(
  Directory workspace,
  List<HarnessCase> cases,
  void Function(String, Object?) say,
) async {
  final dir = Directory(p.join(workspace.path, '_capabilities'))
    ..createSync(recursive: true);

  // --- atomic replace over an existing file ---
  var atomicReplace = false;
  try {
    final target = File(p.join(dir.path, 'vault.kdbx'));
    await target.writeAsBytes(_oldBytes, flush: true);
    final io = HarnessIo(Fault.none);
    final result = await SafeVaultFileWriter(io: io).write(
      targetPath: target.path,
      bytes: _newBytes,
      operation: 'harness capability probe',
    );
    // `atomic: false` is the sandbox fallback, i.e. a NON-atomic in-place
    // write. It must not be allowed to certify this platform as atomic.
    atomicReplace =
        result.atomic && digest(await target.readAsBytes()) == digest(_newBytes);
  } catch (_) {
    atomicReplace = false;
  }
  say('CAP_ATOMIC_REPLACE_OVER_EXISTING', atomicReplace);

  // --- exclusive create really refuses an existing name ---
  var noOverwrite = false;
  try {
    final squat = File(p.join(dir.path, 'claimed'));
    await squat.writeAsBytes(const [1], flush: true);
    await const SafeVaultFileIo().createExclusive(squat.path);
    // No throw means O_EXCL was not honoured; the file is still there but the
    // guarantee is gone.
    noOverwrite = false;
  } on FileSystemException {
    noOverwrite = true;
  } catch (_) {
    noOverwrite = false;
  }
  // The behavioural half: the preexisting-name case must also have passed.
  // A platform where `O_EXCL` throws but the writer still clobbers, or vice
  // versa, is not "no overwrite" by any useful definition.
  final collisionCase = cases.firstWhere(
    (c) => c.name == 'backup_preexisting_name_collision',
  );
  noOverwrite = noOverwrite && collisionCase.passed;
  say('CAP_BACKUP_NO_OVERWRITE', noOverwrite);

  // --- fsync ---
  var flushSupported = false;
  try {
    final f = File(p.join(dir.path, 'flush-probe'));
    final raf = await f.open(mode: FileMode.writeOnly);
    try {
      await raf.writeFrom(Uint8List.fromList(const [1, 2, 3]));
      await raf.flush();
      flushSupported = true;
    } finally {
      await raf.close();
    }
  } catch (_) {
    flushSupported = false;
  }
  say('CAP_FLUSH_SUPPORTED', flushSupported);

  // --- directory sync (best-effort in production, measured here) ---
  var dirSync = false;
  try {
    await const SafeVaultFileIo().syncDirectory(dir.path);
    dirSync = true;
  } catch (_) {
    dirSync = false;
  }
  say('CAP_DIRECTORY_SYNC_SUPPORTED', dirSync);

  return HarnessCapabilities(
    flushSupported: flushSupported,
    directorySyncSupported: dirSync,
    atomicReplaceOverExisting: atomicReplace,
    backupNoOverwrite: noOverwrite,
  );
}

// =============================================================================
// Artifact assembly.
// =============================================================================

/// Builds the artifact for [run], stamped with provenance supplied by the
/// caller (the device cannot know the git commit or the Flutter version).
///
/// `status` is `passed` only when every case passed AND the two guarantees the
/// schema gates on were actually measured true. The artifact is then run
/// through [validateArtifact]: a harness that assembles something the gate
/// would reject reports `failed` with the violations attached, rather than
/// emitting a file that only fails later on the host.
Map<String, dynamic> buildArtifact({
  required HarnessRun run,
  required String platform,
  required String osVersion,
  required String deviceOrRunner,
  required String filesystem,
  required String flutterVersion,
  required String dartVersion,
  required String commit,
  required String command,
  required DateTime startedAtUtc,
  required DateTime completedAtUtc,
}) {
  final caps = run.capabilities;
  final passed =
      run.allPassed && caps.atomicReplaceOverExisting && caps.backupNoOverwrite;

  final artifact = <String, dynamic>{
    'schemaVersion': 1,
    'platform': platform,
    'osVersion': osVersion,
    'deviceOrRunner': deviceOrRunner,
    'filesystem': filesystem,
    'flutterVersion': flutterVersion,
    'dartVersion': dartVersion,
    'commit': commit,
    'command': command,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
    'completedAtUtc': completedAtUtc.toUtc().toIso8601String(),
    'status': passed ? 'passed' : 'failed',
    'flushSupported': caps.flushSupported,
    'directorySyncSupported': caps.directorySyncSupported,
    'atomicReplaceOverExisting': caps.atomicReplaceOverExisting,
    'backupNoOverwrite': caps.backupNoOverwrite,
    'cases': [for (final c in run.cases) c.toJson()],
    'logPath': artifactLogPath(platform),
  };

  final violations = validateArtifact(artifact);
  if (violations.isNotEmpty) {
    artifact['status'] = 'failed';
    artifact['schemaViolations'] = violations;
  }
  return artifact;
}
