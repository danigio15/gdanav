import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'icona_manovra.dart';

/// Le manovre che meritano la vista dello svincolo: uscite, rampe e bivi.
const tipiSvincolo = {18, 19, 20, 21, 23, 24};

bool haSvincolo(Manovra m) => tipiSvincolo.contains(m.tipo);

/// Lo svincolo visto da chi guida, come nei navigatori: la strada in
/// prospettiva con le sue corsie, il ramo da prendere che si stacca, le
/// corsie giuste in blu con la freccia grande, e sopra il cartello (verde se
/// porta in autostrada, blu altrimenti). Disegnato dalla manovra: quante
/// corsie, quali giuste, da che parte si esce.
class DisegnoSvincolo extends CustomPainter {
  DisegnoSvincolo(this.manovra, {this.sopraFoto = false});

  final Manovra manovra;

  /// Sopra la foto vera dello svincolo: niente strada disegnata, solo la
  /// freccia, le corsie e il cartello.
  final bool sopraFoto;

  bool get _destra => const {18, 20, 23}.contains(manovra.tipo);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final orizzonte = h * 0.30;
    if (sopraFoto) {
      _sopraFoto(canvas, w, h);
      _cartello(canvas, w, h, orizzonte);
      return;
    }

    // Cielo e prato.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, orizzonte),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, orizzonte), [
          const Color(0xFF7DB9EC),
          const Color(0xFFDDEEFB),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, orizzonte, w, h - orizzonte),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, orizzonte), Offset(0, h), [
          const Color(0xFFA9CC93),
          const Color(0xFF6E9E5C),
        ]),
    );

    // Si disegna sempre l'uscita a destra; a sinistra si specchia.
    canvas.save();
    if (!_destra) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    _strada(canvas, w, h, orizzonte);
    canvas.restore();

    _cartello(canvas, w, h, orizzonte);
  }

  /// Le corsie da sinistra a destra, già girate se l'uscita è a sinistra;
  /// e da quale corsia comincia il ramo.
  (int n, int k, List<Corsia> corsie) _corsie() {
    var corsie = manovra.corsieUtili ? manovra.corsie : const <Corsia>[];
    if (!_destra) corsie = corsie.reversed.toList();
    if (corsie.isEmpty) {
      // Senza corsie note: tre che proseguono e una che esce.
      return (4, 3, const []);
    }
    final n = corsie.length;
    final prima = corsie.indexWhere((c) => c.giusta);
    var k = prima < 0 ? n - 1 : prima;
    if (k == 0) k = (n / 2).floor().clamp(1, n - 1);
    return (n, k, corsie);
  }

  void _strada(Canvas canvas, double w, double h, double orizzonte) {
    final (n, k, corsie) = _corsie();
    final fuga = Offset(w * 0.46, orizzonte);
    final xl = w * 0.04, xr = w * 0.96;
    const tSep = 0.34;
    double xb(double i) => xl + i * (xr - xl) / n;
    Offset dritto(double i, double t) {
      final x = xb(i);
      return Offset(x + (fuga.dx - x) * t, h - (h - orizzonte) * t);
    }

    // Il ramo che esce: dalla separazione curva verso destra.
    Offset ramo(double i, double u) {
      final p0 = dritto(i, tSep);
      final j = i - k;
      final p1 = dritto(i, tSep + 0.28);
      final p2 = Offset(w * 0.78 + j * w * 0.012, orizzonte + h * 0.12 + j * h * 0.03);
      final p3 = Offset(w * 1.04, orizzonte + h * 0.07 + j * h * 0.022);
      final a = 1 - u;
      return p0 * (a * a * a) + p1 * (3 * a * a * u) + p2 * (3 * a * u * u) + p3 * (u * u * u);
    }

    final asfalto = Paint()..color = const Color(0xFF5B616B);
    final blu = Paint()..color = const Color(0xFF2F6FE4).withValues(alpha: 0.85);
    final bordo = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.006
      ..style = PaintingStyle.stroke;

    Path fascia(Offset Function(double t) sx, Offset Function(double t) dx, double t0, double t1, {int passi = 24}) {
      final p = Path()..moveTo(sx(t0).dx, sx(t0).dy);
      for (var q = 1; q <= passi; q++) {
        final t = t0 + (t1 - t0) * q / passi;
        p.lineTo(sx(t).dx, sx(t).dy);
      }
      for (var q = passi; q >= 0; q--) {
        final t = t0 + (t1 - t0) * q / passi;
        p.lineTo(dx(t).dx, dx(t).dy);
      }
      return p..close();
    }

    // L'asfalto: il tratto comune, la strada che prosegue, il ramo.
    canvas.drawPath(fascia((t) => dritto(0, t), (t) => dritto(n.toDouble(), t), 0, tSep + 0.005), asfalto);
    canvas.drawPath(fascia((t) => dritto(0, t), (t) => dritto(k.toDouble(), t), tSep - 0.01, 1), asfalto);
    canvas.drawPath(fascia((u) => ramo(k.toDouble(), u), (u) => ramo(n.toDouble(), u), 0, 1), asfalto);

    // Le corsie giuste, in blu fino in fondo al ramo.
    for (var i = 0; i < n; i++) {
      final giusta = corsie.isEmpty ? i >= k : corsie[i].giusta;
      if (!giusta) continue;
      final a = i.toDouble(), b = i + 1.0;
      if (i >= k) {
        canvas.drawPath(fascia((t) => dritto(a, t), (t) => dritto(b, t), 0.02, tSep), blu);
        canvas.drawPath(fascia((u) => ramo(a, u), (u) => ramo(b, u), 0, 0.93), blu);
      } else {
        canvas.drawPath(fascia((t) => dritto(a, t), (t) => dritto(b, t), 0.02, 0.9), blu);
      }
    }

    // Le righe: bordi pieni, fra le corsie tratteggiate.
    void linea(Offset Function(double t) f, double t0, double t1, {bool tratteggio = false}) {
      const passi = 40;
      for (var q = 0; q < passi; q++) {
        if (tratteggio && q.isOdd) continue;
        final a = f(t0 + (t1 - t0) * q / passi), b = f(t0 + (t1 - t0) * (q + 1) / passi);
        canvas.drawLine(a, b, bordo);
      }
    }

    linea((t) => dritto(0, t), 0, 1);
    linea((t) => dritto(n.toDouble(), t), 0, tSep);
    linea((t) => dritto(k.toDouble(), t), tSep, 1);
    linea((u) => ramo(k.toDouble(), u), 0, 1);
    linea((u) => ramo(n.toDouble(), u), 0, 1);
    for (var i = 1; i < n; i++) {
      if (i == k) {
        linea((t) => dritto(k.toDouble(), t), 0, tSep, tratteggio: true);
      } else if (i < k) {
        linea((t) => dritto(i.toDouble(), t), 0, 1, tratteggio: true);
      } else {
        linea((t) => dritto(i.toDouble(), t), 0, tSep, tratteggio: true);
        linea((u) => ramo(i.toDouble(), u), 0, 1, tratteggio: true);
      }
    }

    // La freccia grande, lungo il centro del ramo.
    final centro = (k + n) / 2;
    final punti = <Offset>[
      for (var q = 0; q <= 10; q++) dritto(centro, 0.06 + (tSep - 0.06) * q / 10),
      for (var q = 1; q <= 20; q++) ramo(centro, 0.8 * q / 20),
    ];
    final spessore = w * 0.05;
    final ombra = Paint()
      ..color = const Color(0xFF123E91)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final bianco = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final (colore, extra) in [(ombra, w * 0.012), (bianco, 0.0)]) {
      for (var q = 1; q < punti.length; q++) {
        // Più sottile lontano, come in prospettiva.
        colore.strokeWidth = spessore * (1 - 0.6 * q / punti.length) + extra;
        canvas.drawLine(punti[q - 1], punti[q], colore);
      }
    }
    final fine = punti.last, prima = punti[punti.length - 3];
    final angolo = math.atan2(fine.dy - prima.dy, fine.dx - prima.dx);
    final l = spessore * 1.1;
    final punta = Path()
      ..moveTo(fine.dx + math.cos(angolo) * l, fine.dy + math.sin(angolo) * l)
      ..lineTo(fine.dx + math.cos(angolo + 2.2) * l * 0.8, fine.dy + math.sin(angolo + 2.2) * l * 0.8)
      ..lineTo(fine.dx + math.cos(angolo - 2.2) * l * 0.8, fine.dy + math.sin(angolo - 2.2) * l * 0.8)
      ..close();
    canvas.drawPath(
      punta,
      Paint()
        ..color = const Color(0xFF123E91)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(punta, Paint()..color = Colors.white);
  }

  /// Sulla foto: la freccia grande che curva verso il ramo, e in basso le
  /// corsie con quelle giuste in blu.
  void _sopraFoto(Canvas canvas, double w, double h) {
    // In basso un'ombra, perché freccia e corsie si leggano su ogni foto.
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.55, w, h * 0.45),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, h * 0.55), Offset(0, h), [
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0.45),
        ]),
    );
    canvas.save();
    if (!_destra) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    // La freccia: dal basso sale sulla corsia e piega verso l'uscita.
    final percorso = Path()
      ..moveTo(w * 0.56, h * 0.97)
      ..lineTo(w * 0.60, h * 0.74)
      ..quadraticBezierTo(w * 0.64, h * 0.56, w * 0.82, h * 0.50);
    final metriche = percorso.computeMetrics().first;
    final fine = metriche.getTangentForOffset(metriche.length)!;
    final corpo = metriche.extractPath(0, metriche.length - w * 0.02);
    for (final (colore, spessore) in [
      (const Color(0xCC123E91), w * 0.075),
      (Colors.white.withValues(alpha: 0.95), w * 0.05),
    ]) {
      canvas.drawPath(
        corpo,
        Paint()
          ..color = colore
          ..style = PaintingStyle.stroke
          ..strokeWidth = spessore
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    final a = fine.angle, p = fine.position, l = w * 0.065;
    final punta = Path()
      ..moveTo(p.dx + math.cos(-a) * l, p.dy + math.sin(-a) * l)
      ..lineTo(p.dx + math.cos(-a + 2.3) * l * 0.85, p.dy + math.sin(-a + 2.3) * l * 0.85)
      ..lineTo(p.dx + math.cos(-a - 2.3) * l * 0.85, p.dy + math.sin(-a - 2.3) * l * 0.85)
      ..close();
    canvas.drawPath(
      punta,
      Paint()
        ..color = const Color(0xCC123E91)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.013
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(punta, Paint()..color = Colors.white.withValues(alpha: 0.95));
    canvas.restore();

    // Le corsie, in basso a sinistra: le giuste accese su blu.
    final corsie = manovra.corsieUtili ? manovra.corsie : const <Corsia>[];
    if (corsie.isEmpty) return;
    final lato = h * 0.12, pad = h * 0.018;
    final larghezza = corsie.length * (lato + pad) + pad;
    final riquadro = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.03, h * 0.97 - lato - pad * 2, larghezza, lato + pad * 2),
      Radius.circular(h * 0.03),
    );
    canvas.drawRRect(riquadro, Paint()..color = const Color(0xE61B2130));
    for (final (i, c) in corsie.indexed) {
      final x = riquadro.left + pad + i * (lato + pad), y = riquadro.top + pad;
      if (c.giusta) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, lato, lato), Radius.circular(h * 0.02)),
          Paint()..color = const Color(0xFF2F6FE4),
        );
      }
      for (final d in c.direzioni.isEmpty ? const [DirezioneCorsia.dritto] : c.direzioni) {
        final icona = iconaCorsia(d);
        final accesa = c.giusta && (c.consigliata == null || c.consigliata == d);
        final t = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icona.codePoint),
            style: TextStyle(
              fontFamily: icona.fontFamily,
              package: icona.fontPackage,
              fontSize: lato * 0.85,
              color: accesa ? Colors.white : Colors.white.withValues(alpha: c.giusta ? 0.4 : 0.3),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        t.paint(canvas, Offset(x + (lato - t.width) / 2, y + (lato - t.height) / 2));
      }
    }
  }

  /// Il cartello sopra il ramo: uscita e direzione, come in autostrada.
  void _cartello(Canvas canvas, double w, double h, double orizzonte) {
    final verso = manovra.verso.isNotEmpty
        ? manovra.verso
        : (manovra.strada.isNotEmpty ? manovra.strada : manovra.istruzione);
    final autostrada = RegExp(r'\bA\s?\d').hasMatch('$verso ${manovra.strada}');
    final larghezza = w * 0.46, x = _destra ? w * 0.52 : w * 0.02, y = h * 0.035;
    final testo = TextPainter(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          color: Colors.white,
          fontSize: h * 0.058,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
        children: [
          if (manovra.uscita.isNotEmpty)
            TextSpan(
              text: ' ${manovra.uscita} ',
              style: const TextStyle(color: Colors.black, backgroundColor: Colors.white),
            ),
          if (manovra.uscita.isNotEmpty) const TextSpan(text: '  '),
          TextSpan(text: verso.replaceAll(' · ', '\n')),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: larghezza - h * 0.14);
    final altezza = testo.height + h * 0.05;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, larghezza, altezza), Radius.circular(h * 0.02));
    // I pali del portale.
    final palo = Paint()..color = const Color(0xFF8A9099);
    canvas.drawRect(
      Rect.fromLTWH(x + larghezza * 0.2, y + altezza, w * 0.008, orizzonte - y - altezza + h * 0.02),
      palo,
    );
    canvas.drawRect(
      Rect.fromLTWH(x + larghezza * 0.8, y + altezza, w * 0.008, orizzonte - y - altezza + h * 0.02),
      palo,
    );
    canvas.drawRRect(r, Paint()..color = autostrada ? const Color(0xFF0B7A3E) : const Color(0xFF1558B0));
    canvas.drawRRect(
      r.deflate(h * 0.008),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.006,
    );
    testo.paint(canvas, Offset(x + h * 0.03, y + h * 0.025));
    // La freccia del cartello, verso il ramo.
    final fx = x + larghezza - h * 0.07, fy = y + altezza / 2;
    canvas.save();
    canvas.translate(fx, fy);
    canvas.rotate(_destra ? math.pi / 4 : -math.pi / 4);
    final f = h * 0.035;
    canvas.drawPath(
      Path()
        ..moveTo(0, -f * 1.4)
        ..lineTo(f, 0)
        ..lineTo(f * 0.35, 0)
        ..lineTo(f * 0.35, f * 1.3)
        ..lineTo(-f * 0.35, f * 1.3)
        ..lineTo(-f * 0.35, 0)
        ..lineTo(-f, 0)
        ..close(),
      Paint()..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DisegnoSvincolo old) => old.manovra != manovra || old.sopraFoto != sopraFoto;
}

