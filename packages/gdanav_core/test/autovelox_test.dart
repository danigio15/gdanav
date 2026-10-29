import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

import '../tool/autovelox_osm.dart';

void main() {
  test("l'archivio va e torna, e trova quelli vicini", () {
    final testo = ArchivioAutovelox.scrivi([
      (45.46, 9.19, 50, 90.0),
      (45.47, 9.20, null, null),
      (41.9, 12.5, 130, null),
    ]);
    final a = ArchivioAutovelox.leggi(testo);
    expect(a.quanti, 3);
    final vicini = a.vicini(const Punto(45.465, 9.195), 5000);
    expect(vicini, hasLength(2));
    final primo = vicini.firstWhere((s) => s.limiteKmh == 50);
    expect(primo.fissa, isTrue);
    expect(primo.tipo, TipoSegnalazione.autovelox);
    expect(primo.avviso, 'Autovelox, limite 50');
    expect(vicini.firstWhere((s) => s.limiteKmh == null).avviso, 'Autovelox');
    expect(a.vicini(const Punto(41.9, 12.5), 1000).single.limiteKmh, 130);
  });

  test('la direzione: si avvisa solo chi va da quella parte', () {
    final est = Segnalazione(
      id: 'x',
      tipo: TipoSegnalazione.autovelox,
      punto: const Punto(45, 9),
      creata: DateTime(2026),
      direzioneGradi: 90,
    );
    expect(est.riguarda(80), isTrue);
    expect(est.riguarda(140), isTrue);
    expect(est.riguarda(270), isFalse);
    final nord = Segnalazione(
      id: 'y',
      tipo: TipoSegnalazione.autovelox,
      punto: const Punto(45, 9),
      creata: DateTime(2026),
      direzioneGradi: 10,
    );
    expect(nord.riguarda(340), isTrue);
    expect(nord.riguarda(190), isFalse);
  });

  test('i semafori con la foto: fissi, con la loro voce, e la direzione', () {
    final a = ArchivioAutovelox.leggi(ArchivioAutovelox.scrivi(
      [(45.46, 9.19, 50, 90.0)],
      semafori: [(45.47, 9.19, 0.0)],
    ));
    expect(a.quanti, 2);
    final s = a.vicini(const Punto(45.47, 9.19), 100).single;
    expect(s.semaforo, isTrue);
    expect(s.fissa, isTrue);
    expect(s.tipo, TipoSegnalazione.autovelox);
    expect(s.avviso, 'Semaforo con foto');
    expect(s.riguarda(10), isTrue);
    expect(s.riguarda(180), isFalse);
    // L'archivio di prima, senza semafori, si legge ancora.
    final v2 = ArchivioAutovelox.leggi('{"v":2,"generato":"2026-09-28T00:00:00Z","a":[[45,9,50,-1]],"t":[]}');
    expect(v2.quanti, 1);
  });

  test('i Tutor vanno e tornano, e si trovano da un capo o dall\'altro', () {
    final a = ArchivioAutovelox.leggi(ArchivioAutovelox.scrivi(
      [(45.46, 9.19, 50, 90.0)],
      tutor: [(44.0, 11.0, 44.09, 11.0, 130), (40.0, 15.0, 40.01, 15.0, null)],
    ));
    expect(a.quantiTutor, 2);
    final t = a.tutorVicini(const Punto(44.09, 11.0), 2000).single;
    expect(t.limiteKmh, 130);
    expect(t.lunghezzaM, closeTo(10000, 100));
    expect(a.tutorVicini(const Punto(44.045, 11.0), 2000), isEmpty, reason: 'in mezzo, lontano dai capi');
    expect(a.tutorVicini(const Punto(40.0, 15.0), 500).single.limiteKmh, isNull);
    // L'archivio di prima, senza Tutor, si legge ancora.
    final vecchio = ArchivioAutovelox.leggi('{"v":1,"generato":"2026-09-28T00:00:00Z","a":[[45,9,50,-1]]}');
    expect(vecchio.quanti, 1);
    expect(vecchio.quantiTutor, 0);
  });

  test('da OpenStreetMap: autovelox, controlli con la direzione, Tutor, niente doppi', () {
    final e = EstrattoOsm();
    for (final riga in [
      // Un autovelox da solo, col limite e la direzione scritta.
      'n1 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Thighway=speed_camera,maxspeed=50,direction=NE x9.0 y45.0',
      // Un autovelox che è anche l'apparecchio di un controllo: la
      // direzione viene dal controllo (da sud a nord), una volta sola.
      'n2 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Thighway=speed_camera x10.0 y44.0',
      'n3 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente T x10.0 y43.999',
      'n4 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente T x10.0 y44.0002',
      'r10 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Ttype=enforcement,enforcement=maxspeed,maxspeed=IT:rural Mn2@device,n3@from,n4@to',
      // Un controllo senza highway=speed_camera sull'apparecchio.
      'n5 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Tmaxspeed=70 x11.0 y42.0',
      'r11 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Ttype=enforcement,enforcement=maxspeed Mn5@device',
      // Un Tutor: due portali, da una strada (il suo mezzo) all'altra.
      'n6 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Thighway=speed_camera x12.0 y41.0',
      'n7 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Thighway=speed_camera x12.0 y41.1',
      'r12 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Ttype=enforcement,enforcement=average_speed,maxspeed=130 Mn6@device,n7@device',
      // Un Tutor troppo corto per esserlo: si scarta.
      'n8 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente T x13.0 y40.0',
      'n9 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente T x13.0 y40.0001',
      'r13 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Ttype=enforcement,enforcement=average_speed Mn8@from,n9@to',
      // Un nome con la virgola, scritta come la scrive osmium.
      // Un apparecchio col suo limite anche al semaforo: resta un autovelox.
      'r14 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Ttype=enforcement,enforcement=traffic_signals,name=A%2c%%20%B Mn1@device',
      // Un semaforo con la foto: l'apparecchio, e da dove si arriva.
      'n15 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Tman_made=surveillance x14.0 y38.0',
      'n16 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente T x14.0 y37.999',
      'r15 v1 dV c1 t2020-01-01T00:00:00Z i1 ugente Ttype=enforcement,enforcement=traffic_signals Mn15@device,n16@from',
    ]) {
      e.leggi(riga);
    }
    final (autovelox, tutor, semafori) = e.risolvi();
    expect(autovelox, hasLength(3));
    final controllo = autovelox.firstWhere((a) => a.$2 == 10.0);
    expect(controllo.$1, closeTo(44.0002, 1e-9), reason: 'il punto misurato, sulla strada');
    expect(controllo.$3, 90);
    expect(controllo.$4, closeTo(0, 1));
    expect(autovelox.firstWhere((a) => a.$2 == 9.0).$4, 45);
    expect(autovelox.firstWhere((a) => a.$2 == 11.0).$3, 70);
    expect(tutor.single.$5, 130);
    expect((tutor.single.$1, tutor.single.$3), (41.0, 41.1));
    expect(e.relazioni[e.relazioni.length - 2].$1['name'], 'A, B');
    expect(semafori, hasLength(1));
    expect((semafori.single.$1, semafori.single.$2), (38.0, 14.0));
    expect(semafori.single.$3, closeTo(0, 1), reason: 'da sud a nord');
  });

  test('gli estratti della versione di prima, e i doppi al confine', () {
    final a = daGeojson('\u001e{"type":"Feature","geometry":{"type":"Point","coordinates":[9.1,45.2]},'
        '"properties":{"highway":"speed_camera","maxspeed":"90"}}');
    expect(a, (45.2, 9.1, 90, null));
    expect(daGeojson('{"type":"Feature","geometry":{"type":"Point","coordinates":[9,45]},"properties":{}}'), isNull);
    expect(senzaDoppi([a!, a, (45.3, 9.1, null, null)]), hasLength(2));
  });
}
