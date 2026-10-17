// «Pianifica i viaggi»: dentro gdahome il pianificatore stava solo nel menu,
// e nessuno lo trovava. Adesso c'è una scheda sulla mappa, la voce del menu
// col nome nuovo, e chi ospita gdanav lo apre da fuori.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/pianifica_i_viaggi.dart';
import 'package:gdanav_app/schermate/pianificatore.dart';
import 'package:gdanav_app/schermate/premium.dart';
import 'package:gdanav_app/schermate/schermata_principale.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/stato/viaggi_pianificati.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

final _giovedi = DateTime(2026, 10, 15, 21); // giovedì sera: domani è venerdì 16

/// Casa – Lavoro, domani: arrivo entro le 8:30, si parte alle 7:59.
Map<String, Object?> _lavoro() => {
  'id': 'v_1',
  'utente': 'u1',
  'tipo': 'una',
  'nome': 'Casa – Lavoro',
  'da': null,
  'tappe': [
    {'nome': 'Ufficio', 'lat': 41.9, 'lon': 12.5},
  ],
  'quando': {'modo': 'arrivo', 'ora': '08:30', 'giorno': '2026-10-16', 'giorni': <int>[]},
  'avviso': {'acceso': true, 'minuti': 10},
  'prepara': {'clima': null, 'garage': null},
  'prossima': {
    'giorno': '2026-10-16',
    'partenza': DateTime(2026, 10, 16, 7, 59).millisecondsSinceEpoch,
    'arrivo': DateTime(2026, 10, 16, 8, 30).millisecondsSinceEpoch,
    'stimata': true,
  },
  'creatoIl': 1,
  'modificatoIl': 1,
};

/// Uno già passato: non si conta.
Map<String, Object?> _passato() => {
  ..._lavoro(),
  'id': 'v_0',
  'nome': 'Ieri',
  'quando': {'modo': 'arrivo', 'ora': '08:30', 'giorno': '2026-10-14', 'giorni': <int>[]},
  'prossima': null,
};

Future<GestoreViaggiPianificati> _gestore(WidgetTester tester, List<Map<String, Object?>> viaggi) async {
  final g = GestoreViaggiPianificati(
    FonteViaggiDellaCasa((c) async => {'sbloccato': true, 'viaggi': viaggi}),
    orologio: () => _giovedi,
  );
  await tester.runAsync(g.carica);
  return g;
}

Future<void> _monta(
  WidgetTester tester,
  Ambiente a,
  GestoreViaggiPianificati g, {
  GestorePremium? premium,
  ValueNotifier<bool>? apri,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: temaGdanav(Brightness.light),
      home: SchermataPrincipale(
        auto: a.auto,
        viaggio: a.viaggio,
        archivio: a.archivio,
        guida: a.guida,
        posizione: a.posizione,
        segnalazioni: a.segnalazioni,
        pianificati: g,
        premium: premium,
        apriIlPianificatore: apri,
        mappa: (_, _) => const ColoredBox(color: Colors.grey),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('in arrivo: solo quelli che devono ancora venire, dal più vicino', () {
    final viaggi = [ViaggioPianificato.daJson(_passato())!, ViaggioPianificato.daJson(_lavoro())!];
    final fila = viaggiInArrivo(viaggi, _giovedi);
    expect(fila, hasLength(1));
    expect(quandoParti(fila.first.$1, fila.first.$2, _giovedi), 'Domani · parti alle 7:59 · arrivo entro le 8:30');
  });

  testWidgets('sulla mappa: il prossimo viaggio, e toccandolo il pianificatore', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final g = await _gestore(tester, [_lavoro(), _passato()]);
    await _monta(tester, a, g);

    expect(find.text('PIANIFICA I VIAGGI · 1'), findsOneWidget);
    expect(find.text('Casa – Lavoro'), findsOneWidget);
    expect(find.text('Domani · parti alle 7:59 · arrivo entro le 8:30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheda-pianifica')));
    await tester.pumpAndSettle();
    expect(find.byType(SchermataPianificatore), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('senza viaggi la scheda resta, piccola, e porta al pianificatore', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final g = await _gestore(tester, []);
    await _monta(tester, a, g);

    expect(find.text('Pianifica i viaggi'), findsOneWidget);
    expect(find.text('Ti dico io quando partire, col traffico'), findsOneWidget);
    expect(find.byKey(const Key('scheda-pianifica-premium')), findsNothing);
    await tester.tap(find.byKey(const Key('scheda-pianifica')));
    await tester.pumpAndSettle();
    expect(find.byType(SchermataPianificatore), findsOneWidget);
  });

  testWidgets('senza Premium: il bollino, e si apre Premium', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final g = await _gestore(tester, [_lavoro()]);
    final premium = GestorePremium(archivio: Archivio(), tuttoSbloccato: false);
    await _monta(tester, a, g, premium: premium);

    expect(find.byKey(const Key('scheda-pianifica-premium')), findsOneWidget);
    expect(find.text('Casa – Lavoro'), findsNothing, reason: 'i viaggi sono di Premium');
    await tester.tap(find.byKey(const Key('scheda-pianifica')));
    await tester.pumpAndSettle();
    expect(find.byType(SchermataPremium), findsOneWidget);
    expect(find.byType(SchermataPianificatore), findsNothing);
  });

  testWidgets('con un viaggio aperto (e in guida) la scheda non c\'è', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final g = await _gestore(tester, [_lavoro()]);
    await _monta(tester, a, g);
    expect(find.byKey(const Key('scheda-pianifica')), findsOneWidget);

    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Bologna', posizione: Punto(44.49, 11.34))));
    await tester.pump();
    expect(find.byKey(const Key('scheda-pianifica')), findsNothing, reason: 'con un viaggio aperto si guarda quello');
  });

  testWidgets('il menu dice «Pianifica i viaggi», in cima al Viaggio', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final g = await _gestore(tester, [_lavoro()]);
    await _monta(tester, a, g);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final voce = find.byKey(const Key('menu-pianificatore'));
    expect(find.descendant(of: voce, matching: find.text('Pianifica i viaggi')), findsOneWidget);
    expect(find.text('Pianificatore'), findsNothing);
    final yVoce = tester.getTopLeft(voce).dy;
    expect(tester.getTopLeft(find.text('Percorso')).dy, greaterThan(yVoce));

    // Dal menu, che si chiude mentre il pianificatore si apre: niente
    // setState durante il build.
    await tester.tap(voce);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SchermataPianificatore), findsOneWidget);
  });

  testWidgets('chi ospita gdanav apre il pianificatore da fuori', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final g = await _gestore(tester, [_lavoro()]);
    // Chiesto prima che la schermata ci sia: si apre appena c'è.
    final apri = ValueNotifier(true);
    await _monta(tester, a, g, apri: apri);
    await tester.pumpAndSettle();
    expect(find.byType(SchermataPianificatore), findsOneWidget);
    expect(apri.value, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SchermataPianificatore), findsNothing);
    apri.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(SchermataPianificatore), findsOneWidget);
  });
}
