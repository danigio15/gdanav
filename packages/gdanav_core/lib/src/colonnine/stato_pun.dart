import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'colonnina.dart';
import 'disponibilita_tomtom.dart' show FonteDisponibilita;
import 'pun.dart';

/// Libere e occupate adesso, dalla Piattaforma Unica Nazionale.
///
/// La PUN dà lo stato punto per punto (EVSE), quindi la colonnina deve avere
/// i suoi EVSE ID ([Colonnina.evse]): arrivano dall'archivio. Si chiede come
/// lo chiede la mappa pubblica del sito: credenziali ospite di Cognito (le
/// stesse di chi apre la mappa, nessun login, l'identity pool è quello che
/// il sito pubblica in `/config.json`), e una richiesta firmata a
/// `/v1/chargepoints/group` con al massimo cento EVSE per volta.
///
/// Chiede il telefono che guarda, solo per le colonnine che si guardano, e
/// uno stato letto vale [validita]. Niente di questo costa: la PUN è
/// pubblica e senza chiave.
class DisponibilitaPun implements FonteDisponibilita {
  DisponibilitaPun({
    http.Client? client,
    this.validita = const Duration(minutes: 1),
    this.validitaTutti = const Duration(minutes: 3),
    DateTime Function()? adesso,
  })  : _http = client ?? http.Client(),
        _adesso = adesso ?? DateTime.now;

  final http.Client _http;
  final DateTime Function() _adesso;

  /// Quanto vale uno stato letto.
  final Duration validita;

  static const api = 'https://api.pun.piattaformaunicanazionale.it';
  static const regione = 'eu-south-1';

  /// L'identity pool che il sito pubblica in `/config.json`: lo stesso che
  /// legge AgID nel Cruscotto Italia.
  static const pool = 'eu-south-1:e3b2ab05-2046-43dd-8ed0-c0f14c69d507';

  /// Quanti EVSE per richiesta: quanti ne chiede il sito.
  static const blocco = 100;

  /// Quanti EVSE al massimo per una colonnina. L'Isola A3 del Centro
  /// Direzionale ne ha 202: tre richieste. Oltre, si guarda un campione.
  static const massimoEvse = 300;

  final _recenti = <String, (DateTime, Colonnina)>{};
  _Credenziali? _credenziali;
  String? _identita;

  /// Le richieste passano una alla volta: dieci colonnine sullo schermo non
  /// diventano dieci richieste insieme.
  Future<void> _turno = Future.value();

  @override
  Future<Colonnina> aggiorna(Colonnina c) async {
    if (c.evse.isEmpty) return c;
    if (_recenti[c.id] case (final quando, final gia) when _adesso().difference(quando) < validita) return gia;
    final prima = _turno;
    final fatto = Completer<void>();
    _turno = fatto.future;
    try {
      await prima;
      final nuova = await _aggiorna(c);
      _recenti[c.id] = (_adesso(), nuova);
      return nuova;
    } finally {
      fatto.complete();
    }
  }

  Future<Colonnina> _aggiorna(Colonnina c) async {
    final evse = c.evse.take(massimoEvse).toList();
    final letti = <String, Map>{};
    for (var i = 0; i < evse.length; i += blocco) {
      final parte = evse.sublist(i, math.min(i + blocco, evse.length));
      for (final r in await punti(parte)) {
        if (r['evse_id'] case final String id) letti[id] = r;
      }
    }
    final prese = [
      for (final id in evse)
        if (letti[id] case final r?)
          if (presaDi(r) case final p?) p,
    ];
    // Nessuno dei suoi punti risponde: com'era, senza inventare niente.
    if (prese.isEmpty) return c;
    return Colonnina(
      id: c.id,
      nome: c.nome,
      posizione: c.posizione,
      operatore: c.operatore,
      fonte: c.fonte,
      evse: c.evse,
      connettori: prese,
    );
  }

  /// Un punto di ricarica della PUN come presa, con lo stato di adesso. La
  /// presa è la migliore che ha (come nell'archivio: un punto è un'auto).
  static Connettore? presaDi(Map r) {
    final connettori = ((r['connectors'] as List?) ?? const []).whereType<Map>();
    final p = Pun.presa(
      connettori.map((x) => '${x['standard'] ?? ''}').join(','),
      connettori.map((x) => '${x['max_electric_power'] ?? 0}').join(','),
    );
    if (p == null) return null;
    return Connettore(tipo: p.tipo, potenzaKw: p.potenzaKw, stato: statoDi(r));
  }

