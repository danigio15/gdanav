import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Key;
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/voce.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Ambiente> inViaggio(WidgetTester tester, {int km = 20, Future<Punto?> Function()? dove}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: km, dove: dove);
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

  /// Finché il ricalcolo in corso non è finito, bene o male.
  Future<void> finisceIlRicalcolo(WidgetTester tester, Ambiente a) async {
    for (var i = 0; i < 20 && a.guida.ricalcolando; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('un ricalcolo che cade non spegne i ricalcoli: alla posizione dopo fuori strada si riprova', (
    tester,
  ) async {
    // Il GPS che una volta non risponde: pianifica non arriva a calcolare, e
    // l'errore esce.
    var cade = false;
    final a = await inViaggio(
      tester,
      dove: () async {
        if (cade) {
          cade = false;
          throw PlatformException(code: 'gps', message: 'il GPS non risponde');
        }
        return const Punto(42, 12);
      },
    );
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final primo = (a.viaggio.stato as ViaggioPronto).viaggio;
    int detti() => a.voce.frasi.where((f) => f == 'Ricalcolo il percorso.').length;

    cade = true;
    const lontano = Punto(42.05, 12.05); // ~4 km a est
    // Due letture fuori strada bastano per ricalcolare.
    for (var i = 0; i < 2; i++) {
      await vai(tester, a, lontano);
    }
    await finisceIlRicalcolo(tester, a);
    expect(detti(), 1);
    expect(a.guida.ricalcolando, isFalse);
    expect((a.viaggio.stato as ViaggioPronto).viaggio, same(primo));

    // Ancora fuori strada: si riprova, e stavolta il percorso nuovo arriva.
    await vai(tester, a, lontano);
    await finisceIlRicalcolo(tester, a);
    expect(detti(), 2);
    expect(a.guida.ricalcolando, isFalse);
    expect((a.viaggio.stato as ViaggioPronto).viaggio, isNot(same(primo)));
  });

  testWidgets('una guida nuova parte senza l\'avanzamento di quella prima', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    await vai(tester, a, punti[2]);
    expect(a.guida.avanzamento, isNotNull);
    await tester.runAsync(a.guida.ferma);
    a.guida.avvia();
    expect(a.guida.avanzamento, isNull);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('«Fine» chiude la guida', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fine'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(a.guida.attiva, isFalse);
    expect(find.text('Dove andiamo?'), findsOneWidget);
  });

  testWidgets('la voce si silenzia', (tester) async {
    final a = await inViaggio(tester);
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('audio')));
    await tester.pump();
    expect(a.guida.muto, isTrue);
    expect(a.guida.audio, ModoAudio.soloAvvisi);
    expect(await a.archivio.voceMuta(), isTrue);
    final prima = a.voce.frasi.length;
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    await vai(tester, a, punti.last);
    expect(a.voce.frasi.length, prima);
    await tester.pumpAndSettle();
  });
}
