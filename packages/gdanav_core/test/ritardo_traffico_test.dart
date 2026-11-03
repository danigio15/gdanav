import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Una strada dritta verso nord: un punto ogni ~1 km, a [kmh].
PercorsoCalcolato dritta(int km, {double kmh = 120}) {
  final punti = [for (var i = 0; i <= km; i++) Punto(42 + i * 0.009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: kmh),
    ],
    manovre: const [],
  );
}

void main() {
  group('il ritardo che si dichiara', () {
    test('dal sommario: la differenza col tempo senza traffico, o il ritardo detto se è di più', () {
      expect(
        ritardoDalSommario(
            {'travelTimeInSeconds': 4000, 'noTrafficTravelTimeInSeconds': 3400, 'trafficDelayInSeconds': 120}),
        const Duration(seconds: 600),
      );
      expect(
        ritardoDalSommario(
            {'travelTimeInSeconds': 3500, 'noTrafficTravelTimeInSeconds': 3400, 'trafficDelayInSeconds': 300}),
        const Duration(seconds: 300),
      );
    });

    test('mai negativo, e un numero sballato non allunga il viaggio di giorni', () {
      expect(ritardoDalSommario({'travelTimeInSeconds': 3000, 'noTrafficTravelTimeInSeconds': 3400}), Duration.zero);
      expect(ritardoDalSommario({'trafficDelayInSeconds': 900000}), const Duration(hours: 3));
      expect(ritardoDalSommario(const {}), Duration.zero);
    });
  });

  group('i tempi col traffico', () {
    test('la coda fa perdere almeno il suo ritardo anche se la velocità detta ne farebbe perdere meno', () {
      // Valhalla stimava già 60 km/h: con la «velocità della coda» a 50 si
      // perdevano due minuti, TomTom ne dice dieci.
      final p = dritta(20, kmh: 60);
      final linea = Linea(p.punti);
      final t = p.conTraffico([
        Coda(daM: linea.cumulate[5], aM: linea.cumulate[15], ritardo: const Duration(minutes: 10), velocitaKmh: 50),
      ]);
      expect((t.durata - p.durata).inSeconds, closeTo(600, 5));
      expect(t.ritardoTraffico.inSeconds, closeTo(600, 5));
    });

    test('e se la velocità detta è più lenta, vale lei: il ritardo è quello vero', () {
      final p = dritta(20);
      final linea = Linea(p.punti);
      final t = p.conTraffico([
        Coda(daM: linea.cumulate[5], aM: linea.cumulate[10], ritardo: const Duration(minutes: 1), velocitaKmh: 20),
      ]);
      // 5 km a 20 invece che a 120: 15 minuti meno 2,5.
      expect(t.ritardoTraffico.inSeconds, closeTo(750, 10));
      expect((t.durata - p.durata).inSeconds, closeTo(t.ritardoTraffico.inSeconds, 1));
    });

    test('il rallentamento fuori dalle code si spalma sul resto della strada', () {
      final p = dritta(100);
      final linea = Linea(p.punti);
      final t = p.conTraffico(
        [Coda(daM: linea.cumulate[40], aM: linea.cumulate[50], ritardo: const Duration(minutes: 5))],
        totale: const Duration(minutes: 12),
      );
      expect((t.durata - p.durata).inSeconds, closeTo(720, 10));
      expect(t.ritardoTraffico.inSeconds, closeTo(720, 10));
      expect(t.tratti[10].velocitaKmh, lessThan(120));
      expect(t.ritardoDichiarato, const Duration(minutes: 12));
    });

    test('ma mai oltre metà del tempo senza traffico', () {
      final p = dritta(10);
      final t = p.conTraffico(const [], totale: const Duration(hours: 2));
      expect((t.durata - p.durata).inSeconds, closeTo(p.durata.inSeconds * 0.5, 2));
    });

    test('riapplicato, il traffico non si somma a quello di prima', () {
      final p = dritta(30);
      final t = p.conTraffico(const [], totale: const Duration(minutes: 3));
      final di = t.conTraffico(const [], totale: const Duration(minutes: 3));
      expect(di.durata, t.durata);
    });
  });

  group('il ritardo che resta davanti', () {
    test('in guida: la coda passata non conta più, quella davanti sì', () {
      final p = dritta(100);
      final linea = Linea(p.punti);
      final t = p.conTraffico([
        Coda(daM: linea.cumulate[20], aM: linea.cumulate[30], ritardo: const Duration(minutes: 4)),
        Coda(daM: linea.cumulate[70], aM: linea.cumulate[80], ritardo: const Duration(minutes: 6)),
      ]);
      final g = Guida(t);
      expect(g.aggiorna(p.punti[1]).ritardoTraffico.inSeconds, closeTo(600, 15));
      expect(g.aggiorna(p.punti[50]).ritardoTraffico.inSeconds, closeTo(360, 15));
      // Dentro la coda: ne resta metà.
      expect(g.aggiorna(p.punti[75]).ritardoTraffico.inSeconds, closeTo(180, 20));
      expect(g.aggiorna(p.punti[90]).ritardoTraffico, Duration.zero);
    });

    test('senza traffico non c\'è niente da dire', () {
      final g = Guida(dritta(20));
      expect(g.aggiorna(dritta(20).punti[2]).ritardoTraffico, Duration.zero);
    });

    test('coi tempi di TomTom (senza il percorso senza traffico) si stima dalle code e dal resto', () {
      final p = dritta(100);
      final linea = Linea(p.punti);
      final tomtom = PercorsoCalcolato(
        punti: p.punti,
        tratti: p.tratti,
        manovre: const [],
        code: [Coda(daM: linea.cumulate[60], aM: linea.cumulate[70], ritardo: const Duration(minutes: 8))],
        ritardoTraffico: const Duration(minutes: 10),
        trafficoVero: true,
      );
      final all = ritardoTrafficoAvanti(tomtom, percorsiM: 0, quotaTempoRestante: 1);
      expect(all, const Duration(minutes: 10));
      final meta = ritardoTrafficoAvanti(tomtom, percorsiM: linea.cumulate[65], quotaTempoRestante: 0.35);
      // Metà coda (4 min) più il 35% dei 2 minuti sparsi.
      expect(meta.inSeconds, closeTo(240 + 42, 2));
      expect(ritardoTrafficoAvanti(tomtom, percorsiM: linea.cumulate[90], quotaTempoRestante: 0.1).inSeconds, 12);
    });
  });

  group('come si dice', () {
    test('sotto il minuto niente, poi arancio, da dieci minuti rosso', () {
      expect(gravitaRitardo(0), 0);
      expect(gravitaRitardo(3), 1);
      expect(gravitaRitardo(10), 2);
      expect(testoRitardoTraffico(0), '');
      expect(testoRitardoTraffico(7), '+7 min di traffico');
      expect(testoRitardoTraffico(65), '+1 h 05 di traffico');
      expect(testoRitardoTraffico(120), '+2 h di traffico');
    });

    test('il numero non balla a ogni lettura', () {
      final r = RitardoMostrato();
      expect(r.aggiorna(const Duration(seconds: 420)), 7);
      expect(r.aggiorna(const Duration(seconds: 380)), 7);
      expect(r.aggiorna(const Duration(seconds: 450)), 7);
      expect(r.aggiorna(const Duration(seconds: 300)), 5);
      // Finita la coda, la scritta se ne va subito.
      expect(r.aggiorna(const Duration(seconds: 40)), 0);
      expect(r.aggiorna(const Duration(seconds: 200)), 3);
    });
  });
}
