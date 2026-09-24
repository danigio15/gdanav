import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Le colonnine che non arrivano mai: un server in coda senza fine.
class ColonnineMute implements FonteColonnine {
  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) => Completer<List<Colonnina>>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('si vede a che punto è, e se le colonnine non arrivano lo dice', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final archivio = Archivio();
    final auto = GestoreAuto(archivio: archivio);
    await tester.runAsync(auto.avvia);
    addTearDown(auto.dispose);
    auto.manuale.imposta(80);
    final viaggio = GestoreViaggio(
      archivio: archivio,
      auto: auto,
      posizione: () async => const Punto(42, 12),
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async => dritta(500),
        colonnine: ColonnineMute(),
        profilo: profilo,
        preferenze: preferenze,
      ),
      luoghi: LuoghiFinti(),
    );
    final fasi = <FaseViaggio>[];
    viaggio.addListener(() {
      if (viaggio.stato case Calcolo(:final fase) when !fasi.contains(fase)) fasi.add(fase);
    });

    unawaited(viaggio.pianifica(const Luogo(nome: 'Milano', posizione: Punto(46.5, 12))));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(viaggio.stato, isA<Calcolo>());
    expect(fasi, [FaseViaggio.percorso, FaseViaggio.colonnine]);

    await tester.pump(GestoreViaggio.tempoMassimo);
    expect(viaggio.stato, isA<ErroreViaggio>());
    expect((viaggio.stato as ErroreViaggio).messaggio, contains('colonnine non rispondono'));
  });
}
