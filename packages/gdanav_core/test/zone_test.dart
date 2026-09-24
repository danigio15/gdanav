import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  test('i riquadri di una zona si contano per livello di zoom', () {
    // Tutto il mondo a zoom 0 e 1: 1 + 4.
    const mondo = Zona('mondo', 'Mondo', -85, -180, 85, 179.999);
    expect(mondo.riquadri(zoomMassimo: 1), 5);
    final campania = regioniItalia.firstWhere((z) => z.id == 'campania');
    final r = campania.riquadri();
    expect(r, greaterThan(10000));
    expect(r, lessThan(30000));
    expect(campania.megabyteStimati(), inInclusiveRange(150, 600));
    expect(campania.riquadri(zoomMassimo: 13), lessThan(r ~/ 3));
  });

  test('ci sono tutte le venti regioni, e i riquadri sono sensati', () {
    expect(regioniItalia, hasLength(20));
    expect(regioniItalia.map((z) => z.id).toSet(), hasLength(20));
    for (final z in regioniItalia) {
      expect(z.nord, greaterThan(z.sud), reason: z.nome);
      expect(z.est, greaterThan(z.ovest), reason: z.nome);
      expect(z.sud, inInclusiveRange(35.0, 48.0), reason: z.nome);
    }
  });

  test('una zona intorno a un punto', () {
    final z = Zona.intorno(const Punto(40.85, 14.27), raggioKm: 30);
    expect(z.nord - z.sud, closeTo(60 / 111, 1e-9));
    expect(z.riquadri(), lessThan(regioniItalia.firstWhere((z) => z.id == 'campania').riquadri()));
  });
}
