import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  test('in autostrada, con l\'uscita lontana, la mappa si allontana', () {
    expect(zoomLontanoInGuida(velocitaMs: 130 / 3.6, allaProssimaM: 12000), closeTo(-zoomLontanoAlPiu, 1e-9));
  });

  test('in città, o vicino alla prossima svolta, resta vicina', () {
    expect(zoomLontanoInGuida(velocitaMs: 40 / 3.6, allaProssimaM: 12000), 0);
    expect(zoomLontanoInGuida(velocitaMs: 130 / 3.6, allaProssimaM: 600), 0);
  });

  test('arrivando all\'uscita torna vicina piano, senza gradini', () {
    double? prima;
    for (var m = 4000.0; m >= 0; m -= 10) {
      final z = zoomLontanoInGuida(velocitaMs: 130 / 3.6, allaProssimaM: m);
      if (prima != null) expect((z - prima).abs(), lessThan(0.05), reason: 'a $m m');
      prima = z;
    }
    // Lo stesso accelerando.
    prima = null;
    for (var kmh = 0.0; kmh <= 150; kmh += 1) {
      final z = zoomLontanoInGuida(velocitaMs: kmh / 3.6, allaProssimaM: 9000);
      if (prima != null) expect((z - prima).abs(), lessThan(0.06), reason: 'a $kmh km/h');
      prima = z;
    }
  });
}
