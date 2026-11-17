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
  });

  test('la ricarica di casa vale anche dopo altri viaggi: una batteria più giù è la stessa energia', () {
    // «Per portarla al 100% ho ricaricato a casa», e si parte all'82% dopo
    // altri viaggi: 18 punti sotto la si scartava, e il conto andava al
    // prezzo delle opzioni.
    expect(casa.valePer(partenza: DateTime(2026, 10, 20, 8, 13), batteriaPartenza: 82), isTrue);
    expect(casa.valePer(partenza: DateTime(2026, 10, 20, 8), batteriaPartenza: 60), isTrue);
    // Una settimana dopo, se la casa non ha visto altre ricariche, è ancora lei.
    expect(casa.valePer(partenza: DateTime(2026, 10, 27, 8), batteriaPartenza: 35), isTrue);
    // Dopo più di due settimane no.
    expect(casa.valePer(partenza: DateTime(2026, 11, 5, 8), batteriaPartenza: 35), isFalse);
    // Senza sapere la batteria ci si fida tre giorni.
    expect(casa.valePer(partenza: DateTime(2026, 10, 22, 8)), isTrue);
    expect(casa.valePer(partenza: DateTime(2026, 10, 27, 8)), isFalse);
    // Più carica di come la ricarica l'aveva lasciata: si è caricato altrove.
    final finoA60 = RicaricaDiCasa(finitaIl: DateTime(2026, 10, 19, 23), kwh: 20, socA: 60, euroRete: 4);
    expect(finoA60.valePer(partenza: DateTime(2026, 10, 20, 8), batteriaPartenza: 95), isFalse);
    expect(finoA60.valePer(partenza: DateTime(2026, 10, 20, 8), batteriaPartenza: 64), isTrue);
    // Una ricarica «finita» dopo la partenza non è di questo viaggio; dieci
    // minuti di orologi diversi sì.
    expect(casa.valePer(partenza: DateTime(2026, 10, 19, 22), batteriaPartenza: 80), isFalse);
    expect(casa.valePer(partenza: DateTime(2026, 10, 19, 22, 55), batteriaPartenza: 100), isTrue);
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
    expect(e.origine, PrezzoDiPartenza.opzioni);
    expect(e.euroAlKwhCasa, 0.3);
  });

  test('senza una ricarica che vale ma con la tariffa di casa: il prezzo di casa, non quello delle opzioni', () {
    final e = costoDellEnergia(consumatiKwh: 2.8, partenzaKwh: 57, euroAlKwhDiCasa: 0.22, euroAlKwhDiRiserva: 0.3)!;
    expect(e.origine, PrezzoDiPartenza.tariffa);
    expect(e.euroCasa, closeTo(2.8 * 0.22, 1e-9));
    expect(e.euroAlKwhCasa, 0.22);
    expect(e.quotaSole, isNull);
    // Una tariffa a zero non è una tariffa.
    expect(
      costoDellEnergia(consumatiKwh: 2.8, euroAlKwhDiCasa: 0, euroAlKwhDiRiserva: 0.3)!.origine,
      PrezzoDiPartenza.opzioni,
    );
  });

  test('la ricarica col suo prezzo vince sulla tariffa; senza il suo prezzo, la tariffa per la parte di rete', () {
    final vera = costoDellEnergia(consumatiKwh: 10, partenzaKwh: 77, casa: casa, euroAlKwhDiCasa: 0.25)!;
    expect(vera.origine, PrezzoDiPartenza.ricarica);
    expect(vera.euroCasa, closeTo(1.2, 1e-9));
    expect(vera.euroAlKwhCasa, isNull);
    // La casa non aveva il prezzo quando ha visto la ricarica, ma sa che il
    // 40% era del sole: quello non si paga.
    final senzaEuro = RicaricaDiCasa(finitaIl: DateTime(2026, 10, 19, 23), kwh: 60, socA: 100, kwhSole: 24);
    final e = costoDellEnergia(consumatiKwh: 10, partenzaKwh: 77, casa: senzaEuro, euroAlKwhDiCasa: 0.25)!;
    expect(e.origine, PrezzoDiPartenza.tariffa);
    expect(e.euroCasa, closeTo(10 * 0.25 * 0.6, 1e-9));
    expect(e.quotaSole, closeTo(0.4, 1e-9));
  });

  test('la risposta della casa: la ricarica dell\'auto in uso, la tariffa, e se l\'auto è seguita', () {
    final e = EnergiaDiCasa.daRisposta(
      {
        'ricariche': [
          {'nome': 'La Furia', 'finitaIl': '2026-10-19T23:00:00.000Z', 'socA': 80, 'kwh': 12, 'euroRete': 3},
          {'nome': 'La Tartaruga', 'finitaIl': '2026-10-18T23:00:00.000Z', 'socA': 100, 'kwh': 30, 'euroRete': 2.4},
        ],
        'prezzo': {'euroAlKwh': 0.24},
        'auto': ['La Furia', 'La Tartaruga'],
      },
      nomi: ['La Tartaruga', null],
    );
    expect(e.ricarica?.kwh, 30);
    expect(e.euroAlKwh, 0.24);
    expect(e.conTariffa, isTrue);
    expect(e.autoSeguita, isTrue);
    // La casa ha risposto, ma il prezzo dell'energia non ce l'ha e l'auto
    // non la segue.
    final vuota = EnergiaDiCasa.daRisposta({'ricariche': [], 'prezzo': null, 'auto': []}, nomi: ['La Tartaruga']);
    expect(vuota.ricarica, isNull);
    expect(vuota.conTariffa, isFalse);
    expect(vuota.autoSeguita, isFalse);
    // Una casa di prima manda solo le ricariche: il resto non lo dice.
    final diPrima = EnergiaDiCasa.daRisposta({
      'ricariche': [
        {'nome': 'Auto', 'finitaIl': '2026-10-19T23:00:00.000Z', 'kwh': 9},
      ],
    });
    expect(diPrima.ricarica?.kwh, 9);
    expect(diPrima.conTariffa, isNull);
    expect(diPrima.autoSeguita, isNull);
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
