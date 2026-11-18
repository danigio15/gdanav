import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/diagnosi_auto.dart';
import 'package:gdanav_app/stato/strade_osm.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/* ─── Le strade vere per il contromano, anche dopo giorni ─────────────────
 *
 * «Ancora sbagliato st'incrocio»: la correzione del contromano c'era, ma
 * l'indirizzo delle tessere si leggeva una volta sola e cambia a ogni
 * aggiornamento della mappa. Con l'app accesa da giorni ogni tessera
 * rispondeva «non c'è» e il navigatore restava senza strade. */

/// Un servizio di tessere finto: l'indice dice la versione di adesso, e solo
/// quella ha le tessere.
class _Servizio {
  var versione = 'v1';
  final chieste = <String>[];
  final indici = <int>[0];

  late final client = MockClient((r) async {
    final u = r.url.toString();
    chieste.add(u);
    if (u.endsWith('/planet')) {
      indici[0]++;
      return http.Response(
        jsonEncode({
          'tiles': ['https://tessere.prova/$versione/{z}/{x}/{y}.pbf'],
        }),
        200,
      );
    }
    if (u.contains('/$versione/')) return http.Response.bytes([1, 2, 3], 200);
    return http.Response('', 404);
  });
}

void main() {
  group('le tessere di OpenFreeMap', () {
    test('dopo un aggiornamento della mappa si rilegge l\'indirizzo e la tessera arriva', () async {
      final s = _Servizio();
      final fonte = TessereOpenFreeMap(client: s.client, indice: 'https://tessere.prova/planet');
      expect(await fonte(14, 1, 2), isNotNull);
      expect(s.indici[0], 1);
      // La mappa si aggiorna: la versione di prima non c'è più.
      s.versione = 'v2';
      final dopo = await fonte(14, 1, 3);
      expect(dopo, isNotNull, reason: 'si rilegge l\'indice e si riprova con la versione nuova');
      expect(dopo, Uint8List.fromList([1, 2, 3]));
      expect(s.indici[0], 2);
      // E poi si continua con quella, senza rileggere l'indice ogni volta.
      expect(await fonte(14, 1, 4), isNotNull);
      expect(s.indici[0], 2);
    });

    test('una tessera che non c\'è con l\'indirizzo giusto è una tessera vuota', () async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/planet')) {
          return http.Response(
            jsonEncode({
              'tiles': ['https://tessere.prova/v1/{z}/{x}/{y}.pbf'],
            }),
            200,
          );
        }
        return http.Response('', 404);
      });
      final fonte = TessereOpenFreeMap(client: client, indice: 'https://tessere.prova/planet');
      expect(await fonte(14, 1, 2), Uint8List(0));
    });

    test('senza rete: niente tessera (si riproverà)', () async {
      final client = MockClient((r) async => throw http.ClientException('niente rete'));
      final fonte = TessereOpenFreeMap(client: client, indice: 'https://tessere.prova/planet');
      expect(await fonte(14, 1, 2), isNull);
    });
  });

  group('le strade attorno al percorso', () {
    const punti = [Punto(42, 12), Punto(42.004, 12.004)];

    test('se una tessera non arriva non si risponde a metà: vuoto, e la volta dopo tutto', () async {
      var giro = 0;
      final chieste = <(int, int)>[];
      final strade = StradeOsm((z, x, y) async {
        chieste.add((x, y));
        // Al primo giro una tessera manca.
        if (giro == 0 && chieste.length == 1) return null;
        return Uint8List(0);
      });
      final tessere = tessereAttorno(punti, marginiM: 300).length;
      expect(tessere, greaterThan(1), reason: 'la prova vuole più tessere');
      expect(await strade.attorno(punti), isEmpty);
      giro = 1;
      final prima = chieste.length;
      await strade.attorno(punti);
      // Al secondo giro si chiede solo quella che mancava: le altre sono tenute.
      expect(chieste.length - prima, 1);
    });
  });

  group('il diario dei sensi unici', () {
    test('tiene le ultime righe, la più nuova in cima, con l\'ora', () {
      var minuto = 0;
      final d = DiarioSensi(quante: 3, ora: () => DateTime(2026, 1, 1, 8, minuto++, 5));
      for (final r in ['uno', 'due', 'tre', 'quattro']) {
        d.scrivi(r);
      }
      expect(d.voci, ['08:03:05 quattro', '08:02:05 tre', '08:01:05 due']);
    });

    testWidgets('nella diagnosi si legge cosa è successo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiarioDeiSensi(voci: ['08:00:00 contromano evitato a 1,2 km'])),
        ),
      );
      expect(find.text('I sensi unici'), findsOneWidget);
      expect(find.textContaining('contromano evitato'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiarioDeiSensi(voci: [])),
        ),
      );
      expect(find.textContaining('Ancora nessun controllo'), findsOneWidget);
    });
  });
}
