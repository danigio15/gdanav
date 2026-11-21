import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/percorso_per_assistenza.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  test('il percorso per l\'assistenza: la linea a sei decimali, e si rilegge uguale', () {
    final punti = [for (var i = 0; i < 50; i++) Punto(41.0 + i * 0.0001, 14.2 + i * 0.00013)];
    final c = Linea(punti).cumulate;
    final p = PercorsoCalcolato(
      punti: punti,
      tratti: [Tratto(lunghezzaM: c.last, velocitaKmh: 40)],
      limiti: [for (var i = 0; i < punti.length - 1; i++) 50],
      manovre: [Manovra(istruzione: 'Parti', voce: 'Parti', lunghezzaM: c.last, secondi: 60, inizio: 0, tipo: 1)],
    );
    final righe = percorsoPerLAssistenza(p).split('\n');
    expect(righe.first, 'GdANav percorso 1');
    final letti = decodificaPolyline(righe[1]);
    expect(letti, hasLength(punti.length));
    for (var i = 0; i < punti.length; i++) {
      expect(distanzaM(letti[i], punti[i]), lessThan(0.2));
    }
  });
}
