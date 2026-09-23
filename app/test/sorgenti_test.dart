import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/sorgenti/sorgente_android_auto.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  test('Android Auto: legge la mappa mandata da Kotlin', () {
    final s = SorgenteAndroidAuto.statoDaMappa({'batteria': 55, 'autonomia_km': 240.0, 'letto_ms': 0})!;
    expect(s.sorgente, TipoSorgente.androidAuto);
    expect(s.batteria, 55);
    expect(s.autonomiaKm, 240);
    expect(s.letto, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('Android Automotive si riconosce', () {
    expect(SorgenteAndroidAuto.statoDaMappa({'batteria': 55, 'automotive': true})!.sorgente, TipoSorgente.automotive);
  });

  test("se l'auto non passa la batteria non si inventa niente", () {
    expect(SorgenteAndroidAuto.statoDaMappa({'autonomia_km': 240}), isNull);
    expect(SorgenteAndroidAuto.statoDaMappa('rotto'), isNull);
  });
}
