import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/schermate/zone_ztl.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/avvisi_ztl.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/gestore_ztl.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Un quadrato dai lati [sud]…[nord] e [ovest]…[est].
List<Punto> riquadro(double sud, double ovest, double nord, double est) => [
  Punto(sud, ovest),
  Punto(sud, est),
  Punto(nord, est),
  Punto(nord, ovest),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // La strada finta va dritta a nord da (42, 12). La ZTL la attraversa poco
  // dopo la partenza; l'area pedonale le sta accanto.
  final zona = ZonaLimitata(
    id: 'r1',
    tipo: TipoZona.ztl,
    nome: 'Centro storico',
    citta: 'Napoli',
    anelli: [riquadro(42.047, 11.996, 42.053, 12.004)],
  );
  final pedonale = ZonaLimitata(
    id: 'w9',
    tipo: TipoZona.pedonale,
    nome: 'Piazza',
    anelli: [riquadro(42.1, 12.0002, 42.101, 12.001)],
  );
  const bologna = Luogo(nome: 'Bologna', descrizione: 'Emilia-Romagna', posizione: Punto(44.49, 11.34));

  /// Il percorso come lo darebbe il calcolo con le ZTL: senza risposta la
  /// evita e chiede (passandoci 3 minuti in meno); col permesso ci passa.
  var chiesti = 0;
  CostruisciPianificatore conZtl(GestoreZtl ztl) =>
      (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async {
          chiesti++;
          final p = dritta(20);
          final si = ztl.permessi[zona.chiave];
          return p.conZtl(
            si == true
                ? ZtlDelViaggio(attraversate: [zona], pedonali: [pedonale])
                : ZtlDelViaggio(
                    evitate: [zona],
                    daChiedere: si == null ? zona : null,
                    puntiPassandoci: si == null ? p.punti : const [],
                    durataPassandoci: si == null ? p.durata - const Duration(minutes: 3) : null,
                    pedonali: [pedonale],
                  ),
          );
        },
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      );

  Future<(Ambiente, GestoreZtl)> conViaggio(WidgetTester tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final ztl = GestoreZtl(Archivio(), zone: () async => ArchivioZtl([zona, pedonale]));
    await tester.runAsync(ztl.carica);
    final a = await ambiente(tester, costruisci: conZtl(ztl), ztl: ztl);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    chiesti = 0;
    await tester.runAsync(() => a.viaggio.vaiA(bologna));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    return (a, ztl);
  }

  testWidgets('il foglio del percorso dice cosa evita, e chiede il permesso', (tester) async {
    final (_, ztl) = await conViaggio(tester);
    // La ZTL della domanda non ha anche la pastiglia: lo dice la domanda.
    expect(find.text('⛔ Evita la ZTL Centro storico'), findsNothing);
    expect(find.text('🚶 1 area pedonale'), findsOneWidget);
    expect(find.byKey(const Key('domanda-ztl')), findsOneWidget);
    expect(find.textContaining('Passandoci arrivi 3 minuti prima. Hai il permesso per entrare?'), findsOneWidget);
    expect(find.textContaining('⛔ ZTL Centro storico, attiva'), findsOneWidget);

    // «No, evitala»: si ricorda, e la domanda sparisce senza rifare niente.
    await scorriScheda(tester, volte: 1);
    await tester.tap(find.byKey(const Key('ztl-no')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(ztl.scelte.permessi[zona.chiave]?.si, isFalse);
    expect(ztl.scelte.permessi[zona.chiave]?.nome, 'Napoli · Centro storico');
    expect(find.byKey(const Key('domanda-ztl')), findsNothing);
    expect(find.text('⛔ Evita la ZTL Centro storico'), findsOneWidget);
    expect(chiesti, 1);
    // E resta anche dopo: l'archivio l'ha scritto.
    expect((await tester.runAsync(Archivio().scelteZtl))!.permessi[zona.chiave]?.si, isFalse);
  });

  testWidgets('«Sì, ho il permesso»: si rifà il percorso, che ci passa', (tester) async {
    final (a, ztl) = await conViaggio(tester);
    await scorriScheda(tester, volte: 1);
    await tester.tap(find.byKey(const Key('ztl-si')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(ztl.scelte.permessi[zona.chiave]?.si, isTrue);
    expect(chiesti, 2);
    expect((a.viaggio.stato as ViaggioPronto).viaggio.percorso.ztl?.attraversate.single.id, 'r1');
    expect(find.byKey(const Key('domanda-ztl')), findsNothing);
    expect(find.text('✅ Nella ZTL Centro storico col permesso'), findsOneWidget);
  });

  testWidgets('le impostazioni: sulla mappa, gli avvisi e i permessi da cambiare', (tester) async {
    preparaPiattaforma();
    final ztl = GestoreZtl(Archivio(), zone: () async => ArchivioZtl([zona]));
    await tester.runAsync(ztl.carica);
    await tester.pumpWidget(MaterialApp(home: ZoneZtlSchermata(ztl: ztl)));
    expect(find.textContaining('Ancora nessuna'), findsOneWidget);

    await tester.runAsync(() => ztl.rispondi(zona, true));
    await tester.pumpAndSettle();
    expect(find.text('Napoli · Centro storico'), findsOneWidget);
    expect(find.text('Hai il permesso: il percorso ci passa'), findsOneWidget);

    await tester.tap(find.text('Napoli · Centro storico'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(ztl.permessi[zona.chiave], isFalse);
    expect(find.text('Niente permesso: il percorso la evita quando è attiva'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ztl-mappa')));
    await tester.tap(find.byKey(const Key('ztl-avvisi')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(ztl.scelte.sullaMappa, isFalse);
    expect(ztl.scelte.avvisi, isFalse);
    final letto = (await tester.runAsync(Archivio().scelteZtl))!;
    expect(letto.sullaMappa, isFalse);
    expect(letto.permessi[zona.chiave]?.si, isFalse);

    // Scorsa via, la ZTL si dimentica: la prossima volta si richiede.
    await tester.drag(find.text('Napoli · Centro storico'), const Offset(-600, 0));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(ztl.scelte.permessi, isEmpty);
  });

  testWidgets('in guida, avvicinandosi a una ZTL attiva che il percorso evita, lo dice', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    // Accanto alla strada, venticinque metri a est: il percorso la sfiora.
    final accanto = ZonaLimitata(
      id: 'r2',
      tipo: TipoZona.ztl,
      nome: 'Chiaia',
      citta: 'Napoli',
      anelli: [riquadro(42.047, 12.0003, 42.053, 12.004)],
    );
    final ztl = GestoreZtl(Archivio(), zone: () async => ArchivioZtl([accanto]));
    await tester.runAsync(ztl.carica);
    final a = await ambiente(tester, km: 20, ztl: ztl);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    final avvisi = AvvisiZtl.di(a.guida, ztl);
    Future<void> vai(Punto p) async {
      a.posizioni.add(p);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    // Lontana: niente.
    await vai(const Punto(42.02, 12));
    expect(avvisi.avviso, isNull);
    // A trecento metri: «il percorso la evita».
    await vai(const Punto(42.044, 12));
    expect(avvisi.avviso?.titolo, 'ZTL Chiaia, attiva');
    expect(avvisi.avviso?.testo, 'Il percorso la evita');
    expect(avvisi.avviso!.metri, inInclusiveRange(200, 400));
    expect(find.byKey(const Key('avviso-ztl')), findsOneWidget);
    // Quella che si evita non si dice a voce: solo quella in cui si entra.
    expect(a.voce.frasi.where((f) => f.contains('ZTL')), isEmpty);
    // Passata: sparisce.
    await vai(const Punto(42.06, 12));
    expect(avvisi.avviso, isNull);

    // Spenti gli avvisi, niente anche tornando indietro.
    await tester.runAsync(() => ztl.avvisa(false));
    await vai(const Punto(42.044, 12));
    expect(avvisi.avviso, isNull);
  });

  test('sulla mappa: i contorni, lo stato e il nome; e la strada che passerebbe dentro', () {
    final orari = ZonaLimitata(
      id: 'r3',
      tipo: TipoZona.ztl,
      nome: 'Tridente',
      citta: 'Roma',
      orari: OrariZtl.leggi('Mo-Fr 06:30-18:00'),
      anelli: [riquadro(41.9, 12.47, 41.91, 12.48)],
    );
    final dati = datiZtl([orari, pedonale], DateTime(2026, 9, 29, 10));
    final elementi = (dati['features']! as List).cast<Map<String, Object?>>();
    final poligoni = [
      for (final e in elementi)
        if ((e['geometry']! as Map)['type'] == 'Polygon') e['properties']! as Map,
    ];
    expect(poligoni, [
      {'tipo': 'ztl', 'attiva': true},
      {'tipo': 'pedonale', 'attiva': true},
    ]);
    final nomi = [
      for (final e in elementi)
        if ((e['geometry']! as Map)['type'] == 'Point') (e['properties']! as Map)['etichetta'],
    ];
    expect(nomi, ['ZTL · attiva fino alle 18', 'Area pedonale']);
    // La sera è spenta fino al mattino dopo.
    final sera = datiZtl([orari], DateTime(2026, 9, 29, 20));
    expect(
      [for (final e in (sera['features']! as List).cast<Map<String, Object?>>()) (e['properties']! as Map)['etichetta']],
      contains('ZTL · non attiva fino alle 6:30'),
    );

    final p = dritta(20);
    final conDomanda = p.conZtl(
      ZtlDelViaggio(
        evitate: [zona],
        daChiedere: zona,
        puntiPassandoci: [for (final q in p.punti) Punto(q.lat, q.lon + 0.01)],
        durataPassandoci: p.durata - const Duration(minutes: 3),
      ),
    );
    final passandoci = (datiPassandoci(conDomanda)['features']! as List).cast<Map<String, Object?>>();
    expect(passandoci, hasLength(2));
    expect((passandoci.last['properties']! as Map)['etichetta'], '-3 min');
    // Senza domanda, niente strada a puntini.
    expect((datiPassandoci(p)['features']! as List), isEmpty);
  });

  test('le scelte si scrivono e si rileggono', () {
    final s = ScelteZtl.daJson(
      const ScelteZtl(
        sullaMappa: false,
        permessi: {'napoli|centro storico': PermessoZtl(si: true, nome: 'Napoli · Centro storico')},
      ).toJson(),
    );
    expect(s.sullaMappa, isFalse);
    expect(s.avvisi, isTrue);
    expect(s.permessi['napoli|centro storico']?.si, isTrue);
    expect(s.permessi['napoli|centro storico']?.nome, 'Napoli · Centro storico');
    expect(ScelteZtl.daJson(const {}).sullaMappa, isTrue);
  });
}
