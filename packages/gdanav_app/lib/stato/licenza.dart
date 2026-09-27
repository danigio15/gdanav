import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Le licenze di gdanav da sola (del telefono), come le rilascia il quadro di
/// gdahome: il contratto è `docs/LICENZE.md` di gdahome. Qui servono per i
/// **codici regalo**; l'abbonamento comprato nel negozio resta controllato dal
/// telefono, senza il quadro.

/// Il quadro: rilascia le licenze e riscatta i codici.
final quadroLicenze = Uri.parse('https://quadro.gdahome.org/');

/// Un gettone letto e verificato.
class GettoneLicenza {
  const GettoneLicenza({
    required this.testo,
    required this.app,
    required this.soggetto,
    required this.licenza,
    required this.origine,
    required this.scade,
    required this.fino,
  });

  /// Il gettone com'è arrivato, da ricordare.
  final String testo;

  /// `gdanav` o `gdahome` (che comprende gdanav).
  final String app;

  /// `tel_…` per gdanav da sola.
  final String soggetto;
  final String licenza;

  /// `negozio`, `regalo`, `installatore`.
  final String origine;

  /// Quando finisce la licenza; `null`: per sempre.
  final DateTime? scade;

  /// Quando smette di valere questo gettone (va rinnovato prima).
  final DateTime fino;
}

List<int>? _base64url(String s) {
  try {
    return base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
  } catch (_) {
    return null;
  }
}

/// Verifica [gettone] come dice il contratto: firma giusta con [chiavePubblica],
/// `v == 1`, `sog == soggetto`, `fino > adesso`, `scade` nullo o futuro, `app`
/// gdanav o gdahome. `null` se una sola cosa non torna, o se la chiave è vuota
/// (le licenze non sono ancora accese).
Future<GettoneLicenza?> verificaGettone(
  String gettone, {
  required String soggetto,
  required String chiavePubblica,
  DateTime? adesso,
}) async {
  if (chiavePubblica.isEmpty) return null;
  final pezzi = gettone.split('.');
  if (pezzi.length != 2) return null;
  final chiave = _base64url(chiavePubblica), firma = _base64url(pezzi[1]), corpo = _base64url(pezzi[0]);
  if (chiave == null || chiave.length != 32 || firma == null || firma.length != 64 || corpo == null) return null;
  try {
    final giusta = await Ed25519().verify(
      ascii.encode(pezzi[0]),
      signature: Signature(firma, publicKey: SimplePublicKey(chiave, type: KeyPairType.ed25519)),
    );
    if (!giusta) return null;
    final j = jsonDecode(utf8.decode(corpo));
    if (j is! Map<String, Object?>) return null;
    final ora = (adesso ?? DateTime.now()).millisecondsSinceEpoch;
    final app = j['app'], sog = j['sog'], fino = j['fino'], scade = j['scade'];
    if (j['v'] != 1 || sog != soggetto) return null;
    if (app != 'gdanav' && app != 'gdahome') return null;
    if (fino is! num || fino <= ora) return null;
    if (scade != null && (scade is! num || scade <= ora)) return null;
    return GettoneLicenza(
      testo: gettone,
      app: app! as String,
      soggetto: soggetto,
      licenza: j['lic'] as String? ?? '',
      origine: j['origine'] as String? ?? '',
      scade: scade == null ? null : DateTime.fromMillisecondsSinceEpoch((scade as num).toInt()),
      fino: DateTime.fromMillisecondsSinceEpoch(fino.toInt()),
    );
  } catch (_) {
    return null;
  }
}

/// Fra i gettoni della risposta del quadro, quello che vale per questo
/// telefono (gdanav o gdahome), il più lungo.
Future<GettoneLicenza?> gettoneMigliore(
  Iterable<String> gettoni, {
  required String soggetto,
  required String chiavePubblica,
  DateTime? adesso,
}) async {
  GettoneLicenza? migliore;
  for (final g in gettoni) {
    final v = await verificaGettone(g, soggetto: soggetto, chiavePubblica: chiavePubblica, adesso: adesso);
    if (v != null && (migliore == null || v.fino.isAfter(migliore.fino))) migliore = v;
  }
  return migliore;
}

