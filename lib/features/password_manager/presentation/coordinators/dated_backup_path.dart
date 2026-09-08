import 'package:path/path.dart' as p;

/// The dated-backup naming shared by every "durable copy before a
/// destructive change" (Constitution VII): the pre-rekey copy and, since
/// spec 017, the pre-clear-history copy.
///
/// `<name>.<yyyyMMdd-HHmmss-ffffff>.<suffix><ext>`, next to the database —
/// the same convention as spec-008's `.pre-merge.kdbx` backups.
String datedBackupPath(
  String databasePath, {
  required String suffix,
  DateTime? now,
}) {
  final stamp = _stamp(now ?? DateTime.now());
  return p.join(
    p.dirname(databasePath),
    '${p.basenameWithoutExtension(databasePath)}.$stamp.$suffix'
    '${p.extension(databasePath)}',
  );
}

String _stamp(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}-'
      '${now.microsecond.toString().padLeft(6, '0')}';
}
