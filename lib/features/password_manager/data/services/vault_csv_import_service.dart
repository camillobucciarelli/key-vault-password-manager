import 'dart:io';

import '../../domain/models/vault_custom_field.dart';

enum VaultCsvSourceFormat {
  bitwarden,
  onePassword,
  lastPass,
  chrome,
  applePasswords,
  generic,
}

class VaultCsvImportItem {
  const VaultCsvImportItem({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.customFields = const [],
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<VaultCustomField> customFields;
}

class VaultCsvParseResult {
  const VaultCsvParseResult({
    required this.items,
    required this.skippedRows,
    required this.totalRows,
    required this.format,
  });

  final List<VaultCsvImportItem> items;
  final int skippedRows;
  final int totalRows;
  final VaultCsvSourceFormat format;
}

class VaultCsvImportService {
  static const _standardColumns = {
    'name',
    'title',
    'username',
    'password',
    'url',
    'website',
    'notes',
    'note',
  };

  static const _ignoredColumns = {'type', 'favorite', 'fav', 'reprompt'};

  Future<VaultCsvParseResult> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('CSV file not found.');
    }

    final csvContent = await file.readAsString();
    if (csvContent.trim().isEmpty) {
      throw Exception('CSV file is empty.');
    }

    final delimiter = _detectDelimiter(csvContent);
    final rows = _parseCsvRows(csvContent, delimiter);
    if (rows.isEmpty) {
      throw Exception('CSV file is empty.');
    }

    final headers = rows.first;
    if (headers.isEmpty) {
      throw Exception('CSV header is missing.');
    }

    final normalizedHeaders = headers
        .map(_normalizeHeader)
        .toList(growable: false);
    if (normalizedHeaders.every((header) => header.isEmpty)) {
      throw Exception('CSV header is invalid.');
    }

    final format = _detectFormat(normalizedHeaders);
    final items = <VaultCsvImportItem>[];
    var skippedRows = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final mapped = _mapRow(normalizedHeaders, headers, row);
      if (mapped == null) {
        skippedRows += 1;
        continue;
      }
      items.add(mapped);
    }

