/// Il viaggio vero Napoli → Milano, coi server pubblici veri (FOSSGIS,
/// Overpass): quanto ci mette ogni pezzo. Solo con GDANAV_RETE=1, in CI;
/// i tempi escono come avvisi di GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
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

  test('i prezzi veri del Ministero, a Milano', () async {
    final orologio = Stopwatch()..start();
    try {
      final d = await ClientePrezziMimit().vicino(milano, km: 3);
      final primo = d.isEmpty ? null : d.first;
      avviso(
        'Prezzi MIMIT',
        '${orologio.elapsedMilliseconds} ms, ${d.length} distributori; il primo: ${primo?.nome} '
            '${primo?.prezzi.map((p) => '${p.nome} ${p.euro}${p.self ? ' self' : ''}').join(', ')} '
            'aggiornato ${primo?.aggiornato}',
      );
    } catch (e) {
      avviso('Prezzi MIMIT', 'errore dopo ${orologio.elapsedMilliseconds} ms: $e');
    }
  }, skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false);

  // I dati grezzi del Ministero intorno a Napoli, per le anteprime dell'app.
  test('prezzi grezzi del Ministero, a Napoli', () async {
    try {
      final r = await http.post(
        Uri.parse('https://carburanti.mise.gov.it/ospzApi/search/zone'),
        headers: {'content-type': 'application/json', 'accept': 'application/json'},
        body: jsonEncode({
          'points': [
            {'lat': 40.8518, 'lng': 14.2681},
          ],
          'radius': 3,
          'fuelType': '0-x',
          'priceOrder': 'asc',
        }),
      );
      final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
      final risultati = (json['results'] as List).take(14).toList();
      avviso('Prezzi MIMIT grezzi', jsonEncode({'results': risultati}));
    } catch (e) {
      avviso('Prezzi MIMIT grezzi', 'errore: $e');
    }
  }, skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false);
}
