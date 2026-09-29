import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  group('la potenza minima è per le soste', () {
    test('di serie da 50 kW in su', () {
      expect(const PreferenzeRicarica().potenzaMinimaKw, 50);
    });

    test('la scelta più bassa è 22 kW', () {
      expect(const PreferenzeRicarica(potenzaMinimaKw: PreferenzeRicarica.minimaSoste).potenzaMinimaKw, 22);
    });

    test('«Tutte» salvato da una versione di prima si rilegge come la scelta più bassa', () {
      final p = PreferenzeRicarica.daJson({'potenza_minima_kw': 22});
      expect(p.potenzaMinimaKw, PreferenzeRicarica.minimaSoste);
    });
  });
}
