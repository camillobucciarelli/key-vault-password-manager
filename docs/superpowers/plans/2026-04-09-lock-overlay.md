# Lock Overlay — Privacy e Inattività — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere un privacy overlay istantaneo sul background, un lock overlay con sblocco biometrico, e un timer di inattività configurabile per database.

**Architecture:** `_VaultViewState` gestisce tutto lo stato di lock (`_isBackground`, `_isLocked`, `_inactivityTimer`) e renderizza due overlay in uno `Stack` sopra il contenuto esistente. Il lock NON cancella la password in memoria (solo "Use password" lo fa) — la biometria funge da gate di identità. Il timeout di inattività è salvato in `DatabaseSecurityProfile` e configurabile nel dialog delle impostazioni esistente.

**Tech Stack:** Flutter, `dart:async` (Timer), `BiometricDataSource` (già presente), `VaultSessionCoordinator` (già presente), `DatabaseSecurityProfile` entity + model.

---

## File modificati

| File | Ruolo |
|------|-------|
| `lib/features/password_manager/domain/entities/database_security_profile.dart` | Aggiunge `inactivityLockTimeoutSeconds` (nullable int) |
| `lib/features/password_manager/data/models/database_security_profile_model.dart` | Serializzazione JSON del nuovo campo |
| `lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart` | Aggiunge `getInactivityLockTimeoutForPath()`, aggiorna `DatabaseSettingsUpdateRequest` e `updateDatabaseSettings` |
| `lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart` | Aggiunge `_PrivacyOverlay` e `_LockOverlay` |
| `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` | Sostituisce la logica di lock-navigation con overlay + timer inattività |
| `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart` | Aggiunge dropdown timeout nel dialog "Database settings" |

---

## Task 1 — Estendi DatabaseSecurityProfile e il suo Model

**Files:**
- Modify: `lib/features/password_manager/domain/entities/database_security_profile.dart`
- Modify: `lib/features/password_manager/data/models/database_security_profile_model.dart`

- [ ] **Step 1: Aggiorna l'entity**

Sostituisci l'intero contenuto di `database_security_profile.dart`:

```dart
class DatabaseSecurityProfile {
  const DatabaseSecurityProfile({
    required this.databaseId,
    this.keyFilePath,
    this.biometricProtectionEnabled = true,
    this.inactivityLockTimeoutSeconds,
    this.updatedAt,
  });

  final String databaseId;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final int? inactivityLockTimeoutSeconds;
  final DateTime? updatedAt;

  DatabaseSecurityProfile copyWith({
    String? keyFilePath,
    bool? biometricProtectionEnabled,
    int? inactivityLockTimeoutSeconds,
    DateTime? updatedAt,
    bool clearKeyFilePath = false,
    bool clearInactivityTimeout = false,
  }) {
    return DatabaseSecurityProfile(
      databaseId: databaseId,
      keyFilePath: clearKeyFilePath ? null : keyFilePath ?? this.keyFilePath,
      biometricProtectionEnabled:
          biometricProtectionEnabled ?? this.biometricProtectionEnabled,
      inactivityLockTimeoutSeconds: clearInactivityTimeout
          ? null
          : inactivityLockTimeoutSeconds ?? this.inactivityLockTimeoutSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
```

- [ ] **Step 2: Aggiorna il model**

Sostituisci l'intero contenuto di `database_security_profile_model.dart`:

