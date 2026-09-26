import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'abbinamento.dart';
import 'messaggio.dart';

/// Chiude e apre i messaggi con AES-256-GCM. Il relay vede solo
///
///     {"v":1,"n":"<nonce>","c":"<cifrato+tag>"}
///
/// e i dati associati legano ogni busta al canale e a chi l'ha mandata.
class Busta {
  Busta(this._chiave, this._canale);

  static Future<Busta> per(Abbinamento a) async => Busta(a.chiave, await a.canale());

  final Uint8List _chiave;
  final String _canale;
  final _aes = AesGcm.with256bits();

  /// Il messaggio più vecchio che si accetta, contro chi rispedisce buste
  /// vecchie registrate dal relay.
  static const tolleranza = Duration(minutes: 5);

  Future<String> chiudi(Messaggio m, Mittente da, {List<int>? nonce}) async {
    final scatola = await _aes.encrypt(
      utf8.encode(jsonEncode(m.toJson())),
      secretKey: SecretKey(_chiave),
      nonce: nonce ?? _nonce(),
      aad: _aad(da),
    );
    return jsonEncode({
      'v': 1,
      'n': base64UrlSenzaPadding.encode(scatola.nonce),
      'c': base64UrlSenzaPadding.encode([...scatola.cipherText, ...scatola.mac.bytes]),
    });
  }

  /// Lancia se la busta è rotta, non è per questo canale, non viene da [da]
  /// o è troppo vecchia.
  Future<Messaggio> apri(String testo, Mittente da, {DateTime? ora}) async {
    final json = jsonDecode(testo) as Map<String, Object?>;
    if (json['v'] != 1) throw FormatException('Versione della busta non supportata: ${json['v']}');
    final c = base64UrlSenzaPadding.decode(json['c'] as String);
    if (c.length < 16) throw const FormatException('Busta troppo corta');
    final chiaro = await _aes.decrypt(
      SecretBox(
        c.sublist(0, c.length - 16),
        nonce: base64UrlSenzaPadding.decode(json['n'] as String),
        mac: Mac(c.sublist(c.length - 16)),
      ),
      secretKey: SecretKey(_chiave),
      aad: _aad(da),
    );
    final m = Messaggio.daJson(jsonDecode(utf8.decode(chiaro)) as Map<String, Object?>);
    if ((ora ?? DateTime.now()).toUtc().difference(m.ts).abs() > tolleranza) {
      throw const FormatException('Messaggio fuori tempo');
    }
    return m;
  }

  List<int> _aad(Mittente da) => utf8.encode('gdanav/v1/$_canale/${da.name}');

  static List<int> _nonce() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(256));
  }
}
