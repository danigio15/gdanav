import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/schermate/la_tua_auto.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav/stato/gestore_posizione.dart';
import 'package:gdanav/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  List<String> cerca(String f) => [
    for (final v in catalogoVeicoli)
      if (corrisponde(v, f)) v.id,
  ];

  test('la ricerca delle auto ignora accenti, trattini e spazi', () {
    expect(semplice('Škoda Enyaq'), 'skoda enyaq');
    expect(semplice('Citroën ë-C4'), 'citroen e c4');
    expect(cerca('skoda enyaq'), contains('skoda-enyaq-85'));
    expect(cerca('id3'), contains('volkswagen-id3-58'));
    expect(cerca('ID.3 58'), contains('volkswagen-id3-58'));
    expect(cerca('tesla model y'), containsAll(['tesla-model-y-lr', 'tesla-model-y-rwd']));
    expect(cerca(''), hasLength(catalogoVeicoli.length));
    expect(cerca('nessunaautocosì'), isEmpty);
  });

  testWidgets("con l'auto d'esempio e Home Assistant «Leapmotor B10», si parte già filtrati", (tester) async {
    preparaPiattaforma(
      portachiavi: {
        'abbinamento_home_assistant': Abbinamento.nuovo(
          relay: Uri.parse('wss://relay.esempio.dev'),
          nomeAuto: 'La mia Leapmotor B10',
        ).uri,
      },
    );
    final archivio = Archivio();
    final auto = GestoreAuto(archivio: archivio);
    await tester.runAsync(auto.avvia);
    final posizione = GestorePosizione(archivio: archivio, letture: () => const Stream.empty());
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: LaTuaAuto(auto: auto, posizione: posizione),
      ),
    );
    await tester.pump();
    expect(find.text('leapmotor b10'), findsOneWidget);
    expect(find.text('B10 67,1 kWh (Design, Pro Max)'), findsOneWidget);
    expect(find.text('C10'), findsNothing);
    auto.dispose();
  });
}
