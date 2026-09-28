/// Cosa c'è davvero dentro un riquadro di traffico di TomTom.
///
/// Lo strato del traffico sulla mappa filtra su dei nomi di campo. Se un nome
/// è sbagliato non si vede nessun errore: si vede una città senza code, che è
/// indistinguibile da una città che scorre. Questa prova va a leggere un
/// riquadro vero e stampa i nomi che ci trova dentro, così la prossima volta
/// non si tira a indovinare.
///
/// Gira solo in CI, con GDANAV_RETE=1 e la chiave in GDANAV_TOMTOM. La chiave
/// non finisce mai in quello che stampa.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void avviso(String titolo, String testo) => stdout.writeln('::notice title=$titolo::$testo');

/// Le parole leggibili dentro un pacchetto protobuf: i nomi degli strati e
/// dei campi ci stanno dentro in chiaro, e per sapere come si chiamano non
/// serve saper leggere un protobuf.
List<String> paroleDentro(List<int> byte, {int minimo = 4}) {
  final fuori = <String>[];
  final corrente = StringBuffer();
  for (final b in byte) {
    if (b >= 0x20 && b < 0x7F) {
      corrente.write(String.fromCharCode(b));
    } else {
      if (corrente.length >= minimo) fuori.add(corrente.toString());
      corrente.clear();
    }
  }
  if (corrente.length >= minimo) fuori.add(corrente.toString());
  return fuori;
}

void main() {
  test('un riquadro di traffico di TomTom, e come si chiamano i suoi campi', () async {
    final chiave = Platform.environment['GDANAV_TOMTOM'] ?? '';
    if (chiave.isEmpty) {
      avviso('TomTom', 'nessuna chiave in GDANAV_TOMTOM: saltata');
      return;
    }
    // Napoli, zoom 14: dentro ci sono tangenziale e centro, alle ore di
    // punta non è mai tutto libero.
    const z = 14, x = 8759, y = 6420;
    final url = Uri.parse(
      'https://api.tomtom.com/traffic/map/4/tile/flow/relative/$z/$x/$y.pbf'
      '?key=${Uri.encodeQueryComponent(chiave)}',
    );
    final r = await http.get(url);
    // Mai stampare l'indirizzo: dentro c'è la chiave.
    avviso('TomTom riquadro', 'flow/relative/$z/$x/$y.pbf → HTTP ${r.statusCode}, ${r.bodyBytes.length} byte');
    if (r.statusCode != 200) {
      avviso('TomTom riquadro', 'il server ha detto di no: lo strato del traffico non può funzionare');
      return;
    }

    var byte = r.bodyBytes.toList();
    if (byte.length > 2 && byte[0] == 0x1F && byte[1] == 0x8B) byte = gzip.decode(byte);
    final parole = paroleDentro(byte).toSet().toList()..sort();
    /* Dei nomi veri interessano quelli corti: gli strati e i campi. Le stringhe
     * lunghe sono i valori (nomi di strada e simili). */
    final nomi = parole.where((p) => p.length <= 28).toList();
    avviso('TomTom campi', nomi.join(' · '));

    expect(byte, isNotEmpty, reason: 'un riquadro vuoto vuol dire nessun traffico da disegnare');
    // Quello su cui filtra lo strato: se questi due non ci sono, la mappa
    // resta senza traffico comunque vada.
    for (final atteso in ['Traffic flow', 'traffic_level', 'road_category']) {
      avviso(
          'TomTom c\'è «$atteso»?', nomi.contains(atteso) ? 'sì' : 'NO — lo strato filtra su un nome che non esiste');
    }
  },
      timeout: const Timeout(Duration(minutes: 1)),
      skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false);
}
