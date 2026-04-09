# Lock Overlay — Privacy e Inattività

**Data:** 2026-04-09

## Obiettivo

Migliorare la sicurezza visiva e comportamentale del vault:

1. Nascondere il contenuto immediatamente quando l'app va in background (privacy nel multitasking).
2. Mostrare un lock overlay sopra il vault (senza navigare) che si sblocca con sola biometria.
3. Aggiungere un timer di inattività configurabile per database.

---

## Comportamento

### Privacy overlay

- Si attiva su `AppLifecycleState.inactive | paused | hidden`.
- Copre tutto il contenuto del vault con uno sfondo opaco + logo/icona app. Nessun testo sensibile visibile.
- Se l'app torna in foreground prima che il lock scatti, l'overlay scompare senza mostrare la lock screen.

### Lock overlay

Si attiva in due casi:

- **Background lock**: elapsed ≥ 30 s dal momento in cui l'app è passata in background.
- **Inactivity lock**: il timer di inattività configurato scade senza interazioni dell'utente.

Il lock overlay si sovrappone al vault (nessuna navigazione). Contiene:

- Logo/icona app.
- Pulsante biometrico, auto-attivato immediatamente all'apertura dell'overlay.
- Link secondario "Usa password" visibile solo se la biometria fallisce o viene annullata — naviga al `DatabaseUnlockScreen` esistente.

### Sblocco biometrico

L'overlay chiama `BiometricDataSource.authenticate()` direttamente (non tramite `DatabaseUnlockBloc`). In caso di successo, rimuove l'overlay e il vault torna visibile.

### Inactivity timer

- Un `Listener` avvolge il contenuto del vault e resetta il timer ad ogni `PointerDownEvent`.
- Il timer viene cancellato quando l'app va in background (il background lock ha la precedenza).
- Il timer riparte al resume se il vault non è bloccato.
- Se il timeout è `null` (opzione "Nessuno"), il timer non viene avviato.

---

## Architettura

### Stack nel vault (`vault_shell.part.dart`)

```
Stack
├── Listener(onPointerDown: _resetInactivityTimer)
│   └── vault content (invariato)
├── _PrivacyOverlay   — visibile quando _isBackground && !_isLocked
└── _LockOverlay      — visibile quando _isLocked
```

### Stato in `_VaultViewState`

```dart
bool _isBackground = false;   // app non visibile, overlay privacy
bool _isLocked = false;        // vault bloccato, overlay lock
Timer? _inactivityTimer;
bool _showPasswordFallback = false;  // dopo fallimento biometrico
```

### Nuovo campo su `DatabaseSecurityProfile`

```dart
final int? inactivityLockTimeoutSeconds; // null = disattivato
```

Opzioni nel dropdown delle impostazioni:

| Label | Valore |
|-------|--------|
| Nessuno | null |
| 10 secondi | 10 |
| 20 secondi | 20 |
| 30 secondi | 30 |
| 1 minuto | 60 |
| 2 minuti | 120 |
| 5 minuti | 300 |

Il valore viene letto all'avvio del vault dalla `VaultSessionCoordinator.getBiometricProtectionEnabledForPath` (stessa infrastruttura già usata per la biometria).

---

## File modificati

| File | Tipo modifica |
|------|---------------|
| `domain/entities/database_security_profile.dart` | Aggiunge `inactivityLockTimeoutSeconds` (nullable int) |
| `data/models/database_security_profile_model.dart` | Serializzazione JSON del nuovo campo |
| `presentation/screens/vault/vault_shell.part.dart` | Stato `_isBackground`/`_isLocked`, `Listener`, `Timer`, `Stack` con overlay |
| `presentation/screens/vault/vault_entries_details.part.dart` | Widget `_PrivacyOverlay` e `_LockOverlay` |
| `presentation/screens/vault/vault_navigation.part.dart` | Dropdown timeout nel dialog "Database settings" |
| `presentation/coordinators/vault_session_coordinator.dart` | Legge/scrive `inactivityLockTimeoutSeconds` |

---

## Gestione errori

- Se la biometria non è disponibile sul device, il lock overlay mostra direttamente il link "Usa password" senza tentare l'autenticazione.
- Se il `DatabaseSecurityProfile` non è trovato (vault non registrato), il timeout di inattività non viene attivato.
- La navigazione a `DatabaseUnlockScreen` via "Usa password" usa il percorso esistente e, al successo, torna al vault tramite il coordinator già in uso.

---

## Non in scope

- Timeout del background lock configurabile (resta fisso a 30 s).
- Lock automatico su desktop.
- Supporto inattività per autofill entry point.
