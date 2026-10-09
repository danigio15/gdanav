import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Una risposta vera di TomTom: il percorso da Via Nazionale a Corso Malta
/// (Napoli), con le manovre come le manda lui. Le code e le sezioni sono
/// quelle di un percorso trafficato, nello stesso formato.
Map<String, Object?> corsoMalta() =>
    jsonDecode(File('test/dati/tomtom_corso_malta.json').readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> primaRotta() => (corsoMalta()['routes'] as List).first as Map<String, Object?>;

/// Un client che risponde sempre [corpo], e si ricorda cosa gli è stato
/// chiesto.
({http.Client client, List<http.BaseRequest> chieste}) finto(Object corpo, {int stato = 200}) {
  final chieste = <http.BaseRequest>[];
  return (
    client: MockClient((r) async {
      chieste.add(r);
      return http.Response(corpo is String ? corpo : jsonEncode(corpo), stato,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
    chieste: chieste,
  );
}

void main() {
  group('lettura della risposta', () {
    test('il tracciato è quello dei pezzi, senza ripetere i punti di giunzione', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.punti, hasLength(285));
      expect(p.punti.first.lat, closeTo(40.85561, 0.0001));
      expect(p.punti.first.lon, closeTo(14.27407, 0.0001));
    });

    test('le manovre sono quelle di TomTom, tradotte nei numeri di prima', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.manovre.map((m) => m.tipo), [1, 26, 15, 16, 23, 5]);
    });

    test('le etichette del testo non finiscono sullo schermo', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.manovre[2].istruzione, isNot(contains('<')));
      expect(p.manovre[2].istruzione, contains('Corso Malta'));
      // Dove TomTom unisce due manovre, si dice la frase unita.
      expect(p.manovre[2].istruzione, contains('sulla sinistra'));
    });

    test('la manovra che chiedeva di tenere la sinistra non dice di svoltare', () {
      final p = ClienteTomTom.leggi(primaRotta());
      final tieniLaSinistra = p.manovre[3];
      expect(tieniLaSinistra.istruzione, 'Spostati sulla sinistra');
      // 16 è «leggera sinistra»: la freccia non è quella della svolta.
      expect(tieniLaSinistra.tipo, 16);
    });

    /* Le corsie non stanno nelle istruzioni: arrivano come sezioni «LANES»,
     * e queste sono quelle vere di TomTom per lo stesso percorso. Al
     * Sottopasso Malta tre corsie, le due di sinistra da seguire. */
    test('le corsie tornano: al Sottopasso Malta le due di sinistra', () {
      final p = ClienteTomTom.leggi(primaRotta());
      final tieniLaSinistra = p.manovre[3];
      expect(tieniLaSinistra.corsie.map((c) => c.giusta), [true, true, false]);
      expect(tieniLaSinistra.corsie.first.consigliata, DirezioneCorsia.leggeraSinistra);
      expect(tieniLaSinistra.corsie.last.direzioni, [DirezioneCorsia.dritto]);
      expect(tieniLaSinistra.corsieUtili, isTrue);
      // Gira a sinistra in Corso Malta: la corsia di sinistra.
      expect(p.manovre[2].corsie.map((c) => c.giusta), [true, false]);
      // Tieni la destra per la Tangenziale: quella di destra.
      expect(p.manovre[4].corsie.map((c) => c.giusta), [false, true]);
      // Partenza, rotonda e arrivo non ne hanno; il tratto a metà strada,
      // senza una manovra dentro, non si attacca a nessuna.
      for (final i in [0, 1, 5]) {
        expect(p.manovre[i].corsie, isEmpty, reason: 'manovra $i');
      }
    });

    test('il cartello: numeri della strada e direzione', () {
      final p = ClienteTomTom.leggi(primaRotta());
      final versoTangenziale = p.manovre[4];
      expect(versoTangenziale.verso, 'A56 · Capodichino');
      expect(versoTangenziale.strada, 'Tangenziale di Napoli');
    });

    test('la rotonda dice quale uscita prendere', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.manovre[1].uscitaRotonda, 1);
    });

    test('le manovre puntano dentro il tracciato', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.manovre.every((m) => m.inizio >= 0 && m.inizio < p.punti.length), isTrue);
    });

    test('la lunghezza torna con quella dichiarata da TomTom', () {
      final rotta = primaRotta();
      final somma = (rotta['summary'] as Map)['lengthInMeters'] as num;
      final p = ClienteTomTom.leggi(rotta);
      // L'ultima manovra è l'arrivo e non ha strada dopo di sé: i tratti
      // coprono tutto quello che viene prima.
      expect(p.lunghezzaM, closeTo(somma.toDouble(), 2));
    });

    test('senza altimetria il percorso è piatto, non inventato', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.tratti.every((t) => t.dislivelloM == 0), isTrue);
      expect(p.tratti, isNotEmpty);
    });

    test('le code arrivano dalla stessa risposta, in metri sul tracciato', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.code, hasLength(1));
      final c = p.code.single;
      expect(c.tipo, 'Coda');
      expect(c.velocitaKmh, 7);
      expect(c.ritardo, const Duration(seconds: 156));
      expect(c.livello, 2);
      expect(c.daM, greaterThan(0));
      expect(c.aM, greaterThan(c.daM));
    });

    test('i limiti di velocità sono quelli di TomTom, segmento per segmento', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.limiti, hasLength(p.punti.length - 1));
      // 50 in città fino al punto 60, poi 80 sulla tangenziale.
      expect(p.limiteSul(0), 50);
      expect(p.limiteSul(59), 50);
      expect(p.limiteSul(60), 80);
      expect(p.limiteSul(202), 80);
      // Oltre l'ultima sezione TomTom non dice niente, e non si inventa.
      expect(p.limiteSul(203), isNull);
    });

    test('senza sezioni dei limiti la lista resta vuota, non piena di zeri', () {
      final rotta = primaRotta();
      rotta['sections'] =
          (rotta['sections']! as List).where((s) => (s! as Map)['sectionType'] != 'SPEED_LIMIT').toList();
      expect(ClienteTomTom.leggi(rotta).limiti, isEmpty);
    });

    test('pedaggi, autostrade e traghetti dalle sezioni', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.conPedaggi, isTrue);
      expect(p.conAutostrade, isTrue);
      expect(p.conTraghetti, isFalse);
    });

    test('il tempo è già quello del traffico di adesso', () {
      final p = ClienteTomTom.leggi(primaRotta());
      expect(p.trafficoVero, isTrue);
      // 802 s col traffico contro 651 senza: si perdono 151 secondi, anche
      // se `trafficDelayInSeconds` dice 0 (conta solo gli eventi segnalati).
      expect(p.ritardoTraffico.inSeconds, 156);
    });
  });

  group('le chiamate', () {
    test('calcola chiede un percorso solo, con traffico e istruzioni', () async {
      final f = finto(corsoMalta());
      final c = ClienteTomTom('CHIAVE', client: f.client);
      final p = await c.calcola(const [Punto(40.85561, 14.27407), Punto(40.86395, 14.29052)]);
      expect(p.manovre, isNotEmpty);
      expect(f.chieste, hasLength(1));
      final via = f.chieste.single.url;
      expect(via.path, contains('40.85561,14.27407:40.86395,14.29052'));
      expect(via.queryParameters['traffic'], 'true');
      expect(via.queryParameters['language'], 'it-IT');
      expect(via.queryParameters.containsKey('maxAlternatives'), isFalse);
      // Le sezioni vanno ripetute una per una: separate da virgole TomTom
      // risponde 400 (provato in CI).
      expect(via.queryParametersAll['sectionType'], ClienteTomTom.sezioniChieste);
      expect(via.queryParametersAll['sectionType'], contains('speedLimit'));
    });

    test('ricalcolando in movimento, la partenza porta il verso in cui si va', () async {
      // Senza verso TomTom può partire dalla carreggiata dall'altra parte, e
      // il percorso appena ricalcolato comincia con un'inversione.
      final f = finto(corsoMalta());
      final c = ClienteTomTom('CHIAVE', client: f.client);
      await c.calcola(const [PuntoInMoto(40.85561, 14.27407, rotta: 92.6, velocitaMs: 14), Punto(40.86395, 14.29052)]);
      expect(f.chieste.single.url.queryParameters['vehicleHeading'], '93');
      // Fermi, o un punto qualunque: niente verso, che sarebbe inventato.
      await c.calcola(const [PuntoInMoto(40.85561, 14.27407, rotta: 92.6, velocitaMs: 0.4), Punto(40.86395, 14.29052)]);
      await c.calcola(const [Punto(40.85561, 14.27407), Punto(40.86395, 14.29052)]);
      expect(f.chieste.skip(1).map((r) => r.url.queryParameters.containsKey('vehicleHeading')), [false, false]);
    });

    test('le scelte del percorso diventano gli «avoid» di TomTom', () async {
      final f = finto(corsoMalta());
      final c = ClienteTomTom('CHIAVE', client: f.client);
      await c.calcola(
        const [Punto(45, 9), Punto(46, 10)],
        opzioni: const OpzioniPercorso(
          modo: ModoGuida.risparmio,
          evitaPedaggi: true,
          evitaTraghetti: true,
        ),
      );
      final q = f.chieste.single.url.queryParameters;
      expect(q['avoid'], 'tollRoads,ferries');
      expect(q['vehicleMaxSpeed'], '100');
    });

    test('le ZTL da evitare vanno nel corpo, come «avoidAreas»: allora è un POST', () async {
      final f = finto(corsoMalta());
      final c = ClienteTomTom('CHIAVE', client: f.client);
      await c.calcola(const [Punto(40.84, 14.25), Punto(40.86, 14.25)]);
      expect(f.chieste.last.method, 'GET', reason: 'senza aree da evitare resta com\'era');
      await c.alternative(
        const Punto(40.84, 14.25),
        const Punto(40.86, 14.25),
        evita: const [Rettangolo(40.845, 14.245, 40.855, 14.255), Rettangolo(40.83, 14.23, 40.84, 14.24)],
      );
      final r = f.chieste.last as http.Request;
      expect(r.method, 'POST');
      expect(r.url.queryParameters['maxAlternatives'], '2');
      final corpo = jsonDecode(r.body) as Map<String, Object?>;
      final rettangoli = ((corpo['avoidAreas'] as Map)['rectangles'] as List).cast<Map>();
      expect(rettangoli, hasLength(2));
      expect(rettangoli.first['southWestCorner'], {'latitude': 40.845, 'longitude': 14.245});
      expect(rettangoli.first['northEastCorner'], {'latitude': 40.855, 'longitude': 14.255});
    });

    test('le alternative arrivano già complete: seguendo non chiede niente', () async {
      final due = corsoMalta();
      (due['routes'] as List).add((due['routes'] as List).first);
      final f = finto(due);
      final c = ClienteTomTom('CHIAVE', client: f.client);
      final scelte = await c.alternative(const Punto(45, 9), const Punto(46, 10), quante: 2);
      expect(scelte, hasLength(2));
      expect(f.chieste.single.url.queryParameters['maxAlternatives'], '2');

      final rifatto = await c.seguendo(scelte.first);
      expect(rifatto, same(scelte.first));
      // Nessuna seconda chiamata: il piano gratuito non si spreca.
      expect(f.chieste, hasLength(1));
    });

    test('un percorso senza manovre si rifà passando dai suoi punti', () async {
      final f = finto(corsoMalta());
      final c = ClienteTomTom('CHIAVE', client: f.client);
      final spoglio = PercorsoCalcolato(
        punti: const [Punto(45, 9), Punto(45.5, 9.5), Punto(46, 10)],
        tratti: const [],
        manovre: const [],
      );
      final rifatto = await c.seguendo(spoglio);
      expect(rifatto.manovre, isNotEmpty);
      expect(f.chieste, hasLength(1));
      final r = f.chieste.single;
      expect(r.method, 'POST');
      final corpo = jsonDecode((r as http.Request).body) as Map<String, Object?>;
      expect(corpo['supportingPoints'], hasLength(3));
    });

    test('il contatore esaurito si legge, non si maschera', () async {
      final f = finto({
        'detailedError': {'code': 'FORBIDDEN', 'message': 'Developer Over Qps'},
      }, stato: 403);
      final c = ClienteTomTom('CHIAVE', client: f.client, pausaSeTroppe: Duration.zero);
      await expectLater(
        c.calcola(const [Punto(45, 9), Punto(46, 10)]),
        throwsA(isA<ErrorePercorso>()
            .having((e) => e.stato, 'stato', 403)
            .having((e) => e.messaggio, 'messaggio', 'Developer Over Qps')),
      );
    });

    test('troppe richieste in un secondo: aspetta e riprova', () async {
      final chieste = <http.BaseRequest>[];
      final client = MockClient((r) async {
        chieste.add(r);
        return chieste.length == 1
            ? http.Response(
                jsonEncode({
                  'detailedError': {
                    'code': 'TOO_MANY_REQUESTS',
                    'message': 'You have exceeded the permitted rate limit'
                  },
                }),
                429)
            : http.Response(jsonEncode(corsoMalta()), 200,
                headers: const {'content-type': 'application/json; charset=utf-8'});
      });
      final c = ClienteTomTom('CHIAVE', client: client, pausaSeTroppe: Duration.zero);
      final p = await c.calcola(const [Punto(40.85, 14.25), Punto(40.86, 14.28)]);
      expect(p.punti, isNotEmpty);
      expect(chieste, hasLength(2));
    });

    test('se le richieste restano troppe, dopo due attese si arrende e lo dice', () async {
      final f = finto({
        'detailedError': {'code': 'TOO_MANY_REQUESTS', 'message': 'You have exceeded the permitted rate limit'},
      }, stato: 429);
      final c = ClienteTomTom('CHIAVE', client: f.client, pausaSeTroppe: Duration.zero);
      await expectLater(
        c.calcola(const [Punto(45, 9), Punto(46, 10)]),
        throwsA(isA<ErrorePercorso>().having((e) => e.stato, 'stato', 429)),
      );
      expect(f.chieste, hasLength(3));
    });

    test('la quota finita non si riprova: sarebbero richieste buttate', () async {
      final f = finto({
        'detailedError': {'code': 'FORBIDDEN', 'message': 'Developer Over Rate'},
      }, stato: 403);
      final c = ClienteTomTom('CHIAVE', client: f.client, pausaSeTroppe: Duration.zero);
      await expectLater(c.calcola(const [Punto(45, 9), Punto(46, 10)]), throwsA(isA<ErrorePercorso>()));
      expect(f.chieste, hasLength(1));
    });

    test('una risposta senza percorsi lo dice', () async {
      final f = finto({'formatVersion': '0.0.12', 'routes': <Object>[]});
      final c = ClienteTomTom('CHIAVE', client: f.client);
      await expectLater(
        c.calcola(const [Punto(45, 9), Punto(46, 10)]),
        throwsA(isA<ErrorePercorso>()),
      );
    });
  });

  group('i numeri delle manovre', () {
    test('sono quelli che l\'app già sa disegnare', () {
      // Le icone e lo svincolo leggono il numero di Valhalla: cambiando
      // motore non deve cambiare niente sopra.
      expect(ClienteTomTom.tipoDellaManovra('TURN_RIGHT'), 10);
      expect(ClienteTomTom.tipoDellaManovra('TURN_LEFT'), 15);
      expect(ClienteTomTom.tipoDellaManovra('KEEP_LEFT'), 24);
      expect(ClienteTomTom.tipoDellaManovra('ENTER_MOTORWAY'), 25);
      expect(ClienteTomTom.tipoDellaManovra('ROUNDABOUT_CROSS'), 26);
      expect(ClienteTomTom.tipoDellaManovra('TAKE_FERRY'), 28);
      expect(ClienteTomTom.tipoDellaManovra('FOLLOW'), 8);
      expect(ClienteTomTom.tipoDellaManovra('qualcosa_di_nuovo'), 0);
    });

    test('l\'inversione si fa dalla parte giusta per il paese', () {
      expect(ClienteTomTom.tipoDellaManovra('MAKE_UTURN'), 13);
      expect(ClienteTomTom.tipoDellaManovra('MAKE_UTURN', drittaADestra: false), 12);
      expect(ClienteTomTom.tipoDellaManovra('TAKE_EXIT'), 20);
      expect(ClienteTomTom.tipoDellaManovra('TAKE_EXIT', drittaADestra: false), 21);
    });
  });
}
