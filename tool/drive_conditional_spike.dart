// Spike live-network per il blocker B1 della spec 008
// (`specs/008-per-field-conflict-resolution/feasibility-report.md`).
//
// DOMANDA A CUI RISPONDE
// ---------------------
// Google Drive REST v3 onora una precondizione HTTP standard (`If-Match`,
// `If-None-Match`, `If-Unmodified-Since`) su `files.update` con
// `uploadType=media`, anche se non la documenta?
//
//   - Se una precondizione palesemente STALE viene rifiutata dal server con
//     `412`, esiste un compare-and-swap server-enforced e B1 cade.
//   - Se la stessa richiesta risponde `200` E il contenuto remoto risulta
//     davvero sovrascritto, l'header e' ignorato e B1 e' confermato.
//
// Lo script NON modifica `lib/`. Non fa parte di nessuna suite CI: richiede
// rete e un access token, e va lanciato a mano.
//
// COME OTTENERE UN ACCESS TOKEN (OAuth 2.0 Playground)
// ---------------------------------------------------
//  1. Usa un account Google USA-E-GETTA. Lo script crea e cancella un solo
//     file di prova, ma non esporre mai un Drive con dati veri.
//  2. Apri https://developers.google.com/oauthplayground/
//  3. Nel pannello "Step 1 – Select & authorize APIs", in fondo, incolla lo
//     scope nel campo "Input your own scopes":
//
//         https://www.googleapis.com/auth/drive
//
//     (e' lo scope che usa l'app: `_requiredDriveScope` in
//     `lib/features/password_manager/data/services/drive_auth_service.dart`.)
//  4. Premi "Authorize APIs" e completa il consenso con l'account usa-e-getta.
//  5. In "Step 2" premi "Exchange authorization code for tokens" e copia il
//     valore di "Access token" (inizia con `ya29.`). Dura circa un'ora.
//
// COME LANCIARLO
// --------------
//     DRIVE_SPIKE_TOKEN='ya29....' dart run tool/drive_conditional_spike.dart
//
// (con fvm: `DRIVE_SPIKE_TOKEN='ya29....' fvm dart run tool/drive_conditional_spike.dart`)
//
// Per non lasciare il token nella history della shell, anteponi uno spazio al
// comando, oppure leggilo da un gestore di segreti:
//
//     DRIVE_SPIKE_TOKEN="$(pbpaste)" dart run tool/drive_conditional_spike.dart
//
// SICUREZZA
// ---------
//  - Il token viene letto SOLO da variabile d'ambiente, non e' mai stampato
//    (nemmeno troncato), non e' mai scritto su file.
//  - Lo script tocca esclusivamente il file che crea lui (`kv-spike-<ts>.bin`,
//    byte casuali) e lo cancella in `finally`. Nessun `.kdbx`, nessun dato di
//    vault, nessun file preesistente.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _tokenEnvVar = 'DRIVE_SPIKE_TOKEN';
const _apiBase = 'https://www.googleapis.com/drive/v3';
const _uploadBase = 'https://www.googleapis.com/upload/drive/v3';
const _bodyPreviewLimit = 600;

Future<void> main() async {
  final token = Platform.environment[_tokenEnvVar]?.trim();
  if (token == null || token.isEmpty) {
    _printMissingTokenHelp();
    exitCode = 2;
    return;
  }

  final client = http.Client();
  final spike = _Spike(client: client, token: token);
  try {
    await spike.run();
  } catch (error, stackTrace) {
    stdout.writeln();
    stdout.writeln('!! Lo spike si e\' interrotto con un\'eccezione:');
    stdout.writeln('   $error');
    stdout.writeln(stackTrace.toString());
    stdout.writeln();
    stdout.writeln('VERDETTO: SPIKE INCOMPLETO — nessuna conclusione su B1.');
    exitCode = 1;
  } finally {
    await spike.cleanUp();
    client.close();
  }
}

