import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../mappa/categorie_poi.dart';

/// Il simbolo di ogni categoria di punto di interesse.
IconData iconaCategoria(CategoriaPoi c) => switch (c.nome) {
  'ristorante' => Icons.restaurant,
  'fastfood' => Icons.fastfood,
  'caffe' => Icons.local_cafe,
  'bar' => Icons.local_bar,
  'spesa' => Icons.local_grocery_store,
  'negozio' => Icons.shopping_bag,
  'hotel' => Icons.hotel,
  'ospedale' => Icons.local_hospital,
  'farmacia' => Icons.local_pharmacy,
  'parcheggio' => Icons.local_parking,
  'officina' => Icons.car_repair,
  'benzina' => Icons.local_gas_station,
  'ricarica' => Icons.ev_station,
  'cultura' => Icons.museum,
  'culto' => Icons.church,
  'scuola' => Icons.school,
  'banca' => Icons.account_balance,
  'servizi' => Icons.account_balance_wallet,
  'verde' => Icons.park,
  _ => Icons.place,
};

Color coloreHex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Un bollino tondo colorato col simbolo bianco e il bordo bianco, come i
/// punti di Google Maps. PNG a [scala]× di [lato] punti.
///
/// [glifo] è quanta parte del lato occupa il simbolo, [bordo] quanto è spesso
/// l'anello bianco: un simbolo semplice regge di più, e su un bollino grande
/// l'anello va cresciuto con lui, o sparisce.
Future<Uint8List> bollinoPng(
  Color colore,
  IconData icona, {
  double lato = 26,
  double scala = 3,
  double glifo = 0.58,
  double bordo = 1.6,
  Path Function(double lato)? disegno,
}) async {
  final registro = ui.PictureRecorder();
  final c = Canvas(registro)..scale(scala);
  final centro = Offset(lato / 2, lato / 2);
  final r = lato / 2 - 1.5;
  c.drawCircle(
    centro.translate(0, 0.8),
    r,
    Paint()
      ..color = const Color(0x38000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
  );
  c.drawCircle(centro, r, Paint()..color = Colors.white);
  c.drawCircle(centro, r - bordo, Paint()..color = colore);
  if (disegno != null) {
    final quanto = lato * glifo;
    c.save();
    c.translate(centro.dx - quanto / 2, centro.dy - quanto / 2);
    c.drawPath(disegno(quanto), Paint()..color = Colors.white);
    c.restore();
    final disegnata = await registro.endRecording().toImage((lato * scala).round(), (lato * scala).round());
    return (await disegnata.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }
  final testo = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icona.codePoint),
      style: TextStyle(
        fontFamily: icona.fontFamily,
        package: icona.fontPackage,
        fontSize: lato * glifo,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  testo.paint(c, centro - Offset(testo.width / 2, testo.height / 2));
  final img = await registro.endRecording().toImage((lato * scala).round(), (lato * scala).round());
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// I colori delle colonnine per stato, come nel resto dell'app.
///
/// «Ignota» è blu, non grigia: Open Charge Map quasi mai dice se le prese
/// sono occupate, e un bollino grigio su mappa chiara si legge «spenta,
/// non ci andare» — che è il contrario di quello che vogliamo dire.
const coloriColonnina = {
  'libera': Color(0xFF16A34A),
  'piena': Color(0xFFD97706),
  'guasta': Color(0xFFDC2626),
  'ignota': Color(0xFF4F46E5),
};

/// Tutte le icone dei punti sulla mappa: categorie, distributori e colonnine.
Future<Map<String, Uint8List>> iconePunti() async => {
  for (final c in [...categoriePoi, poiAltro]) c.immagine: await bollinoPng(coloreHex(c.colore), iconaCategoria(c)),
  'punto-distributore': await bollinoPng(const Color(0xFFF08A24), Icons.local_gas_station, lato: 32),
  /* La pompa col fulmine è nostra, non di Material, e il bollino è più
   * grande degli altri punti: vedi [pompaColFulmine]. */
  for (final MapEntry(:key, :value) in coloriColonnina.entries)
    'punto-colonnina-$key': await bollinoPng(
      value,
      Icons.ev_station,
      lato: 44,
      glifo: 0.80,
      bordo: 2.2,
      disegno: pompaColFulmine,
    ),
};

/// La pompa col fulmine, disegnata da noi in un riquadro di [lato] punti.
///
/// `Icons.ev_station` ha il difetto di tutte le icone pensate per i menu: il
/// fulmine sta dentro al corpo della pompa, sottile, e alla grandezza che ha
/// sulla mappa in auto si chiude — resta una macchia uguale a quella del
/// distributore di benzina, che è la stessa sagoma senza fulmine.
///
/// Qui il corpo è più largo, il fulmine è grasso e lo buca da parte a parte,
/// e la manichetta è staccata sulla destra: tre pieni grossi invece di tanti
/// dettagli, e si legge anche piccola. Le coordinate stanno in un riquadro
/// 24×24 come le icone di Material, così si confrontano a occhio.
Path pompaColFulmine(double lato) {
  final u = lato / 24;
  Path p(List<List<double>> mosse) {
    final path = Path();
    for (final m in mosse) {
      switch (m.length) {
        case 2:
          path.lineTo(m[0] * u, m[1] * u);
        case 4:
          path.quadraticBezierTo(m[0] * u, m[1] * u, m[2] * u, m[3] * u);
        case 3:
          path.moveTo(m[0] * u, m[1] * u);
      }
    }
    return path..close();
  }

  // La manichetta: il braccio che esce a destra e scende.
  final manichetta = p([
    [15.4, 8.2, 0],
    [18.1, 8.2],
    [20.3, 8.2, 20.3, 10.4],
    [20.3, 15.6],
    [20.3, 17.0, 19.0, 17.0],
    [17.7, 17.0, 17.7, 15.6],
    [17.7, 11.2],
    [17.7, 10.6, 17.1, 10.6],
    [15.4, 10.6],
  ]);
  // Il corpo, col fulmine che lo buca: due contorni e riempimento pari-dispari.
  final corpo = p([
    [4.6, 3.4, 0],
    [4.6, 2.0, 6.0, 2.0],
    [14.0, 2.0],
    [15.4, 2.0, 15.4, 3.4],
    [15.4, 20.6],
    [15.4, 22.0, 14.0, 22.0],
    [6.0, 22.0],
    [4.6, 22.0, 4.6, 20.6],
  ]);
  final fulmine = p([
    [11.3, 4.6, 0],
    [6.6, 12.1],
    [9.5, 12.1],
    [8.7, 19.4],
    [13.4, 11.5],
    [10.4, 11.5],
  ]);
  return Path.combine(PathOperation.union, manichetta, Path.combine(PathOperation.difference, corpo, fulmine));
}
