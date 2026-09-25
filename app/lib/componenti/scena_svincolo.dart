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
  static const _altezzaCamera = 5.2;
  static const _separazione = 38.0;
  static const _vicino = 3.0;

  bool get _destra => const {18, 20, 23}.contains(manovra.tipo);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final orizzonte = h * 0.42;
    _cielo(canvas, w, orizzonte);
    _terreno(canvas, w, h, orizzonte);

    final (n, k, giuste, consigliate) = _corsie();
    // La camera sta sopra la corsia accanto al ramo, un po' verso l'interno.
    final camX = (k - 0.2) * _corsia;
    final f = w * 0.95;
    Offset p(double x, double z) => Offset(w / 2 + f * (x - camX) / z, orizzonte + f * _altezzaCamera / z);
    // Il ramo si allontana di lato, sempre di più.
    double scarto(double z) => z <= _separazione ? 0 : 0.0075 * math.pow(z - _separazione, 2).toDouble();
    double pendenza(double z) => z <= _separazione ? 0 : 0.015 * (z - _separazione);
    double xMain(double i, double z) => i * _corsia;
    double xRamo(double i, double z) => i * _corsia + scarto(z);

    canvas.save();
    if (!_destra) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }

    // Uno spessore di terra lontano, dove il ramo sparisce oltre l'orizzonte.
    Path fascia(double Function(double z) sx, double Function(double z) dx, double z0, double z1) {
      final passi = <double>[];
      for (var z = z0; z < z1; z *= 1.06) {
        passi.add(z);
      }
      passi.add(z1);
      final path = Path()..moveTo(p(sx(passi.first), passi.first).dx, p(sx(passi.first), passi.first).dy);
      for (final z in passi) {
        path.lineTo(p(sx(z), z).dx, p(sx(z), z).dy);
      }
      for (final z in passi.reversed) {
        path.lineTo(p(dx(z), z).dx, p(dx(z), z).dy);
      }
      return path..close();
    }

    // Banchine chiare, poi l'asfalto.
    final banchina = Paint()..color = const Color(0xFFC9CCC4);
    canvas.drawPath(fascia((z) => -1.4, (z) => k * _corsia + 0.3, _vicino, 3000), banchina);
    canvas.drawPath(
      fascia((z) => xRamo(k.toDouble(), z) - 0.3, (z) => xRamo(n.toDouble(), z) + 1.4, _vicino, 900),
      banchina,
    );
    final asfalto = Paint()
      ..shader = ui.Gradient.linear(Offset(0, h), Offset(0, orizzonte), [
        const Color(0xFF3A3E45),
        const Color(0xFF5A5F67),
      ]);
    canvas.drawPath(fascia((z) => 0, (z) => xMain(k.toDouble(), z), _vicino, 3000), asfalto);
    canvas.drawPath(fascia((z) => xRamo(k.toDouble(), z), (z) => xRamo(n.toDouble(), z), _vicino, 900), asfalto);

    // Le corsie giuste, blu fino in fondo.
    final blu = Paint()
      ..shader = ui.Gradient.linear(Offset(0, h), Offset(0, orizzonte), [
        const Color(0xFF1E6FE8),
        const Color(0xFF4F95F5),
      ]);
    for (var i = 0; i < n; i++) {
      if (!giuste.contains(i)) continue;
      final a = i + 0.06, b = i + 0.94;
      if (i >= k) {
        canvas.drawPath(fascia((z) => xRamo(a, z), (z) => xRamo(b, z), _vicino, 900), blu);
      } else {
        canvas.drawPath(fascia((z) => xMain(a, z), (z) => xMain(b, z), _vicino, 3000), blu);
      }
    }

    // Le righe: bordi pieni, fra le corsie tratteggiate (4,5 m pieni e 7,5 vuoti).
    final bianco = Paint()..color = const Color(0xFFF4F6F8);
    void riga(double Function(double z) x, double z0, double z1, {bool tratteggio = false, double larga = 0.18}) {
      var z = z0;
      while (z < z1) {
        final lung = tratteggio ? 4.5 : math.max(2.0, z * 0.08);
        final fine = math.min(z + lung, z1);
        final a1 = p(x(z) - larga / 2, z), a2 = p(x(z) + larga / 2, z);
        final b1 = p(x(fine) - larga / 2, fine), b2 = p(x(fine) + larga / 2, fine);
        canvas.drawPath(
          Path()
            ..moveTo(a1.dx, a1.dy)
            ..lineTo(a2.dx, a2.dy)
            ..lineTo(b2.dx, b2.dy)
            ..lineTo(b1.dx, b1.dy)
            ..close(),
          bianco,
        );
        z = fine + (tratteggio ? 7.5 : 0);
      }
    }

    riga((z) => 0.15, _vicino, 3000, larga: 0.25);
    riga((z) => xMain(k.toDouble(), z) - 0.15, _separazione, 3000, larga: 0.25);
    riga((z) => xRamo(k.toDouble(), z) + 0.15, _separazione, 900, larga: 0.25);
    riga((z) => xRamo(n.toDouble(), z) - 0.15, _vicino, 900, larga: 0.25);
    for (var i = 1; i < n; i++) {
      if (i == k) {
        riga((z) => xMain(k.toDouble(), z), _vicino, _separazione, tratteggio: true, larga: 0.3);
      } else if (i < k) {
        riga((z) => xMain(i.toDouble(), z), _vicino, 3000, tratteggio: true);
      } else {
        riga((z) => xRamo(i.toDouble(), z), _vicino, 900, tratteggio: true);
      }
    }

    // Le frecce dipinte sulle corsie giuste, girate come la corsia.
    final freccia = Paint()..color = Colors.white.withValues(alpha: 0.96);
    for (var i = 0; i < n; i++) {
      if (!giuste.contains(i)) continue;
      final ramo = i >= k;
      for (final z0 in [13.0, 30.0, 52.0, 80.0]) {
        final centro = (ramo ? xRamo(i + 0.5, z0) : xMain(i + 0.5, z0));
        final angolo = ramo ? math.atan(pendenza(z0 + 3)) : 0.0;
        final curva = ramo && consigliate[i] != DirezioneCorsia.dritto && z0 > 20;
        _frecciaDipinta(canvas, p, centro, z0, angolo, freccia, piega: curva ? 1 : 0);
      }
    }
    canvas.restore();
  }

  /// Una freccia dipinta per terra, lunga 7 m, nel piano della strada.
  void _frecciaDipinta(
    Canvas canvas,
    Offset Function(double x, double z) p,
    double cx,
    double cz,
    double angolo,
    Paint colore, {
    int piega = 0,
  }) {
    // Nel sistema della corsia: u di lato, v in avanti (metri).
    const forma = [
      Offset(-0.22, 0),
      Offset(0.22, 0),
      Offset(0.22, 4.6),
      Offset(0.62, 4.6),
      Offset(0, 7),
      Offset(-0.62, 4.6),
      Offset(-0.22, 4.6),
    ];
    final c = math.cos(angolo), sn = math.sin(angolo);
    final path = Path();
    for (final (j, q) in forma.indexed) {
      // Piegata verso l'uscita: la punta si sposta di lato.
      final u = q.dx + (piega != 0 ? q.dy * q.dy * 0.035 : 0);
      final x = cx + u * c + q.dy * sn;
      final z = cz + q.dy * c - u * sn;
      final o = p(x, z);
      j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path..close(), colore);
  }

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
