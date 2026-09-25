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
Future<Uint8List> bollinoPng(Color colore, IconData icona, {double lato = 26, double scala = 3}) async {
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
  c.drawCircle(centro, r - 1.6, Paint()..color = colore);
  final testo = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icona.codePoint),
      style: TextStyle(
        fontFamily: icona.fontFamily,
        package: icona.fontPackage,
        fontSize: lato * 0.58,
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
const coloriColonnina = {
  'libera': Color(0xFF16A34A),
  'piena': Color(0xFFF59E0B),
  'guasta': Color(0xFFDC2626),
  'ignota': Color(0xFF64748B),
};

/// Tutte le icone dei punti sulla mappa: categorie, distributori e colonnine.
Future<Map<String, Uint8List>> iconePunti() async => {
  for (final c in [...categoriePoi, poiAltro]) c.immagine: await bollinoPng(coloreHex(c.colore), iconaCategoria(c)),
  'punto-distributore': await bollinoPng(const Color(0xFFF08A24), Icons.local_gas_station, lato: 32),
  for (final MapEntry(:key, :value) in coloriColonnina.entries)
    'punto-colonnina-$key': await bollinoPng(value, Icons.ev_station, lato: 32),
};
