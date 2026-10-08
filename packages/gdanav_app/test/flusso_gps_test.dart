import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/posizione.dart';
import 'package:geolocator/geolocator.dart';

Position _a(double lat) => Position(
  latitude: lat,
  longitude: 9,
  timestamp: DateTime.utc(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// Il GPS della piattaforma, finto: i flussi aperti uno dopo l'altro, e le
/// posizioni chieste una volta sola, che rispondono quando lo dice la prova.
class GpsFinto {
  final flussi = <StreamController<Position>>[];
  final soloIlGps = <bool>[];
  final domande = <Completer<Position>>[];
  final domandeSoloIlGps = <bool>[];

  Stream<Position> apri(bool solo) {
    soloIlGps.add(solo);
    final c = StreamController<Position>();
    flussi.add(c);
    return c.stream;
  }

  Future<Position> chiedi(bool solo, Duration limite) {
    domandeSoloIlGps.add(solo);
    final c = Completer<Position>();
    domande.add(c);
    return c.future;
  }

  /// Risponde a quelle ancora in sospeso: alla fine della prova non deve
  /// restare un'attesa aperta.
  void rispondi(double lat) {
    for (final d in domande) {
      if (!d.isCompleted) d.complete(_a(lat));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // L'orologio è quello finto della prova: va avanti con `pump`. E le
  // iscrizioni si chiudono senza aspettare: il `cancel` di un flusso
  // broadcast torna un futuro nato fuori dal tempo finto, e aspettarlo qui
  // dentro ferma la prova per sempre.
  (FlussoGps, GpsFinto) nuovo(WidgetTester tester) {
    final finto = GpsFinto();
    final gps = FlussoGps(apri: finto.apri, chiedi: finto.chiedi, orologio: () => tester.binding.clock.now());
    return (gps, finto);
  }

  testWidgets('il flusso tace: dopo cinque secondi si chiede una posizione, una alla volta, e arriva come le altre', (
    tester,
  ) async {
    final (gps, finto) = nuovo(tester);
    final arrivate = <Position>[];
    final iscrizione = gps.posizioni.listen(arrivate.add);
    expect(finto.flussi, hasLength(1));
    finto.flussi.first.add(_a(45));
    await tester.pump();
    expect(arrivate.single.latitude, 45);

    // Quattro secondi senza niente: è ancora normale.
    await tester.pump(const Duration(seconds: 4));
    expect(finto.domande, isEmpty);
    // Al giro dopo la sentinella chiede.
    await tester.pump(const Duration(seconds: 2));
    expect(finto.domande, hasLength(1));
    // Finché non risponde non se ne chiede un'altra.
    await tester.pump(const Duration(seconds: 2));
    expect(finto.domande, hasLength(1));
    finto.domande.first.complete(_a(45.001));
    await tester.pump();
    expect(arrivate.map((p) => p.latitude), [45, 45.001]);
    // Il flusso tace ancora: la prossima si chiede al giro dopo, senza
    // aspettare altri cinque secondi.
    await tester.pump(const Duration(seconds: 2));
    expect(finto.domande, hasLength(2));
    finto.rispondi(45.002);
    await tester.pump();
    // Il flusso riparte: si torna ad aspettare, e non lo si riapre.
    finto.flussi.first.add(_a(45.003));
    await tester.pump(const Duration(seconds: 4));
    expect(finto.domande, hasLength(2));
    expect(arrivate.map((p) => p.latitude), [45, 45.001, 45.002, 45.003]);
    expect(finto.flussi, hasLength(1));
    unawaited(iscrizione.cancel());
  });

  testWidgets('la posizione chiesta che arriva dopo una del flusso non torna indietro', (tester) async {
    final (gps, finto) = nuovo(tester);
    final arrivate = <Position>[];
    final iscrizione = gps.posizioni.listen(arrivate.add);
    await tester.pump(const Duration(seconds: 6));
    expect(finto.domande, hasLength(1));
    // Il flusso riparte mentre si aspetta la risposta.
    finto.flussi.first.add(_a(46));
    await tester.pump();
    finto.rispondi(45);
    await tester.pump();
    expect(arrivate.map((p) => p.latitude), [46]);
    unawaited(iscrizione.cancel());
  });

  testWidgets('il flusso che finisce si riapre al giro dopo', (tester) async {
    final (gps, finto) = nuovo(tester);
    final arrivate = <Position>[];
    final iscrizione = gps.posizioni.listen(arrivate.add);
    unawaited(finto.flussi.first.close());
    await tester.pump();
    expect(finto.flussi, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    expect(finto.flussi, hasLength(2));
    finto.flussi.last.add(_a(46));
    await tester.pump();
    expect(arrivate.single.latitude, 46);
    unawaited(iscrizione.cancel());
  });

  testWidgets('il flusso muto da dodici secondi si chiude e si riapre, poi sempre più di rado', (tester) async {
    final (gps, finto) = nuovo(tester);
    final arrivate = <Position>[];
    final iscrizione = gps.posizioni.listen(arrivate.add);
    // Il canale è staccato: il flusso tace, le posizioni chieste rispondono.
    Future<void> avanti(int secondi) async {
      for (var s = 0; s < secondi; s += 2) {
        await tester.pump(const Duration(seconds: 2));
        finto.rispondi(45);
        await tester.pump();
      }
    }

    await avanti(10);
    expect(finto.flussi, hasLength(1));
    // Intanto la posizione è arrivata lo stesso.
    expect(arrivate, isNotEmpty);
    await avanti(2);
    expect(finto.flussi, hasLength(2));
    expect(finto.flussi.first.hasListener, isFalse);
    // Riaperto e ancora muto: la volta dopo si aspetta il doppio.
    await avanti(22);
    expect(finto.flussi, hasLength(2));
    await avanti(2);
    expect(finto.flussi, hasLength(3));
    // Il flusso riparte: si torna a contare da dodici secondi.
    finto.flussi.last.add(_a(47));
    await tester.pump();
    expect(arrivate.last.latitude, 47);
    unawaited(iscrizione.cancel());
    finto.rispondi(45);
    await tester.pump();
  });

  testWidgets('nessuno ascolta: il GPS resta spento e nessuno chiede niente', (tester) async {
    final (gps, finto) = nuovo(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(finto.flussi, isEmpty);
    expect(finto.domande, isEmpty);

    final iscrizione = gps.posizioni.listen((_) {});
    expect(finto.flussi, hasLength(1));
    unawaited(iscrizione.cancel());
    expect(finto.flussi.single.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(finto.flussi, hasLength(1));
    expect(finto.domande, isEmpty);

    // Chi torna ad ascoltare lo riaccende.
    final ancora = gps.posizioni.listen((_) {});
    expect(finto.flussi, hasLength(2));
    unawaited(ancora.cancel());
  });

  testWidgets('un errore si riprova dopo quindici secondi, e col servizio spento solo col GPS', (tester) async {
    final (gps, finto) = nuovo(tester);
    final iscrizione = gps.posizioni.listen((_) {}, onError: (Object _) => fail('l\'errore non deve uscire'));
    finto.flussi.first.addError(const LocationServiceDisabledException());
    await tester.pump();
    expect(finto.flussi.first.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 14));
    expect(finto.flussi, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(finto.flussi, hasLength(2));
    expect(finto.soloIlGps, [false, true]);
    // Anche le posizioni chieste nel frattempo vanno solo al GPS.
    expect(finto.domandeSoloIlGps, isNotEmpty);
    expect(finto.domandeSoloIlGps.last, isTrue);
    unawaited(iscrizione.cancel());
    finto.rispondi(45);
    await tester.pump();
  });
}
