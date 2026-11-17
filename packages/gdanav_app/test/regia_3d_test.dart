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

  /// I messaggi `leggera` fra i [m] mandati: sì o no, nell'ordine.
  List<Object?> leggere(List<Map<String, Object?>> m) => [
    for (final x in m)
      if (x['tipo'] == 'leggera') x['si'],
  ];

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

  testWidgets('con la scena anche sull’auto quella del telefono si fa leggera, e poi torna com’era', (tester) async {
    // «Se lo utilizzo va lento il telefono e il navigatore»: due scene 3D
    // intere sulla stessa scheda grafica, quella del telefono fino a sessanta
    // fotogrammi al secondo.
    expect(Regia3d.sullAuto.value, 0);
    final (telefono, mandati) = await regia(tester);
    telefono.dallaMappa('{"tipo":"caricata"}');
    expect(tipi(mandati), isNot(contains('leggera')), reason: 'da sola resta com’era');
    mandati.clear();

    // La scena parte sull'auto: al telefono arriva subito.
    final (auto, mandatiAuto) = await regia(tester, inAuto: true);
    expect(Regia3d.sullAuto.value, 1);
    // (Fra i messaggi ci sono anche le immagini, che arrivano con calma.)
    expect(leggere(mandati), [true]);
    auto.dallaMappa('{"tipo":"caricata"}');
    expect(tipi(mandatiAuto), isNot(contains('leggera')), reason: 'quella dell’auto ha già le sue regole');

    // La pagina del telefono ricaricata lo risà, prima dello stile.
    mandati.clear();
    telefono.dallaMappa('{"tipo":"caricata"}');
    final t = tipi(mandati);
    expect(t, contains('leggera'));
    expect(t.indexOf('leggera'), lessThan(t.indexOf('stile')));

    // Chiusa la scena dell'auto (anche fermata due volte), il telefono torna com'era.
    mandati.clear();
    auto.ferma();
    auto.ferma();
    expect(Regia3d.sullAuto.value, 0);
    expect(leggere(mandati), [false]);
    telefono.ferma();

    // Una regia del telefono fermata non ascolta più.
    final (altra, _) = await regia(tester, inAuto: true);
    expect(leggere(mandati), [false]);
    altra.ferma();
    expect(Regia3d.sullAuto.value, 0);
  });
}