    return VaultCsvParseResult(
      items: items,
      skippedRows: skippedRows,
      totalRows: rows.length - 1,
      format: format,
    );
  }

  String _detectDelimiter(String csv) {
    final lines = csv.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final commaCount = ','.allMatches(trimmed).length;
      final semicolonCount = ';'.allMatches(trimmed).length;
      if (semicolonCount > commaCount) {
        return ';';
      }
      return ',';
    }
    return ',';
  }

  List<List<String>> _parseCsvRows(String csv, String delimiter) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final currentField = StringBuffer();
    var inQuotes = false;

    void flushField() {
      currentRow.add(currentField.toString().trim());
      currentField.clear();
    }

    void flushRow() {
      if (currentRow.isEmpty) {
        return;
      }
      final hasData = currentRow.any((field) => field.trim().isNotEmpty);
      if (hasData || currentRow.length > 1) {
        rows.add(List<String>.from(currentRow));
      }
      currentRow.clear();
    }

    for (var i = 0; i < csv.length; i++) {
      final char = csv[i];
      final isLast = i == csv.length - 1;

      if (char == '"') {
        if (inQuotes && i + 1 < csv.length && csv[i + 1] == '"') {
          currentField.write('"');
          i += 1;
        } else {
          inQuotes = !inQuotes;
        }
        if (isLast) {
          flushField();
          flushRow();
        }
        continue;
      }

      if (!inQuotes && char == delimiter) {
        flushField();
        if (isLast) {
          flushField();
          flushRow();
        }
        continue;
      }

      if (!inQuotes && (char == '\n' || char == '\r')) {
        if (char == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') {
          i += 1;
        }
        flushField();
        flushRow();
        continue;
      }

      currentField.write(char);

      if (isLast) {
        flushField();
        flushRow();
      }
    }

    return rows;
  }

  VaultCsvImportItem? _mapRow(
    List<String> normalizedHeaders,
    List<String> originalHeaders,
    List<String> row,
  ) {
    final map = <String, String>{};
    for (var i = 0; i < normalizedHeaders.length; i++) {
      final key = normalizedHeaders[i];
      if (key.isEmpty) {
        continue;
      }
      final value = i < row.length ? row[i].trim() : '';
      map[key] = value;
    }

    final title = _firstNonEmpty(map, const [
      'name',
      'title',
      'item',
      'site',
      'application',
      'accountname',
    ]);
    final username = _firstNonEmpty(map, const [
      'username',
      'loginusername',
      'user',
      'email',
      'account',
    ]);
    final password = _firstNonEmpty(map, const [
      'password',
      'loginpassword',
      'passcode',
    ]);
    final url = _firstNonEmpty(map, const [
      'url',
      'website',
      'loginuri',
      'siteurl',
      'origin',
    ]);
    final notes = _firstNonEmpty(map, const [
      'notes',
      'note',
      'extra',
      'comments',
    ]);

    final hasAnyMainValue =
        title.isNotEmpty ||
        username.isNotEmpty ||
        password.isNotEmpty ||
        url.isNotEmpty ||
        notes.isNotEmpty;
    if (!hasAnyMainValue) {
      return null;
    }

    final customFields = <VaultCustomField>[];
    final usedColumns = <String>{
      ..._columnsForAliases(map, const [
        'name',
        'title',
        'item',
        'site',
        'application',
        'accountname',
      ]),
      ..._columnsForAliases(map, const [
        'username',
        'loginusername',
        'user',
        'email',
        'account',
      ]),
      ..._columnsForAliases(map, const [
        'password',
        'loginpassword',
        'passcode',
      ]),
      ..._columnsForAliases(map, const [
        'url',
        'website',
        'loginuri',
        'siteurl',
        'origin',
      ]),
      ..._columnsForAliases(map, const ['notes', 'note', 'extra', 'comments']),
    };

    final otp = _firstNonEmpty(map, const [
      'logintotp',
      'otpauth',
      'otp',
      'totp',
      'verificationcode',
    ]);
    if (otp.startsWith('otpauth://')) {
      customFields.add(VaultCustomField(key: 'otp', value: otp));
      usedColumns.addAll(
        _columnsForAliases(map, const [
          'logintotp',
          'otpauth',
          'otp',
          'totp',
          'verificationcode',
        ]),
      );
    }

    for (var i = 0; i < normalizedHeaders.length; i++) {
      final normalizedHeader = normalizedHeaders[i];
      if (normalizedHeader.isEmpty || usedColumns.contains(normalizedHeader)) {
        continue;
      }
      if (_ignoredColumns.contains(normalizedHeader)) {
        continue;
      }
      final value = i < row.length ? row[i].trim() : '';
      if (value.isEmpty) {
        continue;
      }
      final rawHeader = i < originalHeaders.length
          ? originalHeaders[i].trim()
          : normalizedHeader;
      final customKey = rawHeader.isEmpty ? normalizedHeader : rawHeader;
      if (_standardColumns.contains(_normalizeHeader(customKey))) {
        continue;
      }
      customFields.add(VaultCustomField(key: customKey, value: value));
    }

    return VaultCsvImportItem(
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      customFields: customFields,
    );
  }

  String _firstNonEmpty(Map<String, String> map, List<String> aliases) {
    for (final alias in aliases) {
      for (final entry in map.entries) {
        if (entry.key == alias && entry.value.isNotEmpty) {
          return entry.value;
        }
      }
    }
    return '';
  }

  Set<String> _columnsForAliases(
    Map<String, String> map,
    List<String> aliases,
  ) {
    final result = <String>{};
    for (final alias in aliases) {
      if (map.containsKey(alias)) {
        result.add(alias);
      }
    }
    return result;
  }

  String _normalizeHeader(String value) {
    final lower = value.toLowerCase().trim();
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  VaultCsvSourceFormat _detectFormat(List<String> normalizedHeaders) {
    final headerSet = normalizedHeaders.toSet();
    if (headerSet.contains('loginuri') &&
        headerSet.contains('loginusername') &&
        headerSet.contains('loginpassword')) {
      return VaultCsvSourceFormat.bitwarden;
    }
    if (headerSet.contains('title') &&
        headerSet.contains('url') &&
        headerSet.contains('username') &&
        headerSet.contains('password') &&
        headerSet.contains('otpauth')) {
      return VaultCsvSourceFormat.applePasswords;
    }
    if (headerSet.contains('otpauth') ||
        (headerSet.contains('title') && headerSet.contains('website'))) {
      return VaultCsvSourceFormat.onePassword;
    }
    if (headerSet.contains('grouping') &&
        headerSet.contains('extra') &&
        headerSet.contains('fav')) {
      return VaultCsvSourceFormat.lastPass;
    }
    if (headerSet.contains('name') &&
        headerSet.contains('url') &&
        headerSet.contains('password') &&
        !headerSet.contains('grouping')) {
      return VaultCsvSourceFormat.chrome;
    }
    return VaultCsvSourceFormat.generic;
  }
}