```dart
import '../../domain/entities/database_security_profile.dart';

class DatabaseSecurityProfileModel {
  const DatabaseSecurityProfileModel({
    required this.databaseId,
    this.keyFilePath,
    required this.biometricProtectionEnabled,
    this.inactivityLockTimeoutSeconds,
    this.updatedAt,
  });

  final String databaseId;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final int? inactivityLockTimeoutSeconds;
  final DateTime? updatedAt;

  factory DatabaseSecurityProfileModel.fromEntity(
    DatabaseSecurityProfile entity,
  ) {
    return DatabaseSecurityProfileModel(
      databaseId: entity.databaseId,
      keyFilePath: entity.keyFilePath,
      biometricProtectionEnabled: entity.biometricProtectionEnabled,
      inactivityLockTimeoutSeconds: entity.inactivityLockTimeoutSeconds,
      updatedAt: entity.updatedAt,
    );
  }

  DatabaseSecurityProfile toEntity() {
    return DatabaseSecurityProfile(
      databaseId: databaseId,
      keyFilePath: keyFilePath,
      biometricProtectionEnabled: biometricProtectionEnabled,
      inactivityLockTimeoutSeconds: inactivityLockTimeoutSeconds,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'databaseId': databaseId,
      'keyFilePath': keyFilePath,
      'biometricProtectionEnabled': biometricProtectionEnabled,
      'inactivityLockTimeoutSeconds': inactivityLockTimeoutSeconds,
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
  }

  factory DatabaseSecurityProfileModel.fromMap(Map<String, dynamic> map) {
    return DatabaseSecurityProfileModel(
      databaseId: map['databaseId'] as String,
      keyFilePath: map['keyFilePath'] as String?,
      biometricProtectionEnabled:
          map['biometricProtectionEnabled'] as bool? ?? true,
      inactivityLockTimeoutSeconds:
          map['inactivityLockTimeoutSeconds'] as int?,
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String).toLocal(),
    );
  }
}
```

- [ ] **Step 3: Verifica che non ci siano errori di compilazione**

```bash
flutter analyze lib/features/password_manager/domain/entities/database_security_profile.dart lib/features/password_manager/data/models/database_security_profile_model.dart
```

Expected: `No issues found.`

- [ ] **Step 4: Commit**

```bash
git add lib/features/password_manager/domain/entities/database_security_profile.dart \
        lib/features/password_manager/data/models/database_security_profile_model.dart
git commit -m "feat: add inactivityLockTimeoutSeconds to DatabaseSecurityProfile"
```

---

## Task 2 — Aggiorna VaultSessionCoordinator

**Files:**
- Modify: `lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart`

- [ ] **Step 1: Aggiungi `inactivityLockTimeoutSeconds` a `DatabaseSettingsUpdateRequest`**

Sostituisci la classe `DatabaseSettingsUpdateRequest` (righe 19-37):

```dart
class DatabaseSettingsUpdateRequest {
  const DatabaseSettingsUpdateRequest({
    required this.currentDatabasePath,
    required this.fileName,
    required this.keyFilePath,
    required this.biometricProtectionEnabled,
    required this.changePassword,
    required this.inactivityLockTimeoutSeconds,
    this.currentPassword,
    this.newPassword,
  });

  final String currentDatabasePath;
  final String fileName;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final bool changePassword;
  final int? inactivityLockTimeoutSeconds;
  final String? currentPassword;
  final String? newPassword;
}
```

- [ ] **Step 2: Aggiungi `getInactivityLockTimeoutForPath` al coordinator**

Aggiungi questo metodo dopo `getBiometricProtectionEnabledForPath` (dopo riga 104):

```dart
  Future<int?> getInactivityLockTimeoutForPath({
    required String databasePath,
  }) async {
    if (databasePath.trim().isEmpty) {
      return null;
    }

    final records = await getRegisteredDatabasesUseCase();
    for (final record in records) {
      if (record.canonicalPath != databasePath) {
        continue;
      }
      final profile = await getDatabaseSecurityProfileUseCase(
        record.databaseId,
      );
      return profile?.inactivityLockTimeoutSeconds;
    }
    return null;
  }
```

- [ ] **Step 3: Aggiorna `updateDatabaseSettings` per salvare il nuovo campo**

Nella sezione `profile.copyWith(...)` di `updateDatabaseSettings` (intorno a riga 178), sostituisci:

```dart
        final profile =
            (existingProfile ??
                    DatabaseSecurityProfile(databaseId: record.databaseId))
                .copyWith(
                  keyFilePath: persistedKeyFilePath,
                  biometricProtectionEnabled:
                      request.biometricProtectionEnabled,
                  updatedAt: DateTime.now(),
                  clearKeyFilePath: persistedKeyFilePath == null,
                );
```

con:

