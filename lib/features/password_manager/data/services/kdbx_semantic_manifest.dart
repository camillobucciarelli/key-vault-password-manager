// spec-008 T301/T309 — the canonical semantic manifest of a KDBX file.
//
// **What it is for.** FR-1 requires that a serialized merge candidate is
// reopened with the original credentials and its semantic manifest validated
// before anything replaces the target. "Semantic" is the operative word:
// encryption salts, IVs, the master seed and the ciphertext differ on every
// single serialization of the *same* content, so a byte comparison would report
// every candidate as corrupt. This structure is what two KDBX files are
// compared on instead.
//
// **Provenance.** This is a promotion of the Gate 0 spike manifest
// (`vault_kdbx_service_test.dart`, T001/T002), unchanged in substance. That
// manifest is the executed evidence the T201 freeze was taken from, so it is
// the one this file reproduces rather than a fresh design.
//
// **A known tension, recorded rather than resolved.** FR-7's manifest-
// completeness invariant says the manifest must be "defined by exclusion from a
// closed list — salts, master seed, IVs, ciphertext, `HeaderHash` — and never
// by inclusion of a hand-maintained field list", because a semantic field left
// out is a field on which a real divergence finalizes in silence. This
// implementation is an *inclusion* list. It matches the Gate 0 evidence, and it
// is sufficient for FR-1's serialization-parity check (T309), where both sides
// of the comparison are produced by this same code and an omission cannot hide
// a divergence between two devices. It is **not** yet sufficient for FR-7 step
// 5's short-circuit arbiter, which compares content produced by two different
// devices. Raised with slice 2 and left for T401, which owns that comparison.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kdbx/kdbx.dart';
import 'package:xml/xml.dart';

/// The canonical semantic manifest of [file].
///
/// Deterministic: every map is key-sorted, so two structurally equal files
/// produce equal manifests regardless of iteration order. History order is
/// deliberately *not* sorted — it is meaningful.
Map<String, Object?> kdbxSemanticManifest(KdbxFile file) {
  final groups = <String, Object?>{};
  final entries = <String, Object?>{};

  for (final object in file.body.rootGroup.getAllGroupsAndEntries()) {
    if (object is KdbxGroup) {
      groups[object.uuid.uuid] = _groupManifest(object);
    } else if (object is KdbxEntry) {
      entries[object.uuid.uuid] = _entryManifest(object);
    }
  }

  return {
    'header': _headerManifest(file),
    'meta': _metaManifest(file.body.meta),
    'deletedObjects': _sortedMap({
      // ignore: invalid_use_of_visible_for_testing_member
      for (final deleted in file.body.deletedObjects)
        deleted.uuid.uuid: deleted.deletionTime.get()?.toIso8601String(),
    }),
    'groups': _sortedMap(groups),
    'entries': _sortedMap(entries),
  };
}

/// Stable string form, for equality comparison and for tests that need to
/// point at the first differing path.
String kdbxManifestDigest(Map<String, Object?> manifest) =>
    sha256.convert(utf8.encode(jsonEncode(manifest))).toString();

Map<String, Object?> _headerManifest(KdbxFile file) {
  final header = file.header;
  final manifest = <String, Object?>{
    'version': '${header.version.major}.${header.version.minor}',
    'cipher': header.cipher.toString(),
    'compression': header.compression.toString(),
  };
  if (header.version.major >= KdbxVersion.V4.major) {
    final kdf = header.readKdfParameters;
    manifest['kdfUuid'] = base64.encode(
      KdfField.uuid.read(kdf) ?? Uint8List(0),
    );
    manifest['kdfIterations'] = KdfField.iterations.read(kdf);
    manifest['kdfMemory'] = KdfField.memory.read(kdf);
    manifest['kdfParallelism'] = KdfField.parallelism.read(kdf);
    manifest['kdfVersion'] = KdfField.version.read(kdf);
  }
  return manifest;
}

Map<String, Object?> _metaManifest(KdbxMeta meta) => {
  'databaseName': meta.databaseName.get(),
  'databaseDescription': meta.databaseDescription.get(),
  'defaultUserName': meta.defaultUserName.get(),
  'recycleBinEnabled': meta.recycleBinEnabled.get(),
  'recycleBinUuid': meta.recycleBinUUID.get()?.uuid,
  'historyMaxItems': meta.historyMaxItems.get(),
  'historyMaxSize': meta.historyMaxSize.get(),
  'maintenanceHistoryDays': meta.maintenanceHistoryDays.get(),
  'entryTemplatesGroup': meta.entryTemplatesGroup.get()?.uuid,
  'customData': _sortedMap({
    for (final entry in meta.customData.entries) entry.key: entry.value,
  }),
  'customIcons': _sortedMap({
    for (final icon in meta.customIcons.values)
      icon.uuid.uuid: base64.encode(icon.data),
  }),
};

