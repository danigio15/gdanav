import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Colore e simbolo di ogni segnalazione, uguali nel foglio, sulla mappa e
/// negli avvisi in guida.
(Color, IconData) aspetto(TipoSegnalazione t) => switch (t) {
  TipoSegnalazione.traffico => (const Color(0xFFE5484D), Icons.traffic_rounded),
  TipoSegnalazione.polizia => (const Color(0xFF2F6FEB), Icons.local_police_rounded),
  TipoSegnalazione.incidente => (const Color(0xFF6B7280), Icons.car_crash_rounded),
  TipoSegnalazione.pericolo => (const Color(0xFFF2A413), Icons.warning_rounded),
  TipoSegnalazione.lavori => (const Color(0xFFF97316), Icons.construction_rounded),
  TipoSegnalazione.chiusura => (const Color(0xFFB91C1C), Icons.do_not_disturb_on_rounded),
  TipoSegnalazione.autovelox => (const Color(0xFF7C3AED), Icons.speed_rounded),
};

String nomeIcona(TipoSegnalazione t) => 'segnala-${t.name}';

/// L'icona per la mappa: il fumetto tondo di Waze, colorato, col simbolo
/// bianco e la punta in basso. PNG a [scala]×.
Future<Uint8List> iconaSegnalazionePng(TipoSegnalazione t, {double scala = 3}) async {
  final (colore, icona) = aspetto(t);
  const lato = 44.0, raggio = 18.0;
  final registro = ui.PictureRecorder();
  final c = Canvas(registro)..scale(scala);
  const centro = Offset(lato / 2, raggio + 3);
  final punta = Path()
    ..moveTo(centro.dx - 7, centro.dy + raggio - 4)
    ..lineTo(centro.dx, lato - 1)
    ..lineTo(centro.dx + 7, centro.dy + raggio - 4)
    ..close();
  final ombra = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  c.drawCircle(centro.translate(0, 1.5), raggio, ombra);
  final bianco = Paint()..color = Colors.white;
  c.drawPath(punta.shift(const Offset(0, 1)), bianco);
  c.drawCircle(centro, raggio, bianco);
  final pieno = Paint()..color = colore;
  c.drawPath(punta, pieno);
  c.drawCircle(centro, raggio - 2.5, pieno);
  final testo = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icona.codePoint),
      style: TextStyle(fontFamily: icona.fontFamily, package: icona.fontPackage, fontSize: 22, color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  testo.paint(c, centro - Offset(testo.width / 2, testo.height / 2));
  final img = await registro.endRecording().toImage((lato * scala).round(), (lato * scala).round());
  final dati = await img.toByteData(format: ui.ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}

/// Il bollino tondo nei fogli e negli avvisi.
class BollinoSegnalazione extends StatelessWidget {
  const BollinoSegnalazione(this.tipo, {super.key, this.lato = 56});

  final TipoSegnalazione tipo;
  final double lato;

  @override
  Widget build(BuildContext context) {
    final (colore, icona) = aspetto(tipo);
    return Container(
      width: lato,
      height: lato,
      decoration: BoxDecoration(
        color: colore,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Icon(icona, color: Colors.white, size: lato * 0.55),
    );
  }
}