```dart
        final profile =
            (existingProfile ??
                    DatabaseSecurityProfile(databaseId: record.databaseId))
                .copyWith(
                  keyFilePath: persistedKeyFilePath,
                  biometricProtectionEnabled:
                      request.biometricProtectionEnabled,
                  inactivityLockTimeoutSeconds:
                      request.inactivityLockTimeoutSeconds,
                  updatedAt: DateTime.now(),
                  clearKeyFilePath: persistedKeyFilePath == null,
                  clearInactivityTimeout:
                      request.inactivityLockTimeoutSeconds == null,
                );
```

- [ ] **Step 4: Verifica compilazione**

```bash
flutter analyze lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart
```

Expected: `No issues found.`

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart
git commit -m "feat: add inactivity timeout to VaultSessionCoordinator and settings request"
```

---

## Task 3 — Aggiungi _PrivacyOverlay e _LockOverlay

**Files:**
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart`

Aggiungi i due widget alla fine del file (prima dell'ultima `}` se presente, altrimenti in append).

- [ ] **Step 1: Aggiungi `_PrivacyOverlay`**

Appendi in fondo a `vault_entries_details.part.dart`:

```dart
class _PrivacyOverlay extends StatelessWidget {
  const _PrivacyOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Icon(
          AppIcons.lock,
          size: 48,
          color: colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Aggiungi `_LockOverlay`**

Appendi subito dopo `_PrivacyOverlay`:

```dart
class _LockOverlay extends StatefulWidget {
  const _LockOverlay({
    required this.databasePath,
    required this.onUnlocked,
  });

  final String databasePath;
  final VoidCallback onUnlocked;

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  bool _biometricAvailable = false;
  bool _showPasswordFallback = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBiometric());
  }

  Future<void> _initBiometric() async {
    final available =
        await di.sl<BiometricDataSource>().isBiometricAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) {
      await _triggerBiometric();
    } else {
      setState(() => _showPasswordFallback = true);
    }
  }

  Future<void> _triggerBiometric() async {
    if (_isAuthenticating || !mounted) return;
    setState(() => _isAuthenticating = true);
    final ok = await di.sl<BiometricDataSource>().authenticate(
      reason: 'Unlock vault',
    );
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _isAuthenticating = false;
      _showPasswordFallback = true;
    });
  }

  void _usePassword() {
    di.sl<VaultSessionCoordinator>().lockVault(
      currentDatabasePath: widget.databasePath,
    );
    AppNavigation.pushFadeReplacement(
      context,
      DatabaseUnlockScreen(databasePath: widget.databasePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.lock,
              size: 52,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            if (_biometricAvailable && !_showPasswordFallback)
              FilledButton.icon(
                onPressed: _isAuthenticating ? null : _triggerBiometric,
                icon: Icon(AppIcons.fingerprint),
                label: const Text('Unlock with biometrics'),
              ),
            if (_showPasswordFallback) ...[
              if (_biometricAvailable)
                FilledButton.icon(
                  onPressed: _isAuthenticating ? null : _triggerBiometric,
                  icon: Icon(AppIcons.fingerprint),
                  label: const Text('Unlock with biometrics'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _usePassword,
                child: const Text('Use password'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verifica compilazione**

```bash
flutter analyze lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart
```

Expected: `No issues found.`

- [ ] **Step 4: Commit**

```bash
git add lib/features/password_manager/presentation/screens/vault/vault_entries_details.part.dart
git commit -m "feat: add _PrivacyOverlay and _LockOverlay widgets"
```

---

## Task 4 — Aggiorna _VaultViewState in vault_shell.part.dart

**Files:**
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`

- [ ] **Step 1: Sostituisci i campi di stato e `initState`/`dispose`**

Sostituisci l'intera classe `_VaultViewState` con WidgetsBindingObserver (righe 91–219 circa, fino a `_closeCurrentDatabaseAndSelectAnother`). Sostituisci solo la parte fino a `_closeCurrentDatabaseAndSelectAnother` (che rimane invariata):

```dart
class _VaultViewState extends State<_VaultView> with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _isBackground = false;
  bool _isLocked = false;
  Timer? _inactivityTimer;
  int? _inactivityTimeoutSeconds;
  bool _autofillPromptChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowAutofillOnboardingDialog();
      _loadInactivityTimeout();
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadInactivityTimeout() async {
    if (!mounted) return;
    final databasePath = context.read<VaultBloc>().state.databasePath;
    final seconds = await di
        .sl<VaultSessionCoordinator>()
        .getInactivityLockTimeoutForPath(databasePath: databasePath);
    if (!mounted) return;
    setState(() => _inactivityTimeoutSeconds = seconds);
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final seconds = _inactivityTimeoutSeconds;
    if (seconds == null || _isLocked || _isBackground) return;
    _inactivityTimer = Timer(Duration(seconds: seconds), _triggerInactivityLock);
  }

  void _triggerInactivityLock() {
    if (!mounted || _isLocked) return;
    setState(() => _isLocked = true);
  }

  void _dismissLock() {
    if (!mounted) return;
    setState(() => _isLocked = false);
    _resetInactivityTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
        _inactivityTimer?.cancel();
        if (!_isLocked && mounted) {
          setState(() => _isBackground = true);
        }
        break;
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onAppResumed() {
    if (!mounted) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;

    final elapsed = backgroundedAt != null
        ? DateTime.now().difference(backgroundedAt)
        : Duration.zero;
    final shouldLock = elapsed >= _VaultUiTokens.backgroundLockTimeout;

    setState(() {
      _isBackground = false;
      if (shouldLock) _isLocked = true;
    });

    if (!shouldLock) {
      _resetInactivityTimer();
    }
  }
```

Nota: rimuovi il campo `_isLockNavigationInProgress` (non più necessario).

- [ ] **Step 2: Aggiorna il metodo `build` per aggiungere `Listener` e overlays**

All'interno del `build`, nell'`Stack` interno (dopo `BlocSelector<VaultBloc, VaultState, bool>` per `isLoading`), sostituisci il `Stack(children: [...])` corrente con:

```dart
return Stack(
  children: [
    Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spec = _VaultLayoutSpec.fromWidth(
            constraints.maxWidth,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(
              spec.horizontalPadding,
              topInset + spec.contentTopPadding,
              spec.horizontalPadding,
              spec.horizontalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _VaultSyncStatusStrip(
                  onOpenRecycleBin: () {
                    _showRecycleBinDialog(context);
                  },
                  onChangeDatabase:
                      _closeCurrentDatabaseAndSelectAnother,
                ),
                const SizedBox(height: _VaultUiTokens.panelGap),
                const Expanded(child: _VaultEntriesCardSection()),
              ],
            ),
          );
        },
      ),
    ),
    BlocSelector<VaultBloc, VaultState, bool>(
      selector: (state) => state.isSaving,
      builder: (context, isSaving) {
        if (!isSaving) {
          return const SizedBox.shrink();
        }

        return Container(
          color: Colors.black.withValues(alpha: 0.15),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    ),
    if (_isBackground && !_isLocked)
      const _PrivacyOverlay(),
    if (_isLocked)
      _LockOverlay(
        databasePath: context.read<VaultBloc>().state.databasePath,
        onUnlocked: _dismissLock,
      ),
  ],
);
```

- [ ] **Step 3: Aggiungi import `dart:async` nella vault_screen.dart se mancante**

Controlla il file `lib/features/password_manager/presentation/screens/vault_screen.dart`:

```bash
head -15 lib/features/password_manager/presentation/screens/vault_screen.dart
```

Se `import 'dart:async';` non è presente, aggiungilo.

- [ ] **Step 4: Verifica compilazione**

```bash
flutter analyze lib/features/password_manager/presentation/screens/vault_screen.dart
```

Expected: `No issues found.`

- [ ] **Step 5: Commit**

```bash
git add lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart \
        lib/features/password_manager/presentation/screens/vault_screen.dart
git commit -m "feat: replace lock navigation with overlay + add inactivity timer"
```

---

## Task 5 — Aggiungi dropdown timeout nel dialog Database Settings

**Files:**
- Modify: `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`

- [ ] **Step 1: Carica il timeout corrente prima di aprire il dialog**

Nel metodo `_showDatabaseSettings`, dopo il caricamento di `biometricEnabled` (dopo riga ~432), aggiungi:

```dart
    var inactivityTimeout = await di
        .sl<VaultSessionCoordinator>()
        .getInactivityLockTimeoutForPath(databasePath: currentDatabasePath);
    final initialInactivityTimeout = inactivityTimeout;
```

- [ ] **Step 2: Aggiungi il tracking del cambiamento nel `pendingChanges`**

Nella lista `pendingChanges` (nell'`StatefulBuilder`), aggiungi:

```dart
            final inactivityChanged =
                inactivityTimeout != initialInactivityTimeout;
            final pendingChanges = <String>[
              if (fileNameChanged) 'Database file name',
              if (biometricChanged) 'Biometric protection',
              if (inactivityChanged) 'Inactivity lock',
              if (keyFileChanged) 'Key file',
              if (changePassword) 'Master password',
            ];
```

- [ ] **Step 3: Aggiungi il dropdown nella sezione "General" del dialog**

Subito dopo il `SwitchListTile.adaptive` per `biometricEnabled` (dopo riga ~515), aggiungi:

```dart
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int?>(
                          value: inactivityTimeout,
                          decoration: const InputDecoration(
                            labelText: 'Lock on inactivity',
                            prefixIcon: Icon(AppIcons.lock),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: null,
                              child: Text('Never'),
                            ),
                            DropdownMenuItem(
                              value: 10,
                              child: Text('10 seconds'),
                            ),
                            DropdownMenuItem(
                              value: 20,
                              child: Text('20 seconds'),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text('30 seconds'),
                            ),
                            DropdownMenuItem(
                              value: 60,
                              child: Text('1 minute'),
                            ),
                            DropdownMenuItem(
                              value: 120,
                              child: Text('2 minutes'),
                            ),
                            DropdownMenuItem(
                              value: 300,
                              child: Text('5 minutes'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              inactivityTimeout = value;
                            });
                          },
                        ),
```

- [ ] **Step 4: Passa `inactivityLockTimeoutSeconds` alla request**

Nella chiamata a `updateDatabaseSettings` (intorno a riga ~802), aggiungi il campo:

```dart
            DatabaseSettingsUpdateRequest(
              currentDatabasePath: currentDatabasePath,
              fileName: databaseTitle.trim(),
              keyFilePath: selectedKeyPath,
              biometricProtectionEnabled: biometricEnabled,
              inactivityLockTimeoutSeconds: inactivityTimeout,
              changePassword: changePassword,
              currentPassword: currentPassword,
              newPassword: newPassword,
            ),
```

- [ ] **Step 5: Verifica compilazione**

```bash
flutter analyze lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart
```

Expected: `No issues found.`

- [ ] **Step 6: Verifica compilazione globale**

```bash
flutter analyze
```

Expected: solo gli info pre-esistenti nel file di test, nessun errore.

- [ ] **Step 7: Commit**

```bash
git add lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart
git commit -m "feat: add inactivity lock timeout setting to database settings dialog"
```

---

## Self-review

**Spec coverage:**
- ✅ Privacy overlay su background (Task 4 `_isBackground`)
- ✅ Lock overlay senza navigazione (Task 3 `_LockOverlay`, Task 4)
- ✅ Biometrico auto-attivato all'apertura overlay (Task 3 `_initBiometric`)
- ✅ "Usa password" visibile solo dopo fallimento/mancanza biometrico (Task 3 `_showPasswordFallback`)
- ✅ "Usa password" naviga a `DatabaseUnlockScreen` e chiama `lockVault()` (Task 3 `_usePassword`)
- ✅ Inactivity timer con `Listener` + `Timer` (Task 4)
- ✅ Timer configurabile e persistito (Task 1, 2, 5)
- ✅ Se biometria non disponibile → password fallback diretto (Task 3 `_initBiometric`)
- ✅ Timer cancellato su background, ripartito al resume se non locked (Task 4)
- ✅ Background lock a 30s fisso (Task 4 `_VaultUiTokens.backgroundLockTimeout`)

**Tipi consistenti:** `int?` per `inactivityLockTimeoutSeconds` usato uniformemente in entity, model, coordinator, request, shell. `VaultSessionCoordinator.getInactivityLockTimeoutForPath` restituisce `Future<int?>`. `_VaultViewState._inactivityTimeoutSeconds` è `int?`.
