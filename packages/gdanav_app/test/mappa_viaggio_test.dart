import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/mappa_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/stato/gestore_persone.dart';
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

  /// La telecamera spostata di colpo: in guida, a ogni fotogramma.
  final spostate = <CameraPosition>[];

  @override
  Future<bool?> moveCamera(CameraUpdate cameraUpdate) async {
    final j = cameraUpdate.toJson() as List;
    if (j.first == 'newCameraPosition') spostate.add(CameraPosition.fromMap(j[1])!);
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

    testWidgets('in guida auto e mappa scorrono insieme a ogni fotogramma, senza salti, e l\'auto è dove è adesso', (
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
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      final sulla = Punto((punti[2].lat + punti[3].lat) / 2, punti[2].lon);
      await lettura(sulla);
      final prima = m.spostate.length;
      final segnapostiPrima = m.scritture.where((s) => s.$1 == sorgenteIo).length;
      final animatePrima = m.seguite.length;
      final dopo = Punto(sulla.lat + 0.0002, sulla.lon);
      await lettura(dopo);
      // Una mossa a fotogramma, non una a lettura: la mappa scorre.
      final mosse = m.spostate.sublist(prima);
      expect(mosse.length, greaterThan(15));
      // E il segnaposto con lei, non a salti.
      expect(m.scritture.where((s) => s.$1 == sorgenteIo).length - segnapostiPrima, mosse.length);
      expect(m.seguite.length, animatePrima, reason: 'niente animazioni che si rincorrono');
      // Sempre avanti, a piccoli passi: nessun dente di sega.
      for (var i = 1; i < mosse.length; i++) {
        final passo = mosse[i].target.latitude - mosse[i - 1].target.latitude;
        expect(passo, greaterThanOrEqualTo(-1e-9));
        expect(passo * 111320, lessThan(6), reason: 'un passo per fotogramma, non 25 m in una volta');
      }
      // 25 m/s per (0,5 s di età + 0,9 s di anticipo): una trentina di metri
      // più a nord del GPS. Dal campo: con 0,3 s la freccia arrivava
      // all'incrocio dopo l'auto.
      final camera = mosse.last;
      final avanti = distanzaM(dopo, Punto(camera.target.latitude, sulla.lon));
      expect(avanti, closeTo(35, 4));
      expect(camera.target.latitude, greaterThan(dopo.lat));
      await tester.runAsync(a.guida.ferma);
      await via(tester);
    });
  });

  group('la mappa senza guida, in 3D', () {
    late MappaFinta m;
    late Ambiente a;
    late ControlloMappa controllo;

    Future<void> senzaGuida(WidgetTester tester, {bool inclinata = true, GestorePersone? persone}) async {
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
              persone: persone,
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
      a.gps.add(Lettura(Punto(42 + n * 0.0001, 12), velocitaMs: 12, rotta: 0));
      await tester.pump(const Duration(milliseconds: 1000));
    }

    Future<void> via(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('segue chi guida a ogni fotogramma: girata come va, inclinata, dove l\'auto è adesso', (tester) async {
      await senzaGuida(tester);
      await lettura(tester);
      final prima = m.spostate.length;
      final animatePrima = m.seguite.length;
      final segnapostiPrima = m.scritture.where((s) => s.$1 == sorgenteIo).length;
      n++;
      final ultimo = Punto(42 + n * 0.0001, 12);
      a.gps.add(Lettura(ultimo, velocitaMs: 12, rotta: 0));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      // Una mossa a fotogramma, non un'animazione a lettura: la mappa scorre.
      final mosse = m.spostate.sublist(prima);
      expect(mosse.length, greaterThan(15));
      expect(m.seguite.length, animatePrima, reason: 'niente animazioni che si rincorrono');
      // E il segnaposto con lei, non a salti.
      expect(m.scritture.where((s) => s.$1 == sorgenteIo).length - segnapostiPrima, mosse.length);
      for (var i = 1; i < mosse.length; i++) {
        final passo = mosse[i].target.latitude - mosse[i - 1].target.latitude;
        expect(passo, greaterThanOrEqualTo(-1e-9));
        expect(passo * 111320, lessThan(6), reason: 'un passo per fotogramma, non 10 m in una volta');
      }
      final camera = mosse.last;
      expect(camera.tilt, 58);
      expect(camera.bearing, closeTo(0, 1));
      // Vicina come in guida (`telecameraLibera`): a 43 km/h poco sotto 17,5.
      expect(camera.zoom, inInclusiveRange(17, 17.5));
      // Non dove l'ha vista il GPS, ma dove è adesso: un secondo più avanti,
      // più quanto è vecchia la lettura.
      expect(camera.target.latitude, greaterThan(ultimo.lat));
      expect(distanzaM(ultimo, Punto(camera.target.latitude, camera.target.longitude)), closeTo(15, 4));
      await via(tester);
    });

    testWidgets('un dito la ferma; «Dove sono» la fa seguire di nuovo', (tester) async {
      await senzaGuida(tester);
      await lettura(tester);
      await tester.drag(find.byType(MappaViaggio), const Offset(0, 120));
      expect(controllo.libera, isTrue);
      await tester.pump();
      final prima = m.spostate.length;
      await lettura(tester);
      await lettura(tester);
      expect(m.spostate, hasLength(prima));

      // Si torna sull'auto con un moto, poi la seguono i fotogrammi.
      final animate = m.seguite.length;
      controllo.centra();
      await tester.pump();
      expect(m.seguite, hasLength(animate + 1));
      await lettura(tester);
      await lettura(tester);
      expect(m.spostate.length, greaterThan(prima));
      await via(tester);
    });

    testWidgets('in 2D segue anche lei, col nord in su; mentre si guarda un viaggio da fare no', (tester) async {
      await senzaGuida(tester, inclinata: false);
      await lettura(tester);
      await lettura(tester);
      final ultimo = Punto(42 + n * 0.0001, 12);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final mosse = [...m.seguite.map((s) => s.$1), ...m.spostate];
      expect(mosse, isNotEmpty, reason: 'senza destinazione la mappa segue anche dall\'alto');
      final camera = m.spostate.isNotEmpty ? m.spostate.last : m.seguite.last.$1;
      expect(camera.tilt, 0);
      expect(camera.bearing, 0, reason: 'in 2D il nord resta in su');
      expect(distanzaM(ultimo, Punto(camera.target.latitude, camera.target.longitude)), lessThan(25));

      a.auto.manuale.imposta(90);
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
      await tester.pump();
      expect(a.viaggio.stato, isA<ViaggioPronto>());
      final prima = m.seguite.length, spostatePrima = m.spostate.length;
      await lettura(tester);
      await lettura(tester);
      expect(m.seguite, hasLength(prima));
      expect(m.spostate, hasLength(spostatePrima));
      await via(tester);
    });

    testWidgets('guardata una persona di casa, «Dove sono» la fa seguire di nuovo', (tester) async {
      final persone = GestorePersone();
      addTearDown(persone.dispose);
      await senzaGuida(tester, persone: persone);
      await lettura(tester);
      persone.mostra(const PersonaSullaMappa(id: 'm', nome: 'Mamma', posizione: Punto(41.9, 12.5)));
      await tester.pump();
      expect(controllo.libera, isTrue, reason: 'si guarda la persona, finché non si chiede «Dove sono»');
      final prima = m.spostate.length;
      await lettura(tester);
      expect(m.spostate, hasLength(prima));

      controllo.centra();
      await tester.pump();
      final dopo = m.spostate.length;
      await lettura(tester);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(m.spostate.length, greaterThan(dopo), reason: 'la persona mostrata non tiene ferma la mappa per sempre');
      await via(tester);
    });

    /* «Se non metto una destinazione, se cammino resta fermo alla posizione
     * e non cammina.» A piedi il telefono la velocità la dà bassa o non la dà,
     * e la bussola (sotto i 5 km/h) non conta: la direzione restava quella di
     * partenza, e la freccia, con un punto «dietro» di sé, restava dov'era. */
    Future<({Punto ultimo, CameraPosition camera, Punto segnaposto})> cammina(
      WidgetTester tester, {
      required double kmh,
      required double versoGradi,
      required int secondi,
      bool velocitaDalTelefono = true,
    }) async {
      var qui = const Punto(42.05, 12.05);
      final passo = kmh / 3.6;
      final r = versoGradi * math.pi / 180;
      for (var s = 0; s < secondi; s++) {
        a.gps.add(Lettura(qui, velocitaMs: velocitaDalTelefono ? passo : 0, precisioneM: 5));
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        qui = Punto(
          qui.lat + passo * math.cos(r) / 111195,
          qui.lon + passo * math.sin(r) / (111195 * math.cos(qui.lat * math.pi / 180)),
        );
      }
      final ultimo = a.posizione.qui!;
      final io = m.scritture.lastWhere((s) => s.$1 == sorgenteIo).$2;
      final c = ((io['features'] as List).single as Map)['geometry']['coordinates'] as List;
      final camera = m.spostate.isNotEmpty ? m.spostate.last : m.seguite.last.$1;
      return (ultimo: ultimo, camera: camera, segnaposto: Punto(c[1] as double, c[0] as double));
    }

    for (final (kmh, dalTelefono) in [(1.5, false), (1.5, true), (4.0, true)]) {
      testWidgets('a piedi a $kmh km/h${dalTelefono ? '' : ' (il telefono non dice la velocità)'}, senza destinazione: '
          'segnaposto e mappa camminano con te', (tester) async {
        await senzaGuida(tester);
        // Verso sud: il contrario del nord della partenza, senza bussola.
        final f = await cammina(tester, kmh: kmh, versoGradi: 180, secondi: 40, velocitaDalTelefono: dalTelefono);
        final fatti = 40 * kmh / 3.6;
        expect(fatti, greaterThan(15));
        expect(distanzaM(f.ultimo, f.segnaposto), lessThan(3), reason: 'il segnaposto è dove sei');
        expect(
          distanzaM(f.ultimo, Punto(f.camera.target.latitude, f.camera.target.longitude)),
          lessThan(3),
          reason: 'la mappa ti segue',
        );
        // E guarda dove si va: verso sud.
        expect(diQuantoSiGira(f.camera.bearing, 180).abs(), lessThan(30));
        await via(tester);
      });
    }
  });

  group('la scelta della vista: 2D, 3D, immersiva', () {
    test('si ricorda, e quella letta tardi non cancella quella appena fatta', () async {
      final salvate = <VistaMappa>[];
      final c = ControlloMappa(salvaVista: (v) async => salvate.add(v));
      expect(c.vista, VistaMappa.inclinata);
      await c.carica(Future.value(VistaMappa.piatta));
      expect(c.inclinata, isFalse);
      c.scegliVista(VistaMappa.immersiva);
      expect(salvate, [VistaMappa.immersiva]);
      expect(c.inclinata, isTrue);
      expect(c.immersiva, isTrue);
      final tardi = Completer<VistaMappa>();
      final letta = c.carica(tardi.future);
      c.scegliVista(VistaMappa.piatta);
      tardi.complete(VistaMappa.inclinata);
      await letta;
      expect(c.vista, VistaMappa.piatta);
      c.dispose();
    });

    test('la vista salvata si legge dal suo nome; una parola strana vale 3D', () {
      expect(VistaMappa.daNome('immersiva'), VistaMappa.immersiva);
      expect(VistaMappa.daNome('piatta'), VistaMappa.piatta);
      expect(VistaMappa.daNome('boh'), VistaMappa.inclinata);
    });
  });
}
