import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  group('la potenza minima intorno a te', () {
    test('con «Tutte» nessun minimo: si vedono anche le 11 kW', () {
      const p = PreferenzeRicarica(potenzaMinimaKw: PreferenzeRicarica.tutte);
      expect(p.minimaIntorno, 0);
      // Per le soste del viaggio il minimo resta.
      expect(p.potenzaMinimaKw, 22);
    });

    test('un minimo scelto vale anche intorno a te', () {
      expect(const PreferenzeRicarica(potenzaMinimaKw: 50).minimaIntorno, 50);
      expect(const PreferenzeRicarica(potenzaMinimaKw: 150).minimaIntorno, 150);
    });

    test('«Tutte» salvato da una versione di prima si rilegge come «Tutte»', () {
      final p = PreferenzeRicarica.daJson({'potenza_minima_kw': 22});
      expect(p.potenzaMinimaKw, PreferenzeRicarica.tutte);
      expect(p.minimaIntorno, 0);
    });
  });
}
