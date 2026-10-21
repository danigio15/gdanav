import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/stile.dart' show larghezzaBandieraArrivo, larghezzaPuntaManovra;

/// L'icona di una manovra di Valhalla (il suo campo `type`).
IconData iconaManovra(int tipo) => switch (tipo) {
  4 || 5 || 6 => Icons.sports_score,
  9 => Icons.turn_slight_right,
  23 => Icons.fork_right,
  10 || 2 => Icons.turn_right,
  11 => Icons.turn_sharp_right,
  12 => Icons.u_turn_right,
  13 => Icons.u_turn_left,
  14 => Icons.turn_sharp_left,
  15 || 3 => Icons.turn_left,
  16 => Icons.turn_slight_left,
  24 => Icons.fork_left,
  18 || 20 => Icons.ramp_right,
  19 || 21 => Icons.ramp_left,
  25 || 37 || 38 => Icons.merge,
  26 || 27 => Icons.roundabout_right,
  28 || 29 => Icons.directions_boat,
  _ => Icons.straight,
};

/// La freccia dipinta su una corsia.
IconData iconaCorsia(DirezioneCorsia d) => switch (d) {
  DirezioneCorsia.inversioneSinistra => Icons.u_turn_left,
  DirezioneCorsia.sinistraStretta => Icons.turn_sharp_left,
  DirezioneCorsia.sinistra => Icons.turn_left,
  DirezioneCorsia.leggeraSinistra => Icons.turn_slight_left,
  DirezioneCorsia.dritto => Icons.straight,
  DirezioneCorsia.leggeraDestra => Icons.turn_slight_right,
  DirezioneCorsia.destra => Icons.turn_right,
  DirezioneCorsia.destraStretta => Icons.turn_sharp_right,
  DirezioneCorsia.inversioneDestra => Icons.u_turn_right,
};

/// Le corsie prima dello svincolo, come sul cartello: quelle giuste bianche
/// su blu, le altre spente. Ogni corsia mostra le sue frecce; quella da
/// seguire è accesa.
class CorsieSvincolo extends StatelessWidget {
  const CorsieSvincolo({super.key, required this.corsie, this.lato = 34});

  final List<Corsia> corsie;
  final double lato;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('corsie'),
      decoration: BoxDecoration(color: const Color(0xFF1B2130), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, c) in corsie.indexed) ...[
              if (i > 0)
                Container(
                  width: 2,
                  height: lato * 0.9,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: Colors.white24,
                ),
              Container(
                width: lato + 12,
                height: lato + 12,
                decoration: BoxDecoration(
                  color: c.giusta ? const Color(0xFF2F6FE4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final d in c.direzioni.isEmpty ? const [DirezioneCorsia.dritto] : c.direzioni)
                      Icon(
                        iconaCorsia(d),
                        size: lato,
                        color: !c.giusta
                            ? Colors.white30
                            : (c.consigliata == null || c.consigliata == d)
                            ? Colors.white
                            : Colors.white38,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Il cartello dello svincolo: numero d'uscita e direzione. Verde se porta in
/// autostrada, blu altrimenti, come in Italia.
class CartelloSvincolo extends StatelessWidget {
  const CartelloSvincolo({super.key, required this.manovra});

  final Manovra manovra;

  @override
  Widget build(BuildContext context) {
    final autostrada = RegExp(r'\bA\s?\d').hasMatch(manovra.verso) || RegExp(r'\bA\s?\d').hasMatch(manovra.strada);
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('cartello'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: autostrada ? const Color(0xFF0B7A3E) : const Color(0xFF1558B0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (manovra.uscita.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text(
                'Uscita ${manovra.uscita}',
                style: t.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              manovra.verso,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// La punta della freccia di manovra sulla mappa ([immaginePuntaManovra]):
/// un triangolo bianco bordato di blu scuro, la base in basso e la punta in
/// alto. Larga [larghezzaPuntaManovra] punti, disegnata a [scala].
Future<Uint8List> puntaManovraPng({double scala = 3}) async {
  const larga = larghezzaPuntaManovra, alta = larga * 0.95, bordo = 3.0;
  final registro = ui.PictureRecorder();
  final c = Canvas(registro)..scale(scala);
  final punta = Path()
    ..moveTo(larga / 2, bordo)
    ..lineTo(larga - bordo, alta - bordo)
    ..lineTo(bordo, alta - bordo)
    ..close();
  c.drawPath(
    punta,
    Paint()
      ..color = const Color(0xFF0B3C78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bordo * 2
      ..strokeJoin = StrokeJoin.round,
  );
  c.drawPath(punta, Paint()..color = Colors.white);
  final img = await registro.endRecording().toImage((larga * scala).round(), (alta * scala).round());
  final dati = await img.toByteData(format: ui.ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}

/// La bandiera a scacchi sulla meta ([immagineBandieraArrivo]), al posto del
/// punto rosso: l'asta in mezzo all'immagine, la base in basso (lì si posa
/// sulla meta), la bandiera a destra. Larga [larghezzaBandieraArrivo] punti.
Future<Uint8List> bandieraArrivoPng({double scala = 3}) async {
  const larga = larghezzaBandieraArrivo, alta = larga * 1.15;
  const asta = larga / 2, cima = 3.0, lato = 5.0, colonne = 4, righe = 3;
  final registro = ui.PictureRecorder();
  final c = Canvas(registro)..scale(scala);
  // L'ombra della base, e la base.
  c.drawOval(
    Rect.fromCenter(center: Offset(asta, alta - 3.5), width: 16, height: 6),
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
  );
  c.drawCircle(Offset(asta, alta - 4), 3.2, Paint()..color = const Color(0xFF1F2937));
  // L'asta, bordata di bianco perché si veda anche sullo scuro.
  const asse = Offset(asta, cima);
  c.drawLine(asse, Offset(asta, alta - 4), Paint()
    ..color = Colors.white
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round);
  c.drawLine(asse, Offset(asta, alta - 4), Paint()
    ..color = const Color(0xFF1F2937)
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round);
  // La bandiera a scacchi, un poco mossa, col bordo bianco.
  const x0 = asta + 1.5, y0 = cima + 1;
  Path telo(double dx, double dy, double l) {
    final onda = l * 0.12;
    return Path()
      ..moveTo(x0 + dx, y0 + dy)
      ..quadraticBezierTo(x0 + dx + l * colonne / 2, y0 + dy - onda, x0 + dx + l * colonne, y0 + dy)
      ..lineTo(x0 + dx + l * colonne, y0 + dy + l * righe)
      ..quadraticBezierTo(x0 + dx + l * colonne / 2, y0 + dy + l * righe - onda, x0 + dx, y0 + dy + l * righe)
      ..close();
  }

  c.drawPath(
    telo(0, 0, lato),
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round,
  );
  c.drawPath(telo(0, 0, lato), Paint()..color = Colors.white);
  c.save();
  c.clipPath(telo(0, 0, lato));
  final nero = Paint()..color = const Color(0xFF111827);
  for (var r = 0; r < righe + 1; r++) {
    for (var k = 0; k < colonne; k++) {
      if ((r + k).isOdd) continue;
      c.drawRect(Rect.fromLTWH(x0 + k * lato, y0 + r * lato - lato * 0.12, lato, lato), nero);
    }
  }
  c.restore();
  c.drawPath(
    telo(0, 0, lato),
    Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  final img = await registro.endRecording().toImage((larga * scala).round(), (alta * scala).round());
  final dati = await img.toByteData(format: ui.ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}
