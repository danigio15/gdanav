import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/sorgenti/sorgente_android_auto.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
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

  test('con lo schermo dell\'auto acceso i dati si chiedono freschi', () async {
    /* Dal campo, con la foto dello schermo dell'auto: «i dati batteria non si
     * aggiornano fino a che non apro app dal cellulare».
     *
     * I dati freschi si chiedevano solo mentre si guidava verso una meta
     * (`GestoreGuida._forseChiediDati`). Fermi in garage, o girando senza una
     * meta, con lo schermo dell'auto acceso davanti, non li chiedeva nessuno:
     * restava quello che Home Assistant aveva mandato per conto suo. */
    preparaPiattaforma();
    var adesso = DateTime(2026, 9, 27, 10, 37);
    final auto = _AutoSpia(() => adesso);
    await auto.avvia();
    addTearDown(auto.dispose);

    // Col telefono in tasca e nessuno che guarda, non si chiede niente.
    expect(auto.vaChiestoAdesso, isFalse);
    adesso = adesso.add(const Duration(hours: 3));
    expect(auto.vaChiestoAdesso, isFalse, reason: 'senza nessuno che guarda');

    // Si sale in macchina: subito, perché è il momento in cui il numero
    // vecchio si nota di più.
    auto.schermoDellAuto(true);
    expect(auto.chieste, 1);
    expect(auto.vaChiestoAdesso, isFalse, reason: 'appena chiesto');

    // E poi ogni minuto, finché si è lì.
    adesso = adesso.add(GestoreAuto.ognisQuanto ~/ 2);
    expect(auto.vaChiestoAdesso, isFalse);
    adesso = adesso.add(GestoreAuto.ognisQuanto);
    expect(auto.vaChiestoAdesso, isTrue);

    // Scesi dalla macchina si smette: una richiesta al minuto per tutta la
    // notte non serve a nessuno e si paga.
    auto.schermoDellAuto(false);
    adesso = adesso.add(const Duration(hours: 1));
    expect(auto.vaChiestoAdesso, isFalse);
    expect(auto.chieste, 1);
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

  test("«Esplora l'auto» fa il giro di lettura e poi riaccende il dongle", () async {
    preparaPiattaforma();
    final dongle = _DongleFinto({'0100': '7E8064100983B8011', '015B': '7E803415BA3'});
    final auto = GestoreAuto(archivio: Archivio(), apriObd: (_) async => dongle);
    await auto.avvia();
    await auto.scegliVeicolo(catalogoVeicoli.firstWhere((v) => v.id == 'leapmotor-b10-67'));
    await auto.usaDongle('AA:BB', 'Vgate iCar Pro');
    final righe = <String>[];
    final r = await auto.esploraObd(onRiga: righe.add);
    expect(r, startsWith('# Leapmotor B10 67,1 kWh (Design, Pro Max) · dongle Vgate iCar Pro'));
    expect(r, contains('PID 01 supportati: 01 04 05'));
    expect(righe.last, '# fine');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(auto.stato!.sorgente, TipoSorgente.obd);
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

/// Un gestore che conta le richieste di dati freschi, e che ha un orologio
/// spostabile a mano.
class _AutoSpia extends GestoreAuto {
  _AutoSpia(this._adesso) : super(archivio: Archivio(), ora: () => _adesso());

  final DateTime Function() _adesso;
  int chieste = 0;

  @override
  Future<void> chiediAggiornamento() async {
    chieste += 1;
    await super.chiediAggiornamento();
  }
}
