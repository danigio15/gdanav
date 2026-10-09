import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/mappa_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'aiuti.dart';

/// MapLibre finta: niente mappa, solo quello che le si scrive. Ogni mappa
/// creata, anche quella rifatta cambiando tema, ne ha una sua.
class MappaFinta extends MapLibrePlatform {
  final scritture = <(String, Map<String, dynamic>)>[];
  final telecamere = <String>[];

  /// Le sorgenti la cui prossima scrittura fallisce.
  final fallisci = <String>{};

  /// Quante volte il percorso è arrivato con la sua linea.
  int get percorsi => scritture.where((s) => s.$1 == sorgentePercorso && (s.$2['features'] as List).isNotEmpty).length;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) => _VistaFinta(onPlatformViewCreated);

  @override
  Future<void> initPlatform(int id) async {}

  @override
  Future<void> setGeoJsonSource(String sourceId, Map<String, dynamic> geojson) async {
    if (fallisci.remove(sourceId)) throw PlatformException(code: 'sorgente', message: '$sourceId non scritta');
    // Come il plugin vero: quello che non diventa JSON non arriva alla mappa.
    jsonEncode(geojson);
    scritture.add((sourceId, geojson));
  }

  @override
  Future<bool?> animateCamera(CameraUpdate cameraUpdate, {Duration? duration}) async {
    telecamere.add((cameraUpdate.toJson() as List).first as String);
    return true;
  }

  /// La telecamera che segue l'auto: anche questa si scrive, con la durata e
  /// il moto.
  final seguite = <(CameraPosition, Duration?, CameraAnimationInterpolation?)>[];

  @override
  Future<bool> easeCamera(
    CameraUpdate cameraUpdate, {
    Duration? duration,
    CameraAnimationInterpolation? interpolation,
  }) async {
    final j = cameraUpdate.toJson() as List;
    telecamere.add(j.first as String);
    if (j.first == 'newCameraPosition') {
      seguite.add((CameraPosition.fromMap(j[1])!, duration, interpolation));
    }
    return true;
  }

  @override
  Future<CameraPosition?> updateMapOptions(Map<String, dynamic> optionsUpdate) async => null;

  @override
  Future<CameraPosition?> queryCameraPosition() async => null;

  // Tutto il resto (le immagini, gli strati delle annotazioni, gli edifici):
  // fatto, e basta.
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// La vista della mappa: appena c'è, dice al plugin che la mappa è nata.
class _VistaFinta extends StatefulWidget {
  const _VistaFinta(this.creata);
  final OnPlatformViewCreatedCallback creata;

  @override
  State<_VistaFinta> createState() => _VistaFintaState();
}

class _VistaFintaState extends State<_VistaFinta> {
  static var _id = 0;

  @override
  void initState() {
    super.initState();
    final id = _id++;
    scheduleMicrotask(() => widget.creata(id));
  }

  @override
  // Che si possa toccare, come la mappa vera: le prove ci passano il dito.
  Widget build(BuildContext context) => const ColoredBox(color: Color(0x00000000), child: SizedBox.expand());
}

