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
  TipoSegnalazione.autovelox => (const Color(0xFFD32F2F), Icons.photo_camera_rounded),
};

String nomeIcona(TipoSegnalazione t) => 'segnala-${t.name}';

/// L'icona per la mappa: il fumetto tondo di Waze, colorato, col simbolo
/// bianco e la punta in basso. PNG a [scala]×.
Future<Uint8List> iconaSegnalazionePng(TipoSegnalazione t, {double scala = 3}) {
  final (colore, icona) = aspetto(t);
  return fumettoPng(colore, icona, scala: scala);
}

/// Il fumetto di [iconaSegnalazionePng], di un colore e con un simbolo: o
/// un'[icona], o un [disegno] fatto a mano attorno al centro.
Future<Uint8List> fumettoPng(
  Color colore,
  IconData icona, {
  double scala = 3,
  void Function(Canvas c, Offset centro, Color colore)? disegno,
}) async {
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
  if (disegno != null) {
    disegno(c, centro, colore);
  } else {
    final testo = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icona.codePoint),
        style: TextStyle(fontFamily: icona.fontFamily, package: icona.fontPackage, fontSize: 22, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    testo.paint(c, centro - Offset(testo.width / 2, testo.height / 2));
  }
  final img = await registro.endRecording().toImage((lato * scala).round(), (lato * scala).round());
  final dati = await img.toByteData(format: ui.ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}

/// L'autovelox disegnato: la scatola sul palo con l'obiettivo e il flash,
/// come quelli a bordo strada.
void disegnaAutovelox(Canvas c, Offset centro, Color colore) {
  final bianco = Paint()..color = Colors.white;
  final pieno = Paint()..color = colore;
  c.drawRect(Rect.fromLTWH(centro.dx - 1.6, centro.dy + 2, 3.2, 9), bianco);
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(centro.dx - 9, centro.dy - 9, 18, 12.5), const Radius.circular(2.5)),
    bianco,
  );
  c.drawCircle(centro.translate(-2.5, -2.8), 4, pieno);
  c.drawCircle(centro.translate(-2.5, -2.8), 1.7, bianco);
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(centro.dx + 3, centro.dy - 7, 4, 3), const Radius.circular(0.8)),
    pieno,
  );
}

/// L'autovelox mobile: la scatola sul treppiede, come quelli che la polizia
/// mette a bordo strada.
void disegnaAutoveloxMobile(Canvas c, Offset centro, Color colore) {
  final bianco = Paint()..color = Colors.white;
  final pieno = Paint()..color = colore;
  final gamba = Paint()
    ..color = Colors.white
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  final piede = centro.translate(0, 1.5);
  c.drawLine(piede, centro.translate(-6.5, 10.5), gamba);
  c.drawLine(piede, centro.translate(6.5, 10.5), gamba);
  c.drawLine(piede, centro.translate(0, 10.5), gamba);
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(centro.dx - 8.5, centro.dy - 9.5, 17, 11), const Radius.circular(2.5)),
    bianco,
  );
  c.drawCircle(centro.translate(-2.5, -4), 3.6, pieno);
  c.drawCircle(centro.translate(-2.5, -4), 1.5, bianco);
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(centro.dx + 2.8, centro.dy - 7.8, 3.8, 2.8), const Radius.circular(0.8)),
    pieno,
  );
}

