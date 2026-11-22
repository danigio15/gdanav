/// Le fotografie del riquadro della manovra in guida, sul telefono: lontano
/// dalla svolta (la riga sola) e vicino (il riquadro grande), dritto e di
/// traverso, chiaro e scuro, su una mappa finta disegnata, così il vetro si
/// vede.
///
/// Non è una prova: è un attrezzo per **guardare** (il nome non finisce in
/// `_test.dart`, e `flutter test` da solo non lo prende). Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/riquadro_manovra_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/riquadro/` (che la repository
/// non tiene), col nome che comincia per `FOTO_PREFISSO` se c'è (`prima-`
/// sul codice di prima, per il confronto).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart' show Lettura;
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

/// Roboto e le icone di Material, dalla cartella di Flutter: senza, la
/// fotografia esce a quadratini.
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

const _dove = '../../../../collaudo/foto/riquadro';
final _prefisso = Platform.environment['FOTO_PREFISSO'] ?? '';

/// Una mappa finta: isolati, un parco, le vie, il percorso in blu e la
/// freccia dell'auto dove la mette la guida (più in basso dritti, nel mezzo
/// della parte libera di traverso).
class _MappaFinta extends CustomPainter {
  const _MappaFinta({required this.scuro, required this.sinistra});

  final bool scuro;
  final double sinistra;

  @override
  void paint(Canvas canvas, Size size) {
    final fondo = scuro ? const Color(0xFF1D2740) : const Color(0xFFEDE9E1);
    final isolato = scuro ? const Color(0xFF26314C) : const Color(0xFFE0DACD);
    final parco = scuro ? const Color(0xFF1E3B33) : const Color(0xFFC8E3C0);
    final via = scuro ? const Color(0xFF3A4766) : Colors.white;
    canvas.drawRect(Offset.zero & size, Paint()..color = fondo);
    const passo = 74.0;
    for (var y = -20.0; y < size.height; y += passo) {
      for (var x = -30.0; x < size.width; x += passo) {
        final verde = ((x / passo).round() + (y / passo).round() * 3) % 7 == 0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 7, y + 7, passo - 14, passo - 14), const Radius.circular(4)),
          Paint()..color = verde ? parco : isolato,
        );
      }
    }
    final strada = Paint()
      ..color = via
      ..strokeWidth = 9;
    for (var y = -20.0; y < size.height; y += passo) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), strada);
    }
    for (var x = -30.0; x < size.width; x += passo) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), strada);
    }
    // Un viale in diagonale, con un nome scritto, perché si veda il vetro.
    canvas.drawLine(Offset(0, size.height * 0.05), Offset(size.width, size.height * 0.4), strada..strokeWidth = 16);
    final testo = TextPainter(
      text: TextSpan(
        text: 'Viale delle Prove',
        style: TextStyle(
          fontFamily: 'Roboto',
          color: scuro ? Colors.white60 : Colors.black54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    for (final x in [40.0, 220.0, 420.0, 640.0]) {
      testo.paint(canvas, Offset(x, size.height * 0.05 + x / size.width * size.height * 0.35 - 30));
    }
    // Il percorso e l'auto.
    final libera = size.width - sinistra;
    final auto = Offset(sinistra + libera / 2, size.height * (size.width > size.height ? 0.5 : 0.68));
    canvas.drawLine(
      Offset(auto.dx, size.height),
      Offset(auto.dx, 0),
      Paint()
        ..color = const Color(0xFF2F6FE4)
        ..strokeWidth = 12,
    );
    final freccia = Path()
      ..moveTo(auto.dx, auto.dy - 16)
      ..lineTo(auto.dx + 12, auto.dy + 13)
      ..lineTo(auto.dx, auto.dy + 6)
      ..lineTo(auto.dx - 12, auto.dy + 13)
      ..close();
    canvas.drawCircle(auto, 22, Paint()..color = Colors.white);
    canvas.drawPath(freccia, Paint()..color = const Color(0xFF1A73E8));
  }

  @override
  bool shouldRepaint(_MappaFinta vecchia) => vecchia.scuro != scuro || vecchia.sinistra != sinistra;
}

/// Verso nord ogni 100 m: a 2,5 km si gira a destra, a 4,5 km a sinistra.
(PercorsoCalcolato, List<Punto>) _percorso({String via = 'Via delle Prove'}) {
  final punti = [for (var i = 0; i <= 60; i++) Punto(42 + i * 0.0009, 12)];
  final linea = Linea(punti);
  double da(int a, int b) => linea.cumulate[b] - linea.cumulate[a];
  return (
    PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 50),
      ],
      manovre: [
        Manovra(istruzione: 'Parti verso nord', lunghezzaM: da(0, 25), secondi: 180, inizio: 0, tipo: 1),
        Manovra(
          istruzione: 'Gira a destra in $via',
          lunghezzaM: da(25, 45),
          secondi: 140,
          inizio: 25,
          tipo: 10,
          strada: via,
        ),
        Manovra(
          istruzione: "Gira a sinistra in Viale dell'Esempio",
          lunghezzaM: da(45, 60),
          secondi: 100,
          inizio: 45,
          tipo: 15,
          strada: "Viale dell'Esempio",
        ),
        Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: 60, tipo: 4),
      ],
      limiti: [for (var i = 1; i < punti.length; i++) 50],
    ),
    punti,
  );
}

