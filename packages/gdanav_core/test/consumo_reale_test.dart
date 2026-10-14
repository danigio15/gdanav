import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Lo stesso viaggio confrontato con ABRP: Leapmotor B10 56 kWh, 18 km fra
/// città e tangenziale in 21 minuti, partenza al 63%. ABRP diceva 59%
/// all'arrivo (−4%), gdanav 57% (−6%) con 15,6 kWh/100 km.
void main() {
  final b10 = catalogoVeicoli.firstWhere((v) => v.id == 'leapmotor-b10-56');

  // 18 km: un pezzo lento in centro, la città a 50, la tangenziale a 70.
  const viaggio = [
    Tratto(lunghezzaM: 3000, velocitaKmh: 30),
    Tratto(lunghezzaM: 4000, velocitaKmh: 50),
    Tratto(lunghezzaM: 9000, velocitaKmh: 70),
    Tratto(lunghezzaM: 2000, velocitaKmh: 50),
  ];

  double arrivo(Condizioni c) => PianificatoreSoste(profilo: b10, condizioni: c)
      .pianifica(percorso: viaggio, batteriaPartenza: 63, colonnine: const [])!.batteriaArrivo;

  group('il viaggio di ABRP', () {
    test('dura quanto dice ABRP (21-23 minuti)', () {
      final minuti = viaggio.fold(0.0, (s, t) => s + t.secondi) / 60;
      expect(minuti, inInclusiveRange(20, 23));
    });

    test('col meteo di una sera d\'ottobre (14 °C) si arriva al 59%, come ABRP', () {
      final a = arrivo(Condizioni.daMeteo(temperaturaC: 14));
      expect(a.round(), 59);
    });

    test('col consumo di riferimento di ABRP (188 Wh/km a 110 km/h) anche', () {
      final f = fattoreDaRiferimento(whKm: 188, kmh: 110, profilo: b10);
      expect(f, inInclusiveRange(1.0, 1.15));
      final a = arrivo(Condizioni.daMeteo(temperaturaC: 14, fattoreConsumo: f));
      expect(a.round(), 59);
    });

    test('il consumo del viaggio è da città, non da autostrada (11-13 kWh/100 km)', () {
      final kwh100 = energiaPercorsoKwh(viaggio, b10, Condizioni.daMeteo(temperaturaC: 14)) / 18 * 100;
      expect(kwh100, inInclusiveRange(10.5, 13.5));
    });

    test("l'arrivo non perde un punto all'arrotondamento", () {
      final piano = PianificatoreSoste(profilo: b10).pianifica(
        percorso: viaggio,
        batteriaPartenza: 63,
        colonnine: const [],
      )!;
      final esatto = 63 - piano.energiaKwh / b10.capacitaUtileKwh * 100;
      expect(piano.batteriaArrivo, closeTo(esatto, 1e-9));
      expect(piano.profiloBatteria.last.batteria, closeTo(esatto, 1e-9));
    });
  });

  group('il modello fisico', () {
    double whKm(double kmh) => consumoMedioWhKm([Tratto(lunghezzaM: 1000, velocitaKmh: kmh)], b10);

    test('conta partenze e frenate: in città non è 7-8 kWh/100 km', () {
      expect(whKm(50), inInclusiveRange(90, 130));
      expect(whKm(30), inInclusiveRange(75, 120));
    });

    test('in autostrada vicino al riferimento di ABRP', () {
      expect(whKm(110), inInclusiveRange(165, 195));
      expect(whKm(130), greaterThan(whKm(110)));
    });

    test('le fermate calano con la velocità', () {
      expect(fermatePerKm(30), greaterThan(fermatePerKm(50)));
      expect(fermatePerKm(50), greaterThan(fermatePerKm(90)));
      expect(fermatePerKm(130), lessThan(0.1));
    });

    test('senza temperatura nessun clima inventato', () {
      expect(const Condizioni().climaW, 0);
      expect(Condizioni.daMeteo(temperaturaC: 22).climaW, 0);
      expect(Condizioni.daMeteo(temperaturaC: 5).climaW, greaterThan(1000));
    });
  });

  group('il correttivo', () {
    test('il riferimento di ABRP pesa come 50 km: una misura sola non lo cancella', () {
      final f = fattoreDaRiferimento(whKm: 188, kmh: 110, profilo: b10);
      final c = ConsumoImparato.daRiferimento(RiferimentoConsumo(whKm: 188, kmh: 110, fattore: f));
      expect(c.fattore, f);
      final dopo = c.con(previstoWh: 1000, realeWh: 1300, km: 5);
      expect(dopo.fattore, greaterThan(f));
      expect(dopo.fattore, lessThan(f + 0.05));
      final letto = ConsumoImparato.daJson(jsonDecode(jsonEncode(dopo.toJson())) as Map<String, Object?>);
      expect(letto.riferimento!.whKm, 188);
      expect(letto.riferimento!.kmh, 110);
      expect(letto.fattore, closeTo(dopo.fattore, 1e-12));
    });

    test("quello imparato sul modello di prima non vale più", () {
      final vecchio = ConsumoImparato.daJson(const {'fattore': 1.7, 'km': 400});
      expect(vecchio.fattore, 1);
      expect(vecchio.kmOsservati, 0);
    });

    test('la batteria a punti interi non gonfia il consumo misurato', () {
      // Un'auto che consuma esattamente quanto il modello. La batteria vera
      // parte a 63,7% e si legge per difetto ogni 100 metri, come la manda
      // l'auto; 18 km, poi altri due viaggi uguali.
      final percorso = PercorsoCalcolato(
        punti: [for (var i = 0; i <= 18; i++) Punto(45 + i * 0.009, 9)],
        tratti: [for (var i = 0; i < 18; i++) const Tratto(lunghezzaM: 1000, velocitaKmh: 50)],
        manovre: const [],
      );
      double modello(Tratto t) => energiaTrattoWh(t, b10);
      var imparato = const ConsumoImparato();
      for (final inizio in [63.7, 59.2, 54.95]) {
        final m = MisuratoreConsumo(percorso: percorso, capacitaKwh: b10.capacitaUtileKwh, profilo: modello);
        for (var metri = 0.0; metri <= 18000; metri += 100) {
          final vera = inizio - m.previstaFinoA(metri) / 1000 / b10.capacitaUtileKwh * 100;
          final misura = m.registra(batteria: vera.floorToDouble(), metri: metri);
          if (misura != null) {
            imparato = imparato.con(previstoWh: misura.previstoWh, realeWh: misura.realeWh, km: misura.km);
          }
        }
      }
      expect(imparato.kmOsservati, greaterThan(10));
      expect(imparato.fattore, closeTo(1, 0.08));
    });
  });
}
