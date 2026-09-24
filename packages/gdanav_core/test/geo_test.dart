import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  test("decodifica l'esempio di Google (precisione 5)", () {
    final p = decodificaPolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precisione: 5);
    expect(p, [const Punto(38.5, -120.2), const Punto(40.7, -120.95), const Punto(43.252, -126.453)]);
  });

  test('codifica e decodifica tornano uguali', () {
    const punti = [Punto(45.46427, 9.18951), Punto(44.49381, 11.33875), Punto(41.89193, 12.51133)];
    expect(decodificaPolyline(codificaPolyline(punti), precisione: 5), punti);
    expect(decodificaPolyline(codificaPolyline(punti, precisione: 6)), punti);
  });

  test('Milano–Roma in linea d\'aria sono circa 477 km', () {
    expect(distanzaM(const Punto(45.46427, 9.18951), const Punto(41.89193, 12.51133)) / 1000, closeTo(477, 3));
  });

  test('proietta un punto accanto alla linea', () {
    // Una linea di ~11 km verso est, lungo il parallelo 45.
    final l = Linea(const [Punto(45, 9), Punto(45, 9.1), Punto(45, 9.2)]);
    final p = l.proietta(const Punto(45.009, 9.1)); // ~1 km a nord del punto di mezzo
    expect(p.lungoM, closeTo(l.lunghezzaM / 2, 5));
    expect(p.lontanoM, closeTo(1000, 10));
  });

  test('un punto oltre la fine si proietta sulla fine', () {
    final l = Linea(const [Punto(45, 9), Punto(45, 9.1)]);
    expect(l.proietta(const Punto(45, 9.2)).lungoM, closeTo(l.lunghezzaM, 1e-6));
  });

  test('semplifica tiene primo e ultimo', () {
    final punti = [for (var i = 0; i <= 100; i++) Punto(45, 9 + i * 0.001)];
    final s = semplifica(punti, 1000);
    expect(s.first, punti.first);
    expect(s.last, punti.last);
    expect(s.length, lessThan(15));
  });

  test('rotta: nord, est, sud, ovest', () {
    const o = Punto(45, 9);
    expect(rottaGradi(o, const Punto(45.01, 9)), closeTo(0, 0.01));
    expect(rottaGradi(o, const Punto(45, 9.01)), closeTo(90, 0.1));
    expect(rottaGradi(o, const Punto(44.99, 9)), closeTo(180, 0.01));
    expect(rottaGradi(o, const Punto(45, 8.99)), closeTo(270, 0.1));
  });
}