void main() {
  setUp(_caratteri);

  // Larghezza × altezza in punti, e il bordo sicuro.
  const schermi = <String, (Size, EdgeInsets)>{
    'telefono': (Size(390, 844), EdgeInsets.fromLTRB(0, 47, 0, 34)),
    'traverso': (Size(844, 390), EdgeInsets.fromLTRB(47, 0, 47, 21)),
    'tablet': (Size(820, 1180), EdgeInsets.fromLTRB(0, 24, 0, 20)),
  };

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';
    for (final MapEntry(key: schermo, value: (punti, bordo)) in schermi.entries) {
      for (final (lungo, via) in [(false, 'Via delle Prove'), (true, 'Via del Nome Lunghissimo che Non Finisce Mai')]) {
        if (lungo && schermo == 'tablet') continue;
        final nome = lungo ? '-via-lunga' : '';
        testWidgets('il riquadro della manovra, $schermo$nome ($luce)', (tester) async {
          preparaPiattaforma(portachiavi: impostazioniComplete);
          final (percorso, tappe) = _percorso(via: via);
          final a = await ambiente(
            tester,
            km: 6,
            costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
              percorsi: (_) async => percorso,
              colonnine: ColonnineFinte(),
              profilo: profilo,
              preferenze: preferenze,
            ),
          );
          tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
          await tester.pumpWidget(
            GdanavApp(
              posizione: a.posizione,
              archivio: a.archivio,
              auto: a.auto,
              viaggio: a.viaggio,
              guida: a.guida,
              segnalazioni: a.segnalazioni,
              mappa: (context, c) => CustomPaint(
                painter: _MappaFinta(scuro: scuro, sinistra: c.copertoSinistra),
                child: const SizedBox.expand(),
              ),
            ),
          );
          a.posizione.avvia();
          a.auto.manuale.imposta(70);
          await tester.pump();
          await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.054, 12))));
          await tester.pumpAndSettle();
          expect(a.viaggio.stato, isA<ViaggioPronto>());
          await tester.tap(find.text('Avvia'));
          await tester.pumpAndSettle();
          // Lo schermo della foto solo ora: di traverso il pannello della
          // partenza vuole lo scorrimento per arrivare ad «Avvia».
          const densita = 2.0;
          tester.view
            ..physicalSize = punti * densita
            ..devicePixelRatio = densita;
          final b = FakeViewPadding(
            left: bordo.left * densita,
            top: bordo.top * densita,
            right: bordo.right * densita,
            bottom: bordo.bottom * densita,
          );
          tester.view
            ..padding = b
            ..viewPadding = b;
          // A 1,5 km dalla svolta, poi a 200 m.
          for (final (i, quando) in [(10, 'lontano'), (23, 'vicino')]) {
            a.posizioni.add(tappe[i]);
            // Anche il segnaposto, che se tace dice «GPS assente».
            a.gps.add(Lettura(tappe[i], velocitaMs: 13.9, rotta: 0));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('$_dove/$_prefisso$schermo$nome-$quando-$luce.png'),
            );
          }
          await tester.runAsync(a.guida.ferma);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }

    // La voce del menu e la sua scelta (solo col codice nuovo).
    if (_prefisso != 'prima-') {
      testWidgets('«Dimensione indicazioni» nel menu ($luce)', (tester) async {
        preparaPiattaforma(portachiavi: impostazioniComplete);
        final a = await ambiente(tester);
        tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view
          ..physicalSize = const Size(390, 844) * 2
          ..devicePixelRatio = 2;
        await tester.pumpWidget(a.app());
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('menu-indicazioni')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/${_prefisso}menu-$luce.png'));
        await tester.tap(find.byKey(const Key('menu-indicazioni')));
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/${_prefisso}scelta-$luce.png'));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