/// La vista dello svincolo in PNG, per lo schermo di Android Auto: sulla foto
/// vera se c'è ([foto], JPEG di Mapillary, con [citazione]), altrimenti
/// disegnata.
Future<Uint8List> svincoloPng(
  Manovra m, {
  Uint8List? foto,
  String? citazione,
  double larghezza = 800,
  double altezza = 480,
}) async {
  final registro = ui.PictureRecorder();
  final canvas = Canvas(registro);
  final dimensione = Size(larghezza, altezza);
  ui.Image? scatto;
  if (foto != null) {
    try {
      scatto = (await (await ui.instantiateImageCodec(foto)).getNextFrame()).image;
    } catch (_) {}
  }
  if (scatto != null) {
    // La foto a riempire, tagliata al centro.
    final originale = Size(scatto.width.toDouble(), scatto.height.toDouble());
    final sorgente = applyBoxFit(BoxFit.cover, originale, dimensione).source;
    final da = Alignment.center.inscribe(sorgente, Offset.zero & originale);
    canvas.drawImageRect(scatto, da, Offset.zero & dimensione, Paint()..filterQuality = FilterQuality.medium);
    DisegnoSvincolo(m, sopraFoto: true).paint(canvas, dimensione);
    if (citazione != null) {
      final t = TextPainter(
        text: TextSpan(
          text: citazione,
          style: TextStyle(fontFamily: 'Roboto', color: Colors.white70, fontSize: altezza * 0.03),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: larghezza * 0.6);
      t.paint(canvas, Offset(larghezza - t.width - altezza * 0.02, altezza - t.height - altezza * 0.015));
    }
  } else {
    DisegnoSvincolo(m).paint(canvas, dimensione);
  }
  final immagine = await registro.endRecording().toImage(larghezza.round(), altezza.round());
  final dati = await immagine.toByteData(format: ui.ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}

/// Il popup sul telefono: la vista, i metri che mancano con la barra che si
/// accorcia, e la X per chiuderlo.
class PopupSvincolo extends StatelessWidget {
  const PopupSvincolo({super.key, required this.manovra, required this.metri, required this.onChiudi, this.foto});

  final Manovra manovra;

  /// La foto vera dello svincolo, se Mapillary ce l'ha.
  final (FotoStrada, Uint8List)? foto;
  final double metri;
  final VoidCallback onChiudi;

  static const daMetri = 800.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      key: const Key('popup-svincolo'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 5 / 3,
              child: switch (foto) {
                (final f, final byte) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(byte, key: const Key('foto-svincolo'), fit: BoxFit.cover, gaplessPlayback: true),
                    CustomPaint(painter: DisegnoSvincolo(manovra, sopraFoto: true)),
                    Positioned(
                      right: 8,
                      top: 4,
                      child: Text(
                        f.citazione,
                        style: const TextStyle(color: Colors.white70, fontSize: 10, shadows: [Shadow(blurRadius: 3)]),
                      ),
                    ),
                  ],
                ),
                null => CustomPaint(painter: DisegnoSvincolo(manovra)),
              },
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                decoration: BoxDecoration(color: const Color(0xE6202633), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distanzaBreve(metri),
                      style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 90,
                      child: LinearProgressIndicator(
                        value: (metri / daMetri).clamp(0.0, 1.0),
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: IconButton.filled(
                key: const Key('chiudi-svincolo'),
                style: IconButton.styleFrom(backgroundColor: const Color(0xCC202633)),
                onPressed: onChiudi,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
