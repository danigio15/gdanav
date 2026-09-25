import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Lo svincolo come lo vede chi guida, in 3D vero: una camera ad altezza
/// d'uomo guarda la strada davanti. Le corsie sono larghe 3,6 m, le righe
/// tratteggiate come in autostrada, il ramo che esce curva via; le corsie
/// giuste sono blu con le frecce bianche dipinte sull'asfalto. Intorno cielo
/// con le nuvole, colline, alberi e qualche edificio lontano.
class ScenaSvincolo extends CustomPainter {
  ScenaSvincolo(this.manovra);

  final Manovra manovra;

  static const _corsia = 3.6;
  static const _altezzaCamera = 8.5;
  static const _separazione = 20.0;
  static const _vicino = 4.0;

  bool get _destra => const {18, 20, 23}.contains(manovra.tipo);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final orizzonte = h * 0.36;
    _cielo(canvas, w, orizzonte);
    _terreno(canvas, w, h, orizzonte);

    final (n, k, giuste, _) = _corsie();
    // La camera sta sopra la linea che separa il ramo, un po' verso l'interno.
    final camX = k * _corsia - 0.4;
    final f = math.max(w, h * 1.2) * 0.78;
    Offset p(Offset mondo, [double quota = 0]) =>
        Offset(w / 2 + f * (mondo.dx - camX) / mondo.dy, orizzonte + f * (_altezzaCamera - quota) / mondo.dy);

    // Il ramo: dritto fino alla separazione, poi curva sempre di più
    // (come una clotoide) fino a 70°. Si integra una volta sola, ogni metro.
    final base = <Offset>[const Offset(0, 0)], rotte = <double>[0];
    for (var t = 1; t <= 600; t++) {
      final d = math.max(0.0, t - _separazione);
      final rotta = math.min(1.1, 0.5 * 2.6e-4 * d * d);
      rotte.add(rotta);
      base.add(base.last + Offset(math.sin(rotta), math.cos(rotta)));
    }
    Offset ramo(double j, double t) {
      final i = t.clamp(0.0, 599.0), i0 = i.floor(), fr = i - i0;
      final b = Offset.lerp(base[i0], base[i0 + 1], fr)!;
      final r = rotte[i0] + (rotte[i0 + 1] - rotte[i0]) * fr;
      // Di lato, perpendicolare alla direzione: le corsie restano larghe 3,6 m.
      final lato = (j - k) * _corsia;
      return Offset(k * _corsia + b.dx + lato * math.cos(r), b.dy - lato * math.sin(r));
    }

    Offset principale(double j, double z) => Offset(j * _corsia, z);