  /// Lo stato di un punto. Solo quelli che il gestore aggiorna in tempo reale
  /// dicono il vero: per gli altri la PUN ripete uno stato fisso, e dire
  /// «libera» su quello sarebbe una bugia.
  static StatoPresa statoDi(Map r) {
    if (r['realTime'] == false) return StatoPresa.sconosciuto;
    return statoDaParola('${r['status'] ?? ''}');
  }

  /// La colonnina con lo stato di adesso dei suoi punti di ricarica, preso
  /// da [stati] (quello di tutta Italia, [statiDiTutti]).
  ///
  /// Un punto è una presa, come nell'archivio: la presa i-esima prende lo
  /// stato del punto i-esimo. Vale quando i punti sono tanti quante le prese
  /// e sono tutte uguali — 26.000 colonnine su 30.000: allora l'ordine non
  /// conta —, oppure quando l'archivio ha scritto i punti nello stesso ordine
  /// delle prese ([inOrdine]). Altrimenti non si indovina quale presa è
  /// libera: la colonnina resta com'era, e lo stato si chiede quando la si
  /// tocca ([aggiorna]).
  static Colonnina conStati(Colonnina c, Map<String, String> stati, {bool inOrdine = false}) {
    if (c.evse.isEmpty || c.evse.length != c.connettori.length) return c;
    final prima = c.connettori.first;
    final uguali = c.connettori.every((p) => p.tipo == prima.tipo && p.potenzaKw == prima.potenzaKw);
    if (!uguali && !inOrdine) return c;
    var letti = 0;
    final prese = <Connettore>[];
    for (final (i, p) in c.connettori.indexed) {
      final parola = stati[c.evse[i]];
      if (parola != null) letti++;
      prese.add(parola == null ? p : p.conStato(statoDaParola(parola)));
    }
    if (letti == 0) return c;
    return Colonnina(
      id: c.id,
      nome: c.nome,
      posizione: c.posizione,
      operatore: c.operatore,
      fonte: c.fonte,
      evse: c.evse,
      connettori: prese,
    );
  }

  /// La parola della PUN (`AVAILABLE`, `CHARGING`…) come stato di una presa.
  static StatoPresa statoDaParola(String? parola) => switch ((parola ?? '').toUpperCase()) {
        'AVAILABLE' => StatoPresa.disponibile,
        // Bloccata: c'è un'auto ferma davanti, per chi arriva è occupata.
        'CHARGING' || 'RESERVED' || 'BLOCKED' => StatoPresa.occupata,
        'OUTOFORDER' || 'INOPERATIVE' => StatoPresa.fuoriServizio,
        _ => StatoPresa.sconosciuto,
      };

  /// I punti di ricarica [evse] come li dà la PUN (al massimo [blocco] per
  /// volta): lo stato, le prese, il posto. È la stessa risposta da cui
  /// [aggiorna] legge libere e occupate.
  Future<List<Map>> punti(List<String> evse) async =>
      ((await _chiedi('/v1/chargepoints/group', evse)).dati as List).whereType<Map>().toList();

  /// Lo stato di ogni punto di ricarica d'Italia, come lo disegna la mappa
  /// pubblica della PUN: EVSE ID → parola dello stato (`AVAILABLE`,
  /// `CHARGING`…).
  ///
  /// Sono le pagine di `/v1/chargepoints/public/map/search`, [pagina] punti
  /// per volta, quante ne chiede il sito quando si apre: sette richieste per
  /// tutta Italia. Valgono [validitaTutti]; chi le chiede mentre stanno
  /// arrivando aspetta le stesse, invece di rifarle.
  Future<Map<String, String>> statiDiTutti() {
    if (_tutti case (final quando, final stati) when _adesso().difference(quando) < validitaTutti) {
      return Future.value(stati);
    }
    return _tuttiInArrivo ??= _leggiTutti().whenComplete(() => _tuttiInArrivo = null);
  }

  /// Quanti punti chiede ogni pagina: come il sito.
  static const pagina = 12000;

  /// Quanto vale lo stato di tutta Italia letto.
  final Duration validitaTutti;

  (DateTime, Map<String, String>)? _tutti;
  Future<Map<String, String>>? _tuttiInArrivo;

