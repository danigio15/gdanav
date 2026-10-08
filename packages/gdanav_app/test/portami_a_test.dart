// «Apri in mappa» sulla scheda di una persona, in gdahome: il punto arriva al
// navigatore, e la meta si chiama come la persona.
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';

import 'aiuti.dart';

void main() {
  testWidgets('un punto da chi ospita gdanav diventa la meta, col suo nome', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final app = a.app() as GdanavApp;
    await tester.runAsync(
      () => app.portamiA(nome: 'Giovanni', lat: 40.86, lon: 14.28, descrizione: 'Via Toledo'),
    );
    expect(a.viaggio.destinazione?.nome, 'Giovanni');
    expect(a.viaggio.destinazione?.descrizione, 'Via Toledo');
    expect(a.viaggio.destinazione?.posizione.lat, 40.86);
  });

  testWidgets('coordinate fuori scala non portano da nessuna parte', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final app = a.app() as GdanavApp;
    await tester.runAsync(() => app.portamiA(nome: 'x', lat: 200.0, lon: 14.0));
    expect(a.viaggio.destinazione, isNull);
  });
}
