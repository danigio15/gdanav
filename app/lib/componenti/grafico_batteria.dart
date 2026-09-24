import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../tema.dart';

/// La batteria lungo il viaggio: scende guidando, sale alle soste. La linea
/// tratteggiata è la soglia con cui si vuole arrivare.
class GraficoBatteria extends StatelessWidget {
  const GraficoBatteria({super.key, required this.piano, required this.soglia, this.altezza = 120});

  final PianoViaggio piano;
  final double soglia;
  final double altezza;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      label:
          'Grafico della batteria: parte dal ${piano.profiloBatteria.first.batteria.round()}%, '
          'arriva al ${piano.batteriaArrivo.round()}%',
      child: SizedBox(
        height: altezza,
        child: CustomPaint(
          painter: _Pittore(
            punti: piano.profiloBatteria,
            soste: [for (final s in piano.soste) s.colonnina.distanzaM / 1000],
            soglia: soglia,
            colori: ColoriGdanav.di(context),
            griglia: tema.colorScheme.outlineVariant,
            etichette: tema.textTheme.labelSmall!.copyWith(color: tema.colorScheme.onSurfaceVariant),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Pittore extends CustomPainter {
  _Pittore({
    required this.punti,
    required this.soste,
    required this.soglia,
    required this.colori,
    required this.griglia,
    required this.etichette,
  });

  final List<PuntoBatteria> punti;
  final List<double> soste;
  final double soglia;
  final ColoriGdanav colori;
  final Color griglia;
  final TextStyle etichette;

  @override
  void paint(Canvas canvas, Size size) {
    if (punti.length < 2) return;
    const sx = 30.0, basso = 18.0;
    final w = size.width - sx, h = size.height - basso;
    final km = math.max(punti.last.km, 0.001);
    Offset xy(double k, double b) => Offset(sx + k / km * w, h - b / 100 * h);

    // Griglia e scala: 0, 50, 100%.
    final g = Paint()
      ..color = griglia.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final b in [0, 50, 100]) {
      final y = h - b / 100 * h;
      canvas.drawLine(Offset(sx, y), Offset(size.width, y), g);
      _testo(canvas, '$b%', Offset(0, y - 7));
    }
    // Soglia d'arrivo, tratteggiata.
    final ys = h - soglia / 100 * h;
    final ts = Paint()
      ..color = colori.guasta.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    for (var x = sx; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, ys), Offset(math.min(x + 4, size.width), ys), ts);
    }

    final linea = Path()
      ..moveTo(xy(punti.first.km, punti.first.batteria).dx, xy(punti.first.km, punti.first.batteria).dy);
    for (final p in punti.skip(1)) {
      final o = xy(p.km, p.batteria);
      linea.lineTo(o.dx, o.dy);
    }
    final area = Path.from(linea)
      ..lineTo(xy(punti.last.km, 0).dx, h)
      ..lineTo(sx, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colori.percorso.withValues(alpha: 0.28), colori.percorso.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(sx, 0, w, h)),
    );
    canvas.drawPath(
      linea,
      Paint()
        ..color = colori.percorso
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    // Le soste: un pallino verde dove la batteria risale.
    for (final (i, k) in soste.indexed) {
      final dopo = punti.lastWhere((p) => p.km <= k + 1e-6);
      final o = xy(k, dopo.batteria);
      canvas.drawCircle(o, 7, Paint()..color = colori.libera);
      _testo(canvas, '${i + 1}', o - const Offset(3.5, 7), colore: Colors.white, grassetto: true);
    }
    final fine = xy(punti.last.km, punti.last.batteria);
    canvas.drawCircle(fine, 5, Paint()..color = colori.arrivo);
    _testo(canvas, '0 km', Offset(sx, h + 3));
    final kmTesto = '${punti.last.km.round()} km';
    _testo(canvas, kmTesto, Offset(size.width - 8 * kmTesto.length.toDouble(), h + 3));
  }

  void _testo(Canvas canvas, String s, Offset o, {Color? colore, bool grassetto = false}) {
    TextPainter(
        text: TextSpan(
          text: s,
          style: etichette.copyWith(color: colore, fontWeight: grassetto ? FontWeight.w800 : null),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, o);
  }

  @override
  bool shouldRepaint(_Pittore old) => old.punti != punti || old.colori != colori || old.soglia != soglia;
}
