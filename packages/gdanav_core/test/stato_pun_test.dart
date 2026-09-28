import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Un punto di ricarica come lo restituisce `/v1/chargepoints/group`.
Map<String, Object?> punto(String evse, String stato, {bool? tempoReale = true, String standard = 'IEC_62196_T2'}) => {
      'evse_id': evse,
      'status': stato,
      if (tempoReale != null) 'realTime': tempoReale,
      'connectors': [
        {'standard': standard, 'max_electric_power': 22000},
      ],
      'location': {'_id': 'x', 'party_id': 'BEC'},
    };

Colonnina isola(int quanti) => Colonnina(
      id: 'pun:isola',
      nome: 'Centro Direzionale Isola A3',
      posizione: const Punto(40.8568, 14.2831),
      connettori: [for (var i = 0; i < quanti; i++) const Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22.1)],
      fonte: 'pun',
      evse: [for (var i = 0; i < quanti; i++) 'IT*BEC*EW001*$i'],
    );

/// La PUN finta: Cognito ospite e il gruppo, e un registro di cosa si è chiesto.
class PunFinta {
  PunFinta(this.risposta);

  final Map<String, Object?> Function(String evse) risposta;
  final chieste = <List<String>>[];
  final intestazioni = <Map<String, String>>[];
  var cognito = 0;

  late final client = MockClient((r) async {
    if (r.url.host.startsWith('cognito-identity.')) {
      cognito++;
      final azione = r.headers['x-amz-target'];
      if (azione == 'AWSCognitoIdentityService.GetId') {
        expect((jsonDecode(r.body) as Map)['IdentityPoolId'], DisponibilitaPun.pool);
        return http.Response(jsonEncode({'IdentityId': 'eu-south-1:ospite'}), 200);
      }
      expect(azione, 'AWSCognitoIdentityService.GetCredentialsForIdentity');
      return http.Response(
        jsonEncode({
          'IdentityId': 'eu-south-1:ospite',
          'Credentials': {
            'AccessKeyId': 'ASIAPROVA',
            'SecretKey': 'segreto',
            'SessionToken': 'gettone',
            'Expiration': DateTime.utc(2026, 9, 28, 18).millisecondsSinceEpoch / 1000,
          },
        }),
        200,
      );
    }
    expect(r.url.toString(), '${DisponibilitaPun.api}/v1/chargepoints/group');
    intestazioni.add(r.headers);
    final ids = (jsonDecode(r.body) as List).cast<String>();
    chieste.add(ids);
    return http.Response(jsonEncode([for (final e in ids) risposta(e)]), 200);
  });
}

