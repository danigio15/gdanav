import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/sorgenti/sorgente_android_auto.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('Android Auto: velocità e contachilometri, e la velocità arriva anche senza batteria', () async {
    final s = SorgenteAndroidAuto.statoDaMappa({'batteria': 55, 'velocita_kmh': 87.5, 'odometro_km': 12345.6})!;
    expect(s.velocitaKmh, 87.5);
    expect(s.odometroKm, 12345.6);

    const canale = EventChannel('gdanav/auto_prova');
    final velocita = <double>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      canale,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink.success({'velocita_kmh': 42.0});
          sink.success({'batteria': 60, 'velocita_kmh': 50.0});
        },
      ),
    );
    final sorgente = SorgenteAndroidAuto(canale: canale, onVelocita: velocita.add);
    final letture = <StatoAuto>[];
    sorgente.letture.listen(letture.add);
    await sorgente.avvia();
    await Future<void>.delayed(Duration.zero);
    expect(velocita, [42, 50]);
    expect(letture.single.batteria, 60);
    await sorgente.ferma();
  });
}