  /// Com'è andata l'ultima lettura di tutta Italia: per la diagnosi.
  ({int pagine, int punti, int byte, Duration tempo, String compressione})? ultimaLettura;

  Future<Map<String, String>> _leggiTutti() async {
    final orologio = Stopwatch()..start();
    final stati = <String, String>{};
    var byte = 0, pagine = 0;
    var compressione = '';
    for (var n = 0; n < 40; n++) {
      final r = await _chiedi('/v1/chargepoints/public/map/search', {'page': n, 'size': pagina});
      pagine++;
      byte += r.byte;
      compressione = r.compressione;
      final d = r.dati;
      final contenuto = d is Map ? (d['content'] as List? ?? const []) : const [];
      for (final p in contenuto.whereType<Map>()) {
        if (p['evse_id'] case final String id when id.isNotEmpty) stati[id] = '${p['status'] ?? ''}';
      }
      if (contenuto.isEmpty || (d is Map && d['last'] == true)) break;
    }
    ultimaLettura = (
      pagine: pagine,
      punti: stati.length,
      byte: byte,
      tempo: orologio.elapsed,
      compressione: compressione,
    );
    _tutti = (_adesso(), stati);
    return stati;
  }

  /// Una richiesta firmata alla PUN: il JSON della risposta, e quanto pesava.
  Future<({Object? dati, int byte, String compressione})> _chiedi(String percorso, Object corpoJson) async {
    for (var tentativo = 0;; tentativo++) {
      final c = await _credenzialiValide();
      final corpo = utf8.encode(jsonEncode(corpoJson));
      final uri = Uri.parse('$api$percorso');
      final data = _adesso().toUtc();
      final firmate = {
        'content-type': 'application/json',
        'host': uri.host,
        'x-amz-date': dataAmz(data),
        'x-amz-security-token': c.token,
      };
      final autorizzazione = await firmaSigV4(
        metodo: 'POST',
        uri: uri,
        intestazioni: firmate,
        corpo: corpo,
        idChiave: c.idChiave,
        segreto: c.segreto,
        regione: regione,
        servizio: 'execute-api',
        data: data,
      );
      final r = await _http
          .post(
            uri,
            headers: {
              for (final MapEntry(:key, :value) in firmate.entries)
                if (key != 'host') key: value,
              'authorization': autorizzazione,
            },
            // Byte e non testo: col testo il pacchetto http aggiunge
            // «; charset=utf-8» al content-type, e la firma non torna più.
            body: corpo,
          )
          .timeout(const Duration(seconds: 30));
      // Credenziali scadute o rifiutate: se ne prendono di nuove, una volta.
      if ((r.statusCode == 401 || r.statusCode == 403) && tentativo == 0) {
        _credenziali = null;
        continue;
      }
      if (r.statusCode != 200) throw Exception('PUN: ${r.statusCode}');
      return (
        dati: jsonDecode(utf8.decode(r.bodyBytes)),
        byte: r.bodyBytes.length,
        compressione: r.headers['content-encoding'] ?? '',
      );
    }
  }

  Future<_Credenziali> _credenzialiValide() async {
    if (_credenziali case final c? when c.scadenza.isAfter(_adesso().add(const Duration(minutes: 5)))) return c;
    final identita = _identita ??= (await _cognito('GetId', {'IdentityPoolId': pool}))['IdentityId'] as String;
    final j = (await _cognito('GetCredentialsForIdentity', {'IdentityId': identita}))['Credentials'] as Map;
    return _credenziali = _Credenziali(
      j['AccessKeyId'] as String,
      j['SecretKey'] as String,
      j['SessionToken'] as String,
      DateTime.fromMillisecondsSinceEpoch(((j['Expiration'] as num) * 1000).round(), isUtc: true),
    );
  }

