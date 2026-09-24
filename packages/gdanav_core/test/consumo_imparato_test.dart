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
}
