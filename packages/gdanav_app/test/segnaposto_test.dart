import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ogni segnaposto ha la sua immagine', () async {
    for (final s in Segnaposto.values) {
      final byte = await rootBundle.load(s.asset);
      expect(byte.lengthInBytes, greaterThan(1000), reason: s.asset);
    }
  });

  test('i dati del segnaposto dicono icona e rotta', () {
    final d = datiIo(const Punto(45, 9), 123, Segnaposto.autoRossa);
    final f = (d['features']! as List).single as Map;
    expect(f['properties'], {'icona': 'auto_rossa', 'rotta': 123});
    expect((f['geometry'] as Map)['coordinates'], [9, 45]);
    expect(datiIo(null, 0, Segnaposto.freccia)['features'], isEmpty);
  });

  testWidgets('la rotta viene dal GPS in marcia, dal movimento se il GPS non la sa, e da fermi resta', (tester) async {
    preparaPiattaforma();
    final a = await ambiente(tester);
    a.posizione.avvia();
    Future<void> leggi(Lettura l) async {
      a.gps.add(l);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    await leggi(const Lettura(Punto(45, 9), rotta: 80, velocitaMs: 10));
    expect(a.posizione.rotta, 80, reason: 'la prima non si smorza');

    /* 110 m a nord, senza bussola: la direzione la danno i due punti. Ma non
     * ci arriva in una lettura sola, e non e' un difetto: da quando una
     * lettura storta non deve piu' bastare a girare il segnaposto, ogni
     * lettura sposta il 60% e il resto lo fanno le successive. */
    await leggi(const Lettura(Punto(45.001, 9)));
    expect(a.posizione.rotta, closeTo(32, 1), reason: "da 80 verso 0, il 60% della strada");
    await leggi(const Lettura(Punto(45.002, 9)));
    await leggi(const Lettura(Punto(45.003, 9)));
    await leggi(const Lettura(Punto(45.004, 9)));
    expect(a.posizione.rotta, closeTo(0, 3), reason: 'e in poche letture ci arriva');

    // Fermi: la bussola dice 250, e non la si ascolta.
    final primaDelSemaforo = a.posizione.rotta;
    await leggi(const Lettura(Punto(45.00401, 9), rotta: 250, velocitaMs: 0.2));
    expect(a.posizione.rotta, primaDelSemaforo);
    expect(a.posizione.qui, const Punto(45.00401, 9));
  });

  testWidgets('il segnaposto si sceglie in «La tua auto» e si ricorda', (tester) async {
    preparaPiattaforma();
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    expect(a.posizione.segnaposto, Segnaposto.autoBlu);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('La tua auto'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Come ti vedi sulla mappa'), findsOneWidget);
    await tester.tap(find.text('Freccia'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(a.posizione.segnaposto, Segnaposto.freccia);
    final ricordato = await tester.runAsync(() => Archivio().segnaposto());
    expect(ricordato, Segnaposto.freccia);
  });
}
