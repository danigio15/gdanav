import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/* ── Il traffico di TomTom contato due volte ────────────────────────────────
 *
 * I tempi di un percorso di TomTom hanno già dentro il traffico di adesso.
 * Due strade lo rimettevano sopra: la guida, che ogni cinque minuti rilegge
 * il traffico (TrafficoTomTom.applica) anche sui percorsi di TomTom, e la
 * strada scelta fra le alternative, rifatta con corsie e limiti
 * (`seguendo`) e poi rallentata con le code che aveva già. Sul Corso Malta
 * 802 secondi diventavano 1355. */
Map<String, Object?> corsoMalta() =>
    jsonDecode(File('test/dati/tomtom_corso_malta.json').readAsStringSync()) as Map<String, Object?>;

class _Nessuna implements FonteColonnine {
  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async => const [];
}

void main() {
  test('il traffico riletto su un percorso TomTom non si somma ai tempi che lo hanno già', () async {
    final p = ClienteTomTom.leggiTutte(corsoMalta()).first;
    var chieste = 0;
    final traffico = TrafficoTomTom(
      'chiave',
      client: MockClient((_) async {
        chieste++;
        return http.Response.bytes(utf8.encode(jsonEncode(corsoMalta())), 200);
      }),
    );
    final dopo = await traffico.applica(p);
    expect(dopo.durata.inSeconds, closeTo(p.durata.inSeconds, 30));
    expect(dopo.ritardoTraffico, p.ritardoTraffico);
    // E non si spreca una richiesta del piano gratuito.
    expect(chieste, 0);
  });

  test('su un percorso di Valhalla il traffico si legge ancora', () async {
    final tomtom = ClienteTomTom.leggiTutte(corsoMalta()).first;
    // La stessa strada senza traffico, come la darebbe Valhalla.
    final valhalla = PercorsoCalcolato(punti: tomtom.punti, tratti: tomtom.tratti, manovre: tomtom.manovre);
    var chieste = 0;
    final traffico = TrafficoTomTom(
      'chiave',
      client: MockClient((_) async {
        chieste++;
        return http.Response.bytes(utf8.encode(jsonEncode(corsoMalta())), 200);
      }),
    );
    final dopo = await traffico.applica(valhalla);
    expect(chieste, 1);
    expect(dopo.trafficoVero, isTrue);
    expect(dopo.senzaTraffico, same(valhalla));
  });

  test('una strada TomTom scelta fra le alternative non prende il traffico due volte', () async {
    final scelto = ClienteTomTom.leggiTutte(corsoMalta()).first;
    // Come gestore_viaggio.pianificatoreVero con TomTom: seguendo ridà la
    // stessa strada (ClienteTomTom.seguendo con le manovre), niente traffico a parte.
    final pv = PianificatoreViaggio(
      percorsi: (_) async => scelto,
      colonnine: _Nessuna(),
      profilo: ProfiloVeicolo.esempio,
      seguendo: (p) async => p,
    );
    final p = await pv.percorso(partenza: scelto.punti.first, arrivo: scelto.punti.last, scelto: scelto);
    expect(p.durata.inSeconds, closeTo(scelto.durata.inSeconds, 30));
  });

  test('una strada di Valhalla scelta col traffico lo riporta sulla strada rifatta', () async {
    final tomtom = ClienteTomTom.leggiTutte(corsoMalta()).first;
    final valhalla = PercorsoCalcolato(punti: tomtom.punti, tratti: tomtom.tratti, manovre: tomtom.manovre);
    final scelto = valhalla.conTraffico(TrafficoTomTom.codeDa(corsoMalta(), valhalla.punti),
        totale: TrafficoTomTom.totaleDa(corsoMalta()));
    final pv = PianificatoreViaggio(
      percorsi: (_) async => valhalla,
      colonnine: _Nessuna(),
      profilo: ProfiloVeicolo.esempio,
      seguendo: (_) async => valhalla,
    );
    final p = await pv.percorso(partenza: scelto.punti.first, arrivo: scelto.punti.last, scelto: scelto);
    expect(p.trafficoVero, isTrue);
    expect(p.durata.inSeconds, closeTo(scelto.durata.inSeconds, 30));
  });
}
