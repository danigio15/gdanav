import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema.dart';

/// Un anello che si riempie con la batteria: verde, poi ambra sotto il 30%,
/// rosso sotto il 15%.
class AnelloBatteria extends StatelessWidget {
  const AnelloBatteria({super.key, required this.batteria, this.dimensione = 44, this.spessore = 5, this.child});

  final double? batteria;
  final double dimensione;
  final double spessore;
  final Widget? child;

  static Color colore(BuildContext context, double? b) {
    final c = ColoriGdanav.di(context);
    if (b == null) return c.ignota;
    if (b < 15) return c.guasta;
    if (b < 30) return c.piena;
    return c.libera;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimensione,
      child: CustomPaint(
        painter: _Anello(
          (batteria ?? 0) / 100,
          colore(context, batteria),
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          spessore,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _Anello extends CustomPainter {
  _Anello(this.frazione, this.colore, this.fondo, this.spessore);
  final double frazione;
  final Color colore;
  final Color fondo;
  final double spessore;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(spessore / 2, spessore / 2, size.width - spessore, size.height - spessore);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spessore
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * math.pi, false, p..color = fondo);
    if (frazione > 0) {
      canvas.drawArc(r, -math.pi / 2, 2 * math.pi * frazione.clamp(0, 1), false, p..color = colore);
    }
  }

  @override
  bool shouldRepaint(_Anello old) => old.frazione != frazione || old.colore != colore || old.fondo != fondo;
}