PercorsoCalcolato _strada(List<Punto> punti, {List<Coda> code = const []}) => PercorsoCalcolato(
  punti: punti,
  tratti: const [Tratto(lunghezzaM: 1000, velocitaKmh: 50)],
  manovre: const [],
  code: code,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('i dati del viaggio', () {
    final dritta = [for (var i = 0; i <= 10; i++) Punto(45 + i * 0.001, 9)];

    List<dynamic> elementi(Map<String, Map<String, Object?>> dati, String sorgente) =>
        dati[sorgente]!['features']! as List;

    test('un punto che non è un numero non si porta via la linea del percorso', () {
      final punti = [...dritta]..insert(5, const Punto(double.nan, 9));
      final dati = datiViaggio(Viaggio(percorso: _strada(punti), colonnine: const [], piano: null));
      // Tutto si scrive in JSON, che NaN non lo sa dire.
      expect(() => jsonEncode(dati), returnsNormally);
      final linea = elementi(dati, sorgentePercorso).single as Map;
      expect((linea['geometry'] as Map)['coordinates'], hasLength(11));
      expect(elementi(dati, sorgenteArrivo), hasLength(1));
    });

    test('colonnine e code storte restano fuori, il percorso resta', () {
      final viaggio = Viaggio(
        percorso: _strada(
          dritta,
          code: const [
            Coda(daM: double.nan, aM: 300, ritardo: Duration(minutes: 1)),
            Coda(daM: 100, aM: 400, ritardo: Duration(minutes: 1)),
          ],
        ),
        colonnine: const [
          ColonninaSulPercorso(id: 'a', nome: 'Storta', distanzaM: double.nan, potenzaKw: double.infinity),
          ColonninaSulPercorso(id: 'b', nome: 'Buona', distanzaM: 500, potenzaKw: 150),
        ],
        piano: null,
      );
      final dati = datiViaggio(viaggio);
      expect(() => jsonEncode(dati), returnsNormally);
      expect(elementi(dati, sorgentePercorso), hasLength(1));
      expect(elementi(dati, sorgenteCode), hasLength(1));
      final potenze = [for (final c in elementi(dati, sorgenteColonnine)) ((c as Map)['properties'] as Map)['potenza']];
      expect(potenze, containsAll([0, 150]));
    });

    test('un percorso senza punti non fa cadere niente', () {
      final viaggio = Viaggio(
        percorso: _strada(const []),
        colonnine: const [ColonninaSulPercorso(id: 'a', nome: 'Sola', distanzaM: 100, potenzaKw: 50)],
        piano: null,
      );
      final dati = datiViaggio(viaggio);
      expect(elementi(dati, sorgentePercorso), isEmpty);
      expect(elementi(dati, sorgenteColonnine), isEmpty);
      expect(elementi(dati, sorgenteArrivo), isEmpty);
    });
  });

  group('la mappa della guida', () {
    late List<MappaFinta> mappe;
    late ValueNotifier<Brightness> tema;
    late Ambiente a;

    Future<void> inGuida(WidgetTester tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      mappe = [];
      final prima = MapLibrePlatform.createInstance;
      MapLibrePlatform.createInstance = () {
        final m = MappaFinta();
        mappe.add(m);
        return m;
      };
      addTearDown(() => MapLibrePlatform.createInstance = prima);
      DateTime ora() => tester.binding.clock.now();
      a = await ambiente(tester, km: 20, orologio: ora);
      a.auto.manuale.imposta(90);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
      expect(a.viaggio.stato, isA<ViaggioPronto>());
      a.guida.avvia();
      tema = ValueNotifier(Brightness.light);
      addTearDown(tema.dispose);
      final controllo = ControlloMappa()..inclinata = true;
      addTearDown(controllo.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: tema,
          builder: (_, luce, _) => MaterialApp(
            theme: ThemeData(brightness: luce),
            // Il tema cambia di colpo: la mappa nuova nasce subito.
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: MappaViaggio(
                gestore: a.viaggio,
                controllo: controllo,
                posizione: a.posizione,
                guida: a.guida,
                onPuntoScelto: (_) {},
                onColonnina: (_) {},
                orologio: ora,
              ),
            ),
          ),
        ),
      );
      // La vista finta dice al plugin che la mappa è nata.
      await tester.pump();
      expect(mappe, hasLength(1));
    }

    Future<void> stilePronto(WidgetTester tester, MappaFinta m) async {
      m.onMapStyleLoadedPlatform(null);
      await tester.pump();
    }

    // Alla fine la mappa se ne va, e con lei i suoi orologi.
    Future<void> via(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('il percorso arriva appena lo stile è pronto, e una scrittura fallita si rifà', (tester) async {
      await inGuida(tester);
      final m = mappe.single;
      // Prima dello stile alla mappa non si scrive niente, neanche col passare del tempo.
      await tester.pump(const Duration(seconds: 4));
      expect(m.scritture, isEmpty);

      m.fallisci.add(sorgentePercorso);
      await stilePronto(tester, m);
      // La linea non è passata; le altre sorgenti sì.
      expect(m.percorsi, 0);
      expect(m.scritture.map((s) => s.$1), contains(sorgenteArrivo));

      // La rete di sicurezza la riscrive da sola, anche senza GPS.
      await tester.pump(const Duration(seconds: 4));
      expect(m.percorsi, 1);

      // E anche quando c'è, la riscrive ogni tanto: non resta mai vuota a lungo.
      await tester.pump(const Duration(seconds: 26));
      expect(m.percorsi, 2);
      await via(tester);
    });

    testWidgets('la mappa rifatta col tema non riceve niente prima del suo stile, poi il percorso', (tester) async {
      await inGuida(tester);
      await stilePronto(tester, mappe.first);
      expect(mappe.first.percorsi, 1);

      tema.value = Brightness.dark;
      await tester.pump();
      await tester.pump();
      expect(mappe, hasLength(2));
      final nuova = mappe.last;
      // Arriva una posizione, passa il tempo: la mappa nuova aspetta il suo stile.
      a.posizione.avvia();
      final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
      a.gps.add(Lettura(punti[2], velocitaMs: 13.9));
      a.posizioni.add(punti[2]);
      await tester.pump(const Duration(seconds: 3));
      expect(nuova.scritture, isEmpty);

      await stilePronto(tester, nuova);
      expect(nuova.percorsi, 1);
      await via(tester);
    });

    testWidgets('col GPS muto e nessun avanzamento si vede tutta la strada; con la posizione si segue l\'auto', (
      tester,
    ) async {
      await inGuida(tester);
      final m = mappe.single;
      await stilePronto(tester, m);
      await tester.pump(const Duration(seconds: 2));
      // Prima l'inclinazione, che lo stile nuovo non sa; poi la strada.
      expect(m.telecamere, ['tiltTo', 'newLatLngBounds']);
      // Una volta sola: chi guarda la mappa può anche avvicinarsi.
      await tester.pump(const Duration(seconds: 6));
      expect(m.telecamere, ['tiltTo', 'newLatLngBounds']);

      a.posizione.avvia();
      final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
      a.gps.add(Lettura(punti[2], velocitaMs: 13.9));
      a.posizioni.add(punti[2]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(a.guida.avanzamento, isNotNull);
      expect(m.telecamere.last, 'newCameraPosition');
      await via(tester);
    });

    testWidgets('in guida la telecamera si muove una volta per posizione, lineare, e l\'auto è dove è adesso', (
      tester,
    ) async {
      await inGuida(tester);
      final m = mappe.single;
      await stilePronto(tester, m);
      a.posizione.avvia();
      final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
      Future<void> lettura(Punto p) async {
        a.gps.add(Lettura(p, velocitaMs: 25, rotta: 0));
        // Letta mezzo secondo fa: tanto è indietro quello che dice il GPS.
        a.posizioni.add(
          PuntoInMoto(
            p.lat,
            p.lon,
            velocitaMs: 25,
            rotta: 0,
            alle: DateTime.now().subtract(const Duration(milliseconds: 500)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1000));
      }

      final sulla = Punto((punti[2].lat + punti[3].lat) / 2, punti[2].lon);
      await lettura(sulla);
      final prima = m.seguite.length;
      await lettura(Punto(sulla.lat + 0.0002, sulla.lon));
      // Una sola mossa per posizione: la posizione e la guida non si
      // rubano più il turno a vicenda.
      expect(m.seguite.length, prima + 1);
      final (camera, durata, moto) = m.seguite.last;
      expect(moto, CameraAnimationInterpolation.linear);
      // Lunga quanto l'intervallo fra due posizioni, non 900 ms che frenano.
      expect(durata, const Duration(milliseconds: 1000));
      // 25 m/s per (0,5 s di età + 0,3 s): una ventina di metri più a nord del GPS.
      final avanti = distanzaM(Punto(sulla.lat + 0.0002, sulla.lon), Punto(camera.target.latitude, sulla.lon));
      expect(avanti, closeTo(20, 3));
      expect(camera.target.latitude, greaterThan(sulla.lat + 0.0002));
      await tester.runAsync(a.guida.ferma);
      await via(tester);
    });
  });

  group('la mappa senza guida, in 3D', () {
    late MappaFinta m;
    late Ambiente a;
    late ControlloMappa controllo;

    Future<void> senzaGuida(WidgetTester tester, {bool inclinata = true}) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final mappe = <MappaFinta>[];
      final prima = MapLibrePlatform.createInstance;
      MapLibrePlatform.createInstance = () {
        final m = MappaFinta();
        mappe.add(m);
        return m;
      };
      addTearDown(() => MapLibrePlatform.createInstance = prima);
      a = await ambiente(tester, km: 20, orologio: () => tester.binding.clock.now());
      controllo = ControlloMappa(inclinata: inclinata);
      addTearDown(controllo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MappaViaggio(
              gestore: a.viaggio,
              controllo: controllo,
              posizione: a.posizione,
              onPuntoScelto: (_) {},
              onColonnina: (_) {},
              orologio: () => tester.binding.clock.now(),
            ),
          ),
        ),
      );
      await tester.pump();
      m = mappe.single;
      m.onMapStyleLoadedPlatform(null);
      await tester.pump();
      a.posizione.avvia();
    }

    var n = 0;
    Future<void> lettura(WidgetTester tester) async {
      n++;
      a.gps.add(Lettura(Punto(42 + n * 0.0001, 12), velocitaMs: 12, rotta: 90));
      await tester.pump(const Duration(milliseconds: 1000));
    }

    Future<void> via(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('segue chi guida: girata come va, inclinata, a ogni posizione', (tester) async {
      await senzaGuida(tester);
      await lettura(tester);
      await lettura(tester);
      expect(m.seguite, hasLength(2));
      final (camera, _, moto) = m.seguite.last;
      expect(camera.tilt, 58);
      expect(camera.bearing, closeTo(90, 1));
      expect(camera.zoom, inInclusiveRange(16, 17));
      expect(moto, CameraAnimationInterpolation.linear);
      await via(tester);
    });

    testWidgets('un dito la ferma; «Dove sono» la fa seguire di nuovo', (tester) async {
      await senzaGuida(tester);
      await lettura(tester);
      final prima = m.seguite.length;
      await tester.drag(find.byType(MappaViaggio), const Offset(0, 120));
      expect(controllo.libera, isTrue);
      await lettura(tester);
      await lettura(tester);
      expect(m.seguite, hasLength(prima));

      controllo.centra();
      await tester.pump();
      expect(m.seguite, hasLength(prima + 1));
      await lettura(tester);
      expect(m.seguite, hasLength(prima + 2));
      await via(tester);
    });

    testWidgets('in 2D non segue, e mentre si guarda un viaggio da fare nemmeno', (tester) async {
      await senzaGuida(tester, inclinata: false);
      await lettura(tester);
      await lettura(tester);
      expect(m.seguite, isEmpty);

      controllo.alternaInclinazione();
      await tester.pump();
      await lettura(tester);
      expect(m.seguite, isNotEmpty);

      a.auto.manuale.imposta(90);
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
      await tester.pump();
      expect(a.viaggio.stato, isA<ViaggioPronto>());
      final prima = m.seguite.length;
      await lettura(tester);
      await lettura(tester);
      expect(m.seguite, hasLength(prima));
      await via(tester);
    });
  });

  group('la scelta 2D/3D', () {
    test('si ricorda, e quella letta tardi non cancella quella appena fatta', () async {
      final salvate = <bool>[];
      final c = ControlloMappa(salvaInclinazione: (v) async => salvate.add(v));
      expect(c.inclinata, isTrue);
      await c.carica(Future.value(false));
      expect(c.inclinata, isFalse);
      c.alternaInclinazione();
      expect(salvate, [true]);
      final tardi = Completer<bool>();
      final letta = c.carica(tardi.future);
      c.alternaInclinazione();
      tardi.complete(true);
      await letta;
      expect(c.inclinata, isFalse);
      c.dispose();
    });
  });
}