/// Il semaforo con la foto (il «T-red»): il semaforo, col rosso acceso, e
/// accanto la macchina fotografica.
void disegnaSemaforoConFoto(Canvas c, Offset centro, Color colore) {
  final bianco = Paint()..color = Colors.white;
  final cassa = Rect.fromLTWH(centro.dx - 8.5, centro.dy - 11, 8.5, 21);
  c.drawRRect(RRect.fromRectAndRadius(cassa, const Radius.circular(3)), bianco);
  final lampada = Paint()..color = colore.withValues(alpha: 0.35);
  c.drawCircle(Offset(cassa.center.dx, cassa.top + 4.2), 2.6, Paint()..color = const Color(0xFFE53935));
  c.drawCircle(Offset(cassa.center.dx, cassa.center.dy), 2.6, lampada);
  c.drawCircle(Offset(cassa.center.dx, cassa.bottom - 4.2), 2.6, lampada);
  // La macchina fotografica, a destra.
  final corpo = Rect.fromLTWH(centro.dx + 1.5, centro.dy - 3, 9, 7);
  c.drawRRect(RRect.fromRectAndRadius(corpo, const Radius.circular(1.6)), bianco);
  c.drawRect(Rect.fromLTWH(corpo.left + 2.5, corpo.top - 1.6, 4, 2), bianco);
  c.drawCircle(corpo.center.translate(0, 0.3), 2.2, Paint()..color = colore);
  c.drawCircle(corpo.center.translate(0, 0.3), 0.9, bianco);
}

/// I limiti che hanno il loro cartello accanto all'autovelox sulla mappa.
/// Un limite che non c'e' qui (un 35, un 45) resta senza cartello: meglio
/// l'icona sola che un'immagine che la mappa non trova.
const limitiConCartello = [20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 150];

