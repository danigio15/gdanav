import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Quello che c'è nel QR che Home Assistant mostra, e che l'app inquadra
/// una volta sola.
///
///     gdanav://abbina?v=1&k=<chiave>&r=<relay>&n=<nome auto>
///
/// La chiave non esce mai dal telefono e dalla casa: al relay arrivano solo
/// il [canale] e il gettone di [accesso], che se ne ricavano ma non la
/// rivelano.
class Abbinamento {
  Abbinamento({required this.chiave, required this.relay, this.nomeAuto = ''}) {
    if (chiave.length != 32) throw ArgumentError('La chiave deve essere di 32 byte');
  }

  factory Abbinamento.nuovo({required Uri relay, String nomeAuto = ''}) {
    final r = Random.secure();
    return Abbinamento(
      chiave: Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
      relay: relay,
      nomeAuto: nomeAuto,
    );
  }

  static Abbinamento daUri(String testo) {
    final uri = Uri.parse(testo);
    if (uri.scheme != 'gdanav' || uri.host != 'abbina') {
      throw const FormatException('Non è un QR di gdanav');
    }
    final q = uri.queryParameters;
    if (q['v'] != '1') throw FormatException('Versione di abbinamento non supportata: ${q['v']}');
    final k = q['k'], r = q['r'];
    if (k == null || r == null) throw const FormatException('QR incompleto');
    return Abbinamento(chiave: base64UrlSenzaPadding.decode(k), relay: Uri.parse(r), nomeAuto: q['n'] ?? '');
  }

  final Uint8List chiave;
  final Uri relay;
  final String nomeAuto;

  String get uri => Uri(scheme: 'gdanav', host: 'abbina', queryParameters: {
        'v': '1',
        'k': base64UrlSenzaPadding.encode(chiave),
        'r': relay.toString(),
        if (nomeAuto.isNotEmpty) 'n': nomeAuto,
      }).toString();

  /// Il nome della stanza sul relay.
  Future<String> canale() async => (await _deriva('gdanav/canale/v1')).substring(0, 22);

  /// Il gettone per entrare nella stanza. Il relay ne tiene solo l'impronta.
  Future<String> accesso() async => _deriva('gdanav/accesso/v1');

  Future<Uri> indirizzoRelay(String ruolo) async {
    final base = relay.path.endsWith('/') ? relay.path : '${relay.path}/';
    return relay.replace(
      path: '${base}v1/canale/${await canale()}',
      queryParameters: {'ruolo': ruolo, 'accesso': await accesso()},
    );
  }

  Future<String> _deriva(String etichetta) async {
    final mac = await Hmac.sha256().calculateMac(utf8.encode(etichetta), secretKey: SecretKey(chiave));
    return base64UrlSenzaPadding.encode(mac.bytes);
  }
}

/// Base64 per URL senza `=` in fondo: così si scrive anche Python.
const base64UrlSenzaPadding = _Base64UrlSenzaPadding();

class _Base64UrlSenzaPadding {
  const _Base64UrlSenzaPadding();

  String encode(List<int> byte) => base64Url.encode(byte).replaceAll('=', '');

  Uint8List decode(String testo) => base64Url.decode(base64Url.normalize(testo));
}