void main() {
  final adesso = DateTime.utc(2026, 9, 28, 16);

  group('la firma di AWS', () {
    /* L'esempio della documentazione di AWS (Signature Version 4, «Create a
     * signed request»): se questo torna, la firma è giusta. */
    test("l'esempio ufficiale di AWS torna identico", () async {
      final firma = await firmaSigV4(
        metodo: 'GET',
        uri: Uri.parse('https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08'),
        intestazioni: {
          'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
          'host': 'iam.amazonaws.com',
          'x-amz-date': '20150830T123600Z',
        },
        corpo: const [],
        idChiave: 'AKIDEXAMPLE',
        segreto: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
        regione: 'us-east-1',
        servizio: 'iam',
        data: DateTime.utc(2015, 8, 30, 12, 36),
      );
      expect(
        firma,
        'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, '
        'SignedHeaders=content-type;host;x-amz-date, '
        'Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7',
      );
    });

    test('la data come la vuole AWS', () {
      expect(dataAmz(DateTime.utc(2026, 9, 8, 7, 5, 3)), '20260908T070503Z');
    });
  });

  group('libere e occupate dalla PUN', () {
    test('lo stato di ogni punto diventa quello delle prese', () async {
      final stati = {'IT*BEC*EW001*0': 'AVAILABLE', 'IT*BEC*EW001*1': 'CHARGING', 'IT*BEC*EW001*2': 'OUTOFORDER'};
      final pun = PunFinta((e) => punto(e, stati[e] ?? 'BLOCKED'));
      final d = DisponibilitaPun(client: pun.client, adesso: () => adesso);
      final c = await d.aggiorna(isola(4));
      expect(c.connettori.map((p) => p.stato), [
        StatoPresa.disponibile,
        StatoPresa.occupata,
        StatoPresa.fuoriServizio,
        // Bloccata: un'auto ferma davanti, per chi arriva è occupata.
        StatoPresa.occupata,
      ]);
      expect(c.disponibilitaPer({TipoConnettore.tipo2}).libere, 1);
      expect(c.evse, hasLength(4));
      expect(c.fonte, 'pun');
    });

    test('la richiesta è firmata con le credenziali ospite', () async {
      final pun = PunFinta((e) => punto(e, 'AVAILABLE'));
      await DisponibilitaPun(client: pun.client, adesso: () => adesso).aggiorna(isola(2));
      final h = pun.intestazioni.single;
      expect(h['authorization'], startsWith('AWS4-HMAC-SHA256 Credential=ASIAPROVA/20260928/eu-south-1/execute-api/'));
      expect(h['authorization'], contains('SignedHeaders=content-type;host;x-amz-date;x-amz-security-token'));
      expect(h['x-amz-security-token'], 'gettone');
      expect(h['x-amz-date'], '20260928T160000Z');
      // Senza «; charset=utf-8»: il content-type è firmato così com'è.
      expect(h['content-type'], 'application/json');
    });

    test('a blocchi di cento, come il sito', () async {
      final pun = PunFinta((e) => punto(e, 'AVAILABLE'));
      final c = await DisponibilitaPun(client: pun.client, adesso: () => adesso).aggiorna(isola(202));
      expect(pun.chieste.map((b) => b.length), [100, 100, 2]);
      expect(c.connettori, hasLength(202));
    });

    test('chi non aggiorna in tempo reale non dice «libera»', () async {
      final pun = PunFinta((e) => punto(e, 'AVAILABLE', tempoReale: false));
      final c = await DisponibilitaPun(client: pun.client, adesso: () => adesso).aggiorna(isola(2));
      expect(c.connettori.map((p) => p.stato), everyElement(StatoPresa.sconosciuto));
    });

    test('uno stato letto vale un minuto, e le credenziali si riusano', () async {
      var ora = adesso;
      final pun = PunFinta((e) => punto(e, 'AVAILABLE'));
      final d = DisponibilitaPun(client: pun.client, adesso: () => ora);
      await d.aggiorna(isola(2));
      await d.aggiorna(isola(2));
      expect(pun.chieste, hasLength(1));
      ora = ora.add(const Duration(minutes: 2));
      await d.aggiorna(isola(2));
      expect(pun.chieste, hasLength(2));
      // GetId e GetCredentialsForIdentity una volta sola.
      expect(pun.cognito, 2);
    });

    test('senza EVSE ID non si chiede niente', () async {
      final pun = PunFinta((e) => punto(e, 'AVAILABLE'));
      const osm = Colonnina(
        id: 'osm-node-1',
        nome: 'Enel X',
        posizione: Punto(40.85, 14.28),
        connettori: [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 50)],
        fonte: 'osm',
      );
      expect(identical(await DisponibilitaPun(client: pun.client, adesso: () => adesso).aggiorna(osm), osm), isTrue);
      expect(pun.chieste, isEmpty);
      expect(pun.cognito, 0);
    });

    test('se la PUN non conosce più nessuno dei suoi punti, la colonnina resta com\'era', () async {
      final pun = PunFinta((e) => {'evse_id': 'altro', 'status': 'AVAILABLE'});
      final prima = isola(2);
      expect(
          identical(await DisponibilitaPun(client: pun.client, adesso: () => adesso).aggiorna(prima), prima), isTrue);
    });

    test('credenziali scadute: se ne prendono di nuove e si riprova, una volta', () async {
      var rifiuti = 1;
      var cognito = 0;
      final client = MockClient((r) async {
        if (r.url.host.startsWith('cognito-identity.')) {
          cognito++;
          return http.Response(
            jsonEncode({
              'IdentityId': 'eu-south-1:ospite',
              'Credentials': {
                'AccessKeyId': 'ASIA$cognito',
                'SecretKey': 's',
                'SessionToken': 't',
                'Expiration': DateTime.utc(2026, 9, 28, 18).millisecondsSinceEpoch / 1000,
              },
            }),
            200,
          );
        }
        if (rifiuti-- > 0) return http.Response('{"message":"expired"}', 403);
        return http.Response(jsonEncode([punto('IT*BEC*EW001*0', 'AVAILABLE')]), 200);
      });
      final c = await DisponibilitaPun(client: client, adesso: () => adesso).aggiorna(isola(1));
      expect(c.connettori.single.stato, StatoPresa.disponibile);
      // GetId + credenziali, poi di nuovo le credenziali (l'identità resta).
      expect(cognito, 3);
    });
  });

  group('PUN per chi ha gli EVSE ID, TomTom per le altre', () {
    const osm = Colonnina(
      id: 'osm-node-1',
      nome: 'Enel X',
      posizione: Punto(40.85, 14.28),
      connettori: [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 50)],
      fonte: 'osm',
    );

    test('ognuna da chi la conosce', () async {
      final pun = PunFinta((e) => punto(e, 'AVAILABLE'));
      final tomtom = _Finta();
      final d = DisponibilitaConPun(DisponibilitaPun(client: pun.client, adesso: () => adesso), altra: tomtom);
      expect((await d.aggiorna(isola(1))).connettori.single.stato, StatoPresa.disponibile);
      expect(tomtom.chieste, isEmpty);
      expect((await d.aggiorna(osm)).connettori.single.stato, StatoPresa.occupata);
      expect(tomtom.chieste, ['osm-node-1']);
    });

    test('la PUN giù: si prova TomTom', () async {
      final giu = MockClient((_) async => http.Response('', 503));
      final tomtom = _Finta();
      final d = DisponibilitaConPun(DisponibilitaPun(client: giu, adesso: () => adesso), altra: tomtom);
      expect((await d.aggiorna(isola(1))).connettori.single.stato, StatoPresa.occupata);
      expect(tomtom.chieste, ['pun:isola']);
    });

    test('senza TomTom, la colonnina senza EVSE resta com\'era', () async {
      final pun = PunFinta((e) => punto(e, 'AVAILABLE'));
      final d = DisponibilitaConPun(DisponibilitaPun(client: pun.client, adesso: () => adesso));
      expect(identical(await d.aggiorna(osm), osm), isTrue);
    });
  });
}

/// TomTom finta: dice occupato a tutto, e si ricorda chi ha visto.
class _Finta implements FonteDisponibilita {
  final chieste = <String>[];

  @override
  Future<Colonnina> aggiorna(Colonnina c) async {
    chieste.add(c.id);
    return Colonnina(
      id: c.id,
      nome: c.nome,
      posizione: c.posizione,
      fonte: c.fonte,
      evse: c.evse,
      connettori: [
        for (final p in c.connettori) Connettore(tipo: p.tipo, potenzaKw: p.potenzaKw, stato: StatoPresa.occupata)
      ],
    );
  }
}