/// L'autovelox come lo mette TomTom: il fumetto e, in alto a destra, il
/// cartello col limite, cosi' si sa gia' quanto rallentare. Il fumetto sta
/// al centro dell'immagine: la punta resta sul punto della mappa.
Future<Uint8List> iconaColLimitePng(
  TipoSegnalazione t,
  int limite, {
  double scala = 3,
  Color? colore,
  IconData? icona,
  void Function(Canvas c, Offset centro, Color colore)? disegno,
}) async {
  const lato = 44.0, cartello = 30.0, largo = lato + cartello * 2 - 8;
  final (suo, simbolo) = aspetto(t);
  final fumetto = await ui.instantiateImageCodec(
    await fumettoPng(colore ?? suo, icona ?? simbolo, scala: scala, disegno: disegno),
  );
  final immagine = (await fumetto.getNextFrame()).image;
  final registro = ui.PictureRecorder();
  final c = Canvas(registro);
  final sinistra = (largo - lato) / 2 * scala;
  c.drawImage(immagine, Offset(sinistra, 0), Paint());
  c.scale(scala);
  final centro = Offset(largo / 2 + lato / 2 + cartello / 2 - 10, cartello / 2 + 1);
  final ombra = Paint()
    ..color = const Color(0x40000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  c.drawCircle(centro.translate(0, 1.5), cartello / 2, ombra);
  c.drawCircle(centro, cartello / 2, Paint()..color = Colors.white);
  c.drawCircle(
    centro,
    cartello / 2 - cartello * 0.07,
    Paint()
      ..color = const Color(0xFFD62C2C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cartello * 0.13,
  );
  final testo = TextPainter(
    text: TextSpan(
      text: '$limite',
      style: TextStyle(
        // Sul telefono Roboto c'e' sempre; dove manca vale quello di sistema.
        fontFamily: 'Roboto',
        fontSize: cartello * (limite >= 100 ? 0.36 : 0.44),
        fontWeight: FontWeight.w900,
        color: const Color(0xFF111111),
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  testo.paint(c, centro - Offset(testo.width / 2, testo.height / 2));
  final img = await registro.endRecording().toImage((largo * scala).round(), (lato * scala).round());
  final dati = await img.toByteData(format: ui.ImageByteFormat.png);
  return dati!.buffer.asUint8List();
}

/* ─── Che controllo è ──────────────────────────────────────────────────
 *
 * Dal campo: «cambia simbolo autovelox, non si capisce cosa è», e «icone
 * congrue a autovelox fissi, mobili e semafori con foto». Tre disegni: la
 * scatola sul palo (fisso, da OpenStreetMap), sul treppiede (mobile, quelli
 * segnalati da chi passa) e il semaforo col rosso acceso e la macchina
 * fotografica (il «T-red»). */

/// Che controllo è un autovelox.
enum Controllo {
  fisso(Color(0xFFD32F2F), disegnaAutovelox, 'Autovelox fisso'),
  mobile(Color(0xFFEF6C00), disegnaAutoveloxMobile, 'Autovelox mobile'),
  semaforo(Color(0xFF263238), disegnaSemaforoConFoto, 'Semaforo con foto');

  const Controllo(this.colore, this.disegno, this.nome);

  final Color colore;
  final void Function(Canvas c, Offset centro, Color colore) disegno;
  final String nome;

  /// Il nome dell'immagine sulla mappa, col limite accanto se c'è.
  String immagine([int? limite]) => 'segnala-autovelox-$name${limite == null ? '' : '-$limite'}';
}

/// Di una segnalazione, che controllo è; `null` se non è un autovelox.
Controllo? controlloDi(Segnalazione s) => s.tipo != TipoSegnalazione.autovelox
    ? null
    : s.semaforo
    ? Controllo.semaforo
    : s.fissa
    ? Controllo.fisso
    : Controllo.mobile;

/// Il nome dell'immagine di una segnalazione sulla mappa: gli autovelox col
/// loro disegno, e il cartello del limite accanto quando ce l'hanno (il
/// semaforo no: fotografa il rosso, non la velocità).
String nomeIconaDi(Segnalazione s) {
  final c = controlloDi(s);
  if (c == null) return nomeIcona(s.tipo);
  final l = s.limiteKmh;
  return c.immagine(c != Controllo.semaforo && l != null && limitiConCartello.contains(l) ? l : null);
}

/// Tutte le immagini delle segnalazioni, per la mappa e per l'auto.
Future<Map<String, Uint8List>> iconeSegnalazioni() async => {
  for (final t in TipoSegnalazione.values)
    if (t != TipoSegnalazione.autovelox) nomeIcona(t): await iconaSegnalazionePng(t),
  for (final c in Controllo.values) ...{
    c.immagine(): await fumettoPng(c.colore, Icons.photo_camera_rounded, disegno: c.disegno),
    if (c != Controllo.semaforo)
      for (final l in limitiConCartello)
        c.immagine(l): await iconaColLimitePng(TipoSegnalazione.autovelox, l, colore: c.colore, disegno: c.disegno),
  },
};

/// Il bollino tondo nei fogli e negli avvisi.
class BollinoSegnalazione extends StatelessWidget {
  const BollinoSegnalazione(this.tipo, {super.key, this.lato = 56, this.controllo});

  /// Quello di una segnalazione: per un autovelox, il suo disegno.
  BollinoSegnalazione.di(Segnalazione s, {Key? key, double lato = 56})
    : this(s.tipo, key: key, lato: lato, controllo: controlloDi(s));

  final TipoSegnalazione tipo;
  final double lato;

  /// Che autovelox: col suo disegno invece dell'icona.
  final Controllo? controllo;

  @override
  Widget build(BuildContext context) {
    final c = controllo ?? (tipo == TipoSegnalazione.autovelox ? Controllo.fisso : null);
    if (c != null) {
      return Container(
        width: lato,
        height: lato,
        decoration: BoxDecoration(
          color: c.colore,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: CustomPaint(painter: _Disegno(c)),
      );
    }
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

/// Il disegno di un autovelox, grande quanto il bollino (disegnato su 44
/// punti, come nel fumetto della mappa).
class _Disegno extends CustomPainter {
  const _Disegno(this.controllo);

  final Controllo controllo;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 36;
    canvas.scale(k);
    controllo.disegno(canvas, const Offset(18, 18.5), controllo.colore);
  }

  @override
  bool shouldRepaint(_Disegno vecchio) => vecchio.controllo != controllo;
}
