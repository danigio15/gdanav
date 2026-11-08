import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart' show VistaMappa;
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Il cruscotto della guida col telefono (o il tablet) di traverso: il
/// pannello a sinistra, la mappa a destra, e niente che esce dallo schermo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Larghezza × altezza in punti, densità, e il bordo sicuro (la tacca di
  // lato sui telefoni, in basso la barra dei gesti).
  const schermi = <String, (Size, double, EdgeInsets)>{
    'iPhone 14 di traverso (844×390)': (Size(844, 390), 3, EdgeInsets.fromLTRB(47, 0, 47, 21)),
    'iPhone 14 Pro Max di traverso (932×430)': (Size(932, 430), 3, EdgeInsets.fromLTRB(59, 0, 59, 21)),
    'Android piccolo di traverso (780×360)': (Size(780, 360), 3, EdgeInsets.fromLTRB(0, 24, 0, 0)),
    'iPad Air di traverso (1180×820)': (Size(1180, 820), 2, EdgeInsets.fromLTRB(0, 24, 0, 20)),
    'iPad Pro 12,9" di traverso (1366×1024)': (Size(1366, 1024), 2, EdgeInsets.fromLTRB(0, 24, 0, 20)),
    'tablet Android di traverso (1280×800)': (Size(1280, 800), 2, EdgeInsets.fromLTRB(0, 24, 0, 48)),
  };

  Future<Ambiente> inGuida(WidgetTester tester, {VistaMappa? vista, PercorsoCalcolato? percorso}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(
      tester,
      km: 20,
      costruisci: percorso == null
          ? null
          : (_, profilo, preferenze, _) => PianificatoreViaggio(
              percorsi: (_) async => percorso,
              colonnine: ColonnineFinte(),
              profilo: profilo,
              preferenze: preferenze,
            ),
    );
    if (vista != null) await tester.runAsync(() => a.archivio.salvaVistaMappa(vista));
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    expect(a.guida.attiva, isTrue);
    return a;
  }

  void diTraverso(WidgetTester tester, Size punti, double densita, EdgeInsets bordo) {
    tester.view.physicalSize = punti * densita;
    tester.view.devicePixelRatio = densita;
    final b = FakeViewPadding(
      left: bordo.left * densita,
      top: bordo.top * densita,
      right: bordo.right * densita,
      bottom: bordo.bottom * densita,
    );
    tester.view.padding = b;
    tester.view.viewPadding = b;
    addTearDown(tester.view.reset);
  }

  /// Il widget sta tutto dentro lo schermo (meno il bordo sicuro).
  void dentro(WidgetTester tester, Finder f, Size schermo, EdgeInsets bordo, String cosa) {
    expect(f, findsWidgets, reason: cosa);
    final r = tester.getRect(f.first);
    final sicuro = Rect.fromLTRB(bordo.left, bordo.top, schermo.width - bordo.right, schermo.height - bordo.bottom);
    expect(
      r.left >= sicuro.left - 0.5 &&
          r.top >= sicuro.top - 0.5 &&
          r.right <= sicuro.right + 0.5 &&
          r.bottom <= sicuro.bottom + 0.5,
      isTrue,
      reason: '$cosa: $r fuori da $sicuro',
    );
  }

  for (final MapEntry(key: nome, value: (punti, densita, bordo)) in schermi.entries) {
    testWidgets('di traverso, $nome: il pannello a sinistra, tutto in vista', (tester) async {
      final a = await inGuida(tester);
      diTraverso(tester, punti, densita, bordo);
      await tester.pumpAndSettle();
      // Un overflow qui fallirebbe la prova da solo (un errore di Flutter).
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pannello-traverso')), findsOneWidget);
      dentro(tester, find.text('Fine'), punti, bordo, '«Fine»');
      dentro(tester, find.byKey(const Key('ricalcola')), punti, bordo, 'ricalcola');
      dentro(tester, find.byKey(const Key('2d-3d')), punti, bordo, 'il tasto della vista');
      dentro(tester, find.byKey(const Key('restanti')), punti, bordo, 'i km che restano');
      // La manovra in alto nel pannello, la barra in fondo al pannello.
      final pannello = tester.getRect(find.byKey(const Key('pannello-traverso')));
      expect(tester.getRect(find.text('Fine')).center.dx, lessThan(pannello.right));
      expect(tester.getRect(find.byKey(const Key('2d-3d'))).left, greaterThanOrEqualTo(pannello.right - 0.5));
      // La mappa mette l'auto nella parte libera a destra.
      await tester.pump();
      expect(a.guida.attiva, isTrue);
    });
  }

  testWidgets('di traverso, vicino a uno svincolo: il popup nel pannello, la barra ridotta, niente fuori', (
    tester,
  ) async {
    // Dritto verso nord, uscita a 500 m.
    final punti = [for (var i = 0; i <= 40; i++) Punto(42 + i * 0.0009, 12)];
    final linea = Linea(punti);
    final percorso = PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 110),
      ],
      manovre: [
        const Manovra(istruzione: 'Parti', lunghezzaM: 0, secondi: 0, inizio: 0, tipo: 1),
        Manovra(
          istruzione: "Prendi l'uscita a destra",
          lunghezzaM: linea.lunghezzaM - linea.cumulate[5],
          secondi: 30,
          inizio: 5,
          tipo: 20,
          verso: 'A1 · Roma',
          uscita: '12',
        ),
        Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
      ],
      limiti: [for (var i = 1; i < punti.length; i++) 130],
    );
    for (final (punti2, densita, bordo) in [
      (const Size(844, 390), 3.0, const EdgeInsets.fromLTRB(47, 0, 47, 21)),
      (const Size(780, 360), 3.0, const EdgeInsets.fromLTRB(0, 24, 0, 0)),
      (const Size(1180, 820), 2.0, const EdgeInsets.fromLTRB(0, 24, 0, 20)),
    ]) {
      final a = await inGuida(tester, percorso: percorso);
      diTraverso(tester, punti2, densita, bordo);
      a.posizioni.add(punti[1]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$punti2');
      expect(find.byKey(const Key('popup-svincolo')), findsOneWidget, reason: '$punti2');
      final pannello = tester.getRect(find.byKey(const Key('pannello-traverso')));
      expect(tester.getRect(find.byKey(const Key('popup-svincolo'))).right, lessThanOrEqualTo(pannello.right + 0.5));
      dentro(tester, find.text('Fine'), punti2, bordo, '«Fine» col popup ($punti2)');
      // Col popup, su un telefono, la batteria lascia il posto allo svincolo.
      expect(find.byKey(const Key('batteria-arrivo')), punti2.height < 560 ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('di traverso col 3D aumentato scelto: lo stesso cruscotto', (tester) async {
    await inGuida(tester, vista: VistaMappa.aumentata);
    const punti = Size(844, 390);
    const bordo = EdgeInsets.fromLTRB(47, 0, 47, 21);
    diTraverso(tester, punti, 3, bordo);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('pannello-traverso')), findsOneWidget);
    dentro(tester, find.text('Fine'), punti, bordo, '«Fine»');
    expect(find.byTooltip('Vista: 3D aumentato'), findsOneWidget);
  });

  testWidgets('girando il telefono il cruscotto cambia: dritto in colonna, di traverso a sinistra', (tester) async {
    await inGuida(tester);
    expect(find.byKey(const Key('pannello-traverso')), findsNothing);
    diTraverso(tester, const Size(844, 390), 3, const EdgeInsets.fromLTRB(47, 0, 47, 21));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pannello-traverso')), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('pannello-traverso')), findsNothing);
    expect(find.text('Fine'), findsOneWidget);
  });
}
