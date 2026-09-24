import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  final auto = catalogoVeicoli.firstWhere((v) => v.id == 'volkswagen-id3-58');

  // 40 km di strada extraurbana a 90 km/h, in piano.
  final percorso = PercorsoCalcolato(
    punti: [for (var i = 0; i <= 40; i++) Punto(45 + i * 0.009, 9)],
    tratti: [for (var i = 0; i < 40; i++) const Tratto(lunghezzaM: 1000, velocitaKmh: 90)],
    manovre: const [],
  );
  double whKm() => energiaTrattoWh(const Tratto(lunghezzaM: 1000, velocitaKmh: 90), auto);

  test('il correttivo si applica a quello che si spende, non al recupero', () {
    const salita = Tratto(lunghezzaM: 1000, velocitaKmh: 90, dislivelloM: 30);
    const discesa = Tratto(lunghezzaM: 1000, velocitaKmh: 50, dislivelloM: -80);
    const piu = Condizioni(fattoreConsumo: 1.2);
    expect(energiaTrattoWh(salita, auto, piu), closeTo(energiaTrattoWh(salita, auto) * 1.2, 1e-6));
    expect(energiaTrattoWh(discesa, auto), lessThan(0));
    expect(energiaTrattoWh(discesa, auto, piu), energiaTrattoWh(discesa, auto));
  });

  test('guidando si misura il consumo vero, un tratto ogni due punti di batteria', () {
    final m = MisuratoreConsumo(
      percorso: percorso,
      capacitaKwh: auto.capacitaUtileKwh,
      profilo: (t) => energiaTrattoWh(t, auto),
    );
    expect(m.previstaFinoA(10000), closeTo(whKm() * 10, 1e-6));
    expect(m.registra(batteria: 80, metri: 0), isNull);
    expect(m.registra(batteria: 79, metri: 5000), isNull); // un punto solo
    final misura = m.registra(batteria: 78, metri: 7000)!;
    expect(misura.km, closeTo(7, 1e-9));
    expect(misura.realeWh, closeTo(0.02 * auto.capacitaUtileKwh * 1000, 1e-6));
    expect(misura.previstoWh, closeTo(whKm() * 7, 1e-6));
    // Si riparte da lì.
    expect(m.registra(batteria: 77, metri: 9000), isNull);
    // Una ricarica azzera il riferimento.
    expect(m.registra(batteria: 90, metri: 20000, inCarica: true), isNull);
    expect(m.registra(batteria: 88, metri: 21000), isNotNull);
  });

  test("il fattore impara dai chilometri e non esagera", () {
    var c = const ConsumoImparato();
    // L'auto consuma il 20% in più del modello, per 100 km.
    for (var i = 0; i < 10; i++) {
      c = c.con(previstoWh: 1500, realeWh: 1800, km: 10);
    }
    expect(c.fattore, closeTo(1.2, 0.001));
    expect(c.scartoPercento, 20);
    expect(c.kmOsservati, 100);
    // Un tratto strano pesa poco, e comunque c'è un tetto.
    final strano = c.con(previstoWh: 1000, realeWh: 5000, km: 2);
    expect(strano.fattore, lessThan(1.25));
    expect(ConsumoImparato.daJson(c.toJson()).fattore, closeTo(c.fattore, 1e-12));
    expect(c.con(previstoWh: 0, realeWh: 10, km: 1), same(c));
  });

  test('Home Assistant può dare temperatura esterna, velocità, potenza e contachilometri', () {
    final s = SorgenteHomeAssistant.statoDaMessaggio(
      Messaggio(
        tipo: 'stato_auto',
        ts: DateTime(2026),
        dati: const {
          'batteria': 64,
          'temperatura_esterna_c': 7.5,
          'velocita_kmh': 88,
          'potenza_kw': 17.2,
          'odometro_km': 23456.7,
        },
      ),
    )!;
    expect(s.temperaturaEsternaC, 7.5);
    expect(s.velocitaKmh, 88);
    expect(s.potenzaKw, 17.2);
    expect(s.odometroKm, 23456.7);
  });

  test('le strade dalla velocità: urbane, extraurbane, autostrade', () {
    expect(TipoStrada.daVelocita(45), TipoStrada.urbana);
    expect(TipoStrada.daVelocita(60), TipoStrada.extraurbana);
    expect(TipoStrada.daVelocita(100), TipoStrada.extraurbana);
    expect(TipoStrada.daVelocita(125), TipoStrada.autostrada);
  });

  test('per tipo di strada: km, consumo previsto e vero, precisione, correttivo suo', () {
    var c = const ConsumoImparato();
    // In autostrada la macchina consuma il 20% più del modello; in città come dice.
    for (var i = 0; i < 6; i++) {
      c = c.con(previstoWh: 2000, realeWh: 2400, km: 10, tipo: TipoStrada.autostrada);
      c = c.con(previstoWh: 1200, realeWh: 1200, km: 10, tipo: TipoStrada.urbana);
    }
    final a = c.strade[TipoStrada.autostrada]!;
    expect(a.km, 60);
    expect(a.affidabile, isTrue);
    expect(a.fattore, closeTo(1.2, 0.03));
    expect(a.realeKwh100, closeTo(24, 0.01));
    // All'inizio il calcolo sbagliava, poi ha imparato: la precisione cresce.
    expect(a.precisionePercento, greaterThan(85));
    expect(a.precisionePercento, lessThan(100));
    final u = c.strade[TipoStrada.urbana]!;
    expect(u.fattore, lessThan(1.1));
    expect(c.fattorePer(TipoStrada.autostrada), closeTo(1.2, 0.03));
    expect(c.fattorePer(TipoStrada.urbana), lessThan(1.1));
    // Mai misurate: il correttivo generale.
    expect(c.fattorePer(TipoStrada.extraurbana), c.fattore);
    // Va e torna.
    final letto = ConsumoImparato.daJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
    expect(letto.strade[TipoStrada.autostrada]!.km, 60);
    expect(letto.fattorePer(TipoStrada.autostrada), c.fattorePer(TipoStrada.autostrada));
  });

  test('il correttivo per strada si applica solo a quelle strade', () {
    const auto = Tratto(lunghezzaM: 1000, velocitaKmh: 120);
    const citta = Tratto(lunghezzaM: 1000, velocitaKmh: 40);
    final p = ProfiloVeicolo.esempio;
    const c = Condizioni(fattoriStrada: {TipoStrada.autostrada: 1.2});
    expect(energiaTrattoWh(auto, p, c), closeTo(energiaTrattoWh(auto, p) * 1.2, 0.001));
    expect(energiaTrattoWh(citta, p, c), closeTo(energiaTrattoWh(citta, p), 0.001));
  });

  test('ogni misura sa su che strade è stata presa', () {
    final punti = [for (var i = 0; i <= 20; i++) Punto(45 + i * 0.009, 9)];
    final linea = Linea(punti);
    final percorso = PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: i <= 10 ? 50 : 130),
      ],
      manovre: const [],
    );
    final m = MisuratoreConsumo(percorso: percorso, capacitaKwh: 60, profilo: (t) => t.lunghezzaM * 0.15);
    m.registra(batteria: 80, metri: 0);
    final citta = m.registra(batteria: 78, metri: 9000)!;
    expect(citta.tipo, TipoStrada.urbana);
    expect(citta.velocitaKmh, closeTo(50, 1));
    final autostrada = m.registra(batteria: 75, metri: 20000)!;
    expect(autostrada.tipo, TipoStrada.autostrada);
  });
}
