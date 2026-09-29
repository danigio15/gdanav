/// Le fotografie delle **strade a risparmio**: la proposta in guida, le
/// strade prima di partire col loro nome, e le impostazioni.
///
/// Non è una prova: è un attrezzo per **guardare**, come
/// `ricarica_foto.dart`. Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/risparmio_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/risparmio/`, che la repository
/// non tiene. La mappa è quella finta delle prove (un fondo grigio): quello
/// che si guarda è quello che ci sta sopra.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/strade_risparmio.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_risparmio.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

/// Un carattere vero dal sistema, e le icone: senza, quadratini.
Future<void> _ilCarattere() async {
  const dove = [
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  for (final famiglia in ['Roboto', 'packages/gdanav_app/Roboto']) {
    final carica = FontLoader(famiglia);
    for (final via in dove) {
      final file = File(via);
      if (!file.existsSync()) continue;
      carica.addFont(file.readAsBytes().then((b) => b.buffer.asByteData()));
      await carica.load();
      break;
    }
  }
  final radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null || radice.isEmpty) return;
  final icone = File('$radice/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icone.existsSync()) return;
  await (FontLoader('MaterialIcons')..addFont(icone.readAsBytes().then((b) => b.buffer.asByteData()))).load();
}

PercorsoCalcolato _strada(List<Punto> punti, int minuti, double kwh) {
  final metri = Linea(punti).lunghezzaM;
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: metri, velocitaKmh: metri / (minuti * 60) * 3.6)],
    manovre: const [],
    consumoTomTom: kwh,
  );
}

List<Punto> _dritto(Punto a, Punto b) {
  final n = (distanzaM(a, b) / 500).ceil().clamp(1, 1000);
  return [for (var i = 0; i <= n; i++) Punto(a.lat + (b.lat - a.lat) * i / n, a.lon + (b.lon - a.lon) * i / n)];
}

List<Punto> _via(Punto da, Punto per, Punto a) => [..._dritto(da, per), ..._dritto(per, a).skip(1)];

void main() {
  setUp(() async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    await _ilCarattere();
  });

  const nord = Luogo(nome: 'Salerno', posizione: Punto(42.18, 12));

  void telefono(WidgetTester tester, {bool scuro = false}) {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  /// TomTom finto: la strada di adesso rifatta, e una a ovest che risparmia.
  Future<List<PercorsoCalcolato>> strade(
    List<Punto> davanti, {
    required bool eco,
    ModelloConsumoTomTom? consumo,
    List<Rettangolo> evita = const [],
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) async {
    final da = davanti.first, a = davanti.last;
    final ovest = Punto((da.lat + a.lat) / 2, da.lon - 0.02);
    return [_strada(davanti, 10, 4.1), _strada(_via(da, ovest, a), 14, 2.3)];
  }

  for (final scuro in [false, true]) {
    final tono = scuro ? 'scuro' : 'chiaro';

    testWidgets('in guida, la proposta ($tono)', (tester) async {
      final a = await ambiente(tester, km: 20, strade: strade);
      telefono(tester, scuro: scuro);
      await tester.pumpWidget(a.app());
      a.auto.manuale.imposta(80);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(nord));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();
      a.posizioni.add(const Punto(42.0, 12));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.runAsync(a.guida.controllaStrade);
      await tester.pump(const Duration(seconds: 6));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../../collaudo/foto/risparmio/guida-$tono.png'),
      );
    });

    testWidgets('prima di partire, le strade col loro nome ($tono)', (tester) async {
      const da = Punto(42, 12), a = Punto(42.18, 12);
      final rapida = _strada(_dritto(da, a), 72, 14.2);
      final risparmia = _strada(_via(da, const Punto(42.09, 11.97), a), 76, 12.4);
      final simile = _strada(_via(da, const Punto(42.09, 12.03), a), 73, 13.9);
      final e = await ambiente(
        tester,
        strade: strade,
        costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
          percorsi: (_) async => rapida,
          alternative: (_, _) async => [rapida, risparmia, simile],
          colonnine: ColonnineFinte(),
          profilo: profilo,
          preferenze: preferenze,
        ),
      );
      telefono(tester, scuro: scuro);
      await tester.pumpWidget(e.app());
      e.auto.manuale.imposta(80);
      await tester.pump();
      await tester.runAsync(() => e.viaggio.vaiA(nord));
      await tester.pumpAndSettle();
      await scorriScheda(tester, volte: 1);
      await tester.ensureVisible(find.byKey(const Key('strada-2')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../../collaudo/foto/risparmio/strade-$tono.png'),
      );
    });

    testWidgets('le impostazioni ($tono)', (tester) async {
      telefono(tester, scuro: scuro);
      final archivio = Archivio();
      final auto = GestoreAuto(archivio: archivio);
      await tester.runAsync(auto.avvia);
      addTearDown(auto.dispose);
      final r = GestoreRisparmio(archivio: archivio, auto: auto);
      await tester.runAsync(r.carica);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: StradeRisparmioSchermata(risparmio: r),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../../collaudo/foto/risparmio/impostazioni-$tono.png'),
      );
    });
  }
}