    canvas.save();
    if (!_destra) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }

    /// I parametri lungo una strada: fitti vicino, più radi lontano.
    List<double> passi(double t0, double t1) {
      final l = <double>[];
      for (var t = t0; t < t1; t += math.max(0.5, t * 0.04)) {
        l.add(t);
      }
      return l..add(t1);
    }

    Path fascia(Offset Function(double t) sx, Offset Function(double t) dx, double t0, double t1) {
      final l = passi(t0, t1).where((t) => sx(t).dy > 0.5 && dx(t).dy > 0.5).toList();
      final path = Path()..moveTo(p(sx(l.first)).dx, p(sx(l.first)).dy);
      for (final t in l) {
        path.lineTo(p(sx(t)).dx, p(sx(t)).dy);
      }
      for (final t in l.reversed) {
        path.lineTo(p(dx(t)).dx, p(dx(t)).dy);
      }
      return path..close();
    }

    // Banchine chiare, poi l'asfalto.
    final banchina = Paint()..color = const Color(0xFFCDD0C8);
    canvas.drawPath(
      fascia((z) => const Offset(-1.6, 0) + Offset(0, z), (z) => principale(k.toDouble(), z), _vicino, 3000),
      banchina,
    );
    canvas.drawPath(fascia((t) => ramo(k.toDouble(), t), (t) => ramo(n + 0.45, t), _vicino, 600), banchina);
    final asfalto = Paint()
      ..shader = ui.Gradient.linear(Offset(0, h), Offset(0, orizzonte), [
        const Color(0xFF383C43),
        const Color(0xFF5C6169),
      ]);
    canvas.drawPath(fascia((z) => principale(0, z), (z) => principale(k.toDouble(), z), _vicino, 3000), asfalto);
    canvas.drawPath(fascia((t) => ramo(k.toDouble(), t), (t) => ramo(n.toDouble(), t), _vicino, 600), asfalto);

    // Le corsie giuste, blu da riga a riga (le righe ci vanno sopra).
    final blu = Paint()
      ..shader = ui.Gradient.linear(Offset(0, h), Offset(0, orizzonte), [
        const Color(0xE01C6FF0),
        const Color(0xB35A9CF6),
      ]);
    for (var i = 0; i < n; i++) {
      if (!giuste.contains(i)) continue;
      final a = i.toDouble(), b = i + 1.0;
      if (i >= k) {
        canvas.drawPath(fascia((t) => ramo(a, t), (t) => ramo(b, t), _vicino, 600), blu);
      } else {
        canvas.drawPath(fascia((z) => principale(a, z), (z) => principale(b, z), _vicino, 3000), blu);
      }
    }

    // Fra le carreggiate, dove si separano, la cuspide: asfalto con le
    // strisce bianche oblique, finché lo spazio non diventa prato.
    const cuspide = 58.0;
    canvas.drawPath(
      fascia((t) => principale(k.toDouble(), t), (t) => ramo(k.toDouble(), t), _separazione, _separazione + cuspide),
      asfalto,
    );
    final zebra = Paint()..color = const Color(0xF2F4F6F8);
    for (var t = _separazione + 7; t < _separazione + cuspide - 2; t += 4.5) {
      final a = principale(k.toDouble(), t), b = ramo(k.toDouble(), t + 3.5);
      if ((b.dx - a.dx) < 0.9) continue;
      final a2 = principale(k.toDouble(), t + 1.1), b2 = ramo(k.toDouble(), t + 4.6);
      canvas.drawPath(
        Path()
          ..moveTo(p(a).dx, p(a).dy)
          ..lineTo(p(b).dx, p(b).dy)
          ..lineTo(p(b2).dx, p(b2).dy)
          ..lineTo(p(a2).dx, p(a2).dy)
          ..close(),
        zebra,
      );
    }
    // Chiude la cuspide un cordolo chiaro, poi comincia il prato.
    canvas.drawPath(
      fascia(
        (t) => principale(k.toDouble(), _separazione + cuspide + t),
        (t) => ramo(k.toDouble(), _separazione + cuspide + t),
        0,
        1.2,
      ),
      banchina,
    );

    // Le righe: bordi pieni, fra le corsie tratteggiate (6 m pieni e 9
    // vuoti), larghe 15 cm come sulle strade vere.
    final bianco = Paint()..color = const Color(0xFFF6F8FA);
    void riga(Offset Function(double t) punto, double t0, double t1, {bool tratteggio = false, double larga = 0.15}) {
      Offset lato(double t, double s) {
        final a = punto(t), b = punto(t + 0.5);
        final d = b - a;
        final l = d.distance == 0 ? 1.0 : d.distance;
        return a + Offset(d.dy / l, -d.dx / l) * s;
      }

      var t = t0;
      while (t < t1) {
        final fine = math.min(t + (tratteggio ? 6.0 : math.max(1.0, t * 0.04)), t1);
        if (fine <= _vicino) {
          t = fine + (tratteggio ? 9.0 : 0);
          continue;
        }
        final l = passi(math.max(t, _vicino), fine);
        final path = Path();
        for (final (j, q) in l.indexed) {
          final o = p(lato(q, -larga / 2));
          j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        for (final q in l.reversed) {
          final o = p(lato(q, larga / 2));
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path..close(), bianco);
        t = fine + (tratteggio ? 9.0 : 0);
      }
    }

    riga((z) => principale(0.07, z), _vicino, 3000, larga: 0.25);
    riga((z) => principale(k - 0.07, z), _separazione, 3000, larga: 0.25);
    riga((t) => ramo(k + 0.07, t), _separazione, 600, larga: 0.25);
    riga((t) => ramo(n - 0.07, t), _vicino, 600, larga: 0.25);
    for (var i = 1; i < n; i++) {
      if (i == k) {
        // Il tratteggio che separa il ramo finisce giusto dove si divide.
        riga((z) => principale(k.toDouble(), z), _separazione - 6 - 15 * 3, _separazione, tratteggio: true, larga: 0.4);
      } else if (i < k) {
        riga((z) => principale(i.toDouble(), z), _vicino, 3000, tratteggio: true, larga: 0.2);
      } else {
        riga((t) => ramo(i.toDouble(), t), _vicino, 600, tratteggio: true, larga: 0.2);
      }
    }

    // I guardrail ai lati: la fascia d'acciaio sui paletti.
    final lamiera = Paint()..color = const Color(0xFFB9C0C8);
    final lamieraScura = Paint()..color = const Color(0xFF8E959E);
    void guardrail(Offset Function(double t) punto, double t0, double t1) {
      final l = passi(math.max(t0, _vicino), t1);
      for (var t = (t0 / 4).ceil() * 4.0; t < t1; t += 4) {
        if (t < _vicino) continue;
        final a = p(punto(t)), b = p(punto(t), 0.75);
        canvas.drawLine(a, b, lamieraScura..strokeWidth = math.max(1.0, f * 0.12 / punto(t).dy));
      }
      final fascia = Path();
      for (final (j, q) in l.indexed) {
        final o = p(punto(q), 0.82);
        j == 0 ? fascia.moveTo(o.dx, o.dy) : fascia.lineTo(o.dx, o.dy);
      }
      for (final q in l.reversed) {
        final o = p(punto(q), 0.5);
        fascia.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(fascia..close(), lamiera);
    }

    guardrail((z) => principale(-0.4, z), _vicino, 900);
    guardrail((t) => ramo(n + 0.4, t), _vicino, 300);

    // Le frecce dipinte sulle corsie giuste: ogni punto della freccia segue
    // la corsia, così in curva piega con lei. Prima della rampa, sulle
    // corsie che escono, la freccia piega già verso l'uscita.
    final freccia = Paint()..color = Colors.white;
    for (var i = 0; i < n; i++) {
      if (!giuste.contains(i)) continue;
      for (final t0 in [19.0, 40.0, 68.0, 104.0]) {
        Offset mondo(double u, double v) =>
            i >= k ? ramo(i + 0.5 + u / _corsia, t0 + v) : principale(i + 0.5 + u / _corsia, t0 + v);
        final forma = i >= k && t0 < _separazione + 5 ? _formaPiegata : _forma;
        final path = Path();
        for (final (j, q) in forma.indexed) {
          final o = p(mondo(q.dx, q.dy));
          j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path..close(), freccia);
      }
    }
    canvas.restore();
  }

  /// La freccia che piega verso l'uscita: asta dritta, poi curva a destra
  /// (a sinistra ci pensa lo specchio) e la punta nella nuova direzione.
  static final _formaPiegata = () {
    const asta = 0.24, punta = 0.9, lungaPunta = 3.6;
    final centro = <Offset>[], rotte = <double>[];
    // Parte un po' a sinistra: così la punta resta dentro la corsia.
    var c = const Offset(-0.75, 0);
    for (var s = 0.0; s <= 9.0; s += 0.2) {
      final a = s < 4.0 ? 0.0 : math.min(0.42, (s - 4.0) / 5.0 * 0.42);
      centro.add(c);
      rotte.add(a);
      c += Offset(math.sin(a), math.cos(a)) * 0.2;
    }
    Offset normale(double a) => Offset(math.cos(a), -math.sin(a));
    final fine = centro.last, a = rotte.last;
    return [
      for (final (j, q) in centro.indexed) q - normale(rotte[j]) * asta,
      fine - normale(a) * punta,
      fine + Offset(math.sin(a), math.cos(a)) * lungaPunta,
      fine + normale(a) * punta,
      for (final (j, q) in centro.indexed.toList().reversed) q + normale(rotte[j]) * asta,
    ];
  }();

  /// La freccia come la dipingono sull'asfalto (metri: di lato, in avanti):
  /// asta lunga e stretta, punta larga.
  static const _forma = [
    Offset(-0.22, 0),
    Offset(0.22, 0),
    Offset(0.22, 5.0),
    Offset(0.8, 4.6),
    Offset(0, 8.5),
    Offset(-0.8, 4.6),
    Offset(-0.22, 5.0),
  ];

  /// Il cielo, azzurro in alto e chiaro all'orizzonte, con le nuvole.
  void _cielo(Canvas canvas, double w, double orizzonte) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, orizzonte + 2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, orizzonte),
          [const Color(0xFF4F9BE0), const Color(0xFF9CCAF0), const Color(0xFFE6F2FB)],
          [0, 0.6, 1],
        ),
    );
    final nuvola = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012);
    for (final (x, y, r) in [
      (0.16, 0.30, 0.07),
      (0.24, 0.27, 0.09),
      (0.33, 0.31, 0.06),
      (0.68, 0.18, 0.06),
      (0.76, 0.15, 0.08),
      (0.85, 0.19, 0.055),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w * x, orizzonte * y * 2), width: w * r * 2.2, height: w * r * 0.9),
        nuvola,
      );
    }
  }

  /// Colline lontane, prato, alberi e qualche edificio sfumato.
  void _terreno(Canvas canvas, double w, double h, double orizzonte) {
    // Colline morbide sulla linea dell'orizzonte.
    final colline = Path()..moveTo(0, orizzonte);
    for (var x = 0.0; x <= w; x += w / 40) {
      final y = orizzonte - h * 0.035 * (0.6 + 0.4 * math.sin(x / w * 7.3) * math.cos(x / w * 3.1));
      colline.lineTo(x, y);
    }
    colline
      ..lineTo(w, orizzonte + 1)
      ..lineTo(0, orizzonte + 1)
      ..close();
    canvas.drawPath(colline, Paint()..color = const Color(0xFFA9C9A0));
    // Edifici lontani a sinistra, sfumati nella foschia: facciata chiara,
    // lato in ombra e qualche fila di finestre.
    for (final (x, lw, lh) in [(0.02, 0.06, 0.10), (0.075, 0.045, 0.15), (0.125, 0.055, 0.085), (0.175, 0.035, 0.12)]) {
      final r = Rect.fromLTWH(w * x, orizzonte - h * lh, w * lw, h * lh);
      canvas.drawRect(r, Paint()..color = const Color(0xFFE4E7EB));
      canvas.drawRect(
        Rect.fromLTWH(r.right, r.top + r.height * 0.04, r.width * 0.25, r.height * 0.96),
        Paint()..color = const Color(0xFFC8CDD4),
      );
      final finestra = Paint()..color = const Color(0xFFCBD5E0);
      for (var y = r.top + r.height * 0.12; y < r.bottom - r.height * 0.1; y += r.height * 0.14) {
        canvas.drawRect(Rect.fromLTWH(r.left + r.width * 0.12, y, r.width * 0.76, r.height * 0.05), finestra);
      }
    }
    // La foschia sull'orizzonte.
    canvas.drawRect(
      Rect.fromLTWH(0, orizzonte - h * 0.16, w, h * 0.16),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, orizzonte - h * 0.16), Offset(0, orizzonte), [
          const Color(0x00E6F2FB),
          const Color(0x99E6F2FB),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, orizzonte, w, h - orizzonte),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, orizzonte), Offset(0, h), [
          const Color(0xFFB7D59E),
          const Color(0xFF8DBB6E),
        ]),
    );
    // Alberi: chioma tonda con ombra, tronco, più piccoli lontano.
    for (final (x, y, r) in [
      (0.05, 0.47, 0.035),
      (0.12, 0.455, 0.022),
      (0.30, 0.44, 0.012),
      (0.70, 0.445, 0.014),
      (0.82, 0.46, 0.024),
      (0.93, 0.49, 0.04),
    ]) {
      final c = Offset(w * x, h * y);
      final raggio = w * r;
      canvas.drawRect(
        Rect.fromCenter(center: c.translate(0, raggio * 1.1), width: raggio * 0.25, height: raggio * 1.2),
        Paint()..color = const Color(0xFF7A6A55),
      );
      canvas.drawCircle(c, raggio, Paint()..color = const Color(0xFF6FA35A));
      canvas.drawCircle(
        c.translate(-raggio * 0.3, -raggio * 0.3),
        raggio * 0.55,
        Paint()..color = const Color(0xFF85B86C),
      );
    }
  }

  /// Quante corsie, da quale comincia il ramo (girate se si esce a
  /// sinistra), quali sono giuste e, per ognuna, la freccia consigliata.
  (int n, int k, Set<int> giuste, Map<int, DirezioneCorsia?> consigliate) _corsie() {
    var corsie = manovra.corsieUtili ? manovra.corsie : const <Corsia>[];
    if (!_destra) corsie = corsie.reversed.toList();
    if (corsie.isEmpty) {
      // Senza corsie note: tre che proseguono e una che esce.
      return (4, 3, {3}, {3: DirezioneCorsia.leggeraDestra});
    }
    final n = corsie.length;
    final prima = corsie.indexWhere((c) => c.giusta);
    var k = prima < 0 ? n - 1 : prima;
    if (k == 0) k = (n / 2).floor().clamp(1, n - 1);
    return (
      n,
      k,
      {
        for (var i = 0; i < n; i++)
          if (corsie[i].giusta) i,
      },
      {for (var i = 0; i < n; i++) i: corsie[i].consigliata},
    );
  }

  @override
  bool shouldRepaint(ScenaSvincolo old) => old.manovra != manovra;
}

/// La scena in PNG, per lo schermo di Android Auto.
Future<Uint8List> scenaSvincoloPng(Manovra m, {double larghezza = 800, double altezza = 480}) async {
  final registro = ui.PictureRecorder();
  ScenaSvincolo(m).paint(Canvas(registro), Size(larghezza, altezza));
  final immagine = await registro.endRecording().toImage(larghezza.round(), altezza.round());
  return (await immagine.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}
