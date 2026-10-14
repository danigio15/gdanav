import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Torino → Milano, due strade: la prima per la A4 (due sezioni `TOLL_ROAD`
/// attaccate allo svincolo), la seconda senza pedaggi. Tutto in Italia.
List<PercorsoCalcolato> torinoMilano() => ClienteTomTom.leggiTutte(
      jsonDecode(File('test/dati/tomtom_pedaggi.json').readAsStringSync()) as Map<String, Object?>,
    );

/// Utrecht da Valhalla, con tre manovre segnate `toll`.
PercorsoCalcolato utrechtAPagamento() => PercorsoCalcolato.daValhalla(
      jsonDecode(File('test/dati/valhalla_pedaggi.json').readAsStringSync()) as Map<String, Object?>,
    );

/// Una strada dritta di [km] con le [sezioni] di TomTom date.
PercorsoCalcolato conSezioni(int km, List<Map<String, Object?>> sezioni) => ClienteTomTom.leggi({
      'summary': {'lengthInMeters': km * 1000, 'travelTimeInSeconds': km * 30},
      'legs': [
        {
          'points': [
            for (var i = 0; i <= km; i++) {'latitude': 45 + i * 0.009, 'longitude': 7.0},
          ],
        },
      ],
      'sections': sezioni,
    });

void main() {
  const tariffa = TariffaPedaggio();

  group('dove si paga', () {
    test('TomTom: le sezioni attaccate diventano un tratto solo, col paese', () {
      final [a4, statale] = torinoMilano();
      expect(a4.conPedaggi, isTrue);
      expect(a4.pedaggi, hasLength(1));
      expect(a4.pedaggi.single.paese, 'ITA');
      expect(a4.pedaggi.single.lunghezzaM / 1000, closeTo(108.1, 0.2));
      expect(statale.conPedaggi, isFalse);
      expect(statale.pedaggi, isEmpty);
    });

    test('TomTom: la tangenziale di Napoli nella risposta vera', () {
      final r = (jsonDecode(File('test/dati/tomtom_corso_malta.json').readAsStringSync()) as Map)['routes'] as List;
      final p = ClienteTomTom.leggi((r.first as Map).cast<String, Object?>());
      expect(p.pedaggi, hasLength(1));
      // Senza la sezione COUNTRY il paese non si sa, e si stima lo stesso.
      expect(p.pedaggi.single.paese, isNull);
      expect(p.pedaggi.single.daM, greaterThan(0));
    });

    test('Valhalla: dalle manovre segnate `toll`', () {
      final p = utrechtAPagamento();
      expect(p.conPedaggi, isTrue);
      // Maliesingel (due manovre di fila) e Gansstraat: due tratti.
      expect(p.pedaggi, hasLength(2));
      final km = p.pedaggi.fold(0.0, (s, t) => s + t.lunghezzaM) / 1000;
      expect(km, closeTo(0.929 + 0.581 + 1.718, 0.4));
    });

    test('i percorsi copiati (traffico, ZTL) tengono i pedaggi', () {
      final p = torinoMilano().first;
      expect(p.conTraffico(const []).pedaggi, p.pedaggi);
      expect(p.conZtl(null).pedaggi, p.pedaggi);
    });

    test('TomTom: si chiedono le sezioni dei pedaggi e dei paesi', () {
      expect(ClienteTomTom.sezioniChieste, containsAll(['tollRoad', 'tollVignette', 'country']));
    });
  });

  group('quanto costa', () {
    test('a km per la tariffa, arrotondato ai dieci centesimi', () {
      final c = tariffa.stima(torinoMilano().first);
      // 108 km × 0,08 €/km = 8,65 €.
      expect(c.euro, 8.7);
      expect(c.stimato, isTrue);
      expect(c.prezzo, '~8,70 €');
      expect(c.breve, '~8,70 €');
      expect(c.riga, 'Pedaggio ~8,70 €');
      expect(c.perStima, '~8,70 € pedaggio');
      expect(c.senzaPedaggi, isFalse);
    });

    test('senza tratti a pagamento: «Senza pedaggi»', () {
      final c = tariffa.stima(torinoMilano().last);
      expect(c.senzaPedaggi, isTrue);
      expect(c.breve, 'Senza pedaggi');
      expect(c.riga, 'Senza pedaggi');
    });

    test('la classe del veicolo moltiplica la tariffa', () {
      final p = torinoMilano().first;
      expect(tariffa.copia(classe: ClassePedaggio.quattro).stima(p).euro, 16.9);
      expect(tariffa.copia(euroAlKmClasseA: 0.1).stima(p).euro, 10.8);
    });

    test('un tratto corto costa almeno il minimo, una volta sola se i tratti sono vicini', () {
      // Utrecht: 3 km a pagamento in due tratti a 250 m l'uno dall'altro.
      expect(tariffa.stima(utrechtAPagamento()).euro, 1.0);
      expect(tariffa.copia(minimoPerTratta: 0).stima(utrechtAPagamento()).euro, closeTo(0.3, 0.11));
      // Due tratti lontani: due minimi.
      final p = conSezioni(40, [
        {'sectionType': 'TOLL_ROAD', 'startPointIndex': 2, 'endPointIndex': 4},
        {'sectionType': 'TOLL_ROAD', 'startPointIndex': 30, 'endPointIndex': 32},
      ]);
      expect(tariffa.stima(p).euro, 2.0);
    });

    test('in guida: solo quello che resta, e il tratto in cui si è conta tutto', () {
      final p = torinoMilano().first;
      final t = p.pedaggi.single;
      expect(tariffa.stima(p, daM: t.daM + 50000).euro, 8.7);
      final passato = tariffa.stima(p, daM: t.aM + 1);
      expect(passato.conPrezzo, isFalse);
      expect(passato.senzaPedaggi, isTrue);
    });

    test('all\'estero non si stima, e la vignetta non ha un prezzo per viaggio', () {
      final francia = conSezioni(60, [
        {'sectionType': 'COUNTRY', 'startPointIndex': 0, 'endPointIndex': 20, 'countryCode': 'ITA'},
        {'sectionType': 'COUNTRY', 'startPointIndex': 20, 'endPointIndex': 60, 'countryCode': 'FRA'},
        {'sectionType': 'TOLL_ROAD', 'startPointIndex': 5, 'endPointIndex': 18},
        {'sectionType': 'TOLL_ROAD', 'startPointIndex': 25, 'endPointIndex': 55},
      ]);
      final c = tariffa.stima(francia);
      expect(c.km, closeTo(13, 0.5));
      expect(c.kmNonStimati, closeTo(30, 0.5));
      expect(c.breve, '~1,00 € + estero');

      final soloFrancia = tariffa.stima(conSezioni(20, [
        {'sectionType': 'COUNTRY', 'startPointIndex': 0, 'endPointIndex': 20, 'countryCode': 'FRA'},
        {'sectionType': 'TOLL_ROAD', 'startPointIndex': 0, 'endPointIndex': 20},
      ]));
      expect(soloFrancia.breve, 'Pedaggio estero');

      final svizzera = tariffa.stima(conSezioni(20, [
        {'sectionType': 'COUNTRY', 'startPointIndex': 0, 'endPointIndex': 20, 'countryCode': 'CHE'},
        {'sectionType': 'TOLL_VIGNETTE', 'startPointIndex': 2, 'endPointIndex': 18},
      ]));
      expect(svizzera.vignetta, isTrue);
      expect(svizzera.conPrezzo, isFalse);
      expect(svizzera.breve, 'Vignetta');
      expect(svizzera.riga, 'Con vignetta');
      expect(svizzera.perStima, 'Con vignetta');
      expect(c.perStima, 'Pedaggio ~1,00 € + estero');
    });

    test('si paga ma non si sa dove: «Pedaggio», senza prezzo', () {
      final p = PercorsoCalcolato(
          punti: const [Punto(45, 7), Punto(45.1, 7)], tratti: const [], manovre: const [], conPedaggi: true);
      final c = tariffa.stima(p);
      expect(c.sconosciuto, isTrue);
      expect(c.breve, 'Pedaggio');
      expect(c.riga, 'Con pedaggio');
    });

    test('il prezzo vero del motore vince sulla stima', () {
      final a4 = torinoMilano().first;
      final p = PercorsoCalcolato(
        punti: a4.punti,
        tratti: a4.tratti,
        manovre: a4.manovre,
        conPedaggi: true,
        pedaggi: a4.pedaggi,
        prezzoPedaggio: 12.4,
      );
      final c = tariffa.stima(p);
      expect(c.stimato, isFalse);
      expect(c.prezzo, '12,40 €');
      expect(c.riga, 'Pedaggio 12,40 €');
      // Usciti dall'autostrada non resta niente.
      expect(tariffa.stima(p, daM: p.pedaggi.single.aM + 1).euro, 0);
    });
  });

  group('le opzioni', () {
    test('classe e tariffa si salvano, e non cambiano la strada', () {
      const o = OpzioniPercorso(classePedaggio: ClassePedaggio.b, euroAlKm: 0.09);
      final letto = OpzioniPercorso.daJson(o.toJson());
      expect(letto.classePedaggio, ClassePedaggio.b);
      expect(letto.euroAlKm, 0.09);
      expect(letto.tariffaPedaggio.euroAlKm, closeTo(0.09 * 1.03, 1e-9));
      expect(o.stessaStrada(const OpzioniPercorso()), isTrue);
      expect(o.stessaStrada(const OpzioniPercorso(evitaPedaggi: true)), isFalse);
      // Le opzioni salvate prima dei pedaggi: classe A, tariffa di partenza.
      final vecchie = OpzioniPercorso.daJson(const {'modo': 'veloce'});
      expect(vecchie.classePedaggio, ClassePedaggio.a);
      expect(vecchie.euroAlKm, TariffaPedaggio.euroAlKmPredefinito);
    });

    test('evitare i pedaggi: TomTom e Valhalla', () {
      const o = OpzioniPercorso(evitaPedaggi: true);
      expect(o.valhalla, {'use_tolls': 0.0});
      expect(o.riassunto, 'Più veloce · senza pedaggi');
    });
  });

  test('gli euro con la virgola', () {
    expect(euroItaliani(12.4), '12,40 €');
    expect(arrotondaPedaggio(8.65), 8.7);
    expect(arrotondaPedaggio(8.64), 8.6);
  });
}
