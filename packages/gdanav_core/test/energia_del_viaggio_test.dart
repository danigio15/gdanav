import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  // Una 77 kWh: partita al 100% dalla ricarica di casa (60 kWh, 24 col sole,
  // 7,20 € di rete), una sosta in autostrada da 30 kWh pagata 18 €.
  final casa = RicaricaDiCasa(
    finitaIl: DateTime(2026, 10, 19, 23),
    kwh: 60,
    socA: 100,
    kwhSole: 24,
    euroRete: 7.20,
  );

  test('il kWh di casa costa quanto la sua ricarica: il sole niente, la rete il suo prezzo', () {
    expect(casa.euroAlKwh, closeTo(0.12, 1e-9));
    expect(casa.quotaSole, closeTo(0.4, 1e-9));
    expect(casa.valePer(partenza: DateTime(2026, 10, 20, 8), batteriaPartenza: 99), isTrue);
    // Ricaricata una settimana fa, o con la batteria molto più giù: non vale.
    expect(casa.valePer(partenza: DateTime(2026, 10, 27, 8), batteriaPartenza: 99), isFalse);
    expect(casa.valePer(partenza: DateTime(2026, 10, 20, 8), batteriaPartenza: 60), isFalse);
  });

  test('prima la batteria di casa, poi le soste; quello che resta non è del viaggio', () {
    final e = costoDellEnergia(
      consumatiKwh: 90,
      partenzaKwh: 77,
      casa: casa,
      soste: const [RicaricaInViaggio(dove: 'Ionity', kwh: 30, euroPagati: 18)],
    )!;
    expect(e.kwhDaCasa, 77);
    expect(e.euroCasa, closeTo(77 * 0.12, 1e-9));
    expect(e.kwhDalleSoste, closeTo(13, 1e-9));
    // 0,60 €/kWh alla colonnina, per i 13 kWh usati.
    expect(e.euroSoste, closeTo(7.8, 1e-9));
    expect(e.totale, closeTo(9.24 + 7.8, 1e-9));
    expect(e.prezzoCasaVero, isTrue);
    expect(e.sosteStimate, isFalse);
  });

  test('senza la ricarica di casa: il prezzo delle opzioni, e lo si dice', () {
    final e = costoDellEnergia(consumatiKwh: 20, partenzaKwh: 50, euroAlKwhDiRiserva: 0.3)!;
    expect(e.euroCasa, closeTo(6, 1e-9));
    expect(e.prezzoCasaVero, isFalse);
  });

  test('nel riepilogo: da casa, la sosta, e il totale', () {
    final e = costoDellEnergia(
      consumatiKwh: 90,
      partenzaKwh: 77,
      casa: casa,
      soste: const [RicaricaInViaggio(dove: 'Ionity Arezzo', kwh: 30, euroStimati: 16.2)],
    )!;
    final r = RiepilogoViaggio(
      destinazione: 'Napoli',
      durata: const Duration(hours: 4),
      metri: 520000,
      elettrica: true,
      kwh: 90,
      consumoStimato: false,
      energia: e,
      soste: const [RicaricaInViaggio(dove: 'Ionity Arezzo', kwh: 30, euroStimati: 16.2)],
    );
    expect(r.righe, contains(('Da casa', '77,0 kWh · ~9,24 € · 40% dal sole')));
    expect(r.righe, contains(('Ricarica', 'Ionity Arezzo: 30,0 kWh · ~16,20 € (stima)')));
    expect(r.euroEnergia, closeTo(9.24 + 13 * 0.54, 1e-9));
  });
}
