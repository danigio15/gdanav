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
}
