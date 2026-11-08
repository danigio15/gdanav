import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/mappa_3d.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'aiuti.dart';
import 'webview_finta.dart';

/// Il 3D aumentato vero, con una WebView finta: parte, e se la pagina dice
/// che il telefono non ce la fa (o non risponde) si torna alla vista di
/// prima, lo si dice e (se è il telefono) lo si ricorda.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('quando il 3D aumentato non va', () {
    test('cosa vuol dire ogni messaggio della pagina', () {
      expect(nonVaPer(const Errore3d('webgl2')), ('webgl2', true));
      expect(nonVaPer(const Errore3d('software')), ('software', true));
      expect(nonVaPer(const Errore3d('contesto')), ('contesto', false));
      expect(nonVaPer(const Prestazioni3d(fps: 14, lento: true, triangoli: 1)), ('lento', true));
      expect(nonVaPer(const Prestazioni3d(fps: 50, lento: false, triangoli: 1)), isNull);
      expect(nonVaPer(const Pronta3d()), isNull);
    });
  });

  late WebViewFinta finta;
  setUp(() {
    finta = WebViewFinta();
    WebViewPlatform.instance = finta;
    provaMappa3dPossibile = true;
  });
  tearDown(() => provaMappa3dPossibile = null);

  Future<Ambiente> inGuidaAumentata(WidgetTester tester, {VistaMappa prima = VistaMappa.immersiva}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.runAsync(() async {
      await a.archivio.salvaVistaMappa(prima);
      await a.archivio.salvaVistaMappa(VistaMappa.aumentata);
    });
    await tester.pumpWidget(a.app(vero3d: true));
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    await tester.tap(find.text('Avvia'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
    return a;
  }

  Future<void> fine(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  }

  testWidgets('col 3D aumentato la guida apre la pagina 3D, e le manda lo stile quando è caricata', (tester) async {
    await inGuidaAumentata(tester);
    expect(find.byKey(const Key('mappa-3d')), findsOneWidget);
    final w = finta.ultimo;
    expect(w.caricata, paginaMappa3d);
    w.dallaPagina(canale3d, {'tipo': 'caricata'});
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final tipi = w.messaggi.map((m) => m['tipo']).toSet();
    expect(tipi, containsAll(['opzioni', 'stile']));
    w.dallaPagina(canale3d, {'tipo': 'pronto'});
    w.dallaPagina(canale3d, {'tipo': 'prestazioni', 'fps': 55, 'lento': false, 'triangoli': 500000});
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('mappa-3d')), findsOneWidget, reason: 'va: resta');
    await fine(tester);
  });

  for (final (messaggio, motivo) in [
    ({'tipo': 'prestazioni', 'fps': 12, 'lento': true, 'triangoli': 800000}, 'lento'),
    ({'tipo': 'errore', 'motivo': 'software'}, 'software'),
    ({'tipo': 'errore', 'motivo': 'webgl2'}, 'webgl2'),
  ]) {
    testWidgets('la pagina dice «$motivo»: si torna alla vista di prima, lo si dice e lo si ricorda', (tester) async {
      final a = await inGuidaAumentata(tester);
      final w = finta.ultimo;
      w.dallaPagina(canale3d, {'tipo': 'caricata'});
      await tester.pump();
      w.dallaPagina(canale3d, {'tipo': 'pronto'});
      w.dallaPagina(canale3d, messaggio);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('mappa-3d')), findsNothing, reason: 'la mappa di sempre');
      expect(
        find.text('3D aumentato non è disponibile su questo telefono: torno alla vista immersiva'),
        findsOneWidget,
      );
      expect(find.byTooltip('Vista: Immersiva').last, findsOneWidget);
      expect(a.controllo?.vista, VistaMappa.immersiva);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(await tester.runAsync(a.archivio.aumentataNonVa), motivo);
      expect(await tester.runAsync(a.archivio.vistaMappa), VistaMappa.immersiva);
      // Un secondo messaggio non rifà niente: l'avviso è uno.
      w.dallaPagina(canale3d, messaggio);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('aumentato-non-va')), findsOneWidget);
      await fine(tester);
    });
  }

  testWidgets('la pagina non risponde: si torna indietro per questa volta, senza ricordarlo', (tester) async {
    final a = await inGuidaAumentata(tester, prima: VistaMappa.inclinata);
    expect(find.byKey(const Key('mappa-3d')), findsOneWidget);
    await tester.pump(Mappa3d.attesa + const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('mappa-3d')), findsNothing);
    expect(find.text('3D aumentato non è partito: torno alla vista 3D'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(await tester.runAsync(a.archivio.aumentataNonVa), isNull);
    expect(await tester.runAsync(a.archivio.vistaMappa), VistaMappa.aumentata, reason: 'la prossima volta si riprova');
    await fine(tester);
  });

  testWidgets('ricordato che non va: la guida parte con la mappa di sempre, in 3D', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.runAsync(() async {
      await a.archivio.salvaVistaMappa(VistaMappa.aumentata);
      await a.archivio.salvaAumentataNonVa('lento');
    });
    await tester.pumpWidget(a.app(vero3d: true));
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('mappa-3d')), findsNothing);
    expect(a.controllo?.vista, VistaMappa.inclinata);
    expect(finta.controlli, isEmpty, reason: 'la pagina 3D non si apre neanche');
    await fine(tester);
  });
}
