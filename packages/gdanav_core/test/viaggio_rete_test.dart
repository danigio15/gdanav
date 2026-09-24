/// Il viaggio vero Napoli → Milano, coi server pubblici veri (FOSSGIS,
/// Overpass): quanto ci mette ogni pezzo. Solo con GDANAV_RETE=1, in CI;
/// i tempi escono come avvisi di GitHub.
library;

import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void avviso(String titolo, String testo) => stdout.writeln('::notice title=$titolo::$testo');

void main() {
  const napoli = Punto(40.8518, 14.2681), milano = Punto(45.4642, 9.19);
  final valhalla = ClienteValhalla(Uri.parse('https://valhalla1.openstreetmap.de/'));

  test('Napoli → Milano coi server veri', () async {
    final orologio = Stopwatch()..start();
    final percorso = await valhalla.calcola([napoli, milano]);
    avviso('Valhalla', '${orologio.elapsedMilliseconds} ms, ${percorso.punti.length} punti');

    for (final s in ClienteOverpass().server) {
      orologio.reset();
      try {
        final c = await ClienteOverpass(server: [s]).lungo(percorso.punti);
        avviso('Overpass ${s.host}', '${orologio.elapsedMilliseconds} ms, ${c.length} colonnine');
      } catch (e) {
        avviso('Overpass ${s.host}', 'errore dopo ${orologio.elapsedMilliseconds} ms: $e');
      }
    }

    // Dal relay: la prima volta i riquadri si chiedono a Overpass, la
    // seconda arrivano dalla cache di Cloudflare.
    for (final volta in ['prima', 'seconda']) {
      orologio.reset();
      try {
        final c = await ClienteColonnineRelay(Uri.parse('https://gdanav.gdahome.org/')).lungo(percorso.punti);
        avviso('Relay, $volta volta', '${orologio.elapsedMilliseconds} ms, ${c.length} colonnine');
      } catch (e) {
        avviso('Relay, $volta volta', 'errore dopo ${orologio.elapsedMilliseconds} ms: $e');
      }
    }

    orologio.reset();
    final v = await PianificatoreViaggio(
      percorsi: valhalla.calcola,
      colonnine: FonteColonnineConRiserva(
          [ClienteColonnineRelay(Uri.parse('https://gdanav.gdahome.org/')), ClienteOverpass()]),
      profilo: veicoloPerId('leapmotor-b10-67')!,
    ).pianifica(partenza: napoli, arrivo: milano, batteria: 64);
    avviso(
      'Viaggio intero',
      '${orologio.elapsedMilliseconds} ms, ${v.colonnine.length} colonnine sulla strada, '
          '${v.piano?.soste.length} soste, arrivo ${v.piano?.batteriaArrivo.round()}%',
    );
    expect(v.piano, isNotNull);
  },
      skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false,
      timeout: const Timeout(Duration(minutes: 10)));
}
