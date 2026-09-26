import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final vettore = jsonDecode(File('../../docs/vettore_prova.json').readAsStringSync()) as Map<String, Object?>;
  final a = Abbinamento(
    chiave: Uint8List.fromList(List.generate(32, (i) => i)),
    relay: Uri.parse('wss://relay.esempio.dev'),
    nomeAuto: 'Auto di prova',
  );

  test('si scrive come capita: trattini, spazi, minuscole, O per zero', () {
    expect(CodiceAbbinamento.normalizza('7kq2m-9xapd'), '7KQ2M9XAPD');
    expect(CodiceAbbinamento.normalizza(' 7KQ2M 9XAPD '), '7KQ2M9XAPD');
    expect(CodiceAbbinamento.normalizza('7KQ2M-9XAPO'), '7KQ2M9XAP0');
    expect(CodiceAbbinamento.normalizza('7KQ2M-9XAPl'), '7KQ2M9XAP1');
    expect(CodiceAbbinamento.normalizza('7KQ2M-9XAP'), isNull);
    expect(CodiceAbbinamento.normalizza('7KQ2M-9XAPU'), isNull);
    expect(CodiceAbbinamento.mostra('7KQ2M9XAPD'), '7KQ2M-9XAPD');
  });

  test('un codice nuovo è di dieci caratteri dell\'alfabeto', () {
    final c = CodiceAbbinamento.nuovo();
    expect(CodiceAbbinamento.normalizza(c), c);
  });

  test('stesse derivazioni di Python', () async {
    final (chiave, id) = await CodiceAbbinamento.deriva(vettore['codice'] as String);
    expect(id, vettore['codice_id']);
    expect(base64UrlSenzaPadding.encode(chiave), vettore['codice_chiave']);
  });

  test('apre la busta scritta da Home Assistant', () async {
    final letto = await CodiceAbbinamento.apri(vettore['codice_busta'] as String, vettore['codice'] as String);
    expect(letto.uri, a.uri);
  });

  test('col codice sbagliato non si apre', () async {
    expect(
      CodiceAbbinamento.apri(vettore['codice_busta'] as String, '0000000000'),
      throwsA(isA<FormatException>()),
    );
  });

  test('l\'indirizzo http del relay', () {
    expect(CodiceAbbinamento.indirizzo(Uri.parse('wss://relay.esempio.dev'), 'x').toString(),
        'https://relay.esempio.dev/v1/codici/x');
    expect(CodiceAbbinamento.indirizzo(Uri.parse('ws://127.0.0.1:8799/'), 'x').toString(),
        'http://127.0.0.1:8799/v1/codici/x');
    expect(CodiceAbbinamento.indirizzo(Uri.parse('https://gdanav.gdahome.org/'), 'x').toString(),
        'https://gdanav.gdahome.org/v1/codici/x');
  });

  test('scritto il codice, prende la busta dal relay e la apre', () async {
    final busta = await CodiceAbbinamento.chiudi(a, '7KQ2M9XAPD');
    final chiesti = <Uri>[];
    final client = MockClient((r) async {
      chiesti.add(r.url);
      return http.Response(busta, 200);
    });
    final letto =
        await CodiceAbbinamento.recupera(Uri.parse('https://gdanav.gdahome.org/'), '7kq2m-9xapd', client: client);
    expect(letto.uri, a.uri);
    expect(chiesti.single.toString(), 'https://gdanav.gdahome.org/v1/codici/${vettore['codice_id']}');
  });

  test('scaduto o sbagliato: lo dice', () async {
    final client = MockClient((_) async => http.Response('', 404));
    expect(
      CodiceAbbinamento.recupera(Uri.parse('https://gdanav.gdahome.org/'), '7KQ2M9XAPD', client: client),
      throwsA(predicate((e) => '$e'.contains('scaduto'))),
    );
    expect(
      CodiceAbbinamento.recupera(Uri.parse('https://gdanav.gdahome.org/'), 'abc', client: client),
      throwsA(predicate((e) => '$e'.contains('10 lettere'))),
    );
  });
}
