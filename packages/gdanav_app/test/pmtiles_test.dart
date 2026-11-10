import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/sorgenti/pmtiles.dart';

void main() {
  test('i numeri delle tessere sono quelli del formato (curva di Hilbert)', () {
    // Gli stessi della libreria di riferimento (pmtiles per Python).
    expect(idTessera(0, 0, 0), 0);
    expect(idTessera(1, 0, 0), 1);
    expect(idTessera(1, 0, 1), 2);
    expect(idTessera(1, 1, 1), 3);
    expect(idTessera(1, 1, 0), 4);
    expect(idTessera(2, 3, 2), 16);
    expect(idTessera(14, 8838, 6144), 314676585);
    expect(idTessera(14, 8839, 6144), 314676586);
    expect(idTessera(14, 8838, 6145), 314676588);
  });

  test('le tessere si leggono dal pacchetto, decompresse; quelle che mancano no', () async {
    // Un pacchetto vero, fatto con la libreria di riferimento: tre tessere.
    final p = await LettorePmtiles.apri('test/dati/edifici-prova.pmtiles');
    addTearDown(p.chiudi);
    expect(p.zoomMinimo, 14);
    expect(p.zoomMassimo, 14);
    expect(utf8.decode((await p.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
    expect(utf8.decode((await p.tessera(14, 8839, 6144))!), 'la tessera accanto');
    expect(utf8.decode((await p.tessera(14, 8838, 6145))!), 'e quella sotto');
    expect(await p.tessera(14, 8839, 6145), isNull);
    expect(await p.tessera(13, 4419, 3072), isNull);
  });

  test('un file che non è un pacchetto si dice', () async {
    expect(LettorePmtiles.apri('pubspec.yaml'), throwsFormatException);
  });
}