/// L'identità di questo telefono verso il quadro: `tel_` + 32 cifre
/// esadecimali, e il segreto che la prima volta il quadro si segna.
typedef IdentitaTelefono = ({String telefono, String segreto});

IdentitaTelefono nuovaIdentitaTelefono([Random? caso]) {
  final r = caso ?? Random.secure();
  String esa(int byte) => [for (var i = 0; i < byte; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  return (telefono: 'tel_${esa(16)}', segreto: esa(32));
}

/// L'alfabeto dei codici: senza lettere che si confondono (I, L, O, 0, 1).
const alfabetoCodici = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// «gda xxxx-xxxx xxxx» → «GDA-XXXX-XXXX-XXXX»; `null` se non è un codice.
String? normalizzaCodice(String scritto) {
  var s = scritto.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (s.startsWith('GDA')) s = s.substring(3);
  if (s.length != 12 || s.split('').any((c) => !alfabetoCodici.contains(c))) return null;
  return 'GDA-${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8)}';
}

/// Quello che il quadro non accetta, già in parole.
class ErroreLicenza implements Exception {
  const ErroreLicenza(this.messaggio, {this.stato});
  final String messaggio;
  final int? stato;

  @override
  String toString() => messaggio;
}

/// Il quadro visto dal telefono: `POST /v1/licenze/riscatta` e
/// `POST /v1/licenze/telefono`. Risponde coi gettoni.
class ClienteLicenze {
  ClienteLicenze({http.Client? client, Uri? base, this.attesa = const Duration(seconds: 20)})
    : _client = client ?? http.Client(),
      base = base ?? quadroLicenze;

  final http.Client _client;
  final Uri base;
  final Duration attesa;

  /// Riscatta [codice] per questo telefono: torna i gettoni.
  Future<List<String>> riscatta(String codice, IdentitaTelefono io) =>
      _chiedi('v1/licenze/riscatta', {'codice': codice, 'telefono': io.telefono, 'segreto': io.segreto});

  /// I gettoni di adesso per questo telefono (anche nessuno: licenza tolta).
  Future<List<String>> rinnova(IdentitaTelefono io) =>
      _chiedi('v1/licenze/telefono', {'telefono': io.telefono, 'segreto': io.segreto});

  Future<List<String>> _chiedi(String via, Map<String, String> corpo) async {
    final http.Response r;
    try {
      r = await _client
          .post(base.resolve(via), headers: {'content-type': 'application/json'}, body: jsonEncode(corpo))
          .timeout(attesa);
    } catch (_) {
      throw const ErroreLicenza('Il servizio delle licenze non risponde. Controlla la rete e riprova.');
    }
    switch (r.statusCode) {
      case 200:
        break;
      case 404:
        throw const ErroreLicenza('Questo codice non esiste: controlla le lettere.', stato: 404);
      case 409:
        throw const ErroreLicenza('Questo codice è già stato usato.', stato: 409);
      case 403 || 401:
        throw ErroreLicenza('Il servizio delle licenze non riconosce questo telefono.', stato: r.statusCode);
      default:
        throw ErroreLicenza('Il servizio delle licenze non risponde. Riprova tra poco.', stato: r.statusCode);
    }
    try {
      final j = jsonDecode(r.body) as Map<String, Object?>;
      final g = j['gettoni'];
      if (g is! Map) return const [];
      return [
        for (final v in g.values)
          if (v is String && v.isNotEmpty) v,
      ];
    } catch (_) {
      throw const ErroreLicenza('Il servizio delle licenze ha risposto in modo strano. Riprova tra poco.');
    }
  }
}
