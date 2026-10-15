/// Le fotografie del **Pianificatore**: l'elenco dei viaggi, un viaggio
/// programmato, uno di ogni settimana e un giro a tappe, come li disegna
/// l'app (con i viaggi di una casa finta). Non è una prova: è un attrezzo per
/// guardare.
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/pianificatore_foto.dart
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/pianificatore.dart';
import 'package:gdanav_app/stato/viaggi_pianificati.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

Future<void> _caratteri() async {
  final radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null || radice.isEmpty) return;
  final cartella = '$radice/bin/cache/artifacts/material_fonts';
  Future<ByteData> leggi(String nome) => File('$cartella/$nome').readAsBytes().then((b) => b.buffer.asByteData());
  for (final famiglia in ['Roboto', 'packages/gdanav_app/Roboto']) {
    final f = FontLoader(famiglia);
    for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
      if (File('$cartella/Roboto-$peso.ttf').existsSync()) f.addFont(leggi('Roboto-$peso.ttf'));
    }
    await f.load();
  }
  if (File('$cartella/MaterialIcons-Regular.otf').existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(leggi('MaterialIcons-Regular.otf'))).load();
  }
}

final _dove = Platform.environment['FOTO_PIANIFICATORE'] ?? '../../../../collaudo/foto/pianificatore';

/// Giovedì sera: domani è venerdì 16.
final _adesso = DateTime(2026, 10, 15, 21);

Map<String, Object?> _posto(String nome, double lat, double lon, [int sosta = 0]) => {
  'nome': nome,
  'lat': lat,
  'lon': lon,
  if (sosta > 0) 'sostaMin': sosta,
};

Map<String, Object?> _stima(int minuti, double km, {bool traffico = true}) => {
  'durataS': minuti * 60,
  'km': km,
  'fonte': traffico ? 'traffico' : 'strada',
  'alle': _adesso.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
};

final _viaggi = <Map<String, Object?>>[
  {
    'id': 'v_1',
    'tipo': 'una',
    'nome': '',
    'da': _posto('Napoli', 40.85, 14.27),
    'tappe': [_posto('Caserta, centro', 41.07, 14.33)],
    'quando': {'modo': 'arrivo', 'ora': '09:00', 'giorno': '2026-10-16', 'giorni': <int>[]},
    'avviso': {'acceso': true, 'minuti': 10},
    'prepara': {'clima': null, 'garage': null},
    'stima': _stima(48, 39.4),
  },
  {
    'id': 'v_2',
    'tipo': 'settimana',
    'nome': 'Casa – Lavoro',
    'da': _posto('Casa', 40.85, 14.27),
    'tappe': [_posto('Lavoro', 40.91, 14.35)],
    'quando': {
      'modo': 'arrivo',
      'ora': '08:30',
      'giorno': null,
      'giorni': [1, 2, 3, 4, 5],
    },
    'avviso': {'acceso': true, 'minuti': 10},
    'prepara': {
      'clima': {'entity': 'climate.auto', 'minuti': 10},
      'garage': {'entity': 'cover.garage'},
    },
    'stima': _stima(31, 18.2, traffico: false),
  },
  {
    'id': 'v_3',
    'tipo': 'tappe',
    'nome': 'Giro clienti',
    'da': null,
    'tappe': [
      _posto('Ufficio', 40.86, 14.28, 30),
      _posto('Cliente', 41.0, 14.4, 60),
      _posto('Supermercato', 40.95, 14.3, 20),
      _posto('Casa', 40.85, 14.27),
    ],
    'quando': {'modo': 'partenza', 'ora': '08:30', 'giorno': '2026-10-17', 'giorni': <int>[]},
    'avviso': {'acceso': true, 'minuti': 10},
    'prepara': {'clima': null, 'garage': null},
    'stima': _stima(126, 186),
  },
];

Map<String, Object?> _conLaProssima(Map<String, Object?> v) {
  final p = prossimaVolta(ViaggioPianificato.daJson(v)!, _adesso)!;
  return {
    ...v,
    'prossima': {
      'partenza': p.partenza.millisecondsSinceEpoch,
      'arrivo': p.arrivo.millisecondsSinceEpoch,
      'stimata': p.stimata,
    },
  };
}

GestoreViaggiPianificati _gestore({bool sbloccato = true, bool vuoto = false}) => GestoreViaggiPianificati(
  FonteViaggiDellaCasa(
    (c) async => {
      'sbloccato': sbloccato,
      'viaggi': [if (!vuoto) ..._viaggi.map(_conLaProssima)],
    },
  ),
  orologio: () => _adesso,
);

Future<Luogo?> _scegli(String _) async => null;
Future<void> _avvia(ViaggioPianificato _) async {}

void main() {
  setUp(_caratteri);

  Future<void> foto(
    WidgetTester tester,
    String nome,
    Widget Function(GestoreViaggiPianificati g) pagina, {
    double alto = 1000,
    bool scuro = false,
    bool sbloccato = true,
    bool vuoto = false,
  }) async {
    tester.view
      ..physicalSize = Size(390 * 3, alto * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final g = _gestore(sbloccato: sbloccato, vuoto: vuoto);
    await tester.runAsync(g.carica);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
        home: pagina(g),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/$nome-${scuro ? 'scuro' : 'chiaro'}.png'));
  }

  ViaggioPianificato viaggio(int i) => ViaggioPianificato.daJson(_conLaProssima(_viaggi[i]))!;

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';
    testWidgets('elenco ($luce)', (tester) async {
      await foto(
        tester,
        '1-elenco',
        (g) => SchermataPianificatore(gestore: g, scegli: _scegli, avvia: _avvia),
        alto: 1100,
        scuro: scuro,
      );
    });
    testWidgets('programmato ($luce)', (tester) async {
      await foto(
        tester,
        '2-programmato',
        (g) => ModificaViaggio(gestore: g, iniziale: viaggio(0), scegli: _scegli, avvia: _avvia),
        scuro: scuro,
      );
    });
    testWidgets('a tappe ($luce)', (tester) async {
      await foto(
        tester,
        '3-a-tappe',
        (g) => ModificaViaggio(gestore: g, iniziale: viaggio(2), scegli: _scegli, avvia: _avvia),
        alto: 1150,
        scuro: scuro,
      );
    });
    testWidgets('ricorrente ($luce)', (tester) async {
      await foto(
        tester,
        '4-ricorrente',
        (g) => ModificaViaggio(gestore: g, iniziale: viaggio(1), scegli: _scegli, avvia: _avvia),
        alto: 1150,
        scuro: scuro,
      );
    });
  }
  testWidgets('senza Premium', (tester) async {
    await foto(
      tester,
      '5-senza-premium',
      (g) => SchermataPianificatore(gestore: g, scegli: _scegli, avvia: _avvia, premium: () {}),
      alto: 700,
      sbloccato: false,
      vuoto: true,
    );
  });
  testWidgets('nessun viaggio', (tester) async {
    await foto(
      tester,
      '6-vuoto',
      (g) => SchermataPianificatore(gestore: g, scegli: _scegli, avvia: _avvia),
      alto: 700,
      vuoto: true,
    );
  });
}
