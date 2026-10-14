import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/avvisi_guida.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/scelte_avvisi.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Gli avvisi della guida, uno per uno: a voce, solo a schermo o spenti.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> aspetta(WidgetTester tester, [int ms = 30]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

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
    // Il limite ha solo «A voce» e «No voce».
    final limite = find.byKey(const Key('avviso-limite'));
    await tester.scrollUntilVisible(limite, 200);
    expect(find.descendant(of: limite, matching: find.text('Spento')), findsNothing);
    final noVoce = find.descendant(of: limite, matching: find.text('No voce'));
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
}
