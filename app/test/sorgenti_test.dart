import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/sorgenti/sorgente_android_auto.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

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

  test('un dongle OBD scelto dà i dati dell\'auto e resta salvato', () async {
    preparaPiattaforma();
    final dongle = _DongleFinto({'015B': '7E803415BA3', '010D': '7E803410D3C'});
    final auto = GestoreAuto(archivio: Archivio(), apriObd: (_) async => dongle);
    await auto.avvia();
    await auto.usaDongle('AA:BB', 'Vgate iCar Pro');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(auto.stato!.sorgente, TipoSorgente.obd);
    expect(auto.stato!.batteria, closeTo(64, 0.1));
    expect(auto.velocitaAuto(), 60);
    expect((await Archivio().dongleObd())!.nome, 'Vgate iCar Pro');
    await auto.togliDongle();
    expect(await Archivio().dongleObd(), isNull);
    auto.dispose();
  });
}

class _DongleFinto implements CanaleObd {
  _DongleFinto(this.risposte);
  final Map<String, String> risposte;
  final _in = StreamController<String>.broadcast();

  @override
  Stream<String> get ricevuti => _in.stream;

  @override
  Future<void> scrivi(String testo) async {
    final c = testo.trim();
    final r = risposte[c] ?? (c.startsWith('AT') ? 'OK' : 'NO DATA');
    Future<void>.delayed(Duration.zero, () => _in.add('$r\r>'));
  }

  @override
  Future<void> chiudi() async {}
}
