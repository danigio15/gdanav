import 'dart:async';
import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// [m] metri a nord di Roma.
Punto aNord(double m) => Punto(41.9 + m / 111195, 12.5);

void main() {
  group('il limite senza navigazione', () {
    late List<List<Punto>> domande;
    late Completer<int?> risposta;
    late int cambi;
    late LimiteDellaStrada l;
    var ora = DateTime(2026, 10, 29, 8);

    setUp(() {
      domande = [];
      cambi = 0;
      ora = DateTime(2026, 10, 29, 8);
      risposta = Completer<int?>();
      l = LimiteDellaStrada((t) {
        domande.add(t);
        return risposta.future;
      }, cambiato: () => cambi++);
    });

    /// Si va a nord a [v] m/s per [secondi], una posizione al secondo.
    double fatti = 0;
    void vai(int secondi, {double v = 16}) {
      for (var i = 0; i < secondi; i++) {
        fatti += v;
        ora = ora.add(const Duration(seconds: 1));
        l.posizione(aNord(fatti), velocitaMs: v, alle: ora);
      }
    }

    setUp(() => fatti = 0);

    test('chiede andando, con qualche posizione, e mostra il limite dell\'ultima strada', () async {
      vai(2);
      expect(domande, isEmpty, reason: 'due posizioni non dicono la strada');
      vai(1);
      expect(domande, hasLength(1));
      expect(domande.single, hasLength(3));
      risposta.complete(50);
      await Future<void>.delayed(Duration.zero);
      expect(l.limiteKmh, 50);
      expect(cambi, 1);
    });

    test('non chiede di continuo: ogni tanti metri, e mai due volte in pochi secondi', () async {
      vai(3);
      risposta.complete(50);
      await Future<void>.delayed(Duration.zero);
      risposta = Completer<int?>();
      // 16 m/s: 250 m in 16 s.
      vai(15);
      expect(domande, hasLength(1));
      vai(1);
      expect(domande, hasLength(2));
      // In autostrada 250 m passano in 7 s: si aspetta lo stesso 10 s.
      risposta.complete(130);
      await Future<void>.delayed(Duration.zero);
      risposta = Completer<int?>();
      vai(8, v: 36);
      expect(domande, hasLength(2));
      vai(2, v: 36);
      expect(domande, hasLength(3));
    });

    test('da fermi non chiede, e il limite resta (il semaforo)', () async {
      vai(3);
      risposta.complete(50);
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 60; i++) {
        ora = ora.add(const Duration(seconds: 1));
        l.posizione(aNord(fatti), velocitaMs: 0, alle: ora);
      }
      expect(domande, hasLength(1));
      expect(l.limiteKmh, 50);
    });

    test('senza risposte nuove, dopo un tratto lungo il cartello sparisce', () async {
      vai(3);
      risposta.complete(50);
      await Future<void>.delayed(Duration.zero);
      // Il server non risponde più.
      risposta = Completer<int?>();
      vai(110);
      expect(l.limiteKmh, isNull);
      expect(cambi, 2);
    });

    test('un errore non toglie il limite, e si riprova dopo un poco', () async {
      vai(3);
      risposta.complete(50);
      await Future<void>.delayed(Duration.zero);
      risposta = Completer<int?>()..completeError(Exception('rete'));
      risposta.future.ignore();
      vai(19);
      await Future<void>.delayed(Duration.zero);
      expect(domande, hasLength(2));
      expect(l.limiteKmh, 50);
      risposta = Completer<int?>();
      vai(20);
      expect(domande, hasLength(2), reason: 'dopo un errore si aspetta mezzo minuto');
      vai(12);
      expect(domande, hasLength(3));
    });

    test('in guida no: i limiti li ha il percorso', () {
      var guida = true;
      l = LimiteDellaStrada((t) {
        domande.add(t);
        return risposta.future;
      }, attivo: () => !guida);
      vai(20);
      expect(domande, isEmpty);
      guida = false;
      vai(1);
      expect(domande, hasLength(1));
    });
  });

  group('Valhalla, il limite qui', () {
    test('chiede le ultime posizioni appoggiate alle strade, e prende l\'ultima strada', () async {
      Map<String, Object?>? corpo;
      final client = MockClient((r) async {
        expect(r.url.path, '/trace_attributes');
        corpo = jsonDecode(r.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'edges': [
              {'speed_limit': 90},
              {'speed_limit': 50},
            ],
          }),
          200,
        );
      });
      final v = ClienteValhalla(Uri.parse('https://valhalla.example/'), client: client);
      expect(await v.limiteQui([aNord(0), aNord(20), aNord(40)]), 50);
      expect(corpo!['shape_match'], 'map_snap');
      expect(corpo!['shape'], hasLength(3));
    });

    test('l\'ultima strada senza limite noto: nessun cartello, non quello di prima', () {
      expect(
        ClienteValhalla.limiteInFondo({
          'edges': [
            {'speed_limit': 90},
            {'speed_limit': 0},
          ],
        }),
        isNull,
      );
      expect(
        ClienteValhalla.limiteInFondo({
          'edges': [
            {'speed_limit': 90},
            <String, Object?>{},
          ],
        }),
        isNull,
      );
      expect(ClienteValhalla.limiteInFondo({'edges': []}), isNull);
    });

    test('il server che non risponde bene: nessun limite', () async {
      final v = ClienteValhalla(
        Uri.parse('https://valhalla.example/'),
        client: MockClient((r) async => http.Response('no', 500)),
      );
      expect(await v.limiteQui([aNord(0), aNord(20)]), isNull);
    });
  });
}
