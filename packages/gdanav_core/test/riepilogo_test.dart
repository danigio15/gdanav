import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  test('all\'arrivo con l\'elettrica: durata, distanza, energia e costo', () {
    const r = RiepilogoViaggio(
      destinazione: 'Napoli',
      durata: Duration(hours: 2, minutes: 41),
      metri: 263400,
      elettrica: true,
      kwh: 38.1,
      consumoStimato: false,
      euroAlKwh: 0.30,
    );
    expect(r.durataTesto, '2 h 41 min');
    expect(r.distanzaTesto, '263 km');
    expect(r.consumoTesto, '38,1 kWh · 14,5 kWh/100 km');
    expect(r.costoTesto, '~11,43 € energia');
    expect(r.perAuto, 'Sei arrivato a Napoli · 2 h 41 min · 263 km · 38,1 kWh · ~11,43 €');
    expect([for (final (n, _) in r.righe) n], ['Durata', 'Distanza', 'Energia', 'Costo']);
  });

  test('con la termica e il pedaggio: il costo è la somma', () {
    final r = RiepilogoViaggio(
      destinazione: 'Roma',
      durata: const Duration(minutes: 24),
      metri: 12400,
      elettrica: false,
      litri: 0.9,
      euroAlLitro: 1.80,
      pedaggio: const CostoPedaggio(euro: 2.4, km: 30, classe: ClassePedaggio.a, stimato: true),
    );
    expect(r.durataTesto, '24 min');
    expect(r.distanzaTesto, '12,4 km');
    expect(r.consumoTesto, '~0,9 l · 7,3 l/100 km');
    expect(r.costoTesto, '~1,62 € carburante + ~2,40 € pedaggio = ~4,02 €');
    expect(r.righe.last, ('di cui', '~1,62 € carburante · ~2,40 € pedaggio'));
    expect(r.righe[r.righe.length - 2], ('Costo', '~4,02 €'));
  });

  test('senza consumo né prezzi: solo durata e distanza', () {
    const r = RiepilogoViaggio(destinazione: 'Casa', durata: Duration(minutes: 7), metri: 850, elettrica: true);
    expect(r.consumoTesto, isNull);
    expect(r.costoTesto, isNull);
    expect(r.distanzaTesto, '850 m');
    expect(r.perAuto, 'Sei arrivato a Casa · 7 min · 850 m');
  });

  test('i prezzi stanno nelle opzioni, e si ricordano', () {
    const o = OpzioniPercorso();
    expect(o.euroAlKwh, OpzioniPercorso.euroAlKwhPredefinito);
    final c = OpzioniPercorso.daJson(o.copia(euroAlKwh: 0.25, euroAlLitro: 1.9).toJson());
    expect(c.euroAlKwh, 0.25);
    expect(c.euroAlLitro, 1.9);
    // Il prezzo non cambia la strada.
    expect(o.stessaStrada(c), isTrue);
  });

  test('sull\'auto il riepilogo sta in righe, e il costo c\'è sempre', () {
    final r = RiepilogoViaggio(
      destinazione: 'Roma',
      durata: const Duration(minutes: 24),
      metri: 12400,
      elettrica: false,
      litri: 0.9,
      euroAlLitro: 1.80,
      pedaggio: const CostoPedaggio(euro: 2.4, km: 30, classe: ClassePedaggio.a, stimato: true),
    );
    expect(r.righeAuto, [
      ('Durata e distanza', '24 min · 12,4 km'),
      ('Carburante', '~0,9 l · 7,3 l/100 km'),
      ('Costo ~4,02 €', '~1,62 € carburante · ~2,40 € pedaggio'),
    ]);
    // Senza prezzi, il costo dice dove metterli.
    const senza = RiepilogoViaggio(destinazione: 'Napoli', durata: Duration(minutes: 9), metri: 800, elettrica: true);
    expect(senza.righeAuto.last.$1, 'Costo');
    expect(senza.righeAuto.length, lessThanOrEqualTo(4));
  });

  // Dal campo: «Costo ~2,10 €: ~1,05 € energia · ~1,05 € pedaggio. Verifica i
  // costi perché non mi trovo: 1 € di energia per 3,5 kWh».
  group('il riepilogo che non tornava', () {
    RiepilogoViaggio arrivo({CostoDellEnergia? energia, SenzaPrezzoVero? manca, double kwh = 3.5, double? largo}) =>
        RiepilogoViaggio(
          destinazione: 'Via dei Limoni',
          durata: const Duration(minutes: 47),
          metri: 13600,
          elettrica: true,
          kwh: kwh,
          consumoStimato: false,
          kwhPiuOMeno: largo,
          euroAlKwh: 0.30,
          // La Tangenziale: un prezzo di listino, non una stima.
          pedaggio: const CostoPedaggio(euro: 1.05, stimato: false),
          energia: energia,
          senzaPrezzoVero: manca,
        );

    test('col prezzo delle opzioni non dice «Casa»: è una stima, quanto vale, e cosa manca', () {
      final r = arrivo(
        energia: costoDellEnergia(consumatiKwh: 3.5, partenzaKwh: 57, euroAlKwhDiRiserva: 0.30),
        manca: SenzaPrezzoVero.senzaTariffa,
      );
      expect(r.righe, contains(('Batteria', '3,5 kWh · ~1,05 € · stima a 0,30 €/kWh')));
      expect(r.righe.map((x) => x.$1), isNot(contains('Da casa')));
      expect(r.righeAuto[2], (
        'Ricarica',
        'Batteria 3,5 kWh · ~1,05 € · stima a 0,30 €/kWh · in GdAHome manca il prezzo dell\'energia',
      ));
      // Il pedaggio di listino non ha la tilde: non è lo stesso numero dell'energia.
      expect(r.righeAuto.last, ('Costo ~2,10 €', '~1,05 € energia · 1,05 € pedaggio'));
      expect(r.note.single, startsWith('Il costo dell\'energia è una stima (0,30 €/kWh)'));
      expect(r.note.single, contains('opzioni del percorso'));
      expect(r.note.single, contains('plancia, sezione Energia'));
    });

    test('in GdANav da sola la stima si dice, senza parlare di una casa che non c\'è', () {
      final r = arrivo(energia: costoDellEnergia(consumatiKwh: 3.5, euroAlKwhDiRiserva: 0.30));
      expect(
        r.note,
        ['Il costo dell\'energia è una stima (0,30 €/kWh): il prezzo si cambia nelle opzioni del percorso.'],
      );
      expect(r.righeAuto[2], ('Ricarica', 'Batteria 3,5 kWh · ~1,05 € · stima a 0,30 €/kWh'));
    });

    test('con la tariffa di casa dice «prezzo di casa», e che il sole non lo sa', () {
      final r = arrivo(
        energia: costoDellEnergia(consumatiKwh: 3.5, euroAlKwhDiCasa: 0.22, euroAlKwhDiRiserva: 0.30),
        manca: SenzaPrezzoVero.ricaricaNonVale,
      );
      expect(r.righe, contains(('Da casa', '3,5 kWh · ~0,77 € · prezzo di casa 0,22 €/kWh')));
      expect(r.righeAuto[2], ('Ricarica', 'Casa 3,5 kWh · ~0,77 € · prezzo di casa 0,22 €/kWh'));
      expect(
          r.note.single, startsWith('Energia al prezzo della rete di casa (0,22 €/kWh): la parte dal sole non si sa'));
      expect(r.note.single, contains('è di più di due settimane fa'));
    });

    test('con la ricarica di casa: il suo prezzo e la quota dal sole, e niente da spiegare', () {
      final casa =
          RicaricaDiCasa(finitaIl: DateTime(2026, 11, 14, 15), kwh: 20, socA: 100, kwhSole: 13, euroRete: 1.75);
      expect(casa.valePer(partenza: DateTime(2026, 11, 16, 8, 13), batteriaPartenza: 82), isTrue);
      final r =
          arrivo(energia: costoDellEnergia(consumatiKwh: 3.5, partenzaKwh: 57, casa: casa, euroAlKwhDiRiserva: 0.3));
      expect(r.righe, contains(('Da casa', '3,5 kWh · ~0,31 € · 65% dal sole')));
      expect(r.note, isEmpty);
    });

    test('quattro punti di batteria su 13 km sono una misura larga: «circa», e quanto', () {
      // Dall'82% al 78% di una batteria da 70 kWh: 2,8 kWh, più o meno 0,7.
      final r = arrivo(kwh: 2.8, largo: 0.7);
      expect(r.consumoCirca, isTrue);
      expect(r.consumoTesto, 'circa 2,8 kWh · circa 21 kWh/100 km');
      expect(r.note, contains(startsWith('Energia misurata dai punti della batteria (±0,7 kWh)')));
      expect(r.perAuto, contains('circa 2,8 kWh'));
      // Su un viaggio lungo lo stesso punto non pesa.
      const lungo = RiepilogoViaggio(
        destinazione: 'Poggio Sereno',
        durata: Duration(hours: 2),
        metri: 180000,
        elettrica: true,
        kwh: 31.5,
        consumoStimato: false,
        kwhPiuOMeno: 0.7,
      );
      expect(lungo.consumoCirca, isFalse);
      expect(lungo.consumoTesto, '31,5 kWh · 17,5 kWh/100 km');
    });
  });
}
