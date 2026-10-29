import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/icone_segnalazioni.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Gli autovelox sulla mappa: fissi, mobili e semafori con la foto, ognuno
/// col suo disegno, e il cartello del limite accanto quando ce l'hanno.
void main() {
  Segnalazione una(String id, {bool fissa = false, bool semaforo = false, int? limite, TipoSegnalazione? tipo}) =>
      Segnalazione(
        id: id,
        tipo: tipo ?? TipoSegnalazione.autovelox,
        punto: const Punto(41.9, 12.5),
        creata: DateTime(2026),
        fissa: fissa || semaforo,
        semaforo: semaforo,
        limiteKmh: limite,
      );

  test('ogni controllo il suo disegno, e il limite accanto solo dove ha senso', () {
    expect(nomeIconaDi(una('a', fissa: true, limite: 50)), 'segnala-autovelox-fisso-50');
    expect(nomeIconaDi(una('b', fissa: true)), 'segnala-autovelox-fisso');
    expect(nomeIconaDi(una('c', limite: 90)), 'segnala-autovelox-mobile-90');
    expect(nomeIconaDi(una('d', fissa: true, limite: 45)), 'segnala-autovelox-fisso', reason: 'un 45 non ha cartello');
    expect(nomeIconaDi(una('e', semaforo: true, limite: 50)), 'segnala-autovelox-semaforo');
    expect(nomeIconaDi(una('f', tipo: TipoSegnalazione.polizia)), 'segnala-polizia');
    final dati = datiSegnalazioni([una('a', fissa: true, limite: 50)]);
    final p = ((dati['features']! as List).single as Map)['properties'] as Map;
    expect(p['icona'], 'segnala-autovelox-fisso-50');
    expect(una('s', semaforo: true).avviso, 'Semaforo con foto');
    expect(controlloDi(una('s', semaforo: true))!.nome, 'Semaforo con foto');
  });

  testWidgets('ogni immagine che la mappa chiede c\'è', (tester) async {
    final tutte = await tester.runAsync(iconeSegnalazioni);
    final nomi = tutte!.keys.toSet();
    for (final s in [
      for (final l in [null, ...limitiConCartello]) ...[
        una('f$l', fissa: true, limite: l),
        una('m$l', limite: l),
        una('s$l', semaforo: true, limite: l),
      ],
      for (final t in TipoSegnalazione.values) una(t.name, tipo: t),
    ]) {
      expect(nomi, contains(nomeIconaDi(s)));
    }
  });

  testWidgets('il bollino di un autovelox è il suo disegno', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(children: [BollinoSegnalazione.di(una('m')), BollinoSegnalazione(TipoSegnalazione.polizia)]),
      ),
    );
    expect(
      find.descendant(of: find.byType(BollinoSegnalazione).first, matching: find.byType(CustomPaint)),
      findsWidgets,
    );
    expect(find.byIcon(Icons.local_police_rounded), findsOneWidget);
  });
}
