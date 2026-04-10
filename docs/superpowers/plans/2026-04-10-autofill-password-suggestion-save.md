# Autofill: Password Suggestion & Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement proper password suggestion (fill + strong password generation) and password saving on iOS and Android, with KeePass-standard field compliance.

**Architecture:** Extract a `PasswordGeneratorService` to the domain layer; update `VaultAutofillMatcher` to recognise KeePass-standard `KPH:` fields and `androidapp://`/`iosbundleid://` URL schemes; update the Android coordinator to save with standard field names and offer a generated-password dataset; upgrade the iOS snapshot pipeline to register credentials in `ASCredentialIdentityStore` and process pending saves; rewrite the iOS `CredentialProviderViewController` to filter by service identifiers and support iOS 17 strong-password suggestion.

**Tech Stack:** Flutter/Dart (get_it DI), Swift (AuthenticationServices, ASCredentialIdentityStore, UserDefaults App Group), `flutter_autofill_service ^0.21.0`.

---

## File Map

| File | Action |
|------|--------|
| `lib/features/password_manager/domain/services/password_generator_service.dart` | **Create** |
| `test/features/password_manager/domain/services/password_generator_service_test.dart` | **Create** |
| `lib/features/password_manager/presentation/screens/vault/vault_dialog_password.part.dart` | **Modify** — use `PasswordGeneratorService` |
| `lib/features/password_manager/di/password_manager_domain_di.dart` | **Modify** — register service |
| `lib/features/password_manager/di/password_manager_data_di.dart` | **Modify** — inject into coordinators |
| `lib/features/password_manager/domain/services/vault_autofill_matcher.dart` | **Modify** — `androidapp://`, `iosbundleid://`, `KPH:` keys |
| `test/features/password_manager/domain/services/vault_autofill_matcher_test.dart` | **Modify** — new matcher tests |
| `lib/features/password_manager/data/services/android_autofill_coordinator.dart` | **Modify** — `KPH: androidPackage`, generated-password dataset |
| `lib/features/password_manager/data/datasources/ios_autofill_data_source.dart` | **Modify** — add `registerIdentities`, `readAndClearPendingSaves` |
| `lib/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart` | **Modify** — call `registerIdentities`, process pending saves |
| `ios/Runner/AppDelegate.swift` | **Modify** — handle `registerIdentities`, `readAndClearPendingSaves` |
| `ios/CredentialProviderExtension/SharedAutofillStore.swift` | **Modify** — decode `customFields`, add pending-saves r/w |
| `ios/CredentialProviderExtension/CredentialProviderViewController.swift` | **Rewrite** — proper matching, iOS 17 strong password, pending save on generate |
| `ios/CredentialProviderExtension/CredentialProviderPasswordGenerator.swift` | **Create** — native Swift generator |
| `ios/Podfile` | **Modify** — `platform :ios, '17.0'` |

---

## Task 1: PasswordGeneratorService (domain layer)

**Files:**
- Create: `lib/features/password_manager/domain/services/password_generator_service.dart`
- Create: `test/features/password_manager/domain/services/password_generator_service_test.dart`
- Modify: `lib/features/password_manager/di/password_manager_domain_di.dart`

- [ ] **Step 1.1 — Write the failing test**

Create `test/features/password_manager/domain/services/password_generator_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/services/password_generator_service.dart';

void main() {
  group('PasswordGeneratorService', () {
    final service = PasswordGeneratorService();

    test('generates password of requested length', () {
      final pw = service.generate(const PasswordGeneratorOptions(
        length: 20,
        includeLowercase: true,
        includeUppercase: true,
        includeDigits: true,
        includeSymbols: true,
      ));
      expect(pw.length, 20);
    });

    test('default options produce a 16-char password', () {
      final pw = service.generate(const PasswordGeneratorOptions.defaults());
      expect(pw.length, 16);
    });

    test('only includes chars from selected sets', () {
      const symbolChars = r'!@#$%^&*()-_=+[]{};:,.<>?';
      final pw = service.generate(const PasswordGeneratorOptions(
        length: 40,
        includeLowercase: false,
        includeUppercase: false,
        includeDigits: true,
        includeSymbols: false,
      ));
      for (final char in pw.split('')) {
        expect('0123456789'.contains(char), isTrue,
            reason: 'unexpected char: $char');
      }
    });

    test('always includes at least one char from each enabled set', () {
      for (var i = 0; i < 50; i++) {
        final pw = service.generate(const PasswordGeneratorOptions(
          length: 8,
          includeLowercase: true,
          includeUppercase: true,
          includeDigits: true,
          includeSymbols: true,
        ));
        expect(pw.contains(RegExp('[a-z]')), isTrue);
        expect(pw.contains(RegExp('[A-Z]')), isTrue);
        expect(pw.contains(RegExp('[0-9]')), isTrue);
        expect(pw.contains(RegExp(r'[!@#$%^&*()\-_=+\[\]{};:,.<>?]')), isTrue);
      }
    });

    test('throws when no character sets selected', () {
      expect(
        () => service.generate(const PasswordGeneratorOptions(
          length: 8,
          includeLowercase: false,
          includeUppercase: false,
          includeDigits: false,
          includeSymbols: false,
        )),
        throwsStateError,
      );
    });

    test('throws when length shorter than enabled set count', () {
      expect(
        () => service.generate(const PasswordGeneratorOptions(
          length: 3,
          includeLowercase: true,
          includeUppercase: true,
          includeDigits: true,
          includeSymbols: true,
        )),
        throwsStateError,
      );
    });
  });
}
```

