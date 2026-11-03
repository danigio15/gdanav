import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/servizi.dart';
import 'package:gdanav_app/stato/dimostrazione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/prova_di_guida.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  test('senza GDANAV_DIMOSTRAZIONE non c\'è nessuna dimostrazione', () {
    expect(Servizi.dimostrazione, isEmpty);
    expect(Dimostrazione.daCompilazione, isNull);
    expect(Dimostrazione.daNome(''), isNull);
    expect(Dimostrazione.daNome('qualsiasi'), isNull);
    expect(Dimostrazione.daNome('traffico7'), Dimostrazione.traffico7);
    expect(Dimostrazione.daNome('traffico18'), Dimostrazione.traffico18);
  });

  for (final (d, minuti, code) in [(Dimostrazione.traffico7, 7, 1), (Dimostrazione.traffico18, 18, 2)]) {
    test('${d.name}: 40 km, +$minuti min in $code code, e la striscia dice lo stesso', () {
      final p = d.percorso();
      expect(p.lunghezzaM, closeTo(40000, 200));
      expect(p.ritardoTraffico.inMinutes, minuti);
      final s = strisciaTraffico(p, percorsiM: 2000)!.allineataA(minuti, p.ritardoTraffico);
      expect(s.code, hasLength(code));
      expect(s.code.fold(0, (t, c) => t + c.minuti), minuti);
    });
  }

  testWidgets('parte da sola: il viaggio verso la meta e la guida accesa', (tester) async {
    preparaPiattaforma();
    const d = Dimostrazione.traffico18;
    final prova = ProvaDiGuida(acceleratore: Dimostrazione.acceleratore);
    addTearDown(prova.chiudi);
    final a = await ambiente(tester, costruisci: d.pianificatore, dove: d.posizione, prova: prova);
    await tester.runAsync(() => d.avvia(auto: a.auto, viaggio: a.viaggio, guida: a.guida, prova: prova));
    expect(a.auto.elettrica, isFalse);
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.destinazione.nome, 'Orvieto');
    expect(pronto.viaggio.percorso.ritardoTraffico.inMinutes, 18);
    expect(a.guida.attiva, isTrue);
    expect(prova.attiva, isTrue);
    expect(prova.fattiM, closeTo(2000, 50));
    // In archivio l'auto resta quella di prima.
    expect(await tester.runAsync(a.archivio.elettrica), isTrue);
    a.guida.ferma();
  });
}
