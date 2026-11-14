import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/strade_attorno.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Una strada dritta verso nord di [km] che parte da [da] (punti inventati).
PercorsoCalcolato dritta(Punto da, int km) {
  final punti = [for (var i = 0; i <= km; i++) Punto(da.lat + i * 0.009, da.lon)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 90),
    ],
    manovre: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* «In galleria si perde, va per un po' nel vuoto e poi si blocca, per poi
   * riprendersi quando si esce.» Una galleria di un chilometro a 70 all'ora:
   * cinquanta secondi senza GPS, e in mezzo una posizione larga del telefono
   * (dalle celle, trecento metri di lato). */
  testWidgets('in galleria la guida va avanti lungo il percorso, senza GPS, e poi si riallinea', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final ora = tester.binding.clock.now;
    final a = await ambiente(
      tester,
      km: 20,
      orologioGuida: ora,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (t) async => dritta(t.first, 20),
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    a.guida.avvia();
    await tester.pump();
    final linea = Linea((a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti);
    const v = 70 / 3.6;
    var metri = 1000.0;
    Future<void> lettura({double? precisione, double est = 0}) async {
      final p = _a(linea, metri);
      final q = Punto(p.lat, p.lon + est / 84000);
      a.posizioni.add(PuntoInMoto(q.lat, q.lon, rotta: 0, velocitaMs: v, alle: ora(), precisioneM: precisione ?? 5));
      await tester.pump();
    }

    // Cinque secondi col GPS, fino all'ingresso della galleria.
    for (var i = 0; i < 5; i++) {
      await lettura();
      await tester.pump(const Duration(seconds: 1));
      metri += v;
    }
    final ingresso = a.guida.avanzamento!.percorsiM;
    expect(a.guida.stimaSenzaGps, isFalse);
    // Cinquanta secondi senza GPS (al ventesimo una posizione larga, fuori strada).
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(seconds: 1));
      metri += v;
      if (i == 20) await lettura(precisione: 300, est: 300);
      final av = a.guida.avanzamento!;
      expect(av.posizioneSulPercorso, isNotNull, reason: 'secondo $i: sempre sulla strada, mai nel vuoto');
      if (i >= 3) expect(a.guida.stimaSenzaGps, isTrue, reason: 'secondo $i');
    }
    final stimati = a.guida.avanzamento!.percorsiM - ingresso;
    expect(stimati, closeTo(v * 50, v * 3), reason: 'avanti alla velocità di prima ($stimati m)');
    expect(a.guida.gpsPersoInGuida, isFalse);
    // Il GPS torna: si riallinea su di lui.
    await lettura();
    expect(a.guida.stimaSenzaGps, isFalse);
    expect((a.guida.avanzamento!.percorsiM - metri).abs(), lessThan(5));
    // Tre minuti e più senza niente: la stima si ferma, «GPS assente».
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(a.guida.gpsPersoInGuida, isTrue);
    final fermo = a.guida.avanzamento!.percorsiM;
    await tester.pump(const Duration(seconds: 5));
    expect(a.guida.avanzamento!.percorsiM, fermo, reason: 'oltre tre minuti non si va più avanti');
    await tester.runAsync(a.guida.ferma);
  });

  test('le strade attorno, dalla mappa: linee, multilinee e sensi unici', () {
    final tratti = trattiDaFeatures([
      {
        'type': 'Feature',
        'properties': {'class': 'primary', 'oneway': 1},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [14.3, 41.0],
            [14.301, 41.0],
          ],
        },
      },
      '{"type":"Feature","properties":{"class":"minor","oneway":-1},"geometry":{"type":"MultiLineString",'
          '"coordinates":[[[14.3,41.0],[14.3,41.001]],[[14.31,41.0],[14.31,41.001]]]}}',
      {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Point',
          'coordinates': [14.3, 41.0],
        },
      },
    ]);
    expect(tratti.length, 3);
    expect(tratti.first.senso, 1);
    expect(tratti.first.punti.first, const Punto(41.0, 14.3));
    expect(tratti[1].senso, -1);
    expect(tratti[2].senso, -1);
  });
}

Punto _a(Linea l, double metri) {
  final c = l.cumulate;
  var i = 1;
  while (i < c.length - 1 && c[i] < metri) {
    i++;
  }
  final t = ((metri - c[i - 1]) / (c[i] - c[i - 1])).clamp(0.0, 1.0);
  final a = l.punti[i - 1], b = l.punti[i];
  return Punto(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon));
}
