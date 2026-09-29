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
    expect(nomeZtl('Zona Traffico Limitato'), '');
  });

  test('il nome senza la città, quando la ripete', () {
    expect(nomeZtl('Bologna - Centro Storico', 'Bologna'), 'Centro Storico');
    expect(nomeZtl('Via Matteotti Lerici', 'Lerici'), 'Via Matteotti');
    expect(nomeZtl('Siracusa', 'Siracusa'), '');
    expect(nomeZtl('ZTL Gravina in Puglia', 'Gravina in Puglia'), '');
    expect(nomeZtl('Lancianovecchia', 'Lanciano'), 'Lancianovecchia');
    expect(nomeZtl('Settore A', 'Firenze'), 'Settore A');
    expect(nomeZtl('ZTL di Verona', 'Verona'), '');
    expect(nomeZtl('ZTL di Polpet', 'Ponte nelle Alpi'), 'Polpet');
    expect(nomeZtl('ZTL del Centro Storico', 'Modugno'), 'Centro Storico');
    expect(nomeZtl("ZTL d'Alba", 'Alba Adriatica'), 'Alba');
    expect(nomeZtl('Pitigliano ZTL zona A', 'Pitigliano'), 'zona A');
    // Senza la sigla davanti, «di» fa parte del nome.
    expect(nomeZtl('Via di Porta Romana', 'Firenze'), 'Via di Porta Romana');
  });

  test('il nome italiano, e il comune in cui cade', () {
    expect(nomeItaliano({'name': 'Casteddu/Cagliari', 'name:it': 'Cagliari'}), 'Cagliari');
    expect(nomeItaliano({'name': 'Lerici'}), 'Lerici');
    expect(nomeItaliano(const {}), isNull);
    List<Punto> quadrato(double lat, double lon, double lato) => [
          Punto(lat, lon),
          Punto(lat, lon + lato),
          Punto(lat + lato, lon + lato),
          Punto(lat + lato, lon),
        ];
    final comuni = [
      ZonaLimitata(id: 'r1', tipo: TipoZona.ztl, nome: 'Grande', anelli: [quadrato(44.0, 9.8, 0.2)]),
      // Un comune tutto dentro l'altro: vince il più piccolo.
      ZonaLimitata(id: 'r2', tipo: TipoZona.ztl, nome: 'Piccolo', anelli: [quadrato(44.05, 9.85, 0.02)]),
    ];
    expect(comuneDi(const Punto(44.06, 9.86), comuni), 'Piccolo');
    expect(comuneDi(const Punto(44.15, 9.95), comuni), 'Grande');
    expect(comuneDi(const Punto(45.0, 9.9), comuni), isNull);
    expect(citta(const {}, const Punto(44.06, 9.86), [(const Punto(44.061, 9.861), 'Frazione', 1)], comuni), 'Piccolo');
    expect(citta(const {}, const Punto(45.0, 9.9), [(const Punto(45.01, 9.9), 'Frazione', 1)], comuni), 'Frazione');
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
