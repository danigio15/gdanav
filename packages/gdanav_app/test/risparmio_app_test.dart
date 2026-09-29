import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/schermate/strade_risparmio.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_risparmio.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/gestore_ztl.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Una strada finta lungo [punti], che dura [minuti] e consuma [kwh].
PercorsoCalcolato strada(List<Punto> punti, int minuti, double kwh) {
  final metri = Linea(punti).lunghezzaM;
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: metri, velocitaKmh: metri / (minuti * 60) * 3.6)],
    manovre: const [],
    consumoTomTom: kwh,
  );
}

/// Da [a] a [b], un punto ogni cinquecento metri circa.
List<Punto> dritto(Punto a, Punto b) {
  final n = (distanzaM(a, b) / 500).ceil().clamp(1, 1000);
  return [for (var i = 0; i <= n; i++) Punto(a.lat + (b.lat - a.lat) * i / n, a.lon + (b.lon - a.lon) * i / n)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nord = Luogo(nome: 'Nord', posizione: Punto(42.18, 12));

  /// TomTom finto: la strada di adesso rifatta (4 kWh) e, per la eco, una
  /// che gira a ovest (3,4 kWh, tre minuti in più). Per le più rapide, una a
  /// est che fa arrivare sei minuti prima.
  late List<bool> chieste;
  late ArchivioZtl? zoneFinte;
  Future<List<PercorsoCalcolato>> strade(
    List<Punto> davanti, {
    required bool eco,
    ModelloConsumoTomTom? consumo,
    List<Rettangolo> evita = const [],
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) async {
    chieste.add(eco);
    expect(consumo, isNotNull, reason: 'il modello di consumo va sempre a TomTom');
    final da = davanti.first, a = davanti.last;
    final adesso = strada(davanti, 10, 4);
    Punto via(double dLon) => Punto((da.lat + a.lat) / 2, da.lon + dLon);
    final giro = [...dritto(da, via(eco ? -0.02 : 0.02)), ...dritto(via(eco ? -0.02 : 0.02), a).skip(1)];
    return [adesso, eco ? strada(giro, 13, 3.4) : strada(giro, 4, 4.3)];
  }

  setUp(() {
    chieste = [];
    zoneFinte = null;
  });

  Future<Ambiente> inGuida(WidgetTester tester, {Duration durata = const Duration(seconds: 20)}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final ztl = GestoreZtl(Archivio(), zone: () async => zoneFinte ?? ArchivioZtl.vuoto);
    await tester.runAsync(ztl.carica);
    final a = await ambiente(tester, km: 20, strade: strade, ztl: ztl, durataProposta: durata);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(nord));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(const Punto(42.0, 12));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(a.guida.avanzamento, isNotNull);
    return a;
  }

  Future<void> confronta(WidgetTester tester, Ambiente a) async {
    await tester.runAsync(a.guida.controllaStrade);
    await tester.pump();
  }

  testWidgets('in guida: la strada che risparmia, sulla scheda coi due tasti, e «Prendila» rifà il viaggio lì', (
    tester,
  ) async {
    final a = await inGuida(tester);
    await confronta(tester, a);
    // Senza code davanti si chiede solo la strada eco: niente quota sprecata.
    expect(chieste, [true]);
    final p = a.risparmio!.proposta!;
    expect(p.motivo, MotivoProposta.risparmio);
    expect(p.risparmio, closeTo(0.6, 0.001));
    expect(find.byKey(const Key('proposta-strada')), findsOneWidget);
    expect(find.text('C\'è una strada che risparmia energia'), findsOneWidget);
    expect(find.text('−0,6 kWh'), findsOneWidget);
    expect(find.text('+3 min'), findsOneWidget);
    // La batteria all'arrivo, con la strada nuova: di più.
    final arrivo = a.guida.batteriaArrivo!;
    expect(a.guida.batteriaArrivoCon(p)!, greaterThan(arrivo));
    expect(
      find.textContaining('Arrivi con il ${a.guida.batteriaArrivoCon(p)!.round()}% invece del ${arrivo.round()}%'),
      findsOneWidget,
    );
    expect(a.voce.frasi.last, 'C\'è una strada che risparmia energia, 3 minuti in più.');

    await tester.tap(find.byKey(const Key('prendi-strada')));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proposta-strada')), findsNothing);
    final dopo = (a.viaggio.stato as ViaggioPronto).viaggio.percorso;
    expect(dopo.punti, p.percorso.punti, reason: 'il viaggio ora va per la strada a ovest');
    expect(a.guida.attiva, isTrue);
    expect(a.voce.frasi, contains('Prendo la strada a risparmio.'));
  });

  testWidgets('«Resto qui»: la stessa strada non torna; e se non si tocca niente si chiude da sola', (tester) async {
    final a = await inGuida(tester, durata: const Duration(seconds: 2));
    await confronta(tester, a);
    expect(a.risparmio!.proposta, isNotNull);
    await tester.tap(find.byKey(const Key('resta-strada')));
    await tester.pump();
    expect(a.risparmio!.proposta, isNull);
    expect(find.byKey(const Key('proposta-strada')), findsNothing);

    // Cinque minuti dopo la stessa strada: niente.
    await confronta(tester, a);
    expect(a.risparmio!.proposta, isNull);
    expect(chieste, [true, true]);

    // Un viaggio nuovo la dimentica, e allora torna; lasciata scadere, si
    // chiude da sola e conta come rifiutata.
    a.risparmio!.dimentica();
    await confronta(tester, a);
    expect(a.risparmio!.proposta, isNotNull);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2200)));
    await tester.pump();
    expect(a.risparmio!.proposta, isNull);
    await confronta(tester, a);
    expect(a.risparmio!.proposta, isNull);
  });

  testWidgets('con le code davanti, anche la strada più rapida', (tester) async {
    final a = await inGuida(tester);
    // Il traffico ha messo una coda di otto minuti più avanti.
    final pronto = a.viaggio.stato as ViaggioPronto;
    a.viaggio.stato = ViaggioPronto(
      pronto.destinazione,
      Viaggio(
        percorso: pronto.viaggio.percorso.conTraffico([
          const Coda(daM: 8000, aM: 9000, ritardo: Duration(minutes: 8), livello: 3),
        ]),
        colonnine: pronto.viaggio.colonnine,
        piano: pronto.viaggio.piano,
      ),
      pronto.batteriaPartenza,
      calcolatoAlle: pronto.calcolatoAlle,
    );
    // Spenta la eco (sotto soglia), resta la rapida.
    await tester.runAsync(() => a.risparmio!.cambia(copiaSoglie(a.risparmio!.soglie, minimoPercento: 20)));
    await confronta(tester, a);
    expect(chieste, unorderedEquals([true, false]));
    final p = a.risparmio!.proposta!;
    expect(p.motivo, MotivoProposta.rapida);
    expect(find.text('C\'è una strada più rapida'), findsOneWidget);
    expect(find.text('−6 min'), findsOneWidget);
    expect(find.text('+0,3 kWh'), findsOneWidget);
    expect(a.voce.frasi.last, 'C\'è una strada più rapida: 6 minuti in meno.');
  });

  testWidgets('una strada che entrerebbe in una ZTL attiva senza permesso non si propone', (tester) async {
    // Proprio dove passa la strada eco, a ovest.
    zoneFinte = ArchivioZtl([
      ZonaLimitata(
        id: 'r1',
        tipo: TipoZona.ztl,
        nome: 'Centro',
        citta: 'Paese',
        anelli: [
          [
            const Punto(42.085, 11.97),
            const Punto(42.085, 11.99),
            const Punto(42.095, 11.99),
            const Punto(42.095, 11.97),
          ],
        ],
      ),
    ]);
    final a = await inGuida(tester);
    await confronta(tester, a);
    expect(chieste, [true]);
    expect(a.risparmio!.proposta, isNull);
  });

  testWidgets('spente nelle impostazioni, non si chiede niente a TomTom', (tester) async {
    final a = await inGuida(tester);
    await tester.runAsync(() => a.risparmio!.cambia(copiaSoglie(a.risparmio!.soglie, proponi: false)));
    await confronta(tester, a);
    expect(chieste, isEmpty);
    expect(a.risparmio!.proposta, isNull);
  });

  testWidgets('le impostazioni: si cambiano, e restano', (tester) async {
    preparaPiattaforma();
    final archivio = Archivio();
    final auto = GestoreAuto(archivio: archivio);
    await tester.runAsync(auto.avvia);
    addTearDown(auto.dispose);
    final r = GestoreRisparmio(archivio: archivio, auto: auto);
    await tester.runAsync(r.carica);
    await tester.pumpWidget(MaterialApp(home: StradeRisparmioSchermata(risparmio: r)));
    expect(find.text('Proponimele durante il viaggio'), findsOneWidget);
    expect(find.text('5 %'), findsOneWidget);
    expect(find.text('+10 min'), findsOneWidget);

    await tester.tap(find.byKey(const Key('risparmio-minimo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('minimo-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('risparmio-massimo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('massimo-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('risparmio-rapide')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('10 %'), findsOneWidget);
    expect(find.text('+5 min'), findsOneWidget);
    final letto = (await tester.runAsync(archivio.soglieRisparmio))!;
    expect(letto.minimoPercento, 10);
    expect(letto.massimoInPiu, const Duration(minutes: 5));
    expect(letto.ancheRapide, isFalse);
    expect(letto.proponi, isTrue);
    expect(riassuntoRisparmio(letto), 'Da 10 % in su, fino a +5 min');

    // Spente: le altre righe non si toccano più.
    await tester.tap(find.byKey(const Key('risparmio-proponi')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(r.soglie.proponi, isFalse);
    expect(riassuntoRisparmio(r.soglie), 'Spente');
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('risparmio-rapide'))).onChanged, isNull);
  });

  test('i numeri come si scrivono', () {
    expect(quantitaConSegno(-1.84, 'kWh'), '−1,8 kWh');
    expect(quantitaConSegno(0.31, 'l'), '+0,3 l');
    expect(minutiConSegno(const Duration(minutes: 4)), '+4 min');
    expect(minutiConSegno(const Duration(minutes: -6), meno: '-'), '-6 min');
    expect(minutiConSegno(const Duration(minutes: 65)), '+1 h 05');
    expect(minutiConSegno(const Duration(seconds: 20)), 'stesso tempo');
    final soglie = soglieDaJson(
      soglieJson(const SoglieRisparmio(minimoPercento: 15, massimoInPiu: Duration(minutes: 20), ancheRapide: false)),
    );
    expect(soglie.minimoPercento, 15);
    expect(soglie.massimoInPiu, const Duration(minutes: 20));
    expect(soglie.ancheRapide, isFalse);
    expect(soglie.proponi, isTrue);
  });

  test('sulla mappa: la strada verde e il fumetto dove si stacca di più', () {
    final adesso = strada(dritto(const Punto(42, 12), const Punto(42.18, 12)), 10, 4);
    final giro = [
      ...dritto(const Punto(42, 12), const Punto(42.09, 11.98)),
      ...dritto(const Punto(42.09, 11.98), const Punto(42.18, 12)).skip(1),
    ];
    final p = PropostaStrada(
      percorso: strada(giro, 13, 3.4),
      motivo: MotivoProposta.risparmio,
      consumo: 3.4,
      consumoAdesso: 4,
      differenza: const Duration(minutes: 3),
      firma: const {'x'},
    );
    final testo = sintesiProposta(p, 'kWh', meno: '-');
    expect(testo, '-0,6 kWh · +3 min');
    final elementi = (datiRisparmio(p, adesso, testo)['features']! as List).cast<Map<String, Object?>>();
    expect(elementi, hasLength(2));
    final fumetto = elementi.last;
    expect((fumetto['properties']! as Map)['etichetta'], '-0,6 kWh · +3 min');
    expect(((fumetto['geometry']! as Map)['coordinates']! as List).first, closeTo(11.98, 0.002));
    expect((datiRisparmio(null, adesso, '')['features']! as List), isEmpty);
  });
}
