/// La scena della freccia allo svincolo, per guardarla con MapLibre GL JS
/// in un browser: lo stile dell'auto, il percorso, la freccia di manovra, la
/// sua punta e il segnaposto.
///
/// Non è una prova (il nome non finisce in `_test.dart`). Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && GDANAV_FOTO=/tmp/scena flutter test test/foto/freccia_svincolo_foto.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_core/gdanav_core.dart';

const _metriPerGrado = 111195.08;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la scena dello svincolo', () async {
    final dove = Directory(Platform.environment['GDANAV_FOTO'] ?? 'collaudo/foto/svincolo')..createSync(recursive: true);
    // Come nella foto dal campo: verso nord, a sinistra, e dopo trentacinque
    // metri ancora a sinistra (verso sud).
    const partenza = Punto(40.8500, 14.2500);
    Punto sposta(Punto p, {double nord = 0, double est = 0}) =>
        Punto(p.lat + nord / _metriPerGrado, p.lon + est / (_metriPerGrado * 0.7570));
    final a = sposta(partenza, nord: 200);
    final b = sposta(a, est: -35);
    final punti = <Punto>[
      for (var m = 0.0; m <= 200; m += 10) sposta(partenza, nord: m),
      for (var m = 5.0; m <= 35; m += 5) sposta(a, est: -m),
      for (var m = 10.0; m <= 150; m += 10) sposta(b, nord: -m),
    ];
    const prima = Manovra(istruzione: 'Svolta a sinistra', lunghezzaM: 35, secondi: 8, inizio: 20, tipo: 15);
    const seconda = Manovra(istruzione: 'Svolta a sinistra', lunghezzaM: 150, secondi: 30, inizio: 27, tipo: 15);
    final viaggio = Viaggio(
      percorso: PercorsoCalcolato(punti: punti, tratti: const [], manovre: const [prima, seconda]),
      colonnine: const [],
      piano: null,
    );
    List<double> xy(Punto p) => [p.lon, p.lat];
    final percorso = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': [for (final p in punti) xy(p)],
          },
        },
      ],
    };
    File('${dove.path}/percorso.json').writeAsStringSync(jsonEncode(percorso));
    File('${dove.path}/manovra.json').writeAsStringSync(jsonEncode(datiManovra(viaggio, prima)));
    File('${dove.path}/io.json').writeAsStringSync(jsonEncode({'lon': punti[14].lon, 'lat': punti[14].lat}));
    File('${dove.path}/centro.json').writeAsStringSync(jsonEncode(xy(sposta(a, nord: -40))));
    File('${dove.path}/stile.json').writeAsStringSync(jsonEncode(stileMappa(scuro: false, perAuto: true)));
    for (final s in ['freccia', 'auto_blu']) {
      final b = await rootBundle.load('assets/segnaposto/$s.png');
      File('${dove.path}/$s.png').writeAsBytesSync(b.buffer.asUint8List());
    }
  });
}
