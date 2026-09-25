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
      final risultati = json['results'] as List;
      avviso('Prezzi MIMIT grezzi', '${risultati.length} distributori');
      if (Platform.environment['GDANAV_PREZZI'] case final file?) {
        File(file).writeAsStringSync(jsonEncode({'results': risultati}));
      }
    } catch (e) {
      avviso('Prezzi MIMIT grezzi', 'errore: $e');
    }
  }, skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false);

  // Le colonnine vere intorno a Utrecht, con lo stato TomTom se c'è la
  // chiave: per le anteprime dell'app.
  test('colonnine vere intorno a Utrecht', () async {
    const qui = Punto(52.0907, 5.1214);
    try {
      final tutte = await ClienteColonnineRelay(Uri.parse('https://gdanav.gdahome.org/')).lungo([qui], distanzaKm: 8);
      final rapide = [
        for (final c in tutte)
          if (c.connettori.any((x) => x.potenzaKw >= 50)) c,
      ]..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
      final chiave = Platform.environment['GDANAV_TOMTOM'] ?? '';
      final stato = chiave.isEmpty ? null : DisponibilitaTomTom(chiave);
      // Tutte insieme: una alla volta non si sta nel tempo.
      final elenco = await Future.wait([
        for (final c in rapide.take(25))
          if (stato == null)
            Future.value(c)
          else
            stato.aggiorna(c).timeout(const Duration(seconds: 10)).catchError((Object _) => c),
      ]);
      final note = elenco.where((c) => c.connettori.any((x) => x.stato != StatoPresa.sconosciuto)).length;
      avviso('Colonnine Utrecht', '${tutte.length} in tutto, ${rapide.length} rapide, con stato TomTom: $note');
      if (Platform.environment['GDANAV_COLONNINE'] case final file?) {
        File(file).writeAsStringSync(
          jsonEncode([
            for (final c in elenco)
              {
                'id': c.id,
                'nome': c.nome,
                'operatore': c.operatore,
                'lat': c.posizione.lat,
                'lon': c.posizione.lon,
                'connettori': [
                  for (final x in c.connettori) {'tipo': x.tipo.name, 'kw': x.potenzaKw, 'stato': x.stato.name},
                ],
              },
          ]),
        );
      }
    } catch (e) {
      avviso('Colonnine Utrecht', 'errore: $e');
    }
  },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false);

  // In Italia: quante colonnine rapide intorno a Napoli hanno lo stato di
  // adesso da TomTom.
  test('stato delle colonnine intorno a Napoli', () async {
    const qui = Punto(40.8518, 14.2681);
    final chiave = Platform.environment['GDANAV_TOMTOM'] ?? '';
    if (chiave.isEmpty) return;
    try {
      final tutte = await ClienteColonnineRelay(Uri.parse('https://gdanav.gdahome.org/')).lungo([qui], distanzaKm: 10);
      final rapide = [
        for (final c in tutte)
          if (c.connettori.any((x) => x.potenzaKw >= 40)) c,
      ]..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
      final stato = DisponibilitaTomTom(chiave);
      final elenco = await Future.wait([
        for (final c in rapide.take(15))
          stato.aggiorna(c).timeout(const Duration(seconds: 60)).catchError((Object _) => c),
      ]);
      avviso(
          'Colonnine Napoli',
          [
            '${tutte.length} in tutto, ${rapide.length} rapide',
            for (final c in elenco)
              '${c.nome} (${c.operatore}): ${c.connettori.map((x) => '${x.tipo.name}=${x.stato.name}').join(' ')}',
          ].join(' | '));
    } catch (e) {
      avviso('Colonnine Napoli', 'errore: $e');
    }
  },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: Platform.environment['GDANAV_RETE'] == null ? 'solo con GDANAV_RETE=1' : false);
}