- [ ] **Step 1.2 — Run test, confirm it fails**

```bash
flutter test test/features/password_manager/domain/services/password_generator_service_test.dart
```

Expected: compile error or target-not-found failure.

- [ ] **Step 1.3 — Create the service**

Create `lib/features/password_manager/domain/services/password_generator_service.dart`:

```dart
import 'dart:math' as math;

class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    required this.length,
    required this.includeLowercase,
    required this.includeUppercase,
    required this.includeDigits,
    required this.includeSymbols,
  });

  const PasswordGeneratorOptions.defaults()
      : length = 16,
        includeLowercase = true,
        includeUppercase = true,
        includeDigits = true,
        includeSymbols = true;

  final int length;
  final bool includeLowercase;
  final bool includeUppercase;
  final bool includeDigits;
  final bool includeSymbols;

  int get enabledSetsCount {
    var count = 0;
    if (includeLowercase) count++;
    if (includeUppercase) count++;
    if (includeDigits) count++;
    if (includeSymbols) count++;
    return count;
  }
}

class PasswordGeneratorService {
  static const _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = '0123456789';
  static const _symbols = r'!@#$%^&*()-_=+[]{};:,.<>?';

  String generate(PasswordGeneratorOptions options) {
    final enabledSets = <String>[];
    if (options.includeLowercase) enabledSets.add(_lowercase);
    if (options.includeUppercase) enabledSets.add(_uppercase);
    if (options.includeDigits) enabledSets.add(_digits);
    if (options.includeSymbols) enabledSets.add(_symbols);

    if (enabledSets.isEmpty) {
      throw StateError('At least one character set is required.');
    }
    if (options.length < enabledSets.length) {
      throw StateError('Length is too short for selected character sets.');
    }

    final random = math.Random.secure();
    final chars = <String>[];

    for (final set in enabledSets) {
      chars.add(_pickChar(set, random));
    }

    final combined = enabledSets.join();
    for (var i = chars.length; i < options.length; i++) {
      chars.add(_pickChar(combined, random));
    }

    for (var i = chars.length - 1; i > 0; i--) {
      final j = _secureInt(random, i + 1);
      final temp = chars[i];
      chars[i] = chars[j];
      chars[j] = temp;
    }

    return chars.join();
  }

  String _pickChar(String source, math.Random random) {
    return source[_secureInt(random, source.length)];
  }

  int _secureInt(math.Random random, int maxExclusive) {
    final limit = 256 - (256 % maxExclusive);
    while (true) {
      final value = random.nextInt(256);
      if (value < limit) return value % maxExclusive;
    }
  }
}
```

- [ ] **Step 1.4 — Run test, confirm it passes**

```bash
flutter test test/features/password_manager/domain/services/password_generator_service_test.dart
```

Expected: all 6 tests pass.

- [ ] **Step 1.5 — Register in DI**

In `lib/features/password_manager/di/password_manager_domain_di.dart`, add import and registration:

```dart
import '../domain/services/password_generator_service.dart';
// (add alongside existing imports)

// inside registerPasswordManagerDomainDependencies:
sl.registerLazySingleton(() => PasswordGeneratorService());
```

- [ ] **Step 1.6 — Update vault dialog to use the service**

In `lib/features/password_manager/presentation/screens/vault/vault_dialog_password.part.dart`:

Replace the private `_generateSecurePassword` call in `_showPasswordGeneratorDialog` with `sl<PasswordGeneratorService>().generate(options)`. Keep `_PasswordGeneratorOptions` in this file for now — it's still used as local UI state. The function `_generateSecurePassword`, `_pickSecureChar`, `_nextSecureInt` can all be deleted.

