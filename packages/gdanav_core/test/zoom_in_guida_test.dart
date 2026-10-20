import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  test('in autostrada, con l\'uscita lontana, la mappa si allontana', () {
    expect(zoomLontanoInGuida(velocitaStradaKmh: 115, allaProssimaM: 12000), closeTo(-zoomLontanoAlPiu, 1e-9));
  });

  test('in città, o vicino alla prossima svolta, resta vicina', () {
    expect(zoomLontanoInGuida(velocitaStradaKmh: 35, allaProssimaM: 12000), 0);
    expect(zoomLontanoInGuida(velocitaStradaKmh: 115, allaProssimaM: 600), 0);
  });

  test('arrivando all\'uscita torna vicina piano, senza gradini', () {
    double? prima;
    for (var m = 4000.0; m >= 0; m -= 10) {
      final z = zoomLontanoInGuida(velocitaStradaKmh: 115, allaProssimaM: m);
      if (prima != null) expect((z - prima).abs(), lessThan(0.05), reason: 'a $m m');
      prima = z;
    }
  });

  test('dal campo: in autostrada, frenando e ripartendo, lo zoom non si muove', () {
    // «Zoom in e out frequenti: non farlo sulla velocità dell'auto ma capisci
    // il percorso.» L'auto va da 130 a 60 e torna a 130 (una coda, un
    // camion): la strada è sempre l'autostrada, e la guida dice quella.
    final linea = [for (var i = 0; i <= 200; i++) Punto(45 + i * 0.001, 9)];
    final percorso = PercorsoCalcolato(
      punti: linea,
      tratti: const [],
      manovre: const [
        Manovra(istruzione: 'Parti', lunghezzaM: 22000, secondi: 700, inizio: 0, tipo: 1),
        Manovra(istruzione: 'Esci', lunghezzaM: 300, secondi: 20, inizio: 200, tipo: 20),
      ],
    );
    final guida = Guida(percorso);
    final zoom = <double>{};
    for (var i = 2; i < 150; i++) {
      final kmh = i % 20 < 10 ? 130.0 : 60.0;
      final a = guida.aggiorna(PuntoInMoto(45 + i * 0.001, 9, rotta: 0, velocitaMs: kmh / 3.6));
      expect(a.velocitaStradaKmh, closeTo(22000 / 700 * 3.6, 1e-9));
      if (a.allaProssimaM > lontanoTuttoOltreM) {
        zoom.add(zoomLontanoInGuida(velocitaStradaKmh: a.velocitaStradaKmh!, allaProssimaM: a.allaProssimaM));
      }
    }
    expect(zoom, {-zoomLontanoAlPiu});
  });
}
