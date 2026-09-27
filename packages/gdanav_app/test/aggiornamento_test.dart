import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/schermate/aggiorna_gdanav.dart';
import 'package:gdanav_app/servizi.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_aggiornamento.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'aiuti.dart';

/// Il relay finto: risponde con [minima], o non risponde.
MockClient relay(int? minima, {List<Uri>? chieste}) => MockClient((r) async {
  chieste?.add(r.url);
  if (minima == null) throw http.ClientException('niente rete');
  return http.Response('{"gdanav":{"minima":$minima}}', 200);
});

GestoreAggiornamento gestore(int costruzione, http.Client client, {bool debug = false}) =>
    GestoreAggiornamento(archivio: Archivio(), client: client, costruzione: costruzione, debug: debug);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(preparaPiattaforma);

  test('una build più vecchia della minima si blocca', () async {
    final chieste = <Uri>[];
    final g = gestore(40, relay(50, chieste: chieste));
    await g.controlla();
    expect(g.minima, 50);
    expect(g.daAggiornare, isTrue);
    expect(chieste.single.toString(), 'https://gdanav.gdahome.org/v1/versioni');
  });

  test('la minima stessa e le più nuove vanno', () async {
    for (final c in [50, 51]) {
      final g = gestore(c, relay(50));
      await g.controlla();
      expect(g.daAggiornare, isFalse, reason: 'build $c');
    }
  });

  test('spento di base: minima 0 non blocca nessuno', () async {
    final g = gestore(1, relay(0));
    await g.controlla();
    expect(g.daAggiornare, isFalse);
  });

  test('le build a mano (0) e quelle di debug non si bloccano mai', () async {
    final aMano = gestore(0, relay(999));
    await aMano.controlla();
    expect(aMano.daAggiornare, isFalse);
    final debug = gestore(3, relay(999), debug: true);
    await debug.controlla();
    expect(debug.daAggiornare, isFalse);
    // Senza dart-define la build è 0.
    expect(Servizi.costruzione, 0);
  });

  test('senza rete resta bloccata: la minima si ricorda', () async {
    await gestore(40, relay(50)).controlla();
    final dopo = gestore(40, relay(null));
    await dopo.carica();
    expect(dopo.daAggiornare, isTrue);
    await dopo.controlla();
    expect(dopo.daAggiornare, isTrue);
  });

  test('il relay può anche sbloccare, abbassando la minima', () async {
    await gestore(40, relay(50)).controlla();
    final g = gestore(40, relay(0));
    await g.carica();
    expect(g.daAggiornare, isTrue);
    await g.controlla();
    expect(g.daAggiornare, isFalse);
    expect(await Archivio().versioneMinima(), 0);
  });

  test('risposte strane non cambiano niente', () async {
    await gestore(40, relay(50)).controlla();
    for (final (stato, corpo) in [
      (200, 'non json'),
      (200, '{"gdanav":{"minima":"70"}}'),
      (200, '{"gdanav":{"minima":-1}}'),
      (200, '[]'),
      (500, '{"gdanav":{"minima":0}}'),
    ]) {
      final g = GestoreAggiornamento(
        archivio: Archivio(),
        client: MockClient((_) async => http.Response(corpo, stato)),
        costruzione: 40,
        debug: false,
      );
      await g.carica();
      await g.controlla();
      expect(g.minima, 50, reason: corpo);
    }
  });

  test('dentro gdahome non si controlla: ci pensa lei', () {
    final a = Archivio();
    expect(GestoreAggiornamento.per(archivio: a, premiumOspite: ValueNotifier(true)), isNull);
    expect(GestoreAggiornamento.per(archivio: a, senzaPremium: true), isNull);
    expect(GestoreAggiornamento.per(archivio: a, gdahome: Object()), isNull);
    expect(GestoreAggiornamento.per(archivio: a, client: relay(0)), isNotNull);
  });

  testWidgets('chiede all\'avvio e tornando in primo piano, non troppo spesso', (tester) async {
    final chieste = <Uri>[];
    var ora = DateTime(2026, 9, 27, 8);
    final g = GestoreAggiornamento(
      archivio: Archivio(),
      client: relay(50, chieste: chieste),
      costruzione: 40,
      debug: false,
      orologio: () => ora,
    );
    addTearDown(g.dispose);
    await tester.runAsync(() async {
      await g.avvia();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(chieste, hasLength(1));
    expect(g.daAggiornare, isTrue);
    void primoPiano() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    ora = ora.add(const Duration(minutes: 2));
    await tester.runAsync(() async => primoPiano());
    expect(chieste, hasLength(1));
    ora = ora.add(const Duration(minutes: 15));
    await tester.runAsync(() async {
      primoPiano();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(chieste, hasLength(2));
  });

  test('il negozio giusto per il telefono', () {
    expect(indirizziNegozio(TargetPlatform.android).map((u) => '$u'), [
      'market://details?id=it.gdanav.gdanav',
      'https://play.google.com/store/apps/details?id=it.gdanav.gdanav',
    ]);
    expect(indirizziNegozio(TargetPlatform.iOS).first.scheme, 'itms-apps');
  });

  testWidgets('bloccata: al posto di tutto la schermata per aggiornare', (tester) async {
    final a = await ambiente(tester);
    final g = gestore(40, relay(50));
    addTearDown(g.dispose);
    await tester.pumpWidget(
      GdanavApp(
        archivio: a.archivio,
        auto: a.auto,
        viaggio: a.viaggio,
        guida: a.guida,
        posizione: a.posizione,
        aggiornamento: g,
        mappa: (_, _) => const ColoredBox(color: Colors.grey),
      ),
    );
    await tester.pump();
    expect(find.byType(SchermataAggiorna), findsNothing);

    await tester.runAsync(g.controlla);
    await tester.pump();
    expect(find.text(SchermataAggiorna.titolo), findsOneWidget);
    expect(find.byKey(const Key('aggiorna-negozio')), findsOneWidget);
    // Solo il negozio: nessun altro bottone.
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('il bottone apre il negozio della piattaforma, e basta', (tester) async {
    final aperti = <List<Uri>>[];
    await tester.pumpWidget(MaterialApp(home: SchermataAggiorna(apri: (u) async => aperti.add(u))));
    expect(find.text('Aggiorna dal Play Store'), findsOneWidget);
    expect(find.textContaining('GitHub'), findsNothing);
    expect(find.textContaining('APK'), findsNothing);
    await tester.tap(find.byKey(const Key('aggiorna-negozio')));
    expect(aperti.single.first.toString(), 'market://details?id=it.gdanav.gdanav');

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(MaterialApp(home: SchermataAggiorna(key: UniqueKey(), apri: (u) async => aperti.add(u))));
      expect(find.text('Aggiorna dall\'App Store'), findsOneWidget);
      await tester.tap(find.byKey(const Key('aggiorna-negozio')));
      expect(aperti.last.first.scheme, 'itms-apps');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets("l'auto sa che va aggiornata, e senza Premium", (tester) async {
    const canale = MethodChannel('gdanav/schermo_auto_prova');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale);
    ponte.premium(true, aggiorna: true);
    ponte.premium(true);
    await tester.pump();
    expect(chiamate.map((c) => c.arguments), [
      {'sbloccato': false, 'ospite': false, 'aggiorna': true},
      {'sbloccato': true, 'ospite': false, 'aggiorna': false},
    ]);
  });
}