Add import at the top of the file (note: `part of` files share the parent file's imports — add in `vault_screen.dart` if not already present):

At the top of `vault_screen.dart`, ensure:
```dart
import 'package:get_it/get_it.dart';
import '../../../../../features/password_manager/domain/services/password_generator_service.dart';
```

Then in `_showPasswordGeneratorDialog`, replace:
```dart
final generatedPassword = _generateSecurePassword(options);
```
with:
```dart
final generatedPassword = GetIt.instance<PasswordGeneratorService>().generate(
  PasswordGeneratorOptions(
    length: options.length,
    includeLowercase: options.includeLowercase,
    includeUppercase: options.includeUppercase,
    includeDigits: options.includeDigits,
    includeSymbols: options.includeSymbols,
  ),
);
```

Delete the private functions `_generateSecurePassword`, `_pickSecureChar`, `_nextSecureInt` and the `import 'dart:math' as math;` import if it was only used for these functions (check `_evaluatePasswordStrength` also uses `math.log`/`math.ln2` — keep the import if so).

- [ ] **Step 1.7 — Confirm app compiles**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 1.8 — Commit**

```bash
git add lib/features/password_manager/domain/services/password_generator_service.dart \
        test/features/password_manager/domain/services/password_generator_service_test.dart \
        lib/features/password_manager/di/password_manager_domain_di.dart \
        lib/features/password_manager/presentation/screens/vault/vault_dialog_password.part.dart \
        lib/features/password_manager/presentation/screens/vault/vault_screen.dart
git commit -m "feat: extract PasswordGeneratorService to domain layer"
```

---

## Task 2: VaultAutofillMatcher — KeePass field standards

**Files:**
- Modify: `lib/features/password_manager/domain/services/vault_autofill_matcher.dart`
- Modify: `test/features/password_manager/domain/services/vault_autofill_matcher_test.dart`

- [ ] **Step 2.1 — Write failing tests for new URL schemes and KPH: keys**

Append to the existing `main()` block in `test/features/password_manager/domain/services/vault_autofill_matcher_test.dart`:

```dart
    test('matches androidapp:// URL scheme as package identifier', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank',
          username: 'alice',
          password: 'pw',
          url: 'androidapp://com.example.bank',
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches iosbundleid:// URL scheme as package identifier', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank iOS',
          username: 'alice',
          password: 'pw',
          url: 'iosbundleid://com.example.bank',
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches KPH: androidPackage custom field', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank',
          username: 'alice',
          password: 'pw',
          url: '',
          customFields: [
            const VaultCustomField(key: 'KPH: androidPackage', value: 'com.example.bank'),
          ],
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches KPH: iosBundle custom field', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank iOS',
          username: 'alice',
          password: 'pw',
          url: '',
          customFields: [
            const VaultCustomField(key: 'KPH: iosBundle', value: 'com.example.bank'),
          ],
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });
```

Note: `_entry` helper in the test file needs a `customFields` parameter. Check the existing helper at the bottom of the test file and update its signature if necessary:

```dart
VaultEntry _entry({
  required String id,
  required String title,
  required String username,
  required String password,
  required String url,
  List<VaultCustomField> customFields = const [],
  DateTime? updatedAt,
}) {
  return VaultEntry(
    id: id,
    groupId: 'group-1',
    title: title,
    username: username,
    password: password,
    url: url,
    notes: '',
    customFields: customFields,
    updatedAt: updatedAt,
  );
}
```

- [ ] **Step 2.2 — Run failing tests**

```bash
flutter test test/features/password_manager/domain/services/vault_autofill_matcher_test.dart
```

Expected: the 4 new tests fail; existing tests still pass.

- [ ] **Step 2.3 — Update `_extractPackageIdentifiers` in `VaultAutofillMatcher`**

In `lib/features/password_manager/domain/services/vault_autofill_matcher.dart`, replace the existing `_extractPackageIdentifiers` method with:

```dart
Set<String> _extractPackageIdentifiers(VaultEntry entry) {
  final values = <String>{};

  // 1. URL schemes: androidapp:// and iosbundleid://
  final trimmedUrl = entry.url.trim();
  if (trimmedUrl.isNotEmpty) {
    final uri = Uri.tryParse(trimmedUrl);
    if (uri != null) {
      if (uri.scheme == 'androidapp' || uri.scheme == 'iosbundleid') {
        final id = _normalize(uri.host.isNotEmpty ? uri.host : uri.path);
        if (id.isNotEmpty) values.add(id);
      }
    }
  }

  // 2. Custom fields: KPH: androidPackage, KPH: iosBundle, and legacy keys
  for (final field in entry.customFields) {
    final normalizedKey = _normalize(field.key);
    final isKphAndroid = normalizedKey == 'kph: androidpackage';
    final isKphIos = normalizedKey == 'kph: iosbundle';
    final isLegacy =
        normalizedKey.contains('package') ||
        normalizedKey.contains('bundle') ||
        normalizedKey.contains('androidapp') ||
        normalizedKey.contains('iosapp');

    if (!isKphAndroid && !isKphIos && !isLegacy) continue;

    final splitValues = field.value
        .split(RegExp(r'[,;\s]+'))
        .map(_normalize)
        .where((v) => v.isNotEmpty);
    values.addAll(splitValues);
  }

  // 3. URL host fallback: bare single-label hosts (e.g. "myapp") as identifier
  final domain = _domainFromUrl(entry.url);
  if (domain.isNotEmpty && !domain.contains('.')) {
    values.add(domain);
  }

  return values;
}
```

- [ ] **Step 2.4 — Run all matcher tests, confirm they pass**

```bash
flutter test test/features/password_manager/domain/services/vault_autofill_matcher_test.dart
```

Expected: all tests pass.

- [ ] **Step 2.5 — Commit**

```bash
git add lib/features/password_manager/domain/services/vault_autofill_matcher.dart \
        test/features/password_manager/domain/services/vault_autofill_matcher_test.dart
git commit -m "feat: add KeePass-standard field support to VaultAutofillMatcher"
```

---

## Task 3: Android — KPH: androidPackage on save + strong password dataset

**Files:**
- Modify: `lib/features/password_manager/data/services/android_autofill_coordinator.dart`
- Modify: `lib/features/password_manager/di/password_manager_data_di.dart`

- [ ] **Step 3.1 — Add `PasswordGeneratorService` to `AndroidAutofillCoordinator`**

In `android_autofill_coordinator.dart`, add the import and update the constructor:

```dart
import '../../domain/services/password_generator_service.dart';
```

Add to class fields and constructor:

```dart
class AndroidAutofillCoordinator with WidgetsBindingObserver {
  AndroidAutofillCoordinator({
    required this.autofillService,
    required this.getActiveDatabaseUseCase,
    required this.getSelectedKeyFilePathUseCase,
    required this.secureDataSource,
    required this.vaultKdbxService,
    required this.matcher,
    required this.passwordGenerator,   // ADD
  });

  // ... existing fields ...
  final PasswordGeneratorService passwordGenerator;  // ADD
```

- [ ] **Step 3.2 — Fix `_buildSaveCustomFields` to use `KPH: androidPackage`**

Replace the method:

```dart
List<VaultCustomField> _buildSaveCustomFields(AutofillMetadata? metadata) {
  final packages = _resolveRequestedPackages(metadata).toList()..sort();
  if (packages.isEmpty) {
    return const [];
  }
  return [VaultCustomField(key: 'KPH: androidPackage', value: packages.join(','))];
}
```

- [ ] **Step 3.3 — Add generated password dataset when no entries match**

In `_handleFillRequest`, after building `datasets`, prepend a generated-password dataset when no matches were found:

Replace the try block inside `_handleFillRequest` with:

```dart
try {
  final entries = await _resolveEntries(context);

  final matched = matcher.findBestMatches(
    entries: entries,
    packageNames: metadata?.packageNames ?? const {},
    webDomains:
        metadata?.webDomains
            .map((webDomain) => webDomain.domain)
            .toSet() ??
        const {},
  );

  final datasets = matched
      .map(
        (entry) => PwDataset(
          label: _buildLabel(entry.title, entry.username),
          username: entry.username,
          password: entry.password,
        ),
      )
      .toList(growable: true);

  // If no existing credentials match, offer a strong generated password
  if (datasets.isEmpty) {
    final generated = passwordGenerator.generate(
      const PasswordGeneratorOptions.defaults(),
    );
    datasets.insert(
      0,
      PwDataset(
        label: 'Generate secure password',
        username: '',
        password: generated,
      ),
    );
  }

  await autofillService.resultWithDatasets(datasets);
} catch (e, st) {
  logError('Unable to build Android autofill dataset.', e, st);
  await autofillService.resultWithDatasets(const []);
}
```

- [ ] **Step 3.4 — Update DI to inject `PasswordGeneratorService`**

In `lib/features/password_manager/di/password_manager_data_di.dart`, update the `AndroidAutofillCoordinator` registration:

```dart
sl.registerLazySingleton(
  () => AndroidAutofillCoordinator(
    autofillService: sl(),
    getActiveDatabaseUseCase: sl(),
    getSelectedKeyFilePathUseCase: sl(),
    secureDataSource: sl(),
    vaultKdbxService: sl(),
    matcher: sl(),
    passwordGenerator: sl(),   // ADD
  ),
);
```

- [ ] **Step 3.5 — Confirm compile**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 3.6 — Commit**

```bash
git add lib/features/password_manager/data/services/android_autofill_coordinator.dart \
        lib/features/password_manager/di/password_manager_data_di.dart
git commit -m "feat: use KPH: androidPackage on Android save and offer generated password when no match"
```

---

## Task 4: iOS snapshot — customFields in JSON + ASCredentialIdentityStore registration

**Files:**
- Modify: `ios/CredentialProviderExtension/SharedAutofillStore.swift`
- Modify: `ios/Runner/AppDelegate.swift`

> No Dart changes needed: `IosAutofillDataSource.saveSnapshot` already includes `customFields` in the JSON payload. Only the Swift side needs to decode them.

- [ ] **Step 4.1 — Add `customFields` to `SharedAutofillCredential`**

Replace the entire contents of `ios/CredentialProviderExtension/SharedAutofillStore.swift`:

```swift
import Foundation
import AuthenticationServices

struct SharedAutofillCredential: Codable {
  let id: String
  let title: String
  let username: String
  let password: String
  let url: String
  let notes: String
  let customFields: [SharedCustomField]

  struct SharedCustomField: Codable {
    let key: String
    let value: String
  }
}

final class SharedAutofillStore {
  private let appGroupId = "group.dev.camillobucciarelli.kdbxKeyVault"
  private let autofillEntriesKey = "autofill_entries_json"
  private let pendingSavesKey = "pending_autofill_saves"

  func readCredentials() -> [SharedAutofillCredential] {
    guard
      let defaults = UserDefaults(suiteName: appGroupId),
      let json = defaults.string(forKey: autofillEntriesKey),
      let data = json.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([SharedAutofillCredential].self, from: data)
    else {
      return []
    }
    return decoded.filter { !$0.username.isEmpty || !$0.password.isEmpty }
  }

  // MARK: - Pending saves (written by extension, read by main app)

  func writePendingSave(_ credential: PendingAutofillSave) {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
    var existing = readPendingSaves(defaults: defaults)
    existing.append(credential)
    if let data = try? JSONEncoder().encode(existing),
       let json = String(data: data, encoding: .utf8) {
      defaults.set(json, forKey: pendingSavesKey)
      defaults.synchronize()
    }
  }

  private func readPendingSaves(defaults: UserDefaults) -> [PendingAutofillSave] {
    guard
      let json = defaults.string(forKey: pendingSavesKey),
      let data = json.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([PendingAutofillSave].self, from: data)
    else {
      return []
    }
    return decoded
  }
}

struct PendingAutofillSave: Codable {
  let title: String
  let username: String
  let password: String
  let url: String
}
```

- [ ] **Step 4.2 — Register identities in `AppDelegate.saveSnapshot` handler**

In `ios/Runner/AppDelegate.swift`, update the `"saveSnapshot"` case to also register `ASCredentialIdentityStore` identities.

Replace the `case "saveSnapshot":` block with:

```swift
case "saveSnapshot":
  guard
    let args = call.arguments as? [String: Any],
    let entries = args["entries"] as? String
  else {
    result(
      FlutterError(
        code: "INVALID_ARGS",
        message: "Missing entries payload.",
        details: nil
      )
    )
    return
  }

  defaults.set(entries, forKey: autofillEntriesKey)
  let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
  defaults.set(timestamp, forKey: autofillLastSyncKey)
  defaults.synchronize()

  // Register credentials in ASCredentialIdentityStore
  // so they appear in the QuickType keyboard bar
  if let data = entries.data(using: .utf8),
     let decoded = try? JSONDecoder().decode([SharedAutofillCredentialPayload].self, from: data) {
    registerCredentialIdentities(from: decoded)
  }

  result(nil)
```

Then add the helper struct and registration method to `AppDelegate`:

```swift
// Add inside AppDelegate class:

private func registerCredentialIdentities(from entries: [SharedAutofillCredentialPayload]) {
  var identities: [ASPasswordCredentialIdentity] = []

  for entry in entries {
    // URL-based service identifier
    if !entry.url.isEmpty,
       let url = URL(string: entry.url),
       let host = url.host, !host.isEmpty,
       !entry.username.isEmpty {
      let serviceId = ASCredentialServiceIdentifier(identifier: host, type: .domain)
      let identity = ASPasswordCredentialIdentity(
        serviceIdentifier: serviceId,
        user: entry.username,
        recordIdentifier: entry.id
      )
      identities.append(identity)
    }

    // Bundle ID via KPH: iosBundle custom field
    if let bundleField = entry.customFields.first(where: {
      $0.key.lowercased() == "kph: iosbundle"
    }), !bundleField.value.isEmpty, !entry.username.isEmpty {
      let serviceId = ASCredentialServiceIdentifier(
        identifier: bundleField.value,
        type: .domain
      )
      let identity = ASPasswordCredentialIdentity(
        serviceIdentifier: serviceId,
        user: entry.username,
        recordIdentifier: entry.id
      )
      identities.append(identity)
    }
  }

  ASCredentialIdentityStore.shared.replaceCredentialIdentities(
    with: identities
  ) { success, error in
    if let error = error {
      print("[Autofill] Failed to register identities: \(error)")
    }
  }
}
```

Add the `SharedAutofillCredentialPayload` struct (private to `AppDelegate.swift`, mirrors the JSON the Dart side sends):

```swift
// At the bottom of AppDelegate.swift (outside the class):

private struct SharedAutofillCredentialPayload: Decodable {
  struct CustomField: Decodable {
    let key: String
    let value: String
  }
  let id: String
  let username: String
  let url: String
  let customFields: [CustomField]
}
```

- [ ] **Step 4.3 — Build the iOS app to verify Swift compiles**

```bash
flutter build ios --no-codesign 2>&1 | tail -20
```

Expected: build succeeds (or only provisioning errors, not compile errors).

- [ ] **Step 4.4 — Commit**

```bash
git add ios/CredentialProviderExtension/SharedAutofillStore.swift \
        ios/Runner/AppDelegate.swift
git commit -m "feat: register credentials in ASCredentialIdentityStore on iOS snapshot sync"
```

---

## Task 5: iOS — pending saves flow

**Files:**
- Modify: `lib/features/password_manager/data/datasources/ios_autofill_data_source.dart`
- Modify: `lib/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart`
- Modify: `ios/Runner/AppDelegate.swift`

- [ ] **Step 5.1 — Add `readAndClearPendingSaves` to `IosAutofillDataSource`**

In `lib/features/password_manager/data/datasources/ios_autofill_data_source.dart`, update the abstract interface and implementation:

```dart
abstract class IosAutofillDataSource {
  Future<void> saveSnapshot(List<VaultEntry> entries);
  Future<void> clearSnapshot();
  Future<List<Map<String, dynamic>>> readAndClearPendingSaves();
}
```

Add the implementation to `IosAutofillDataSourceImpl`:

```dart
@override
Future<List<Map<String, dynamic>>> readAndClearPendingSaves() async {
  if (!_isSupportedPlatform) return const [];

  final raw = await _channel.invokeMethod<List<dynamic>>(
    'readAndClearPendingSaves',
  );
  if (raw == null) return const [];

  return raw
      .whereType<Map<dynamic, dynamic>>()
      .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
      .toList(growable: false);
}
```

- [ ] **Step 5.2 — Handle `readAndClearPendingSaves` in `AppDelegate`**

In `ios/Runner/AppDelegate.swift`, add a new case to the switch:

```swift
case "readAndClearPendingSaves":
  let store = SharedAutofillStore()
  // SharedAutofillStore is in the extension target — use UserDefaults directly here
  guard let savesDefaults = UserDefaults(suiteName: appGroupId),
        let json = savesDefaults.string(forKey: "pending_autofill_saves"),
        let data = json.data(using: .utf8),
        let decoded = try? JSONDecoder().decode([PendingAutofillSavePayload].self, from: data)
  else {
    result([])
    return
  }

  // Clear immediately
  savesDefaults.removeObject(forKey: "pending_autofill_saves")
  savesDefaults.synchronize()

  let mapped: [[String: String]] = decoded.map { save in
    ["title": save.title, "username": save.username, "password": save.password, "url": save.url]
  }
  result(mapped)
```

Add the payload struct at the bottom of `AppDelegate.swift`:

```swift
private struct PendingAutofillSavePayload: Decodable {
  let title: String
  let username: String
  let password: String
  let url: String
}
```

Also add the constant for the pending saves key at the top of `AppDelegate`:

```swift
private let pendingSavesKey = "pending_autofill_saves"
```

- [ ] **Step 5.3 — Process pending saves in `IosAutofillSnapshotCoordinator`**

In `lib/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart`, add `_processPendingSaves` and call it at the top of `syncSnapshot`:

```dart
Future<void> syncSnapshot() async {
  if (!_initialized || _processing || !_isSupportedPlatform) {
    return;
  }

  _processing = true;
  try {
    await _processPendingSaves();   // ADD — process before refreshing snapshot

    final active = await getActiveDatabaseUseCase();
    // ... rest of existing code unchanged ...
```

Add the new method:

```dart
Future<void> _processPendingSaves() async {
  final pending = await iosAutofillDataSource.readAndClearPendingSaves();
  if (pending.isEmpty) return;

  final active = await getActiveDatabaseUseCase();
  final databasePath = active?.canonicalPath;
  if (databasePath == null || databasePath.trim().isEmpty) return;

  final password = await secureDataSource.getMasterPassword() ?? '';
  final keyFilePath = await getSelectedKeyFilePathUseCase();
  if (password.isEmpty && (keyFilePath == null || keyFilePath.isEmpty)) return;

  try {
    final vault = await vaultKdbxService.loadVault(
      databasePath: databasePath,
      password: password,
      keyFilePath: keyFilePath,
    );

    for (final save in pending) {
      final title = (save['title'] as String?) ?? '';
      final username = (save['username'] as String?) ?? '';
      final entryPassword = (save['password'] as String?) ?? '';
      final url = (save['url'] as String?) ?? '';

      if (username.isEmpty && entryPassword.isEmpty) continue;

      await vaultKdbxService.createEntry(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
        groupId: vault.rootGroupId,
        title: title.isEmpty ? (url.isEmpty ? 'Saved credential' : url) : title,
        username: username,
        entryPassword: entryPassword,
        url: url,
        notes: '',
        customFields: const [],
      );
    }
  } catch (e, st) {
    logError('Failed to process pending iOS autofill saves.', e, st);
  }
}
```

- [ ] **Step 5.4 — Build iOS to verify Swift compiles**

```bash
flutter build ios --no-codesign 2>&1 | tail -20
```

Expected: no compile errors.

- [ ] **Step 5.5 — Commit**

```bash
git add lib/features/password_manager/data/datasources/ios_autofill_data_source.dart \
        lib/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart \
        ios/Runner/AppDelegate.swift
git commit -m "feat: add iOS pending-saves queue — extension writes, main app persists to vault"
```

---

## Task 6: iOS deployment target + CredentialProviderPasswordGenerator

**Files:**
- Modify: `ios/Podfile`
- Create: `ios/CredentialProviderExtension/CredentialProviderPasswordGenerator.swift`

- [ ] **Step 6.1 — Raise deployment target in Podfile**

In `ios/Podfile`, change:

```ruby
platform :ios, '13.0'
```
to:
```ruby
platform :ios, '17.0'
```

- [ ] **Step 6.2 — Raise deployment target in Xcode project**

Open `ios/Runner.xcodeproj` in Xcode (or edit the `.pbxproj` directly). Set `IPHONEOS_DEPLOYMENT_TARGET = 17.0` for both the `Runner` target and the `CredentialProviderExtension` target.

Alternatively, run:

```bash
cd ios && sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 13.0/IPHONEOS_DEPLOYMENT_TARGET = 17.0/g' Runner.xcodeproj/project.pbxproj
```

- [ ] **Step 6.3 — Re-install pods**

```bash
cd ios && pod install && cd ..
```

Expected: pods install without errors.

- [ ] **Step 6.4 — Create `CredentialProviderPasswordGenerator.swift`**

Create `ios/CredentialProviderExtension/CredentialProviderPasswordGenerator.swift`:

```swift
import Foundation
import Security

/// A pure-Swift password generator for the Credential Provider Extension process.
/// Mirrors PasswordGeneratorService defaults: 16 chars, all character sets.
struct CredentialProviderPasswordGenerator {
  private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
  private static let digits    = Array("0123456789")
  private static let symbols   = Array("!@#$%^&*()-_=+[]{};:,.<>?")

  func generateDefault() -> String {
    let sets: [[Character]] = [
      CredentialProviderPasswordGenerator.uppercase,
      CredentialProviderPasswordGenerator.lowercase,
      CredentialProviderPasswordGenerator.digits,
      CredentialProviderPasswordGenerator.symbols,
    ]
    return generate(length: 16, sets: sets)
  }

  private func generate(length: Int, sets: [[Character]]) -> String {
    let combined = sets.flatMap { $0 }
    var chars = [Character]()

    // Guarantee one char from each set
    for set in sets {
      chars.append(secureChoice(from: set))
    }

    // Fill remaining positions
    for _ in chars.count..<length {
      chars.append(secureChoice(from: combined))
    }

    // Fisher-Yates shuffle
    for i in stride(from: chars.count - 1, through: 1, by: -1) {
      let j = secureInt(lessThan: i + 1)
      chars.swapAt(i, j)
    }

    return String(chars)
  }

  private func secureChoice<T>(from array: [T]) -> T {
    return array[secureInt(lessThan: array.count)]
  }

  private func secureInt(lessThan max: Int) -> Int {
    let limit = 256 - (256 % max)
    while true {
      var byte: UInt8 = 0
      SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
      let value = Int(byte)
      if value < limit { return value % max }
    }
  }
}
```

- [ ] **Step 6.5 — Build iOS to verify compile**

```bash
flutter build ios --no-codesign 2>&1 | tail -20
```

Expected: no compile errors.

- [ ] **Step 6.6 — Commit**

```bash
git add ios/Podfile \
        ios/Runner.xcodeproj/project.pbxproj \
        ios/CredentialProviderExtension/CredentialProviderPasswordGenerator.swift
git commit -m "feat: raise iOS deployment target to 17 and add native password generator"
```

---

## Task 7: CredentialProviderViewController rewrite

**Files:**
- Rewrite: `ios/CredentialProviderExtension/CredentialProviderViewController.swift`

This is the final and most important task. The new implementation:
1. Filters credentials by `serviceIdentifiers` in `prepareCredentialList`
2. Matches by service + username in `provideCredentialWithoutUserInteraction`
3. On iOS 17, detects `isNewPassword` requests and returns a generated strong password, writing a pending save to the App Group

- [ ] **Step 7.1 — Rewrite `CredentialProviderViewController.swift`**

Replace the entire file contents with:

```swift
import AuthenticationServices

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let store = SharedAutofillStore()
  private let generator = CredentialProviderPasswordGenerator()

  // MARK: - Credential list (user explicitly opened the extension)

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    let credentials = store.readCredentials()
    let best = topMatch(in: credentials, for: serviceIdentifiers)
      ?? credentials.first

    guard let credential = best else {
      cancelWithError(.failed, message: "No credentials available")
      return
    }

    extensionContext.completeRequest(
      withSelectedCredential: ASPasswordCredential(
        user: credential.username,
        password: credential.password
      )
    )
  }

  // MARK: - Silent fill (iOS already knows which credential to use)

  override func provideCredentialWithoutUserInteraction(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    let credentials = store.readCredentials()
    guard let matched = credentials.first(where: { credential in
      credential.username == credentialIdentity.user &&
      credentialMatchesService(
        credential,
        serviceId: credentialIdentity.serviceIdentifier
      )
    }) else {
      cancelWithError(.userInteractionRequired)
      return
    }

    extensionContext.completeRequest(
      withSelectedCredential: ASPasswordCredential(
        user: matched.username,
        password: matched.password
      )
    )
  }

  // MARK: - iOS 17: new password requests + save flow

  @available(iOS 17.0, *)
  override func provideCredentialWithoutUserInteraction(
    for credentialRequest: any ASCredentialRequest
  ) {
    if let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
       passwordRequest.isNewPassword {
      let generated = generator.generateDefault()
      let service = passwordRequest.credentialIdentity.serviceIdentifier
      let title = serviceTitle(from: service)

      // Queue for saving when the main app next resumes
      store.writePendingSave(PendingAutofillSave(
        title: title,
        username: "",
        password: generated,
        url: serviceUrl(from: service)
      ))

      extensionContext.completeRequest(
        withSelectedCredential: ASPasswordCredential(user: "", password: generated)
      )
      return
    }

    // Fallback: treat as a regular fill
    if let passwordRequest = credentialRequest as? ASPasswordCredentialRequest {
      provideCredentialWithoutUserInteraction(
        for: passwordRequest.credentialIdentity as! ASPasswordCredentialIdentity
      )
    } else {
      cancelWithError(.failed, message: "Unsupported credential type")
    }
  }

  override func prepareInterfaceForExtensionConfiguration() {
    extensionContext.completeExtensionConfigurationRequest()
  }

  // MARK: - Matching helpers

  private func topMatch(
    in credentials: [SharedAutofillCredential],
    for serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> SharedAutofillCredential? {
    var best: (credential: SharedAutofillCredential, score: Int)?

    for credential in credentials {
      var score = 0
      for serviceId in serviceIdentifiers {
        score += matchScore(credential: credential, serviceId: serviceId)
      }
      if score > 0 {
        if best == nil || score > best!.score {
          best = (credential, score)
        }
      }
    }

    return best?.credential
  }

  private func credentialMatchesService(
    _ credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Bool {
    return matchScore(credential: credential, serviceId: serviceId) > 0
  }

  private func matchScore(
    credential: SharedAutofillCredential,
    serviceId: ASCredentialServiceIdentifier
  ) -> Int {
    let identifier = serviceId.identifier.lowercased()

    // Domain match against entry URL
    if let entryHost = urlHost(from: credential.url)?.lowercased() {
      let normalizedEntry = stripCommonPrefixes(entryHost)
      let normalizedId = stripCommonPrefixes(identifier)
      if normalizedEntry == normalizedId { return 140 }
      if normalizedEntry.hasSuffix(".\(normalizedId)") ||
         normalizedId.hasSuffix(".\(normalizedEntry)") { return 110 }
      if registrable(normalizedEntry) == registrable(normalizedId) { return 80 }
    }

    // Bundle ID match via androidapp:// / iosbundleid:// URL
    if let urlScheme = URL(string: credential.url)?.scheme,
       (urlScheme == "androidapp" || urlScheme == "iosbundleid"),
       let bundleId = URL(string: credential.url)?.host?.lowercased() {
      if bundleId == identifier { return 140 }
    }

    // Bundle ID match via KPH: iosBundle / KPH: androidPackage custom fields
    for field in credential.customFields {
      let key = field.key.lowercased()
      if key == "kph: iosbundle" || key == "kph: androidpackage" {
        let values = field.value.split(whereSeparator: { ",; ".contains($0) })
          .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        if values.contains(identifier) { return 140 }
      }
    }

    return 0
  }

  // MARK: - URL utilities

  private func urlHost(from rawUrl: String) -> String? {
    let url = rawUrl.contains("://") ? URL(string: rawUrl) : URL(string: "https://\(rawUrl)")
    return url?.host
  }

  private func stripCommonPrefixes(_ domain: String) -> String {
    var d = domain
    for prefix in ["www.", "m.", "mobile."] {
      if d.hasPrefix(prefix) { d = String(d.dropFirst(prefix.count)); break }
    }
    return d
  }

  private func registrable(_ domain: String) -> String {
    let parts = domain.split(separator: ".").filter { !$0.isEmpty }
    guard parts.count >= 2 else { return domain }
    return "\(parts[parts.count - 2]).\(parts.last!)"
  }

  private func serviceTitle(from serviceId: ASCredentialServiceIdentifier) -> String {
    urlHost(from: serviceId.identifier) ?? serviceId.identifier
  }

  private func serviceUrl(from serviceId: ASCredentialServiceIdentifier) -> String {
    let id = serviceId.identifier
    return id.contains("://") ? id : "https://\(id)"
  }

  // MARK: - Error helpers

  private func cancelWithError(
    _ code: ASExtensionError.Code,
    message: String? = nil
  ) {
    var userInfo: [String: Any]? = nil
    if let message = message {
      userInfo = [NSLocalizedDescriptionKey: message]
    }
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain,
        code: code.rawValue,
        userInfo: userInfo
      )
    )
  }
}
```

- [ ] **Step 7.2 — Build the iOS app (including extension) to verify compile**

```bash
flutter build ios --no-codesign 2>&1 | tail -30
```

Expected: no Swift compile errors. (Provisioning/signing errors are expected in CI without a certificate.)

- [ ] **Step 7.3 — Commit**

```bash
git add ios/CredentialProviderExtension/CredentialProviderViewController.swift
git commit -m "feat: rewrite CredentialProviderViewController with proper matching and iOS 17 strong password"
```

---

## Task 8: Full test suite + final check

- [ ] **Step 8.1 — Run all Dart tests**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 8.2 — Run analyzer**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 8.3 — Run iOS build**

```bash
flutter build ios --no-codesign
```

Expected: no compile errors.

- [ ] **Step 8.4 — Commit final**

```bash
git add .
git commit -m "chore: verify all tests pass for autofill suggestion and save feature"
```

---

## Manual Testing Checklist

### Android
- [ ] Install app on Android device with autofill enabled in Settings → Passwords → Autofill service
- [ ] Open an app/website for which NO credentials exist → verify "Generate secure password" dataset appears
- [ ] Open an app/website for which credentials DO exist → verify only existing datasets appear (no "Generate" option)
- [ ] Save a credential via autofill dialog → verify it appears in the vault
- [ ] Verify saved entry uses field key `KPH: androidPackage` (check via vault entry detail)

### iOS
- [ ] Enable app as autofill provider in Settings → Passwords → Password Options → Autofill from → [App Name]
- [ ] Open Safari and navigate to a website matching a stored credential → verify it appears in QuickType bar
- [ ] Tap a QuickType suggestion → verify correct credentials are filled
- [ ] Open a registration form in Safari → tap the password field → verify "Other Passwords" shows the app → verify generated password is offered
- [ ] Accept generated password → wait for main app to open → verify new entry appears in vault
