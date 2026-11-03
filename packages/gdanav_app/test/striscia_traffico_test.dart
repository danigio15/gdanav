import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/striscia_traffico.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

CostruisciPianificatore _conTraffico(int km, List<Coda> code) =>
    (_, profilo, preferenze, _) => PianificatoreViaggio(
      percorsi: (_) async => dritta(km).conTraffico(code),
      colonnine: ColonnineFinte(),
      profilo: profilo,
      preferenze: preferenze,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // «Mostra lateralmente la striscia del traffico con i minuti di ritardo e
  // man mano a che punto è il traffico.»
  group('la striscia del traffico', () {
    Future<void> mostra(WidgetTester tester, StrisciaTraffico s, {double alto = 400}) => tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: alto,
              child: StrisciaTrafficoLaterale(striscia: s),
            ),
          ),
        ),
      ),
    );

    testWidgets('coi minuti e la distanza accanto a ogni coda', (tester) async {
      final p = dritta(40).conTraffico([
        const Coda(daM: 4000, aM: 9000, ritardo: Duration(minutes: 8), livello: 3),
        const Coda(daM: 20000, aM: 26000, ritardo: Duration(minutes: 10)),
      ]);
      await mostra(tester, strisciaTraffico(p, percorsiM: 0)!);
      expect(find.byKey(const Key('striscia-traffico')), findsOneWidget);
      expect(find.text('+8 min'), findsOneWidget);
      expect(find.text('+10 min'), findsOneWidget);
      expect(find.text(distanzaBreve(4000)), findsOneWidget);
      expect(find.text(distanzaBreve(20000)), findsOneWidget);
      // La meta in cima: il viaggio sta tutto nella striscia.
      expect(find.byIcon(Icons.sports_score), findsOneWidget);
      expect(find.text('…'), findsNothing);
      // La coda ferma è rossa, l'altra arancio, ognuna sopra l'altra.
      final ferma = tester.getTopLeft(find.text('+8 min')).dy;
      final coda = tester.getTopLeft(find.text('+10 min')).dy;
      expect(ferma, greaterThan(coda));
      final ctx = tester.element(find.byKey(const Key('striscia-traffico')));
      expect(tester.widget<Text>(find.text('+8 min')).style?.color, ColoriGdanav.di(ctx).guasta);
      expect(tester.widget<Text>(find.text('+10 min')).style?.color, ColoriGdanav.di(ctx).piena);
    });

    testWidgets('dentro la coda dice «ci sei»; in un viaggio lungo in cima «…»', (tester) async {
      final p = dritta(300).conTraffico([const Coda(daM: 5000, aM: 12000, ritardo: Duration(minutes: 7))]);
      await mostra(tester, strisciaTraffico(p, percorsiM: 6000)!);
      expect(find.text('ci sei'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.byIcon(Icons.sports_score), findsNothing);
    });

    testWidgets('senza spazio non si mette', (tester) async {
      final p = dritta(40).conTraffico([const Coda(daM: 5000, aM: 12000, ritardo: Duration(minutes: 7))]);
      await mostra(tester, strisciaTraffico(p, percorsiM: 0)!, alto: 100);
      expect(find.text('+7 min'), findsNothing);
    });

    testWidgets('in guida sta di lato, scende con l\'auto e se ne va passata la coda', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(
        tester,
        km: 40,
        costruisci: _conTraffico(40, [const Coda(daM: 5000, aM: 12000, ritardo: Duration(minutes: 7))]),
      );
      await tester.pumpWidget(a.app());
      a.auto.manuale.imposta(90);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.36, 12))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'scheda');
      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'guida');
      expect(a.guida.attiva, isTrue);

      final striscia = find.byKey(const Key('striscia-traffico'));
      expect(striscia, findsOneWidget);
      expect(find.text('+7 min'), findsOneWidget);
      // Sul bordo destro, sotto gli avvisi e sopra il tachimetro.
      final r = tester.getRect(striscia);
      expect(r.right, greaterThan(tester.view.physicalSize.width / tester.view.devicePixelRatio - 20));
      expect(r.height, greaterThan(StrisciaTrafficoLaterale.altezzaMinima));

      Future<void> vai(Punto p) async {
        a.posizioni.add(p);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
      final primaY = tester.getTopLeft(find.text('+7 min')).dy;
      await vai(punti[1]);
      await vai(punti[3]);
      expect(find.text('+7 min'), findsOneWidget);
      expect(tester.getTopLeft(find.text('+7 min')).dy, greaterThan(primaY));

      await vai(punti[14]);
      expect(striscia, findsNothing);
      a.guida.ferma();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('senza code la striscia non c\'è', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 40);
      await tester.pumpWidget(a.app());
      a.auto.manuale.imposta(90);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.36, 12))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();
      expect(a.guida.attiva, isTrue);
      expect(find.byKey(const Key('striscia-traffico')), findsNothing);
      a.guida.ferma();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