  Future<Map<String, Object?>> _cognito(String azione, Map<String, Object?> corpo) async {
    final r = await _http
        .post(
          Uri.parse('https://cognito-identity.$regione.amazonaws.com/'),
          headers: {
            'content-type': 'application/x-amz-json-1.1',
            'x-amz-target': 'AWSCognitoIdentityService.$azione',
          },
          body: utf8.encode(jsonEncode(corpo)),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) {
      // Un'identità che non vale più (il pool l'ha buttata): la prossima volta
      // se ne chiede una nuova.
      if (azione == 'GetCredentialsForIdentity') _identita = null;
      throw Exception('PUN, credenziali: ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
  }
}

/// Lo stato di adesso da chi lo sa: la PUN per le colonnine che ne hanno gli
/// EVSE ID (gratis, punto per punto), [altra] per le altre — TomTom, che ha
/// una quota. Se la PUN non risponde o non conosce la colonnina, si prova
/// l'altra.
class DisponibilitaConPun implements FonteDisponibilita {
  DisponibilitaConPun(this.pun, {this.altra});

  final FonteDisponibilita pun;
  final FonteDisponibilita? altra;

  @override
  Future<Colonnina> aggiorna(Colonnina c) async {
    if (c.evse.isNotEmpty) {
      try {
        final nuova = await pun.aggiorna(c);
        if (!identical(nuova, c)) return nuova;
      } catch (_) {
        // La PUN giù o cambiata: si va avanti con l'altra.
      }
    }
    return await altra?.aggiorna(c) ?? c;
  }
}

class _Credenziali {
  _Credenziali(this.idChiave, this.segreto, this.token, this.scadenza);

  final String idChiave;
  final String segreto;
  final String token;
  final DateTime scadenza;
}

/// `20150830T123600Z`: la data come la vuole la firma di AWS.
String dataAmz(DateTime d) {
  final u = d.toUtc();
  String due(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${due(u.month)}${due(u.day)}T${due(u.hour)}${due(u.minute)}${due(u.second)}Z';
}

/// La firma di AWS (Signature Version 4) di una richiesta: il valore
/// dell'intestazione `Authorization`. Si firmano le [intestazioni] date,
/// `host` compreso.
Future<String> firmaSigV4({
  required String metodo,
  required Uri uri,
  required Map<String, String> intestazioni,
  required List<int> corpo,
  required String idChiave,
  required String segreto,
  required String regione,
  required String servizio,
  required DateTime data,
}) async {
  final quando = dataAmz(data);
  final giorno = quando.substring(0, 8);
  final nomi = intestazioni.keys.map((k) => k.toLowerCase()).toList()..sort();
  final valori = {for (final MapEntry(:key, :value) in intestazioni.entries) key.toLowerCase(): value.trim()};
  // «/» e non vuoto quando non c'è percorso: con quello vuoto l'esempio di
  // AWS dava un'altra firma.
  final percorso = uri.pathSegments.isEmpty ? '/' : uri.pathSegments.map((s) => '/${_codifica(s)}').join();
  final domanda = [
    for (final MapEntry(:key, :value) in uri.queryParametersAll.entries)
      for (final v in value) '${_codifica(key)}=${_codifica(v)}',
  ]..sort();
  final canonica = [
    metodo,
    percorso,
    domanda.join('&'),
    for (final n in nomi) '$n:${valori[n]}',
    '',
    nomi.join(';'),
    await _sha256Hex(corpo),
  ].join('\n');
  final ambito = '$giorno/$regione/$servizio/aws4_request';
  final daFirmare = ['AWS4-HMAC-SHA256', quando, ambito, await _sha256Hex(utf8.encode(canonica))].join('\n');
  List<int> chiave = utf8.encode('AWS4$segreto');
  for (final pezzo in [giorno, regione, servizio, 'aws4_request']) {
    chiave = await _hmac(chiave, utf8.encode(pezzo));
  }
  final firma = _esadecimale(await _hmac(chiave, utf8.encode(daFirmare)));
  return 'AWS4-HMAC-SHA256 Credential=$idChiave/$ambito, SignedHeaders=${nomi.join(';')}, Signature=$firma';
}

/// Come vuole AWS: tutto codificato tranne lettere, cifre e `-_.~`.
String _codifica(String s) => Uri.encodeComponent(s)
    .replaceAll('!', '%21')
    .replaceAll("'", '%27')
    .replaceAll('(', '%28')
    .replaceAll(')', '%29')
    .replaceAll('*', '%2A');

Future<List<int>> _hmac(List<int> chiave, List<int> testo) async =>
    (await Hmac.sha256().calculateMac(testo, secretKey: SecretKey(chiave))).bytes;

Future<String> _sha256Hex(List<int> byte) async => _esadecimale((await Sha256().hash(byte)).bytes);

String _esadecimale(List<int> byte) => byte.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