void _printMissingTokenHelp() {
  stderr.writeln('''
$_tokenEnvVar non e' impostata: lo spike non puo' partire.

Serve un access token OAuth 2.0 con lo scope:

    https://www.googleapis.com/auth/drive

(lo stesso scope dell'app, `_requiredDriveScope` in
lib/features/password_manager/data/services/drive_auth_service.dart)

Come ottenerlo, con un account Google USA-E-GETTA:
  1. apri https://developers.google.com/oauthplayground/
  2. in "Step 1" incolla lo scope qui sopra nel campo "Input your own scopes"
  3. "Authorize APIs" -> consenso
  4. in "Step 2" premi "Exchange authorization code for tokens"
  5. copia il valore di "Access token" (inizia con ya29., dura ~1 ora)

Poi rilancia (lo spazio iniziale tiene il token fuori dalla history):

     $_tokenEnvVar='ya29....' dart run tool/drive_conditional_spike.dart
''');
}

/// Esito di un singolo PATCH condizionale.
class _ProbeOutcome {
  _ProbeOutcome({
    required this.label,
    required this.decisive,
    required this.status,
    required this.contentState,
  });

  final String label;

  /// `true` per le prove che decidono B1: precondizione palesemente stale.
  final bool decisive;
  final int status;
  final _ContentState contentState;

  bool get rejected => status == 412;
  bool get accepted => status >= 200 && status < 300;
}

/// Cosa e' successo davvero ai byte remoti dopo un PATCH. E' la controprova:
/// senza questa, un `200` non distingue "header ignorato" da "scrittura non
/// avvenuta", e un `412` non prova che la scrittura sia stata respinta.
enum _ContentState {
  /// I byte remoti sono quelli inviati da questa prova: la scrittura e' passata.
  writeApplied,

  /// I byte remoti sono ancora quelli dell'ultima scrittura riuscita: la
  /// scrittura di questa prova NON e' passata.
  writeRejected,

  /// I byte remoti non sono ne' l'uno ne' l'altro: stato inatteso, la prova
  /// non conclude nulla.
  unexpected,

  /// Non e' stato possibile rileggere il file.
  unknown,
}

class _Spike {
  _Spike({required http.Client client, required String token})
    : _client = client,
      _token = token;

  final http.Client _client;
  final String _token;
  final Random _random = Random.secure();
  final List<_ProbeOutcome> _outcomes = <_ProbeOutcome>[];

  String? _fileId;

  /// Byte dell'ultima scrittura che risulta effettivamente applicata sul
  /// remoto. E' il riferimento della controprova.
  Uint8List _lastAppliedBytes = Uint8List(0);

  /// Token letti alla creazione del file, prima di qualunque scrittura: dopo
  /// le prove "fresh" diventano genuinamente stale.
  String? _initialEtagHeader;
  String? _initialVersion;
  String? _initialHeadRevisionId;

  Map<String, String> get _authHeader => {'Authorization': 'Bearer $_token'};

  Future<void> run() async {
    _section('SPIKE B1 — precondizioni condizionali su Google Drive v3');
    stdout.writeln('Nessun token viene stampato in questo output.');

    await _createProbeFile();
    final fileId = _fileId!;

    await _reconnaissance(fileId);
    await _headerPassthroughControl(fileId);
    await _conditionalOnReadControl(fileId);
    await _runPatchMatrix(fileId);
    await _malformedHeaderProbe(fileId);

    _printVerdict();
  }

  // ---------------------------------------------------------------- setup

  Future<void> _createProbeFile() async {
    _section('0. Creazione del file di prova');

    final name = 'kv-spike-${DateTime.now().millisecondsSinceEpoch}.bin';
    final bytes = _randomBytes();
    final boundary = 'kv-spike-boundary-${_random.nextInt(1 << 32)}';
    final uri = Uri.parse(
      '$_uploadBase/files',
    ).replace(queryParameters: {'uploadType': 'multipart'});

    final response = await _client.post(
      uri,
      headers: {
        ..._authHeader,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: _multipartBody(boundary: boundary, name: name, bytes: bytes),
    );

    stdout.writeln('POST $uri');
    stdout.writeln('  nome file: $name  (${bytes.length} byte casuali)');
    _printResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Creazione del file di prova fallita (${response.statusCode}). '
        'Token scaduto o scope insufficiente?',
      );
    }

