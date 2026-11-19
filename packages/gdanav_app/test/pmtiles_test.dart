import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/sorgenti/pmtiles.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('i numeri delle tessere sono quelli del formato (curva di Hilbert)', () {
    // Gli stessi della libreria di riferimento (pmtiles per Python).
    expect(idTessera(0, 0, 0), 0);
    expect(idTessera(1, 0, 0), 1);
    expect(idTessera(1, 0, 1), 2);
    expect(idTessera(1, 1, 1), 3);
    expect(idTessera(1, 1, 0), 4);
    expect(idTessera(2, 3, 2), 16);
    expect(idTessera(14, 8838, 6144), 314676585);
    expect(idTessera(14, 8839, 6144), 314676586);
    expect(idTessera(14, 8838, 6145), 314676588);
  });

  test('le tessere si leggono dal pacchetto, decompresse; quelle che mancano no', () async {
    // Un pacchetto vero, fatto con la libreria di riferimento: tre tessere.
    final p = await LettorePmtiles.apri('test/dati/edifici-prova.pmtiles');
    addTearDown(p.chiudi);
    expect(p.zoomMinimo, 14);
    expect(p.zoomMassimo, 14);
    expect(utf8.decode((await p.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
    expect(utf8.decode((await p.tessera(14, 8839, 6144))!), 'la tessera accanto');
    expect(utf8.decode((await p.tessera(14, 8838, 6145))!), 'e quella sotto');
    expect(await p.tessera(14, 8839, 6145), isNull);
    expect(await p.tessera(13, 4419, 3072), isNull);
  });

  test('un file che non è un pacchetto si dice', () async {
    expect(LettorePmtiles.apri('pubspec.yaml'), throwsFormatException);
  });

  test('un pacchetto letto a pezzi: la testa una volta, poi solo le tessere', () async {
    final b = await File('test/dati/edifici-prova.pmtiles').readAsBytes();
    final letture = <(int, int)>[];
    final p = await LettorePmtiles.daSorgente((i, n) async {
      letture.add((i, n));
      return Uint8List.sublistView(b, i, i + n);
    }, lunghezza: b.length);
    expect(utf8.decode((await p.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
    expect(utf8.decode((await p.tessera(14, 8838, 6145))!), 'e quella sotto');
    expect(await p.tessera(14, 8839, 6145), isNull);
    // La testa (tutto il pacchetto, che è piccolo) basta: nessun'altra lettura.
    expect(letture, [(0, b.length)]);
  });

  group('SorgenteHttp', () {
    late Uint8List b;
    setUp(() async => b = await File('test/dati/edifici-prova.pmtiles').readAsBytes());

    ({MockClient client, List<String> chieste, void Function() scade}) server() {
      final chieste = <String>[];
      var firma = 1;
      final client = MockClient((r) async {
        chieste.add('${r.url.host} ${r.headers['Range']}');
        if (r.url.host == 'github.com') {
          return http.Response('', 302, headers: {'location': 'https://oggetti.example/p?firma=$firma'});
        }
        if (r.url.queryParameters['firma'] != '$firma') return http.Response('scaduto', 403);
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(r.headers['Range']!)!;
        return http.Response.bytes(b.sublist(int.parse(m[1]!), int.parse(m[2]!) + 1), 206);
      });
      return (client: client, chieste: chieste, scade: () => firma++);
    }

    test('il rinvio si chiede una volta, poi i pezzi vanno diritti', () async {
      final s = server();
      var contati = 0;
      final h = SorgenteHttp(
        s.client,
        Uri.parse('https://github.com/x/y/releases/download/edifici/p.pmtiles'),
        letti: (n) => contati += n,
      );
      expect(await h.leggi(0, 7), utf8.encode('PMTiles'));
      expect(await h.leggi(10, 5), b.sublist(10, 15));
      expect(s.chieste, ['github.com bytes=0-6', 'oggetti.example bytes=0-6', 'oggetti.example bytes=10-14']);
      expect(contati, 12);
    });

    test('scaduta la firma, si richiede il rinvio', () async {
      final s = server();
      final h = SorgenteHttp(s.client, Uri.parse('https://github.com/x/y/releases/download/edifici/p.pmtiles'));
      await h.leggi(0, 7);
      s.scade();
      expect(await h.leggi(10, 5), b.sublist(10, 15));
      expect(s.chieste.where((c) => c.startsWith('github.com')).length, 2);
    });
  });
}
