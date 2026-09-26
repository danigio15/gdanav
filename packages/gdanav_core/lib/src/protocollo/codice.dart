import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'abbinamento.dart';

/// Il codice da scrivere a mano al posto del QR, quando non si può
/// inquadrare (Home Assistant aperto sullo stesso telefono, per esempio).
///
/// Home Assistant inventa dieci lettere e cifre, `7KQ2M-9XAPD`, e lascia sul
/// relay l'abbinamento cifrato con una chiave che se ne ricava, sotto un nome
/// che se ne ricava anche lui. Il relay non vede né il codice né la chiave;
/// l'app, scritto il codice, ricava nome e chiave, prende la busta e la apre.
/// Dieci minuti, e una volta sola.
abstract final class CodiceAbbinamento {
  /// Crockford: niente I, L, O, U, che si confondono.
  static const alfabeto = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const lunghezza = 10;
  static const iterazioni = 20000;
  static const durata = Duration(minutes: 10);

  static String nuovo([Random? caso]) {
    final r = caso ?? Random.secure();
    return List.generate(lunghezza, (_) => alfabeto[r.nextInt(alfabeto.length)]).join();
  }

  /// Quello che ha scritto la persona, pulito: maiuscole, senza trattini né
  /// spazi, O come zero e I/L come uno. `null` se non è un codice.
  static String? normalizza(String testo) {
    final c =
        testo.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '').replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
    if (c.length != lunghezza || c.split('').any((x) => !alfabeto.contains(x))) return null;
    return c;
  }

  /// `7KQ2M9XAPD` → `7KQ2M-9XAPD`.
  static String mostra(String codice) => '${codice.substring(0, 5)}-${codice.substring(5)}';

  /// La chiave della busta e il nome sul relay.
  static Future<(Uint8List, String)> deriva(String codice) async {
    final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterazioni, bits: 512).deriveKey(
      secretKey: SecretKey(utf8.encode(codice)),
      nonce: utf8.encode('gdanav/codice/v1'),
    );
    final b = Uint8List.fromList(await k.extractBytes());
    final id = base64UrlSenzaPadding.encode((await Sha256().hash(b.sublist(32))).bytes).substring(0, 22);
    return (b.sublist(0, 32), id);
  }

  static List<int> get _aad => utf8.encode('gdanav/codice/v1');

  static Future<String> chiudi(Abbinamento a, String codice, {List<int>? nonce}) async {
    final (chiave, _) = await deriva(codice);
    final n = nonce ?? AesGcm.with256bits().newNonce();
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(a.uri),
      secretKey: SecretKey(chiave),
      nonce: n,
      aad: _aad,
    );
    return jsonEncode({
      'v': 1,
      'n': base64UrlSenzaPadding.encode(n),
      'c': base64UrlSenzaPadding.encode([...box.cipherText, ...box.mac.bytes]),
    });
  }

  static Future<Abbinamento> apri(String busta, String codice) async {
    final (chiave, _) = await deriva(codice);
    try {
      final j = jsonDecode(busta) as Map<String, Object?>;
      if (j['v'] != 1) throw const FormatException('Versione del codice non supportata');
      final c = base64UrlSenzaPadding.decode(j['c'] as String);
      final chiaro = await AesGcm.with256bits().decrypt(
        SecretBox(c.sublist(0, c.length - 16),
            nonce: base64UrlSenzaPadding.decode(j['n'] as String), mac: Mac(c.sublist(c.length - 16))),
        secretKey: SecretKey(chiave),
        aad: _aad,
      );
      return Abbinamento.daUri(utf8.decode(chiaro));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Codice sbagliato');
    }
  }

  /// L'indirizzo http del relay, da quello del WebSocket.
  static Uri indirizzo(Uri relay, String id) {
    final schema = switch (relay.scheme) {
      'wss' => 'https',
      'ws' => 'http',
      final s => s,
    };
    final base = relay.path.endsWith('/') ? relay.path : '${relay.path}/';
    return relay.replace(scheme: schema, path: '${base}v1/codici/$id', query: null);
  }

  /// Scritto il codice nell'app: si prende la busta dal relay e si apre.
  static Future<Abbinamento> recupera(Uri relay, String testo, {http.Client? client}) async {
    final codice = normalizza(testo);
    if (codice == null) throw const FormatException('Il codice è di 10 lettere e cifre, come 7KQ2M-9XAPD');
    final (_, id) = await deriva(codice);
    final c = client ?? http.Client();
    try {
      final r = await c.get(indirizzo(relay, id)).timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) {
        throw const FormatException('Codice sbagliato o scaduto: in Home Assistant chiedine uno nuovo');
      }
      if (r.statusCode != 200) throw FormatException('Il relay ha risposto ${r.statusCode}');
      return await apri(utf8.decode(r.bodyBytes), codice);
    } finally {
      if (client == null) c.close();
    }
  }
}
