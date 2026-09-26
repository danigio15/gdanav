import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

import 'obd_test.dart' show DongleFinto;

void main() {
  test('le maschere dei PID supportati', () {
    // 0x98 0x3B 0x80 0x11 dalla specifica: PID 01, 04, 05, 0B, 0C, 0D, 0F, 10, 11, 1C, 20.
    expect(pidDaMaschera(0, [0x98, 0x3B, 0x80, 0x11]), [
      0x01,
      0x04,
      0x05,
      0x0B,
      0x0C,
      0x0D,
      0x0F,
      0x10,
      0x11,
      0x1C,
      0x20,
    ]);
  });

  test("l'esplorazione legge soltanto, e il rapporto dice cosa sa l'auto", () async {
    final dongle = DongleFinto({
      'ATI': 'ELM327 v1.5',
      '0100': '7E8064100983B8011',
      '0120': '7E8064120 00000000',
      '015B': '7E803415BA3',
      '010D': '7E803410D00',
      '0902': '7E8101449020131323334\r7E82135363738394142\r7E82243444546474849',
      '22F190': '7EC037F2231',
    });
    final righe = <String>[];
    final r = await EsploraObd(Elm327(dongle), onRiga: righe.add).esegui();
    expect(r, contains('PID 01 supportati: 01 04 05 0B 0C 0D 0F 10 11 1C 20'));
    expect(r, contains('ELM327 v1.5'));
    expect(r, contains('[7E4] 22F190'));
    expect(righe.last, '# fine');
    // Solo letture: nessun servizio che scrive, resetta o apre sessioni.
    final richieste = dongle.scritti.where((c) => !c.startsWith('AT'));
    expect(richieste.every((c) => c.startsWith('01') || c.startsWith('09') || c.startsWith('22')), isTrue);
  });
}
