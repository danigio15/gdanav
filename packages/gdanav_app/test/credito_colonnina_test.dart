import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/dettaglio_colonnina.dart';

void main() {
  test('ogni fonte si cita come chiede la sua licenza', () {
    expect(creditoColonnina('osm'), 'Dati: © OpenStreetMap contributors');
    expect(creditoColonnina('pun'), 'Dati: PUN (MASE), elaborazione onData, CC BY 4.0');
    expect(
      creditoColonnina('osm+pun'),
      'Dati: © OpenStreetMap contributors · PUN (MASE), elaborazione onData, CC BY 4.0',
    );
    expect(creditoColonnina('ocm+osm'), 'Dati: © OpenStreetMap contributors · © Open Charge Map contributors');
  });

  test('senza una fonte da citare, nessuna riga', () {
    expect(creditoColonnina(''), isNull);
    expect(creditoColonnina('ocpi'), isNull);
  });
}
