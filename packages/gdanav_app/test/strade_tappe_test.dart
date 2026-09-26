import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bologna = Luogo(nome: 'Bologna', descrizione: 'Emilia-Romagna', posizione: Punto(44.49, 11.34));
  const firenze = Luogo(nome: 'Firenze', descrizione: 'Toscana', posizione: Punto(43.77, 11.25));
  const siena = Luogo(nome: 'Siena', descrizione: 'Toscana', posizione: Punto(43.32, 11.33));

  // Due strade: la corta ha una coda di 20 minuti, e diventa la più lenta.
  final chiesti = <List<Punto>>[];
  CostruisciPianificatore conAlternative() =>
      (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (t) async {
          chiesti.add(t);
          return dritta(300);
        },
        alternative: (da, a) async => [dritta(250), dritta(300)],
        traffico: (p) async => p.lunghezzaM < 260000
            ? p.conTraffico([Coda(daM: 1000, aM: 30000, ritardo: const Duration(minutes: 40), livello: 3)])
            : p.conTraffico(const []),
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      );

  testWidgets('le strade: col traffico la più veloce prima, e se ne sceglie un\'altra', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: conAlternative());
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();

    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.scelte, hasLength(2));
    expect(pronto.scelte.first.lunghezzaM, greaterThan(290000));
    expect(pronto.scelte.last.ritardoTraffico, const Duration(minutes: 40));
    expect(find.byKey(const Key('strada-1')), findsOneWidget);
    expect(find.text('La più veloce'), findsOneWidget);
    expect(find.byKey(const Key('traffico')), findsOneWidget);

    await scorriScheda(tester, volte: 1);
    await tester.tap(find.byKey(const Key('strada-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final dopo = a.viaggio.stato as ViaggioPronto;
    expect(dopo.scelta, 1);
    expect(dopo.viaggio.percorso.ritardoTraffico, const Duration(minutes: 40));
    expect(find.textContaining('40 min di traffico'), findsOneWidget);
  });

  testWidgets('le tappe: si aggiungono, si tolgono, e il percorso passa da tutte', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: conAlternative());
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(siena));
    await tester.pumpAndSettle();
    chiesti.clear();

    await tester.runAsync(() => a.viaggio.aggiungiTappa(bologna));
    await tester.runAsync(() => a.viaggio.aggiungiTappa(firenze));
    await tester.pumpAndSettle();
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.tappe.map((t) => t.nome), ['Bologna', 'Firenze']);
    // Con le tappe niente alternative: un percorso che passa da tutte.
    expect(pronto.scelte, isEmpty);
    expect(chiesti.last, hasLength(4));
    expect(chiesti.last[1], bologna.posizione);
    expect(find.text('Firenze'), findsOneWidget);

    await tester.runAsync(() => a.viaggio.spostaTappa(1, 0));
    expect((a.viaggio.stato as ViaggioPronto).tappe.first.nome, 'Firenze');

    await scorriScheda(tester, volte: 1);
    await tester.tap(find.byKey(const Key('togli-tappa-0')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect((a.viaggio.stato as ViaggioPronto).tappe.map((t) => t.nome), ['Bologna']);

    // In guida, raggiunta la tappa, si va verso la meta.
    a.viaggio.tappeFatte(const Punto(44.4901, 11.3401));
    expect(a.viaggio.tappe, isEmpty);
  });

  testWidgets('in guida il traffico si rilegge: arrivo e code nuove, e se cambia tanto lo si dice', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 100);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();
    a.guida.avvia();
    a.posizioni.add(const Punto(42.1, 12));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    final prima = a.guida.arrivoAlle!;

    a.viaggio.trafficoFinto = (p) async =>
        p.conTraffico([Coda(daM: 60000, aM: 80000, ritardo: const Duration(minutes: 25), livello: 3)]);
    await tester.runAsync(a.guida.aggiornaTraffico);
    a.posizioni.add(const Punto(42.101, 12));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.viaggio.percorso.code, hasLength(1));
    expect(a.guida.arrivoAlle!.difference(prima).inMinutes, greaterThanOrEqualTo(14));
    expect(a.voce.frasi.last, contains('25 minuti in più'));

    // La coda sparisce: il ritardo torna a zero, non si somma.
    a.viaggio.trafficoFinto = (p) async => p.conTraffico(const []);
    await tester.runAsync(a.guida.aggiornaTraffico);
    expect((a.viaggio.stato as ViaggioPronto).viaggio.percorso.ritardoTraffico, Duration.zero);
    expect(a.voce.frasi.last, contains('alleggerito'));
    await tester.runAsync(a.guida.ferma);
  });
}
