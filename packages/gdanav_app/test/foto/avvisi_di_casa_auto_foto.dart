/// Quello che va allo schermo dell'auto (Android Auto, CarPlay) per gli
/// avvisi di casa, scritto in un file per le fotografie dell'auto.
///
/// Sull'auto l'avviso lo disegna il sistema (`Alert` di Android Auto,
/// `CPNavigationAlert` di CarPlay): qui non si può fotografare. Si scrive
/// invece, caso per caso, **quello che il codice vero manda**
/// ([AvvisiDiCasaInAuto.adesso], con la sua icona), e i disegni dell'auto
/// (`collaudo/.../auto/fai.py`, HTML fotografati con Playwright) lo mettono
/// nella cornice dell'auto. Così titoli, testi e tasti delle fotografie sono
/// quelli veri, e se il codice cambia cambiano anche loro.
///
/// ```sh
/// FOTO_CASA=/percorso/uscita flutter test test/foto/avvisi_di_casa_auto_foto.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/avvisi_di_casa_in_auto.dart';
import 'package:gdanav_app/gdanav_app.dart';

final _dove = Platform.environment['FOTO_CASA'] ?? '../../../../collaudo/foto/avvisi-di-casa';

AvvisoDiCasa _da(Map<String, Object?> busta) => AvvisoDiCasa.daNotifica({'v': 1, ...busta}, casa: 'Villa Gialla')!;

/// Le icone delle schede: senza il loro carattere nelle prove sarebbero quadrati.
Future<void> _icone() async {
  final radice = Platform.environment['FLUTTER_ROOT'];
  final f = File('$radice/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (radice == null || !f.existsSync()) return;
  await (FontLoader('MaterialIcons')..addFont(f.readAsBytes().then((b) => b.buffer.asByteData()))).load();
}

void main() {
  setUp(_icone);

  testWidgets('i dati dell\'auto, caso per caso', (tester) async {
    final casi = <String, Map<String, Object?>>{};
    Future<void> caso(String nome, List<AvvisoDiCasa> avvisi, {String? tocca}) async {
      final coda = CodaAvvisiDiCasa(durata: const Duration(seconds: 8));
      final mandati = <Map<String, Object?>>[];
      final auto = AvvisiDiCasaInAuto(coda, (_, d) => mandati.add(d))..avvia();
      avvisi.forEach(coda.aggiungi);
      if (tocca != null) auto.tasto(coda.attuale?.id, tocca);
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && (mandati.isEmpty || mandati.last['icona'] == null); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      final d = Map.of(mandati.last);
      final icona = d.remove('icona');
      casi[nome] = {...d, if (icona is List<int>) 'icona_png': base64Encode(icona)};
      auto.ferma();
      coda.dispose();
    }

    final lavatrice = _da({
      'id': 'lavatrice',
      'tipo': 'elettrodomestici',
      'titolo': '🧺 Lavatrice finita',
      'testo': '1 h 52 min · 0,21 €',
      'entita': 'sensor.lavatrice_stato',
    });
    final antifurto = _da({
      'id': 'antifurto',
      'tipo': 'inserimenti',
      'titolo': '🛡️ Antifurto inserito',
      'testo': 'Da Marta, alle 08:04',
      'azioni': [
        {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
        {'id': 'guarda', 'etichetta': 'Guarda', 'apre': true},
      ],
    });
    final allarme = _da({
      'id': 'allarme',
      'tipo': 'antifurto',
      'urg': 'urgente',
      'titolo': '🚨 Allarme in casa',
      'testo': 'Movimento in soggiorno',
      'azioni': [
        {'id': 'spegni-sirena', 'etichetta': 'Spegni sirena'},
        {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
        {'id': 'guarda', 'etichetta': 'Guarda', 'apre': true},
      ],
    });
    final auto = _da({'id': 'auto', 'tipo': 'ha_notify', 'titolo': 'Auto carica all\'80%', 'testo': 'Wallbox garage'});
    await caso('lavatrice', [lavatrice]);
    await caso('antifurto', [antifurto]);
    await caso('antifurto-conferma', [antifurto], tocca: 'disinserisci');
    await caso('allarme', [allarme]);
    await caso('gruppo', [lavatrice, antifurto, auto]);
    Directory(_dove).createSync(recursive: true);
    File('$_dove/auto-dati.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(casi));
    expect(casi['antifurto-conferma']?['titolo'], 'Disinserire l\'antifurto?');
  });
}
