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
      expect(via.queryParameters['sectionType'], 'traffic');
      expect(via.queryParameters['language'], 'it-IT');
      expect(via.queryParameters.containsKey('maxAlternatives'), isFalse);
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
      final c = ClienteTomTom('CHIAVE', client: f.client);
      await expectLater(
        c.calcola(const [Punto(45, 9), Punto(46, 10)]),
        throwsA(isA<ErrorePercorso>()
            .having((e) => e.stato, 'stato', 403)
            .having((e) => e.messaggio, 'messaggio', 'Developer Over Qps')),
      );
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