Map<String, Object?> _groupManifest(KdbxGroup group) => {
  'name': group.name.get(),
  'notes': group.notes.get(),
  'parent': group.parent?.uuid.uuid,
  'icon': group.icon.get()?.index,
  'customIcon': group.customIconUuid.get()?.uuid,
  'expanded': group.expanded.get(),
  'enableAutoType': group.enableAutoType.get(),
  'enableSearching': group.enableSearching.get(),
  'defaultAutoTypeSequence': group.defaultAutoTypeSequence.get(),
  // Sibling order is part of the semantics FR-1 preserves.
  'groupOrder': group.groups.map((g) => g.uuid.uuid).toList(),
  'entryOrder': group.entries.map((e) => e.uuid.uuid).toList(),
  'times': _timesManifest(group),
};

/// [includeHistory] is false for a history revision, and that is a statement
/// about the FORMAT rather than a convenience: KDBX persists exactly one level
/// of history, and `KdbxEntry.toXml` omits `<History>` on a history entry. The
/// in-memory object nevertheless carries one — `onBeforeModify` snapshots the
/// live entry through `toXml()`, which at that moment still includes its
/// history — so a nested list exists before a save and never after one.
/// Comparing it would make the parity check fail on an artifact that no vault
/// can hold.
Map<String, Object?> _entryManifest(
  KdbxEntry entry, {
  bool includeHistory = true,
}) => {
  'parent': entry.parent?.uuid.uuid,
  'icon': entry.icon.get()?.index,
  'customIcon': entry.customIconUuid.get()?.uuid,
  'tags': entry.tags.get(),
  'overrideURL': entry.overrideURL.get(),
  // `KdbxColor` exposes no RGB accessor and defines no `==`, but the value is
  // readable: `KdbxNode.node` is a public, exported `XmlElement` and
  // `ColorNode.set` writes the RGB code straight into it.
  'foregroundColor': _xmlText(entry, 'ForegroundColor'),
  'backgroundColor': _xmlText(entry, 'BackgroundColor'),
  // Entry-level AutoType is not modelled by the installed library at all, so
  // it is compared as raw XML for the same reason.
  'autoType': _xmlString(entry, 'AutoType'),
  'times': _timesManifest(entry),
  'strings': _sortedMap({
    for (final string in entry.stringEntries)
      // Key spelling is preserved verbatim, never canonicalized.
      string.key.key: <String, Object?>{
        'protected': string.value is ProtectedValue,
        'value': string.value?.getText(),
      },
  }),
  'binaries': _sortedMap({
    for (final binary in entry.binaryEntries)
      binary.key.key: <String, Object?>{
        'protected': binary.value.isProtected,
        'inline': binary.value.isInline,
        'length': binary.value.value.length,
        // Exact bytes, compared by digest rather than by carrying them.
        'sha256': sha256.convert(binary.value.value).toString(),
      },
  }),
  // History order is meaningful; do not sort it.
  'history': includeHistory
      ? entry.history
            .map((revision) => _entryManifest(revision, includeHistory: false))
            .toList()
      : const <Object?>[],
};

// `KdbxNode.node` is a public, exported `XmlElement`, so constructs the library
// does not model are still fully observable.
XmlElement? _xmlOf(KdbxObject object, String name) {
  final matches = object.node.findElements(name).toList();
  return matches.isEmpty ? null : matches.single;
}

String? _xmlText(KdbxObject object, String name) =>
    _xmlOf(object, name)?.innerText;

String? _xmlString(KdbxObject object, String name) =>
    _xmlOf(object, name)?.toXmlString();

/// Takes the owning object because `KdbxTimes` is not an exported type.
Map<String, Object?> _timesManifest(KdbxObject object) {
  final times = object.times;
  return {
    'creationTime': times.creationTime.get()?.toIso8601String(),
    'lastModificationTime': times.lastModificationTime.get()?.toIso8601String(),
    'locationChanged': times.locationChanged.get()?.toIso8601String(),
    'expiryTime': times.expiryTime.get()?.toIso8601String(),
    'expires': times.expires.get(),
    'usageCount': times.usageCount.get(),
  };
}

Map<String, Object?> _sortedMap(Map<String, Object?> source) {
  final keys = source.keys.toList()..sort();
  return {for (final key in keys) key: source[key]};
}
