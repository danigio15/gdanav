import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Ambiente> inViaggio(WidgetTester tester, {int km = 20}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: km);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    return a;
  }

  Future<void> vai(WidgetTester tester, Ambiente a, Punto p) async {
    a.posizioni.add(p);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  testWidgets('«Avvia» apre la guida, che segue la posizione e arriva', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    expect(a.guida.attiva, isTrue);
    expect(find.text('Fine'), findsOneWidget);

    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    await vai(tester, a, punti[2]);
    expect(a.guida.avanzamento!.restantiM, closeTo(Linea(punti).lunghezzaM - Linea(punti).cumulate[2], 1));
    expect(find.textContaining(' km'), findsWidgets);

    await vai(tester, a, punti.last);
    await tester.pumpAndSettle();
    expect(a.guida.attiva, isFalse);
    expect(a.voce.frasi, contains('Sei arrivato.'));
  });

  testWidgets('uscendo di strada si ricalcola', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final primo = (a.viaggio.stato as ViaggioPronto).viaggio;
    const lontano = Punto(42.05, 12.05); // ~4 km a est
    for (var i = 0; i < 3; i++) {
      await vai(tester, a, lontano);
    }
    for (var i = 0; i < 20 && identical((a.viaggio.stato as dynamic).viaggio, primo); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(a.voce.frasi, contains('Ricalcolo il percorso.'));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect((a.viaggio.stato as ViaggioPronto).viaggio, isNot(same(primo)));
  });

  testWidgets('«Fine» chiude la guida', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fine'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(a.guida.attiva, isFalse);
    expect(find.text('Dove vuoi andare?'), findsOneWidget);
  });

  testWidgets('la voce si silenzia', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Silenzia la voce'));
    await tester.pump();
    expect(a.guida.muto, isTrue);
    final prima = a.voce.frasi.length;
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    await vai(tester, a, punti.last);
    expect(a.voce.frasi.length, prima);
    await tester.pumpAndSettle();
  });
}
