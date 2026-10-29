import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/mappa/stile.dart' show sorgenteSegnalazioni;
import 'package:gdanav_app/schermate/avvisi_guida.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/scelte_avvisi.dart';
import 'package:gdanav_app/stato/voce.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Gli avvisi della guida, uno per uno: a voce, solo a schermo o spenti.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> aspetta(WidgetTester tester, [int ms = 30]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  test('spento sparisce anche dalla mappa, sul telefono e in auto', () {
    Segnalazione una(String id, TipoSegnalazione tipo) =>
        Segnalazione(id: id, tipo: tipo, punto: const Punto(40.85, 14.26), creata: DateTime(2026));
    final tutte = [una('a', TipoSegnalazione.autovelox), una('p', TipoSegnalazione.polizia)];
    List<Object?> ids(Map<String, Object?> d) => [
      for (final f in d['features']! as List) ((f as Map)['properties'] as Map)['id'],
    ];
    final s = ScelteAvvisi();
    expect(ids(datiSegnalazioni(tutte, s)), ['a', 'p']);
    s.scegli(Avviso.polizia, ComeAvvisare.schermo);
    expect(ids(datiSegnalazioni(tutte, s)), ['a', 'p'], reason: 'solo a schermo: sulla mappa resta');
    s.scegli(Avviso.autovelox, ComeAvvisare.spento);
    expect(ids(datiSegnalazioni(tutte, s)), ['p']);
    expect(ids(datiSegnalazioni(tutte)), ['a', 'p'], reason: 'senza scelte, tutte');
  });

  testWidgets('col beep un beep al posto della frase; col silenzio niente', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    a.guida.avvisi.scegli(Avviso.autovelox, ComeAvvisare.beep);
    expect(a.guida.avvisi.riassunto, '1 col beep');
    a.guida.annunciaAvviso('Autovelox tra 500 metri.', quale: Avviso.autovelox);
    a.guida.annunciaAvviso('Polizia tra 500 metri.', quale: Avviso.polizia);
    await tester.pump();
    expect(a.voce.beep, 1);
    expect(a.voce.frasi, ['Polizia tra 500 metri.']);
    // Silenzio: tace anche il beep.
    while (!a.guida.audio.senzaAvvisi) {
      a.guida.alternaVoce();
    }
    a.guida.annunciaAvviso('Autovelox tra 500 metri.', quale: Avviso.autovelox);
    await tester.pump();
    expect(a.voce.beep, 1);
  });

  test('il beep è un WAV vero: due note brevi, senza file', () {
    final w = wavDelBeep();
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    final b = ByteData.sublistView(w);
    expect(b.getUint32(40, Endian.little), w.length - 44);
    // Un terzo di secondo circa: un avviso, non una suoneria.
    final secondi = (w.length - 44) / 2 / b.getUint32(24, Endian.little);
    expect(secondi, inInclusiveRange(0.2, 0.4));
    // Entra piano: niente «clic» all'inizio.
    expect(b.getInt16(44, Endian.little), 0);
  });

  test('di partenza tutti a voce; il limite non si spegne, resta il tachimetro', () {
    final s = ScelteAvvisi();
    expect(Avviso.values.every(s.aVoce), isTrue);
    expect(s.riassunto, 'Tutti a voce');
    s
      ..scegli(Avviso.polizia, ComeAvvisare.spento)
      ..scegli(Avviso.traffico, ComeAvvisare.schermo)
      ..scegli(Avviso.limite, ComeAvvisare.spento);
    expect(s.spento(Avviso.polizia), isTrue);
    expect(s.di(Avviso.traffico), ComeAvvisare.schermo);
    expect(s.di(Avviso.limite), ComeAvvisare.schermo);
    expect(s.riassunto, '1 spento · 2 solo a schermo');
    // Ogni segnalazione ha il suo avviso.
    for (final t in TipoSegnalazione.values) {
      expect(Avviso.diSegnalazione(t).name, t.name);
    }
  });

  test('si ricordano, e un archivio rovinato torna a tutti a voce', () async {
    preparaPiattaforma();
    final archivio = Archivio();
    expect(await archivio.scelteAvvisi(), isEmpty);
    final s = ScelteAvvisi(const {}, (s) => archivio.salvaScelteAvvisi(s))
      ..scegli(Avviso.autovelox, ComeAvvisare.schermo)
      ..scegli(Avviso.ztl, ComeAvvisare.spento);
    await Future<void>.delayed(Duration.zero);
    expect(s.di(Avviso.autovelox), ComeAvvisare.schermo);
    expect(await archivio.scelteAvvisi(), {Avviso.autovelox: ComeAvvisare.schermo, Avviso.ztl: ComeAvvisare.spento});
    expect(ScelteAvvisi.daJson('non è json'), isEmpty);
    expect(ScelteAvvisi.daJson('{"marziani":"spento","polizia":"boh","lavori":"spento"}'), {
      Avviso.lavori: ComeAvvisare.spento,
    });
  });

  testWidgets('la pagina cambia la scelta col tocco', (tester) async {
    final s = ScelteAvvisi();
    await tester.pumpWidget(MaterialApp(home: AvvisiGuidaSchermata(scelte: s)));
    await tester.tap(find.descendant(of: find.byKey(const Key('avviso-polizia')), matching: find.text('Spento')));
    await tester.pumpAndSettle();
    expect(s.spento(Avviso.polizia), isTrue);
    // Voce, Beep, Schermo, Spento.
    await tester.tap(find.descendant(of: find.byKey(const Key('avviso-autovelox')), matching: find.text('Beep')));
    await tester.pumpAndSettle();
    expect(s.di(Avviso.autovelox), ComeAvvisare.beep);
    // Il limite non ha «Spento»: il tachimetro c'è sempre.
    final limite = find.byKey(const Key('avviso-limite'));
    await tester.scrollUntilVisible(limite, 200);
    expect(find.descendant(of: limite, matching: find.text('Spento')), findsNothing);
    expect(find.descendant(of: limite, matching: find.text('Beep')), findsOneWidget);
    final noVoce = find.descendant(of: limite, matching: find.text('Schermo'));
    await tester.ensureVisible(noVoce);
    await tester.pumpAndSettle();
    await tester.tap(noVoce);
    await tester.pumpAndSettle();
    expect(s.di(Avviso.limite), ComeAvvisare.schermo);
  });

  testWidgets('un incidente «solo schermo» si vede e non si sente; spento non si vede nemmeno', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    for (final (i, k) in [(5, 'z~incidente1'), (12, 'z~incidente2')]) {
      a.relay.segnalazioni.add({
        'id': k,
        'tipo': 'incidente',
        'lat': punti[i].lat,
        'lon': punti[i].lon,
        'creata': 0,
        'conferme': 0,
      });
    }
    a.posizione.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    expect(a.segnalazioni.vicine, hasLength(2));

    a.guida.avvisi.scegli(Avviso.incidente, ComeAvvisare.schermo);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(Punto(punti[4].lat + 0.003, punti[4].lon)); // ~700 m prima
    await aspetta(tester);
    expect(find.text('Incidente segnalato'), findsOneWidget);
    expect(a.voce.frasi.where((f) => f.startsWith('Incidente')), isEmpty);

    a.guida.avvisi.scegli(Avviso.incidente, ComeAvvisare.spento);
    await aspetta(tester);
    expect(find.text('Incidente segnalato'), findsNothing);
    a.posizioni.add(Punto(punti[11].lat + 0.003, punti[11].lon));
    await aspetta(tester);
    expect(find.text('Incidente segnalato'), findsNothing);
    expect(a.voce.frasi.where((f) => f.startsWith('Incidente')), isEmpty);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets("in auto valgono le stesse scelte: spento non arriva né sulla mappa né nel riquadro", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.relay.segnalazioni.add({
      'id': 'z~incidente1',
      'tipo': 'incidente',
      'lat': punti[5].lat,
      'lon': punti[5].lon,
      'creata': 0,
      'conferme': 0,
    });
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      auto: a.auto,
      segnalazioni: a.segnalazioni,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    a.posizione.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(Punto(punti[4].lat + 0.003, punti[4].lon));
    await aspetta(tester);

    String mappa() {
      final ultima = chiamate.lastWhere((c) => c.method == 'sorgenti').arguments as Map;
      return (ultima['dati'] as Map)[sorgenteSegnalazioni] as String;
    }

    Map<Object?, Object?> riquadro() => chiamate.lastWhere((c) => c.method == 'avviso').arguments as Map;
    expect(mappa(), contains('incidente'));
    expect(riquadro()['tipo'], 'incidente');

    // Spento nell'app: sparisce dalla mappa e dal riquadro dell'auto.
    a.guida.avvisi.scegli(Avviso.incidente, ComeAvvisare.spento);
    await aspetta(tester);
    expect((jsonDecode(mappa()) as Map)['features'], isEmpty);
    expect(riquadro()['tipo'], isNull);
    await tester.runAsync(a.guida.ferma);
  });
}
