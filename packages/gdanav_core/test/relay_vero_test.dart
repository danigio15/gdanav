@Tags(['relay'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// L'app e una casa finta, attraverso un relay vero. Gira solo se c'è un
/// relay acceso in locale:
///
///     cd relay && npx wrangler dev --port 8799
///     GDANAV_RELAY=ws://127.0.0.1:8799 dart test test/relay_vero_test.dart
void main() {
  final relay = Platform.environment['GDANAV_RELAY'];

  test("stato dalla casa all'app, viaggio dall'app alla casa", () async {
    final a = Abbinamento.nuovo(relay: Uri.parse(relay!), nomeAuto: 'Prova');
    final busta = await Busta.per(a);

    // Un'app non crea stanze: prima della casa, il relay la respinge.
    final troppoPresto = WebSocketChannel.connect(await a.indirizzoRelay('app'));
    await expectLater(troppoPresto.ready, throwsA(anything));

    final casa = WebSocketChannel.connect(await a.indirizzoRelay('casa'));
    await casa.ready;
    final ricevuti = <Messaggio>[];
    casa.stream.listen((dato) async {
      if ((jsonDecode(dato as String) as Map).containsKey('relay')) return;
      final m = await busta.apri(dato, Mittente.app);
      ricevuti.add(m);
      if (m.tipo == TipoMessaggio.richiediStato) {
        casa.sink.add(
          await busta.chiudi(Messaggio(tipo: TipoMessaggio.statoAuto, dati: {'batteria': 67.5}), Mittente.casa),
        );
      }
    });

    final sorgente = SorgenteHomeAssistant(ClienteRelay(a));
    final prima = sorgente.letture.first;
    await sorgente.avvia();
    final stato = await prima.timeout(const Duration(seconds: 10));
    expect(stato.batteria, 67.5);
    expect(stato.sorgente, TipoSorgente.homeAssistant);

    await sorgente.relay.manda(Messaggio(tipo: TipoMessaggio.viaggio, dati: {'in_viaggio': true}));
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return !ricevuti.any((m) => m.tipo == TipoMessaggio.viaggio);
    }).timeout(const Duration(seconds: 10));

    await sorgente.ferma();
    await casa.sink.close();
  }, skip: relay == null ? 'serve GDANAV_RELAY con un relay acceso' : false);

  test('il codice scritto a mano: la casa lo lascia, l\'app lo prende una volta sola', () async {
    final a = Abbinamento.nuovo(relay: Uri.parse(relay!), nomeAuto: 'Prova');
    final codice = CodiceAbbinamento.nuovo();
    final (_, id) = await CodiceAbbinamento.deriva(codice);
    final r = await http.put(
      CodiceAbbinamento.indirizzo(a.relay, id),
      headers: {'content-type': 'application/json'},
      body: await CodiceAbbinamento.chiudi(a, codice),
    );
    expect(r.statusCode, 201);

    final letto = await CodiceAbbinamento.recupera(a.relay, CodiceAbbinamento.mostra(codice).toLowerCase());
    expect(letto.uri, a.uri);
    await expectLater(CodiceAbbinamento.recupera(a.relay, codice), throwsA(predicate((e) => '$e'.contains('scaduto'))));
  }, skip: relay == null ? 'serve GDANAV_RELAY' : false);
}
