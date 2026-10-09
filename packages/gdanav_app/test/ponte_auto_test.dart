import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/stato/gestore_luoghi.dart';
import 'package:gdanav_app/stato/gestore_meteo.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:geolocator/geolocator.dart' show Position;

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  testWidgets("lo schermo dell'auto riceve stile, viaggio, guida e segnaposto; «Fine» dall'auto ferma", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
    final stili = chiamate.firstWhere((c) => c.method == 'stili').arguments as Map;
    expect((jsonDecode(stili['chiaro'] as String) as Map)['name'], 'gdanav chiaro');
    expect((jsonDecode(stili['scuro'] as String) as Map)['name'], 'gdanav scuro');

    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pump();
    final sorgenti = chiamate.lastWhere((c) => c.method == 'sorgenti').arguments as Map;
    final percorso = jsonDecode((sorgenti['dati'] as Map)['gdanav-percorso'] as String) as Map;
    expect((percorso['features'] as List), hasLength(1));

    a.guida.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[3]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    final guida = chiamate.lastWhere((c) => c.method == 'guida').arguments as Map;
    expect(guida['attiva'], isTrue);
    expect(guida['destinazione'], 'Nord');
    expect(guida['restanti'] as double, lessThan(Linea(punti).lunghezzaM));
    final pos = chiamate.lastWhere((c) => c.method == 'posizione').arguments as Map;
    expect(pos['lat'], isNotNull);
    // Il segnaposto lo fa scorrere l'auto: arrivano immagine e rotta.
    expect(pos['icona'], 'auto_blu');
    expect(pos['rotta_io'], isA<double>());

    // Dall'auto si cambia la batteria all'arrivo: si salva e si ricalcola.
    await tester.runAsync(
      () => messaggero.handlePlatformMessage(
        'gdanav/schermo_auto',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('opzioni', {'arrivo': 25})),
        (_) {},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(a.viaggio.minimoArrivo, 25);
    expect((await a.viaggio.archivio.preferenze()).minimoArrivo, 25);
    expect((chiamate.lastWhere((c) => c.method == 'opzioni').arguments as Map)['arrivo'], 25);

    // L'auto preme «Fine».
    await tester.runAsync(
      () => messaggero.handlePlatformMessage(
        'gdanav/schermo_auto',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('ferma')),
        (_) {},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(a.guida.attiva, isFalse);
    expect((chiamate.lastWhere((c) => c.method == 'guida').arguments as Map)['attiva'], isFalse);
  });

  testWidgets("dall'auto si cerca, si sceglie Casa o un risultato e la guida parte da sola", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    final luoghi = GestoreLuoghi(a.archivio);
    await tester.runAsync(luoghi.carica);
    await tester.runAsync(
      () => luoghi.salva(Preferito(TipoPreferito.casa, const Luogo(nome: 'Via Roma 1', posizione: Punto(42.1, 12)))),
    );
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, luoghi: luoghi, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
    final elenco = (chiamate.lastWhere((c) => c.method == 'luoghi').arguments as Map)['elenco'] as List;
    expect(elenco.first, containsPair('etichetta', 'Casa'));
    expect(elenco.first, containsPair('tipo', 'casa'));

    Future<Object?> dallAuto(String metodo, Object? argomenti) async {
      Object? risposta;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall(metodo, argomenti)),
          (dati) => risposta = dati == null ? null : const StandardMethodCodec().decodeEnvelope(dati),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      return risposta;
    }

    final trovati = await dallAuto('cerca', {'testo': 'bologna'}) as List;
    expect(trovati.single, containsPair('nome', 'Bologna'));

    a.auto.manuale.imposta(90);
    await dallAuto('vai', elenco.first);
    expect(a.viaggio.destinazione!.nome, 'Via Roma 1');
    expect(a.guida.attiva, isTrue);
    expect((chiamate.lastWhere((c) => c.method == 'guida').arguments as Map)['attiva'], isTrue);
    expect(
      chiamate.where((c) => c.method == 'messaggio').map((c) => (c.arguments as Map)['testo']),
      contains('Calcolo il percorso per Via Roma 1…'),
    );

    await dallAuto('ferma', null);
    expect(a.guida.attiva, isFalse);
    expect(a.viaggio.stato, isA<NessunViaggio>());
  });

  testWidgets("sull'auto: cruscotto e meteo; Casa, opzioni e voce si cambiano dall'auto", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    final luoghi = GestoreLuoghi(a.archivio);
    await tester.runAsync(luoghi.carica);
    final meteo = GestoreMeteo(viaggio: a.viaggio, fonte: MeteoFinto(7));
    addTearDown(meteo.dispose);
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      luoghi: luoghi,
      auto: a.auto,
      meteo: meteo,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();

    Future<Object?> dallAuto(String metodo, Object? argomenti) async {
      Object? risposta;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall(metodo, argomenti)),
          (dati) => risposta = dati == null ? null : const StandardMethodCodec().decodeEnvelope(dati),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      return risposta;
    }

    Map<Object?, Object?> ultima(String metodo) => chiamate.lastWhere((c) => c.method == metodo).arguments as Map;

    // Batteria e autonomia anche da fermi.
    a.auto.manuale.imposta(80);
    await tester.pump();
    expect(ultima('cruscotto')['batteria'], 80);
    expect(ultima('cruscotto')['autonomia_km'], isNotNull);

    // In viaggio: la batteria all'arrivo e il meteo all'arrivo.
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    a.guida.avvia();
    a.posizioni.add((a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti[3]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final c = ultima('cruscotto');
    expect(c['arrivo_batteria'], isNotNull);
    expect(c['meteo_temperatura'], 7);
    expect(c['meteo_dove'], "all'arrivo");

    // Lavoro salvato dall'auto.
    expect(
      await dallAuto('imposta', {
        'tipo': 'lavoro',
        'luogo': {'nome': 'Ufficio', 'descrizione': 'Via Milano 3', 'lat': 42.2, 'lon': 12.1},
      }),
      isTrue,
    );
    expect(luoghi.lavoro!.luogo.nome, 'Ufficio');
    expect((ultima('luoghi')['elenco'] as List).first, containsPair('tipo', 'lavoro'));

    // Opzioni e voce dall'auto.
    await dallAuto('opzioni', {'pedaggi': true, 'modo': 'risparmio'});
    expect(a.viaggio.opzioni.evitaPedaggi, isTrue);
    expect(a.viaggio.opzioni.modo, ModoGuida.risparmio);
    expect(ultima('opzioni'), containsPair('pedaggi', true));
    await dallAuto('voce', null);
    expect(a.guida.muto, isTrue);
    expect(ultima('opzioni'), containsPair('muto', true));
    // Il primo tocco lascia gli avvisi: l'auto lo sa, e il tocco dopo è il silenzio.
    expect(ultima('opzioni'), containsPair('audio', 'avvisi'));
    await dallAuto('voce', null);
    expect(ultima('opzioni'), containsPair('audio', 'silenzio'));
    await dallAuto('voce', null);
    expect(ultima('opzioni'), containsPair('audio', 'tutto'));
    expect(a.guida.muto, isFalse);
  });

  testWidgets("sull'auto, col GPS muto, il cruscotto non tiene la velocità vecchia", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20, orologio: () => tester.binding.clock.now());
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, auto: a.auto, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    Object? velocita() => (chiamate.lastWhere((c) => c.method == 'cruscotto').arguments as Map)['velocita'];

    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12), velocitaMs: 13.9));
    await tester.pump(const Duration(milliseconds: 100));
    expect((velocita()! as double).round(), 50);
    // Il GPS tace; il cruscotto si rimanda per altro (la batteria).
    await tester.pump(const Duration(seconds: 5));
    a.auto.manuale.imposta(70);
    await tester.pump();
    expect(velocita(), 0);
  });

  testWidgets("il GPS dell'auto arriva sul canale dello schermo e va nel flusso del GPS", (tester) async {
    preparaPiattaforma();
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (_) async => null);
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester);
    final arrivate = <Position>[];
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      canale: canale,
      gpsDellAuto: arrivate.add,
    )..avvia();
    addTearDown(ponte.ferma);
    Future<void> dallAuto(Map<String, Object?> dati) async {
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall('posizione_auto', dati)),
          (_) {},
        ),
      );
      await tester.pump();
    }

    await dallAuto({'lat': 45.1, 'lon': 9.2, 'rotta': 0.0, 'velocita_ms': 13.9, 'precisione_m': 4.0, 'letto_ms': 1000});
    final p = arrivate.single;
    expect((p.latitude, p.longitude), (45.1, 9.2));
    // Nord, ma l'ha detto l'auto: è una direzione.
    expect(rottaDaFidarsi(p.heading, p.headingAccuracy), 0);
    expect(p.speed, 13.9);
    expect(p.accuracy, 4);
    expect(p.timestamp, DateTime.fromMillisecondsSinceEpoch(1000));
    // Senza direzione non diventa nord; senza dove non arriva niente.
    await dallAuto({'lat': 45.2, 'lon': 9.2});
    expect(rottaDaFidarsi(arrivate.last.heading, arrivate.last.headingAccuracy), isNull);
    expect(arrivate.last.speed, 0);
    await dallAuto({'lon': 9.2});
    expect(arrivate, hasLength(2));
  });

  testWidgets('senza Android Auto si tace', (tester) async {
    preparaPiattaforma();
    final a = await ambiente(tester);
    // Nessun gestore sul canale: MissingPluginException, e basta.
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione)..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
  });
}
