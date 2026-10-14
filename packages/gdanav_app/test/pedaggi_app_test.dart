import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// [dritta] di [km], a pagamento dal km [da] al km [a].
PercorsoCalcolato aPagamento(int km, {required double da, required double a}) {
  final d = dritta(km);
  return PercorsoCalcolato(
    punti: d.punti,
    tratti: d.tratti,
    manovre: d.manovre,
    limiti: d.limiti,
    conPedaggi: true,
    conAutostrade: true,
    pedaggi: [TrattoPedaggio(daM: da * 1000, aM: a * 1000, paese: 'ITA')],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bologna = Luogo(nome: 'Bologna', descrizione: 'Emilia-Romagna', posizione: Punto(44.49, 11.34));

  // L'autostrada (250 km, 100 a pagamento) è la più rapida; la statale
  // (300 km) non ha pedaggi.
  var chiesti = 0;
  CostruisciPianificatore dueStrade() =>
      (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (t) async {
          chiesti++;
          return aPagamento(250, da: 20, a: 120);
        },
        alternative: (da, a) async {
          chiesti++;
          return [aPagamento(250, da: 20, a: 120), dritta(300)];
        },
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      );

  testWidgets('le strade come in Waze: il pedaggio di quella che lo ha, «Senza pedaggi» sull\'altra', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: dueStrade());
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();

    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.scelte, hasLength(2));
    expect(pronto.viaggio.percorso.conPedaggi, isTrue);
    // 100 km × 0,08 €/km: nel riepilogo e sulla carta della strada.
    expect(find.byKey(const Key('riga-pedaggio')), findsOneWidget);
    expect(find.text('Pedaggio ~8,00 €'), findsOneWidget);
    expect(find.text('~8,00 €'), findsOneWidget);
    expect(find.text('100 km a pagamento · classe A · stimato'), findsOneWidget);
    await scorriScheda(tester, volte: 1);
    expect(find.text('Senza pedaggi'), findsOneWidget);
    expect(find.text('~8,00 €'), findsOneWidget);

    // Scelta la statale, il riepilogo dice che non si paga.
    await tester.tap(find.byKey(const Key('strada-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect((a.viaggio.stato as ViaggioPronto).scelta, 1);
    expect(find.text('Senza pedaggi'), findsNWidgets(2));
  });

  testWidgets('la classe del veicolo cambia il prezzo, senza rifare il percorso', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: dueStrade());
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();
    final prima = chiesti;

    await tester.runAsync(() => a.viaggio.cambiaOpzioni(a.viaggio.opzioni.copia(classePedaggio: ClassePedaggio.tre)));
    await tester.pumpAndSettle();
    expect(chiesti, prima);
    // 100 km × 0,08 × 1,30.
    expect(find.text('Pedaggio ~10,40 €'), findsOneWidget);
    expect(find.text('100 km a pagamento · classe 3 · stimato'), findsOneWidget);
    // E resta salvata.
    expect((await a.archivio.opzioniPercorso()).classePedaggio, ClassePedaggio.tre);
  });

  testWidgets('dalle opzioni: classe e tariffa', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: dueStrade());
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('riga-pedaggio')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('tariffa-piu')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('tariffa-piu')));
    await tester.pumpAndSettle();
    expect(a.viaggio.opzioni.euroAlKm, closeTo(0.085, 1e-9));
    expect(find.text('0,085 € al km in classe A'), findsOneWidget);
  });

  testWidgets('in guida: il pedaggio che resta, e niente dopo il casello', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: dueStrade());
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    expect(a.guida.pedaggioDavanti?.euro, 8.0);
    // Accanto ai km che restano.
    expect(
      find.descendant(of: find.byKey(const Key('restanti')), matching: find.text('~8,00 €')),
      findsOneWidget,
    );

    // Oltre il km 120 l'autostrada è finita.
    a.posizioni.add(const Punto(42 + 130 * 0.009, 12));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(a.guida.pedaggioDavanti?.senzaPedaggi, isTrue);
    expect(find.byKey(const Key('pedaggio-restante')), findsNothing);
    await tester.runAsync(a.guida.ferma);
    await tester.pumpWidget(const SizedBox());
  });
}
