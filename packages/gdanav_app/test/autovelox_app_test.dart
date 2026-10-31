import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/avvisi_in_guida.dart';
import 'package:gdanav_app/stato/avvisi_strada.dart';
import 'package:gdanav_app/stato/gestore_guida.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/scelte_avvisi.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Gli autovelox più forti: avvisati prima quando si va forte, «rallenta»
/// sopra il limite, i Tutor con la media, e anche senza percorso.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> aspetta(WidgetTester tester, [int ms = 30]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  final strada = dritta(20).punti;

  test('più si va forte, prima si avvisa; in città poco prima', () {
    expect(AvvisiStrada.avvisoAlla(50, limiteKmh: 50), closeTo(208, 1));
    expect(AvvisiStrada.avvisoAlla(30, limiteKmh: 50), 150);
    expect(AvvisiStrada.avvisoAlla(80, limiteKmh: 90), closeTo(444, 1));
    expect(AvvisiStrada.avvisoAlla(130), closeTo(1083, 1));
    expect(AvvisiStrada.avvisoAlla(250), 1200);
  });

  testWidgets('in città, a 50 all\'ora, l\'autovelox non si sente a 900 m ma a poco più di 200', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    // Sulla metà in città della strada, quella col limite a 50.
    final autovelox = ArchivioAutovelox.leggi(
      ArchivioAutovelox.scrivi([(strada[5].lat, strada[5].lon + 0.0001, 50, 0)]),
    );
    final a = await ambiente(tester, km: 20, autovelox: autovelox);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizione.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    Future<void> qui(Punto p) async {
      a.gps.add(Lettura(p, velocitaMs: 13.9, rotta: 0));
      a.posizioni.add(p);
      await aspetta(tester);
    }

    final avvisi = AvvisiStrada.di(a.guida, a.segnalazioni);
    // A 900 m, poi a 500: ancora niente.
    await qui(Punto(punti[5].lat - 0.0081, punti[5].lon));
    await qui(Punto(punti[5].lat - 0.0045, punti[5].lon));
    expect(a.voce.frasi.where((f) => f.startsWith('Autovelox')), isEmpty);
    expect(avvisi.davanti, isNull);
    // A 200 m sì, una volta.
    await qui(Punto(punti[5].lat - 0.0018, punti[5].lon));
    expect(a.voce.frasi.where((f) => f.startsWith('Autovelox, limite 50 tra')), hasLength(1));
    expect(avvisi.davanti!.$2, closeTo(200, 10));
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('a 130 all\'ora l\'autovelox da 90 si sente a un chilometro, con «rallenta», e di nuovo vicino', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final autovelox = ArchivioAutovelox.leggi(
      ArchivioAutovelox.scrivi([(strada[5].lat, strada[5].lon + 0.0001, 90, 0)]),
    );
    final a = await ambiente(tester, km: 20, autovelox: autovelox);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizione.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    Future<void> qui(Punto p) async {
      a.gps.add(Lettura(p, velocitaMs: 36.1, rotta: 0));
      a.posizioni.add(p);
      await aspetta(tester);
    }

    // ~1 km prima: a 50 all'ora sarebbe presto, a 130 no.
    await qui(Punto(punti[5].lat - 0.009, punti[5].lon));
    final dette = a.voce.frasi.where((f) => f.startsWith('Autovelox, limite 90 tra')).toList();
    expect(dette, hasLength(1));
    expect(dette.single, endsWith('Rallenta.'));
    await qui(Punto(punti[5].lat - 0.005, punti[5].lon));
    expect(a.voce.frasi.where((f) => f.startsWith('Rallenta')), isEmpty);
    // A 250 m, sempre a 130: lo si ridice, una volta.
    await qui(Punto(punti[5].lat - 0.00225, punti[5].lon));
    await qui(Punto(punti[5].lat - 0.0015, punti[5].lon));
    expect(a.voce.frasi.where((f) => f == 'Rallenta, limite 90.'), hasLength(1));
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('senza percorso: l\'autovelox davanti, nella nostra direzione, si vede e si sente', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final autovelox = ArchivioAutovelox.leggi(
      ArchivioAutovelox.scrivi([
        (strada[5].lat, strada[5].lon + 0.0001, 70, 0),
        // Per chi va dall'altra parte.
        (strada[5].lat - 0.002, strada[5].lon - 0.0001, 50, 180),
      ]),
    );
    final a = await ambiente(tester, km: 20, autovelox: autovelox);
    await tester.pumpWidget(a.app());
    await tester.pump();
    a.posizione.avvia();
    // Verso nord, a 72 all'ora: si avvisa a meno di 400 m.
    for (var i = 0; i < 4; i++) {
      a.gps.add(Lettura(Punto(strada[4].lat + 0.0055 + 0.0003 * i, strada[4].lon), velocitaMs: 20, rotta: 0));
      await aspetta(tester, 40);
    }
    await tester.pumpAndSettle();
    final avvisi = AvvisiStrada.di(a.guida, a.segnalazioni);
    expect(avvisi.davanti?.$1.limiteKmh, 70);
    expect(avvisi.davanti!.$2, closeTo((strada[5].lat - strada[4].lat - 0.0064) * 111320, 30));
    expect(find.byKey(const Key('avviso-senza-percorso')), findsOneWidget);
    expect(a.voce.frasi.where((f) => f.startsWith('Autovelox, limite 70 tra')), hasLength(1));

    // Da fermi (a piedi, in casa) non si avvisa.
    a.gps.add(Lettura(Punto(strada[4].lat + 0.0042, strada[4].lon), velocitaMs: 1, rotta: 0));
    await aspetta(tester, 40);
    await tester.pumpAndSettle();
    expect(avvisi.davanti, isNull);
  });

  testWidgets('il Tutor: si annuncia, dentro la media, sopra il limite «rallenta», poi la fine', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final autovelox = ArchivioAutovelox.leggi(
      ArchivioAutovelox.scrivi(const [], tutor: [(strada[5].lat, strada[5].lon, strada[10].lat, strada[10].lon, 110)]),
    );
    final a = await ambiente(tester, km: 20, autovelox: autovelox);
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizione.avvia();
    a.segnalazioni.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    expect(a.segnalazioni.tutor, hasLength(1));

    var ora = DateTime(2026, 10, 14, 10);
    final posizioni = StreamController<Punto>.broadcast();
    addTearDown(posizioni.close);
    final voce = VoceFinta();
    final guida = GestoreGuida(
      viaggio: a.viaggio,
      auto: a.auto,
      posizioni: () => posizioni.stream,
      voce: voce,
      avvisi: ScelteAvvisi(),
      orologio: () => ora,
    );
    addTearDown(guida.dispose);
    final avvisi = AvvisiStrada.di(guida, a.segnalazioni);
    guida.avvia();
    Future<void> qui(double lat) async {
      posizioni.add(Punto(lat, punti[0].lon));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    await qui(punti[5].lat - 0.007); // ~780 m prima
    expect(avvisi.tutor, isA<TutorDavanti>());
    expect(voce.frasi.where((f) => f.startsWith('Tutor tra') && f.endsWith('limite 110.')), hasLength(1));

    // Dentro, a 144 all'ora: 40 m al secondo.
    var lat = punti[5].lat + 0.0002;
    for (var i = 0; i < 25; i++) {
      await qui(lat);
      ora = ora.add(const Duration(seconds: 1));
      lat += 40 / 111320;
    }
    final dentro = avvisi.tutor! as DentroTutor;
    expect(dentro.mediaKmh, closeTo(144, 3));
    expect(voce.frasi.where((f) => f.startsWith('La media è') && f.endsWith('limite 110: rallenta.')), hasLength(1));

    // Il riquadro.
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Scaffold(body: AvvisoTutor(stato: dentro)),
      ),
    );
    expect(find.textContaining('Tutor · media 14'), findsOneWidget);
    expect(find.textContaining('rallenta'), findsOneWidget);

    ora = ora.add(const Duration(minutes: 2));
    await qui(punti[10].lat + 0.001);
    expect(avvisi.tutor, isNull);
    expect(voce.frasi.where((f) => f.startsWith('Fine Tutor, media')), hasLength(1));

    // Spento: niente di niente.
    guida.avvisi.scegli(Avviso.tutor, ComeAvvisare.spento);
    expect(avvisi.tutor, isNull);
    await tester.runAsync(guida.ferma);
  });
}
