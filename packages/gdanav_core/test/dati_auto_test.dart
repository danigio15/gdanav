import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// I dati dell'auto che arrivano da GdAAuto (docs/DATI-AUTO.md di GdAAuto)
/// dentro il calcolo: energia, capacità, consumo medio, clima, batteria.
/// Ognuno è facoltativo: senza, il conto è quello di prima.
void main() {
  const p = ProfiloVeicolo.esempio; // 60 kWh, 11 kW in alternata
  final ora = DateTime.utc(2026, 10, 18, 9);
  StatoAuto stato({
    double batteria = 50,
    double? energiaKwh,
    double? capacitaKwh,
    double? consumoMedioKwh100,
    double? potenzaClimaW,
    bool? climaAcceso,
    bool? batteriaInRiscaldamento,
    double? temperaturaEsternaC,
    double? temperaturaBatteriaC,
  }) =>
      StatoAuto(
        sorgente: TipoSorgente.homeAssistant,
        letto: ora,
        batteria: batteria,
        energiaKwh: energiaKwh,
        capacitaKwh: capacitaKwh,
        consumoMedioKwh100: consumoMedioKwh100,
        potenzaClimaW: potenzaClimaW,
        climaAcceso: climaAcceso,
        batteriaInRiscaldamento: batteriaInRiscaldamento,
        temperaturaEsternaC: temperaturaEsternaC,
        temperaturaBatteriaC: temperaturaBatteriaC,
      );

  group('la capacità vera', () {
    test("quella che dice l'auto, o l'energia diviso la percentuale", () {
      expect(stato().capacitaVeraKwh, isNull);
      expect(stato(capacitaKwh: 55.2).capacitaVeraKwh, 55.2);
      expect(stato(batteria: 64, energiaKwh: 41.6).capacitaVeraKwh, closeTo(65, 1e-9));
      // La capacità detta vince sul conto.
      expect(stato(batteria: 64, energiaKwh: 41.6, capacitaKwh: 66).capacitaVeraKwh, 66);
    });

    test('un numero che non è una batteria d\'auto non vale, né sotto il 10%', () {
      expect(stato(capacitaKwh: 5).capacitaVeraKwh, isNull);
      expect(stato(capacitaKwh: 400).capacitaVeraKwh, isNull);
      expect(stato(capacitaKwh: 400, batteria: 50, energiaKwh: 30).capacitaVeraKwh, closeTo(60, 1e-9));
      expect(stato(batteria: 8, energiaKwh: 5).capacitaVeraKwh, isNull);
      expect(stato(batteria: 50, energiaKwh: 300).capacitaVeraKwh, isNull);
    });

    test('il profilo la prende, e senza resta quello del catalogo', () {
      expect(p.conCapacitaDi(null), same(p));
      expect(p.conCapacitaDi(stato()), same(p));
      final vero = p.conCapacitaDi(stato(capacitaKwh: 52));
      expect(vero.capacitaUtileKwh, 52);
      expect((vero.id, vero.massaKg, vero.cdA, vero.potenzaAcKw), (p.id, p.massaKg, p.cdA, p.potenzaAcKw));
      expect(vero.curvaRicarica, same(p.curvaRicarica));
    });

    test('il piano conta i punti con lei', () {
      final strada = List.generate(100, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 110));
      final catalogo = PianificatoreSoste(profilo: p).pianifica(percorso: strada, batteriaPartenza: 90, colonnine: [])!;
      final vero = PianificatoreSoste(profilo: p.conCapacitaDi(stato(capacitaKwh: 50)))
          .pianifica(percorso: strada, batteriaPartenza: 90, colonnine: [])!;
      expect(vero.energiaKwh, closeTo(catalogo.energiaKwh, 1e-9));
      expect(90 - vero.batteriaArrivo, closeTo(catalogo.energiaKwh / 50 * 100, 1e-6));
      expect(90 - catalogo.batteriaArrivo, closeTo(catalogo.energiaKwh / 60 * 100, 1e-6));
    });
  });

  group('la misura in kWh', () {
    final percorso = PercorsoCalcolato(
      punti: [for (var i = 0; i <= 20; i++) Punto(45 + i * 0.009, 9)],
      tratti: [for (var i = 0; i < 20; i++) const Tratto(lunghezzaM: 1000, velocitaKmh: 90)],
      manovre: const [],
    );
    MisuratoreConsumo misuratore() =>
        MisuratoreConsumo(percorso: percorso, capacitaKwh: 60, profilo: (t) => energiaTrattoWh(t, p));

    test("con l'energia dell'auto basta mezzo kWh, e la capacità non conta", () {
      final m = misuratore();
      // La batteria resta al 50%: a punti non si misurerebbe niente.
      expect(m.registra(batteria: 50, energiaKwh: 30.0, metri: 0), isNull);
      expect(m.registra(batteria: 50, energiaKwh: 29.9, metri: 600), isNull); // si parte dal primo cambio
      expect(m.registra(batteria: 50, energiaKwh: 29.6, metri: 2000), isNull); // tre decimi soli
      final misura = m.registra(batteria: 50, energiaKwh: 29.35, metri: 4600)!;
      expect(misura.realeWh, closeTo(550, 1e-6));
      expect(misura.km, closeTo(4, 1e-9));
      expect(misura.previstoWh, closeTo(m.previstaFinoA(4600) - m.previstaFinoA(600), 1e-6));
    });

    test("se l'auto smette di dire l'energia si riparte a punti", () {
      final m = misuratore();
      m.registra(batteria: 50, energiaKwh: 30, metri: 0);
      m.registra(batteria: 50, energiaKwh: 29.9, metri: 500);
      // Niente energia: non si confronta un kWh con un punto.
      expect(m.registra(batteria: 49, metri: 3000), isNull);
      expect(m.registra(batteria: 48, metri: 4000), isNull);
      final misura = m.registra(batteria: 46, metri: 9000)!;
      expect(misura.realeWh, closeTo(0.02 * 60 * 1000, 1e-6));
    });
  });

  group('il consumo medio dell\'auto', () {
    const misto = [
      Tratto(lunghezzaM: 10000, velocitaKmh: 40),
      Tratto(lunghezzaM: 10000, velocitaKmh: 80),
      Tratto(lunghezzaM: 10000, velocitaKmh: 120),
    ];
    final modello = consumoMedioWhKm(misto, p) / 10;

    test('è un rapporto col modello in guida mista, tenuto fra 0,6 e 1,8', () {
      expect(fattoreDaConsumoMedio(kwh100: modello, profilo: p), closeTo(1, 1e-9));
      expect(fattoreDaConsumoMedio(kwh100: modello * 1.2, profilo: p), closeTo(1.2, 1e-9));
      expect(fattoreDaConsumoMedio(kwh100: modello * 5, profilo: p), 1.8);
      expect(fattoreDaConsumoMedio(kwh100: 0, profilo: p), 1);
      // Col freddo il modello conta già il riscaldamento: lo stesso consumo
      // vuol dire un'auto meno sprecona.
      expect(
        fattoreDaConsumoMedio(kwh100: modello * 1.2, profilo: p, condizioni: Condizioni.daMeteo(temperaturaC: 0)),
        lessThan(1.2),
      );
    });

    test('tira il correttivo a metà strada prima di misurare, e poco dopo', () {
      expect(const ConsumoImparato().fattoreCon(null), 1);
      expect(const ConsumoImparato().fattoreCon(1.2), closeTo(1.1, 1e-9));
      expect(const ConsumoImparato(fattore: 1.1, kmOsservati: 50).fattoreCon(1.3), closeTo(1.15, 1e-9));
      final tanti = const ConsumoImparato(fattore: 1.1, kmOsservati: 5000).fattoreCon(1.3);
      expect(tanti, closeTo(1.1 + 0.2 * 0.5 * 50 / 350, 1e-9));
      expect(const ConsumoImparato(fattore: 1.7).fattoreCon(3), lessThanOrEqualTo(1.8));
    });

    test('nelle condizioni del piano, solo se si sa il modello dell\'auto', () {
      const imparato = ConsumoImparato(fattore: 1.05, kmOsservati: 20);
      final s = stato(consumoMedioKwh100: modello * 1.3);
      expect(imparato.condizioni(s).fattoreConsumo, 1.05);
      final c = imparato.condizioni(s, profilo: p).fattoreConsumo;
      expect(c, closeTo(imparato.fattoreCon(1.3), 1e-9));
      expect(c, greaterThan(1.05));
      expect(imparato.condizioni(s, profilo: p, conFattore: false).fattoreConsumo, 1);
    });

    test('il correttivo imparato sul modello di prima non vale più', () {
      expect(ConsumoImparato.modelloAttuale, 3);
      expect(ConsumoImparato.daJson(const {'modello': 2, 'fattore': 1.3, 'km': 400}).fattore, 1);
    });
  });

  group('il clima e la batteria', () {
    test('senza dati le condizioni restano quelle', () {
      const c = Condizioni(temperaturaC: 5, climaW: 1950, ventoControMs: 2, fattoreConsumo: 1.1);
      expect(c.conAuto(null), same(c));
      final uguale = c.conAuto(stato());
      expect((uguale.temperaturaC, uguale.climaW, uguale.ventoControMs, uguale.fattoreConsumo), (5, 1950, 2, 1.1));
      expect(uguale.riscaldamentoBatteriaKwh, 0);
      expect(uguale.temperaturaBatteriaC, isNull);
    });

    test("la temperatura dell'auto vale più di quella del meteo", () {
      final c = Condizioni.daMeteo(temperaturaC: 12, ventoControMs: 3).conAuto(stato(temperaturaEsternaC: 2));
      expect(c.temperaturaC, 2);
      expect(c.climaW, Condizioni.daMeteo(temperaturaC: 2).climaW);
      expect(c.ventoControMs, 3);
    });

    test('col clima acceso, metà la potenza misurata e metà la stima', () {
      final c = const Condizioni().conAuto(stato(temperaturaEsternaC: 0, climaAcceso: true, potenzaClimaW: 1500));
      expect(c.climaW, closeTo((2700 + 1500) / 2, 1e-9));
      // Il riscaldatore a zero non dice niente: resta la stima.
      final zero = const Condizioni().conAuto(stato(temperaturaEsternaC: 0, climaAcceso: true, potenzaClimaW: 0));
      expect(zero.climaW, 2700);
      // Spento adesso non vuol dire spento in viaggio.
      final spento = const Condizioni().conAuto(stato(temperaturaEsternaC: 0, climaAcceso: false, potenzaClimaW: 900));
      expect(spento.climaW, 2700);
    });

    test('la batteria che si scalda costa una volta, alla partenza', () {
      final tipica = const Condizioni().conAuto(stato(batteriaInRiscaldamento: true));
      expect(tipica.riscaldamentoBatteriaKwh, closeTo(1, 1e-9)); // 3 kW per 20 minuti
      final misurata = const Condizioni().conAuto(
          stato(temperaturaEsternaC: -5, batteriaInRiscaldamento: true, climaAcceso: true, potenzaClimaW: 6000));
      expect(misurata.riscaldamentoBatteriaKwh, closeTo(2, 1e-9));
      // Il riscaldatore scalda la batteria: l'abitacolo resta alla stima.
      expect(misurata.climaW, Condizioni.daMeteo(temperaturaC: -5).climaW);
      expect(misurata.senzaCorrettivo.riscaldamentoBatteriaKwh, misurata.riscaldamentoBatteriaKwh);

      final strada = List.generate(50, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 90));
      final senza = PianificatoreSoste(profilo: p).pianifica(percorso: strada, batteriaPartenza: 80, colonnine: [])!;
      final con = PianificatoreSoste(profilo: p, condizioni: const Condizioni(riscaldamentoBatteriaKwh: 1.2))
          .pianifica(percorso: strada, batteriaPartenza: 80, colonnine: [])!;
      expect(con.energiaKwh - senza.energiaKwh, closeTo(1.2, 1e-9));
      expect(senza.batteriaArrivo - con.batteriaArrivo, closeTo(2, 1e-6)); // 1,2 kWh su 60
    });
  });

  group('i tempi di ricarica', () {
    final strada = List.generate(60, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 90));
    Sosta sosta(ColonninaSulPercorso c, [Condizioni condizioni = const Condizioni()]) =>
        PianificatoreSoste(profilo: p, condizioni: condizioni)
            .pianifica(percorso: strada, batteriaPartenza: 60, colonnine: [c])!
            .soste
            .single;
    double secondiPerPunto(Sosta s) => s.ricarica.inSeconds / (s.batteriaPartenza - s.batteriaArrivo);

    test("in alternata si carica con il caricatore dell'auto, non con la colonnina", () {
      const tipo2 = ColonninaSulPercorso(
          id: 'a', nome: 'Tipo 2', distanzaM: 30000, potenzaKw: 22, obbligata: true, alternata: true);
      // 0,6 kWh per punto a 11 kW, non a 22.
      expect(secondiPerPunto(sosta(tipo2)), closeTo(0.6 / 11 * 3600, 1));
      const rapida = ColonninaSulPercorso(id: 'r', nome: 'CCS', distanzaM: 30000, potenzaKw: 22, obbligata: true);
      expect(secondiPerPunto(sosta(rapida)), closeTo(0.6 / 22 * 3600, 1));
    });

    test('la batteria fredda carica piano in continua', () {
      expect(PianificatoreSoste.riduzioneAFreddo(null), 1);
      expect(PianificatoreSoste.riduzioneAFreddo(20), 1);
      expect(PianificatoreSoste.riduzioneAFreddo(15), 1);
      expect(PianificatoreSoste.riduzioneAFreddo(5), closeTo(0.7, 1e-9));
      expect(PianificatoreSoste.riduzioneAFreddo(-20), 0.4);
      const rapida = ColonninaSulPercorso(id: 'r', nome: 'CCS', distanzaM: 30000, potenzaKw: 150, obbligata: true);
      final calda = sosta(rapida);
      final fredda = sosta(rapida, const Condizioni(temperaturaBatteriaC: 5));
      expect((fredda.batteriaArrivo, fredda.batteriaPartenza), (calda.batteriaArrivo, calda.batteriaPartenza));
      expect(fredda.ricarica.inSeconds / calda.ricarica.inSeconds,
          closeTo(1 / 0.7, 0.03)); // la sosta si dice a secondi interi
      // In alternata comanda il caricatore di bordo, non la batteria.
      const tipo2 = ColonninaSulPercorso(
          id: 'a', nome: 'Tipo 2', distanzaM: 30000, potenzaKw: 22, obbligata: true, alternata: true);
      expect(sosta(tipo2, const Condizioni(temperaturaBatteriaC: -10)).ricarica, sosta(tipo2).ricarica);
    });

    test("la temperatura della batteria arriva dall'auto", () {
      expect(const Condizioni().conAuto(stato(temperaturaBatteriaC: 3)).temperaturaBatteriaC, 3);
    });

    test('lungo il percorso, una colonnina con le sole Tipo 2 è in alternata', () {
      const soloTipo2 = Colonnina(
        id: 'a',
        nome: 'Parcheggio',
        posizione: Punto(45, 9),
        connettori: [Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22)],
      );
      const mista = Colonnina(
        id: 'm',
        nome: 'Area di servizio',
        posizione: Punto(45, 9.001),
        connettori: [
          Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 43),
          Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 50),
        ],
      );
      final sul = colonnineSulPercorso(
        Linea(const [Punto(45, 8.99), Punto(45, 9.02)]),
        [soloTipo2, mista],
        compatibili: const {TipoConnettore.ccs2, TipoConnettore.tipo2},
        potenzaMinimaKw: 22,
      );
      expect(sul.firstWhere((c) => c.id == 'a').alternata, isTrue);
      expect(sul.firstWhere((c) => c.id == 'm').alternata, isFalse);
    });
  });
}