    _fileId =
        (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
    _lastAppliedBytes = bytes;
    stdout.writeln('  file id: $_fileId');
  }

  Future<void> cleanUp() async {
    final fileId = _fileId;
    if (fileId == null) {
      return;
    }
    _section('Cleanup');
    try {
      final response = await _client.delete(
        Uri.parse('$_apiBase/files/$fileId'),
        headers: _authHeader,
      );
      stdout.writeln('DELETE files/$fileId -> ${response.statusCode}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        stdout.writeln(
          '  ATTENZIONE: cancella a mano il file di prova dal Drive.',
        );
      }
    } catch (error) {
      stdout.writeln('  DELETE fallita ($error).');
      stdout.writeln('  ATTENZIONE: cancella a mano il file di prova.');
    }
    _fileId = null;
  }

  // -------------------------------------------------------- ricognizione

  Future<void> _reconnaissance(String fileId) async {
    _section('1. Ricognizione — GET files/$fileId?fields=*');

    final uri = Uri.parse(
      '$_apiBase/files/$fileId',
    ).replace(queryParameters: {'fields': '*'});
    final response = await _client.get(uri, headers: _authHeader);
    stdout.writeln('GET $uri');
    _printResponse(response, alwaysPrintBody: false);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('GET di ricognizione fallita (${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final keys = payload.keys.toList()..sort();
    stdout.writeln('  campi restituiti (${keys.length}): ${keys.join(', ')}');

    for (final field in const [
      'etag',
      'version',
      'headRevisionId',
      'modifiedTime',
      'md5Checksum',
    ]) {
      final present = payload.containsKey(field);
      stdout.writeln(
        '  campo JSON "$field": '
        '${present ? 'PRESENTE -> ${payload[field]}' : 'ASSENTE'}',
      );
    }

    // Il campo JSON `etag` e' assente in v3, ma l'header HTTP ETag e' un'altra
    // cosa: va verificato a parte.
    _initialEtagHeader = response.headers['etag'];
    stdout.writeln(
      '  header HTTP "ETag": '
      '${_initialEtagHeader == null ? 'ASSENTE' : _initialEtagHeader!}',
    );
    stdout.writeln(
      '  header HTTP "Last-Modified": '
      '${response.headers['last-modified'] ?? 'ASSENTE'}',
    );

    _initialVersion = payload['version']?.toString();
    _initialHeadRevisionId = payload['headRevisionId']?.toString();
  }

  /// Controllo positivo: prova che header arbitrari attraversano il nostro
  /// `http.Client` e arrivano a un frontend Drive che li interpreta.
  /// `Range` e' documentato e sicuro (sola lettura).
  Future<void> _headerPassthroughControl(String fileId) async {
    _section('2. Controllo — gli header arbitrari arrivano a Drive? (Range)');

    final uri = Uri.parse(
      '$_apiBase/files/$fileId',
    ).replace(queryParameters: {'alt': 'media'});
    final headers = {..._authHeader, 'Range': 'bytes=0-3'};
    _printRequestHeaders(headers);
    final response = await _client.get(uri, headers: headers);
    _printResponse(response, alwaysPrintBody: false);

    stdout.writeln(
      response.statusCode == 206
          ? '  ESITO: 206 Partial Content — gli header di richiesta ARRIVANO a '
                'Drive e vengono interpretati (sul path di lettura).'
          : '  ESITO: atteso 206, ottenuto ${response.statusCode}. Il '
                'passthrough degli header non e\' dimostrato: leggi il resto '
                'con questa riserva.',
    );
  }

  /// `If-Match` stale su una GET di metadata. Se Drive risponde `412` qui, sa
  /// parsare le precondizioni almeno sul path di lettura.
  Future<void> _conditionalOnReadControl(String fileId) async {
    _section('3. Controllo — If-Match stale su GET metadata');

    final uri = Uri.parse('$_apiBase/files/$fileId');
    final headers = {..._authHeader, 'If-Match': '"kv-spike-stale-etag"'};
    _printRequestHeaders(headers);
    final response = await _client.get(uri, headers: headers);
    _printResponse(response, alwaysPrintBody: false);

    stdout.writeln(
      response.statusCode == 412
          ? '  ESITO: 412 — Drive PARSA le precondizioni sul path di lettura.'
          : '  ESITO: ${response.statusCode} — nessuna precondizione applicata '
                'in lettura.',
    );
  }

  // ------------------------------------------------------- matrice PATCH

  Future<void> _runPatchMatrix(String fileId) async {
    _section('4. Matrice PATCH (uploadType=media)');
    stdout.writeln(
      'Ogni prova invia byte NUOVI e diversi; dopo ogni PATCH il file viene\n'
      'riscaricato e confrontato. Questa e\' la controprova: un 200 conta solo\n'
      'se i byte remoti sono davvero cambiati.',
    );

    // Precondizioni "fresh": lette adesso, immediatamente prima della scrittura.
    final fresh = await _readTokens(fileId);

    if (fresh.etagHeader != null) {
      await _patchProbe(
        fileId: fileId,
        label: 'If-Match: <ETag header FRESCO>',
        conditional: {'If-Match': fresh.etagHeader!},
        expectation: '200 (precondizione soddisfatta)',
        decisive: false,
      );
    } else {
      stdout.writeln(
        '\n-- If-Match: <ETag header FRESCO> — SALTATA: la GET non restituisce '
        'header ETag.',
      );
    }

    if (fresh.version != null) {
      await _patchProbe(
        fileId: fileId,
        label: 'If-Match: <campo version FRESCO> (${fresh.version})',
        conditional: {'If-Match': '"${fresh.version}"'},
        expectation: '200 (precondizione soddisfatta)',
        decisive: false,
      );
    }

    if (fresh.headRevisionId != null) {
      await _patchProbe(
        fileId: fileId,
        label: 'If-Match: <headRevisionId FRESCO>',
        conditional: {'If-Match': '"${fresh.headRevisionId}"'},
        expectation: '200 (precondizione soddisfatta)',
        decisive: false,
      );
    }

    // --- Le prove decisive. Qui si decide B1. -----------------------------
    // I valori "iniziali" sono stati letti prima delle scritture qui sopra:
    // ora sono genuinamente stale, non solo inventati.
    await _patchProbe(
      fileId: fileId,
      label: 'If-Match: <valore inventato> — DECISIVA',
      conditional: {'If-Match': '"kv-spike-stale-does-not-exist"'},
      expectation: '412 => B1 RISOLTO; 200 con byte cambiati => B1 CONFERMATO',
      decisive: true,
    );

    if (_initialVersion != null) {
      await _patchProbe(
        fileId: fileId,
        label: 'If-Match: <version STALE> ($_initialVersion) — DECISIVA',
        conditional: {'If-Match': '"$_initialVersion"'},
        expectation:
            '412 => B1 RISOLTO; 200 con byte cambiati => B1 CONFERMATO',
        decisive: true,
      );
    }

    if (_initialEtagHeader != null) {
      await _patchProbe(
        fileId: fileId,
        label: 'If-Match: <ETag header STALE> — DECISIVA',
        conditional: {'If-Match': _initialEtagHeader!},
        expectation:
            '412 => B1 RISOLTO; 200 con byte cambiati => B1 CONFERMATO',
        decisive: true,
      );
    }

    if (_initialHeadRevisionId != null) {
      await _patchProbe(
        fileId: fileId,
        label: 'If-Match: <headRevisionId STALE> — DECISIVA',
        conditional: {'If-Match': '"$_initialHeadRevisionId"'},
        expectation:
            '412 => B1 RISOLTO; 200 con byte cambiati => B1 CONFERMATO',
        decisive: true,
      );
    }

    // --- Varianti di sintassi ---------------------------------------------
    await _patchProbe(
      fileId: fileId,
      label: 'If-Match: *',
      conditional: {'If-Match': '*'},
      expectation: '200 (la risorsa esiste)',
      decisive: false,
    );

    await _patchProbe(
      fileId: fileId,
      label: 'If-None-Match: * — DECISIVA',
      conditional: {'If-None-Match': '*'},
      expectation:
          'la risorsa esiste, quindi 412 se la precondizione e\' onorata; '
          '200 con byte cambiati => ignorata',
      decisive: true,
    );

    await _patchProbe(
      fileId: fileId,
      label: 'If-Unmodified-Since: <data PASSATA> — DECISIVA',
      conditional: {
        'If-Unmodified-Since': HttpDate.format(DateTime.utc(2001, 1, 1)),
      },
      expectation:
          'il file e\' stato modificato dopo, quindi 412 se onorata; '
          '200 con byte cambiati => ignorata',
      decisive: true,
    );

    await _patchProbe(
      fileId: fileId,
      label: 'If-Unmodified-Since: <data FUTURA>',
      conditional: {
        'If-Unmodified-Since': HttpDate.format(DateTime.utc(2099, 1, 1)),
      },
      expectation: '200 (precondizione soddisfatta)',
      decisive: false,
    );
  }

  /// Sonda finale: header condizionale sintatticamente malformato. Un `400`
  /// dice che Drive sta PARSANDO gli header condizionali sul path di upload —
  /// cioe' che arrivano, e che un `200` su valore stale significa "ignorato",
  /// non "non arrivato".
  Future<void> _malformedHeaderProbe(String fileId) async {
    _section('5. Sonda — header condizionale malformato');

    await _patchProbe(
      fileId: fileId,
      label: 'If-Match: <sintassi malformata>',
      conditional: {'If-Match': '"unterminated-quote, W/ bad'},
      expectation:
          '400 => Drive PARSA le precondizioni in upload; '
          '200 => le scarta a monte',
      decisive: false,
    );
  }

  // ------------------------------------------------------------- helpers

  Future<_ProbeOutcome> _patchProbe({
    required String fileId,
    required String label,
    required Map<String, String> conditional,
    required String expectation,
    required bool decisive,
  }) async {
    stdout.writeln('\n-- $label');
    stdout.writeln('   atteso: $expectation');

    final payload = _randomBytes();
    final uri = Uri.parse(
      '$_uploadBase/files/$fileId',
    ).replace(queryParameters: {'uploadType': 'media'});
    final headers = {
      ..._authHeader,
      'Content-Type': 'application/octet-stream',
      ...conditional,
    };

    stdout.writeln('   PATCH $uri');
    _printRequestHeaders(headers);

    final response = await _client.patch(uri, headers: headers, body: payload);
    _printResponse(response, alwaysPrintBody: false);

    final contentState = await _verifyContent(fileId, payload);
    stdout.writeln('   controprova byte remoti: ${_describe(contentState)}');

    final outcome = _ProbeOutcome(
      label: label,
      decisive: decisive,
      status: response.statusCode,
      contentState: contentState,
    );
    _outcomes.add(outcome);
    return outcome;
  }

  /// Riscarica il file e stabilisce se il PATCH ha davvero riscritto i byte.
  Future<_ContentState> _verifyContent(
    String fileId,
    Uint8List attemptedBytes,
  ) async {
    final uri = Uri.parse(
      '$_apiBase/files/$fileId',
    ).replace(queryParameters: {'alt': 'media'});
    final response = await _client.get(uri, headers: _authHeader);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stdout.writeln(
        '   !! rilettura fallita (${response.statusCode}): controprova assente',
      );
      return _ContentState.unknown;
    }

    final remote = response.bodyBytes;
    if (_bytesEqual(remote, attemptedBytes)) {
      _lastAppliedBytes = attemptedBytes;
      return _ContentState.writeApplied;
    }
    if (_bytesEqual(remote, _lastAppliedBytes)) {
      return _ContentState.writeRejected;
    }
    return _ContentState.unexpected;
  }

  Future<({String? etagHeader, String? version, String? headRevisionId})>
  _readTokens(String fileId) async {
    final uri = Uri.parse('$_apiBase/files/$fileId').replace(
      queryParameters: {'fields': 'id,version,headRevisionId,modifiedTime'},
    );
    final response = await _client.get(uri, headers: _authHeader);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Rilettura token fallita (${response.statusCode}).');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      etagHeader: response.headers['etag'],
      version: payload['version']?.toString(),
      headRevisionId: payload['headRevisionId']?.toString(),
    );
  }

  void _printVerdict() {
    _section('VERDETTO');

    final decisive = _outcomes.where((o) => o.decisive).toList();
    final enforced = decisive
        .where(
          (o) => o.rejected && o.contentState == _ContentState.writeRejected,
        )
        .toList();
    final ignored = decisive
        .where(
          (o) => o.accepted && o.contentState == _ContentState.writeApplied,
        )
        .toList();
    final inconclusive = decisive
        .where(
          (o) =>
              o.contentState == _ContentState.unexpected ||
              o.contentState == _ContentState.unknown ||
              (o.rejected && o.contentState != _ContentState.writeRejected),
        )
        .toList();

    stdout.writeln('Prove decisive: ${decisive.length}');
    for (final outcome in decisive) {
      stdout.writeln(
        '  [${outcome.status}] ${_describe(outcome.contentState)} '
        '— ${outcome.label}',
      );
    }
    stdout.writeln();

    if (enforced.isNotEmpty) {
      stdout.writeln(
        'B1 RISOLTO — Drive onora ${enforced.map((o) => o.label).join(' / ')}: '
        'precondizione rifiutata dal server con 412 E byte remoti invariati.',
      );
      stdout.writeln(
        'Esiste un compare-and-swap server-enforced utilizzabile per FR-7/FR-10.',
      );
      return;
    }

    if (inconclusive.isNotEmpty && ignored.isEmpty) {
      stdout.writeln(
        'ESITO NON CONCLUSIVO — nessuna prova decisiva ha dato 412 con byte '
        'invariati, ma ${inconclusive.length} prove hanno uno stato remoto '
        'inatteso. Rilancia lo spike prima di scrivere il report.',
      );
      return;
    }

    stdout.writeln(
      'B1 CONFERMATO — nessuna precondizione server-enforced. '
      '${ignored.length} prove decisive hanno risposto 2xx E hanno riscritto i '
      'byte remoti: gli header condizionali sono accettati e ignorati.',
    );
    stdout.writeln(
      'Guarda la sezione 5 (header malformato) per sapere se Drive li parsa e '
      'li scarta, oppure non li guarda affatto.',
    );
  }

  Uint8List _randomBytes() {
    return Uint8List.fromList(
      List<int>.generate(64, (_) => _random.nextInt(256)),
    );
  }

  Uint8List _multipartBody({
    required String boundary,
    required String name,
    required Uint8List bytes,
  }) {
    final preamble = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '${jsonEncode({'name': name})}\r\n'
      '--$boundary\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    return Uint8List.fromList([
      ...preamble,
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ]);
  }

  void _printRequestHeaders(Map<String, String> headers) {
    final sanitized = headers.map(
      (key, value) => MapEntry(
        key,
        key.toLowerCase() == 'authorization' ? 'Bearer <redacted>' : value,
      ),
    );
    stdout.writeln('   header inviati: $sanitized');
  }

  void _printResponse(http.Response response, {bool alwaysPrintBody = true}) {
    stdout.writeln('   status: ${response.statusCode}');
    final keys = response.headers.keys.toList()..sort();
    for (final key in keys) {
      stdout.writeln('   < $key: ${response.headers[key]}');
    }
    final isError = response.statusCode < 200 || response.statusCode >= 300;
    if (isError || alwaysPrintBody) {
      final body = response.body;
      final preview = body.length > _bodyPreviewLimit
          ? '${body.substring(0, _bodyPreviewLimit)}… [troncato]'
          : body;
      stdout.writeln('   body: $preview');
    }
  }

  String _describe(_ContentState state) => switch (state) {
    _ContentState.writeApplied => 'SCRITTURA APPLICATA (byte remoti cambiati)',
    _ContentState.writeRejected => 'SCRITTURA RESPINTA (byte remoti invariati)',
    _ContentState.unexpected => 'STATO INATTESO (byte ne\' nuovi ne\' vecchi)',
    _ContentState.unknown => 'IGNOTO (rilettura fallita)',
  };

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _section(String title) {
    stdout.writeln();
    stdout.writeln('=' * 72);
    stdout.writeln(title);
    stdout.writeln('=' * 72);
  }
}
