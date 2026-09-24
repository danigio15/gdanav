import 'dart:async';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Un dongle finto: risponde come un ELM327 vero, a pezzi e col «>».
class DongleFinto implements CanaleObd {
  DongleFinto(this.risposte);

  final Map<String, String> risposte;
  final scritti = <String>[];
  final _in = StreamController<String>.broadcast();
  var chiuso = false;

  @override
  Stream<String> get ricevuti => _in.stream;

  @override
  Future<void> scrivi(String testo) async {
    final c = testo.trim();
    scritti.add(c);
    final r = risposte[c] ?? (c.startsWith('AT') ? 'OK' : 'NO DATA');
    // Spezzata in due pezzi, come arriva dal Bluetooth.
    Future<void>.delayed(Duration.zero, () {
      final testo = '$r\r\r>';
      final meta = testo.length ~/ 2;
      _in
        ..add(testo.substring(0, meta))
        ..add(testo.substring(meta));
    });
  }

  @override
  Future<void> chiudi() async => chiuso = true;
}

void main() {
  group('risposte', () {
    test('frame singolo: velocità 50 km/h', () {
      expect(leggiRisposta('7E803410D32', '010D'), [0x32]);
      // Con spazi e «SEARCHING...» del primo giro.
      expect(leggiRisposta('SEARCHING...\r7E8 03 41 0D 32', '010D'), [0x32]);
    });

    test('una risposta lunga a cui mancano pezzi si scarta', () {
      // Dichiara 62 byte ma ne arrivano una ventina.
      const testo = '7EC103E6201010203\r7EC210405060708090A';
      expect(leggiRisposta(testo, '220101'), isNull);
    });

    test('lunghezza dichiarata rispettata quando tutti i pezzi ci sono', () {
      // 10 byte: 62 01 01 + 7 di dati.
      const testo = '7EC100A6201010A0B0C\r7EC210D0E0F10000000';
      expect(leggiRisposta(testo, '220101'), [0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]);
    });

    test('intestazioni a 29 bit (VW MEB e altri)', () {
      expect(leggiRisposta('17FE007B0462028C8A', '22028C'), [0x8A]);
      expect(leggiRisposta('18DAF1DA03410D32', '010D'), [0x32]);
    });

    test('niente dati, errori e risposte negative danno null', () {
      expect(leggiRisposta('NO DATA', '015B'), isNull);
      expect(leggiRisposta('CAN ERROR', '015B'), isNull);
      expect(leggiRisposta('7EC037F2211', '220101'), isNull);
      // Un altro PID non vale.
      expect(leggiRisposta('7E803410C32', '010D'), isNull);
    });
  });

  test('i PID standard: batteria, velocità, temperatura, contachilometri', () {
    double? v(CampoObd c, List<int> b) => profiloStandard.letture.firstWhere((l) => l.campo == c).formula(b);
    expect(v(CampoObd.batteria, [0xFF]), 100);
    expect(v(CampoObd.batteria, [0x80]), closeTo(50.2, 0.1));
    expect(v(CampoObd.velocita, [0x5A]), 90);
    expect(v(CampoObd.temperaturaEsterna, [0x32]), 10);
    expect(v(CampoObd.contachilometri, [0x00, 0x01, 0xE2, 0x40]), 12345.6);
    expect(v(CampoObd.velocita, []), isNull);
  });

  test('il dongle si prepara, chiede a giri e dà lo stato dell\'auto', () async {
    final dongle = DongleFinto({
      'ATZ': 'ELM327 v1.5',
      '015B': '7E803415BA3',
      '010D': '7E803410D58',
      '0146': '7E8034146 2F',
      '01A6': 'NO DATA',
    });
    final s = SorgenteObd(apri: () async => dongle, intervallo: const Duration(hours: 1));
    final letture = <StatoAuto>[];
    s.letture.listen(letture.add);
    await s.avvia();
    await Future<void>.delayed(Duration.zero);
    expect(dongle.scritti.take(6), ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH1', 'ATSP0']);
    expect(dongle.scritti, contains('ATSH7DF'));
    final st = letture.single;
    expect(st.sorgente, TipoSorgente.obd);
    expect(st.batteria, closeTo(64, 0.1));
    expect(st.velocitaKmh, 88);
    expect(st.temperaturaEsternaC, 7);
    expect(st.odometroKm, isNull);
    // L'intestazione non si ripete a ogni richiesta.
    expect(dongle.scritti.where((c) => c.startsWith('ATSH')), hasLength(1));
    await s.ferma();
    expect(dongle.chiuso, isTrue);
  });

  test('se il dongle non c\'è si riprova dopo, senza errori', () async {
    var tentativi = 0;
    final dongle = DongleFinto({'015B': '7E803415B80'});
    final s = SorgenteObd(
      apri: () async {
        tentativi++;
        if (tentativi == 1) throw const ErroreObd('dongle spento');
        return dongle;
      },
      intervallo: const Duration(hours: 1),
    );
    final letture = <StatoAuto>[];
    s.letture.listen(letture.add);
    await s.avvia();
    expect(s.ultimoErrore, contains('dongle spento'));
    // I giri di attesa, poi il nuovo tentativo va.
    for (var i = 0; i < 6; i++) {
      await s.giro();
    }
    await Future<void>.delayed(Duration.zero);
    expect(tentativi, 2);
    expect(letture, isNotEmpty);
    await s.ferma();
  });

  test('un dongle che non risponde dà un errore leggibile', () async {
    final muto = _Muto();
    final elm = Elm327(muto, attesa: const Duration(milliseconds: 50));
    expect(elm.comando('ATZ'), throwsA(isA<ErroreObd>()));
  });
}

class _Muto implements CanaleObd {
  @override
  Stream<String> get ricevuti => const Stream.empty();

  @override
  Future<void> scrivi(String testo) async {}

  @override
  Future<void> chiudi() async {}
}
