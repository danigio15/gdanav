import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/mappe_offline.dart';
import 'package:gdanav_app/stato/gestore_mappe_offline.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// L'archivio delle mappe, in memoria: lo scaricamento va avanti quando lo
/// dice la prova.
class ArchivioFinto implements ArchivioMappe {
  final salvate = <ZonaScaricata>[];
  void Function(double, double)? avanzamento;
  Completer<void>? fine;
  var _id = 0;

  @override
  Future<List<ZonaScaricata>> elenco() async => List.of(salvate);

  @override
  Future<void> scarica(Zona zona, void Function(double progresso, double megabyte) avanzamento) async {
    this.avanzamento = avanzamento;
    fine = Completer<void>();
    await fine!.future;
    salvate.add(ZonaScaricata(id: _id++, zona: zona, megabyte: 310));
  }

  @override
  Future<void> cancella(int id) async => salvate.removeWhere((z) => z.id == id);
}

void main() {
  testWidgets('si scarica una regione, si vede l\'avanzamento, poi si può cancellare', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final archivio = ArchivioFinto();
    final g = GestoreMappeOffline(archivio);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: MappeOffline(gestore: g, qui: const Punto(40.85, 14.27)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Intorno a te'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Campania'), 100);
    await tester.tap(find.text('Campania'));
    await tester.pumpAndSettle();
    expect(find.text('Scaricare Campania?'), findsOneWidget);
    await tester.tap(find.text('Scarica'));
    await tester.pump();
    expect(g.inCorso?.nome, 'Campania');

    archivio.avanzamento!(0.42, 130);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Scarico Campania'), -200);
    expect(find.text('42% · 130 MB'), findsOneWidget);

    archivio.fine!.complete();
    await tester.pumpAndSettle();
    expect(g.inCorso, isNull);
    expect(g.scaricata(regioniItalia.firstWhere((z) => z.id == 'campania')), isTrue);
    expect(find.text('Scaricate'), findsOneWidget);
    expect(find.text('310 MB'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancella Campania'));
    await tester.pumpAndSettle();
    expect(archivio.salvate, isEmpty);
    expect(find.text('Scaricate'), findsNothing);
  });
}
