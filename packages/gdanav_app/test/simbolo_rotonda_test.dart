import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/icona_manovra.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// La rotonda disegnata in [lato]×[lato]: quanto è chiaro il punto a [g]
/// gradi dall'ingresso sull'anello (0 in basso, 90 a destra, in senso
/// antiorario), da 0 a 255.
Future<int Function(double g)> rotonda(int gradi, {double lato = 96}) async {
  final registro = ui.PictureRecorder();
  DisegnoRotonda(gradi: gradi, colore: Colors.white).paint(Canvas(registro), Size.square(lato));
  final img = await registro.endRecording().toImage(lato.toInt(), lato.toInt());
  final dati = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (g) {
    final p = DisegnoRotonda.sulCerchio(Offset(lato / 2, lato / 2), lato * 0.17, g);
    return dati.getUint8((p.dy.round() * lato.toInt() + p.dx.round()) * 4 + 3);
  };
}

void main() {
  // «Alla rotonda la freccia è errata»: l'icona era `Icons.roundabout_right`,
  // che per uscire a destra fa tutto il giro in senso orario (all'inglese).
  // Da noi si gira in senso antiorario: la prima uscita a destra è subito.
  test('uscita a destra: si gira subito a destra, non tutto il giro', () async {
    final chiaro = await rotonda(90);
    expect(chiaro(45), greaterThan(200), reason: 'il quarto fra ingresso e uscita è pieno');
    expect(chiaro(180), lessThan(140), reason: 'in alto l\'anello è solo accennato');
    expect(chiaro(270), lessThan(140), reason: 'a sinistra l\'anello è solo accennato');
  });

  test('uscita a sinistra: si passa da destra e dall\'alto', () async {
    final chiaro = await rotonda(270);
    for (final g in [45.0, 135.0, 225.0]) {
      expect(chiaro(g), greaterThan(200), reason: 'a $g gradi');
    }
    expect(chiaro(315), lessThan(140));
  });

  testWidgets('la manovra della rotonda di TomTom usa la rotonda disegnata, le altre l\'icona', (tester) async {
    const destra = Manovra(
      istruzione: 'Alla rotonda prendi la prima uscita',
      lunghezzaM: 0,
      secondi: 0,
      inizio: 0,
      tipo: 26,
      uscitaRotonda: 1,
      angoloRotonda: 90,
    );
    const svolta = Manovra(istruzione: 'Gira a destra', lunghezzaM: 0, secondi: 0, inizio: 0, tipo: 10);
    await tester.pumpWidget(
      MaterialApp(home: Row(children: [SimboloManovra.di(destra, size: 40), SimboloManovra.di(svolta, size: 40)])),
    );
    final disegno = tester.widget<CustomPaint>(find.byKey(const Key('simbolo-rotonda'))).painter! as DisegnoRotonda;
    expect(disegno.gradi, 90);
    expect(find.byIcon(Icons.roundabout_right), findsNothing);
    expect(find.byIcon(Icons.turn_right), findsOneWidget);
  });
}
