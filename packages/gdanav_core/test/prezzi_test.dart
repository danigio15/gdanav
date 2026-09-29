import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// I prezzi come li scrive la PUN in `punTariffsDetails`: i tre campi per
/// corrente sono quelli visti sul server vero (A2A, Acea, Plenitude).
Map<String, Object?> tariffe({Map<String, num?>? ac, Map<String, num?>? dc, Map<String, num?>? hpc}) => {
      'punTariffsDetails': {
        'acTariff': ac == null ? null : {'energy': null, 'parking': null, 'activation': null, 'time': null, ...ac},
        'dcTariff': dc == null ? null : {'energy': null, 'parking': null, 'activation': null, 'time': null, ...dc},
        'hpcTariff': hpc == null ? null : {'energy': null, 'parking': null, 'activation': null, 'time': null, ...hpc},
      },
    };

void main() {
  test('A2A: l\'energia in corrente alternata, e la sosta', () {
    final p = Prezzi.daiPunti([
      tariffe(ac: {'energy': 0.63, 'parking': 0.08}),
      tariffe(ac: {'energy': 0.69}),
      tariffe(dc: {'energy': 0.69, 'parking': 0.15}),
    ]);
    expect(p.vuoti, isFalse);
    expect(p.perCorrente.keys, [Corrente.ac, Corrente.dc]);
    final ac = p.perCorrente[Corrente.ac]!;
    // Due punti con due prezzi: da… a…
    expect(ac.energia, (da: 0.63, a: 0.69));
    expect(ac.sosta, (da: 0.08, a: 0.08));
    expect(ac.avvio, isNull);
    expect(p.perCorrente[Corrente.dc]!.sosta, (da: 0.15, a: 0.15));
  });

  test('Emobitaly: l\'avvio si paga a parte', () {
    final p = Prezzi.daiPunti([
      tariffe(ac: {'energy': 0.45, 'activation': 0.74}),
      tariffe(ac: {'energy': 0.6, 'activation': 1.14}),
    ]);
    expect(p.perCorrente[Corrente.ac]!.avvio, (da: 0.74, a: 1.14));
  });

  /* Plenitude manda tutti i campi, tutti vuoti; la maggior parte dei gestori
   * non manda niente. In tutti e due i casi il prezzo non c'è. */
  test('chi non lo manda, o lo manda vuoto, non ha prezzi', () {
    expect(Prezzi.daiPunti([tariffe(ac: {}, dc: {}, hpc: {})]).vuoti, isTrue);
    expect(
        Prezzi.daiPunti([
          {'evse_id': 'IT*ENX*E1', 'status': 'AVAILABLE'},
        ]).vuoti,
        isTrue);
    expect(Prezzi.daiPunti(const []).vuoti, isTrue);
  });

  test('zero e cifre fuori misura non sono prezzi', () {
    final p = Prezzi.daiPunti([
      tariffe(dc: {'energy': 0, 'parking': 0}),
      tariffe(hpc: {'energy': 69, 'time': 0.2}),
    ]);
    expect(p.perCorrente.containsKey(Corrente.dc), isFalse);
    expect(p.perCorrente[Corrente.hpc]!.energia, isNull);
    expect(p.perCorrente[Corrente.hpc]!.tempo, (da: 0.2, a: 0.2));
  });

  /* I prezzi arrivano nella stessa risposta dello stato: toccare una
   * colonnina non costa una richiesta in più. */
  test('toccando una colonnina arrivano insieme allo stato', () async {
    final client = MockClient((r) async {
      if (r.url.host.startsWith('cognito-identity.')) {
        return http.Response(
          jsonEncode({
            'IdentityId': 'eu-south-1:ospite',
            'Credentials': {
              'AccessKeyId': 'ASIAPROVA',
              'SecretKey': 'segreto',
              'SessionToken': 'gettone',
              'Expiration': DateTime.utc(2026, 9, 29, 18).millisecondsSinceEpoch / 1000,
            },
          }),
          200,
        );
      }
      final ids = (jsonDecode(r.body) as List).cast<String>();
      return http.Response(
        jsonEncode([
          for (final e in ids)
            {
              'evse_id': e,
              'status': 'AVAILABLE',
              'realTime': true,
              'connectors': [
                {'standard': 'IEC_62196_T2', 'max_electric_power': 22000},
              ],
              ...tariffe(ac: {'energy': 0.63}),
            },
        ]),
        200,
      );
    });
    final a2a = Colonnina(
      id: 'pun:a2a',
      nome: 'A2A Milano',
      posizione: const Punto(45.46, 9.19),
      connettori: const [Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22)],
      fonte: 'pun',
      evse: const ['IT*A2M*E1'],
    );
    expect(a2a.prezzi, isNull, reason: 'dall\'archivio: non si è chiesto');
    final c = await DisponibilitaPun(client: client, adesso: () => DateTime.utc(2026, 9, 29, 8)).aggiorna(a2a);
    expect(c.connettori.single.stato, StatoPresa.disponibile);
    expect(c.prezzi!.perCorrente[Corrente.ac]!.energia, (da: 0.63, a: 0.63));
  });
}
