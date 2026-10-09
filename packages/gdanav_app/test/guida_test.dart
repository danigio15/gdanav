import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Key;
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/voce.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Ambiente> inViaggio(
    WidgetTester tester, {
    int km = 20,
    Future<Punto?> Function()? dove,
    CostruisciPianificatore? costruisci,
  }) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: km, dove: dove, costruisci: costruisci);
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
    // Il server dei percorsi che una volta non risponde: il ricalcolo cade, e
    // la guida resta sul viaggio di prima.
    var cade = false;
    final a = await inViaggio(
      tester,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async {
          if (cade) {
            cade = false;
            throw const ErrorePercorso('il server dei percorsi non risponde');
          }
          return dritta(20);
        },
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
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

  testWidgets('fuori strada si ricalcola da dove si è: niente GPS nuovo, e il viaggio resta sullo schermo', (
    tester,
  ) async {
    var chiesteAlGps = 0;
    final arriva = Completer<void>();
    var inAttesa = false;
    final tappe = <List<Punto>>[];
    final a = await inViaggio(
      tester,
      dove: () async {
        chiesteAlGps++;
        return const Punto(42, 12);
      },
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (t) async {
          tappe.add(t);
          if (inAttesa) await arriva.future;
          return dritta(20);
        },
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final primo = a.viaggio.stato as ViaggioPronto;
    final gps = chiesteAlGps;
    inAttesa = true;
    const lontano = PuntoInMoto(42.05, 12.05, rotta: 90, velocitaMs: 14);
    for (var i = 0; i < 2; i++) {
      await vai(tester, a, lontano);
    }
    expect(a.guida.ricalcolando, isTrue);
    // Mentre si calcola, il viaggio di prima è ancora lì: linea e scheda.
    expect(a.viaggio.stato, same(primo));
    arriva.complete();
    await finisceIlRicalcolo(tester, a);
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect(a.viaggio.stato, isNot(same(primo)));
    expect(chiesteAlGps, gps, reason: 'la posizione la guida ce l\'ha già');
    // Il percorso parte da dove si è, col verso in cui si va.
    expect(tappe.last.first, isA<PuntoInMoto>());
    expect((tappe.last.first as PuntoInMoto).rotta, 90);
    await tester.runAsync(a.guida.ferma);
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
