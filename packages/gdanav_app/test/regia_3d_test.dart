import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/regia_3d.dart';

import 'aiuti.dart';

/// La regia della scena 3D, con una pagina finta: i messaggi che le manda.
void main() {
  Future<(Regia3d, List<Map<String, Object?>>)> regia(WidgetTester tester, {bool inAuto = false}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    final mandati = <Map<String, Object?>>[];
    final r = Regia3d(
      gestore: a.viaggio,
      posizione: a.posizione,
      guida: a.guida,
      manda: mandati.add,
      notte: () => false,
      vista: () => VistaMappa.aumentata,
      inquadratura: () => (libera: false, sopra: 0.0, sinistra: 0.0, destra: 0.0),
      onNonVa: (_, {required ricorda}) {},
      inAuto: inAuto,
    )..avvia();
    return (r, mandati);
  }

  List<String> tipi(List<Map<String, Object?>> m) => [for (final x in m) x['tipo']! as String];

  testWidgets('la pausa chiesta prima che la pagina sia caricata non si perde: arriva prima dello stile', (
    tester,
  ) async {
    // La sezione del navigatore nascosta dietro la plancia (TickerMode spento):
    // la pausa arriva subito, quando la pagina non c'è ancora.
    final (r, mandati) = await regia(tester);
    r.pausa(true);
    expect(mandati, isEmpty, reason: 'la pagina non c’è ancora');
    r.dallaMappa('{"tipo":"caricata"}');
    final t = tipi(mandati);
    expect(t, contains('pausa'));
    expect(mandati[t.indexOf('pausa')]['si'], isTrue);
    expect(t.indexOf('pausa'), lessThan(t.indexOf('opzioni')));
    expect(t.indexOf('pausa'), lessThan(t.indexOf('stile')));
    // Tornata a vedersi: la pausa finisce.
    mandati.clear();
    r.pausa(false);
    expect(mandati.single, containsPair('si', false));
    r.ferma();
  });

  testWidgets('senza pausa voluta la pagina appena caricata non riceve pause; e sa se è sull’auto', (tester) async {
    final (r, mandati) = await regia(tester);
    r.pausa(true);
    r.pausa(false);
    r.dallaMappa('{"tipo":"caricata"}');
    expect(tipi(mandati), isNot(contains('pausa')));
    expect(mandati.firstWhere((m) => m['tipo'] == 'opzioni'), isNot(contains('inAuto')));
    r.ferma();

    final (auto, mandatiAuto) = await regia(tester, inAuto: true);
    auto.dallaMappa('{"tipo":"caricata"}');
    expect(mandatiAuto.firstWhere((m) => m['tipo'] == 'opzioni')['inAuto'], isTrue);
    auto.ferma();
  });
}
