import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

import '../tool/ztl_osm.dart';

void main() {
  test('il nome senza la sigla', () {
    expect(nomeZtl('ZTL Centro Storico'), 'Centro Storico');
    expect(nomeZtl('Z.T.L. - Chiaia'), 'Chiaia');
    expect(nomeZtl('Zona a Traffico Limitato: Tridente'), 'Tridente');
    expect(nomeZtl('ztl'), '');
    expect(nomeZtl('Zona Tempio'), 'Zona Tempio');
    expect(nomeZtl(null), '');
  });

  test("l'id di OpenStreetMap, anche quando osmium lo scrive da area", () {
    expect(idOsm('a2469'), 'r1234');
    expect(idOsm('a246'), 'w123');
    expect(idOsm('w88'), 'w88');
  });

  test('la superficie e la semplificazione', () {
    // Un quadrato di circa 100 m di lato.
    const lato = 0.0009;
    final q = [
      const Punto(40.0, 14.0),
      const Punto(40.0, 14.0 + lato * 1.3),
      const Punto(40.0 + lato, 14.0 + lato * 1.3),
      const Punto(40.0 + lato, 14.0),
    ];
    expect(superficieM2(q), closeTo(10000, 700));
    // Un lato con cento punti allineati si riduce ai suoi estremi.
    final lungo = [
      for (var i = 0; i <= 100; i++) Punto(40.0, 14.0 + lato * 1.3 * i / 100),
      const Punto(40.0 + lato, 14.0 + lato * 1.3),
      const Punto(40.0 + lato, 14.0),
      const Punto(40.0, 14.0),
    ];
    expect(semplificato(lungo, 1).length, 4);
  });
}
