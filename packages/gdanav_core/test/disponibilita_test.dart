import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const area = Colonnina(
  id: 'osm-node-1',
  nome: 'Ionity Secchia Ovest',
  posizione: Punto(44.6, 10.9),
  connettori: [
    Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
    Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
    Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22),
  ],
);

void main() {
  test('TomTom: si ritrova la colonnina vicina e si leggono le prese libere e occupate', () async {
    final chiesti = <String>[];
    final client = MockClient((r) async {
      chiesti.add(r.url.path);
      expect(r.url.queryParameters['key'], 'chiave');
      if (r.url.path.contains('nearbySearch')) {
        return http.Response(
            jsonEncode({
              'results': [
                {
                  'position': {'lat': 44.6012, 'lon': 10.9},
                  'dataSources': {
                    'chargingAvailability': {'id': 'lontana'},
                  },
                },
                {
                  'position': {'lat': 44.6001, 'lon': 10.9},
                  'dataSources': {
                    'chargingAvailability': {'id': 'giusta'},
                  },
                },
              ],
            }),
            200);
      }
      expect(r.url.queryParameters['chargingAvailability'], 'giusta');
      return http.Response(
          jsonEncode({
            'chargingAvailability': 'giusta',
            'connectors': [
              {
                'type': 'IEC62196Type2CCS',
                'total': 4,
                'availability': {
                  'current': {'available': 1, 'occupied': 2, 'reserved': 0, 'unknown': 0, 'outOfService': 1},
                },
              },
            ],
          }),
          200);
    });
    final t = DisponibilitaTomTom('chiave', client: client, validita: Duration.zero);
    final c = await t.aggiorna(area);
    final d = c.disponibilitaPer({TipoConnettore.ccs2});
    expect((d.libere, d.occupate, d.guaste, d.totali), (1, 2, 1, 4));
    expect(c.potenzaPer({TipoConnettore.ccs2}), 350);
    // La Tipo 2, che TomTom non ha detto, resta.
    expect(c.connettori.where((x) => x.tipo == TipoConnettore.tipo2), hasLength(1));

    // La seconda volta l'id si ricorda: una richiesta sola.
    chiesti.clear();
    await t.aggiorna(area);
    expect(chiesti, hasLength(1));
  });

  test('TomTom: fra le colonnine vicine si sceglie quella con le stesse prese; col 429 si riprova', () async {
    var troppe = 1;
    final t = DisponibilitaTomTom(
      'chiave',
      client: MockClient((r) async {
        if (troppe-- > 0) return http.Response('', 429);
        if (r.url.path.contains('nearbySearch')) {
          Map<String, Object?> punto(String id, double lat, String presa) => {
                'position': {'lat': lat, 'lon': 10.9},
                'dataSources': {
                  'chargingAvailability': {'id': id},
                },
                'chargingPark': {
                  'connectors': [
                    {'connectorType': presa, 'ratedPowerKW': 22},
                  ],
                },
              };
          return http.Response(
            jsonEncode({
              'results': [punto('lente', 44.6, 'Chademo'), punto('rapide', 44.6008, 'IEC62196Type2CCS')],
            }),
            200,
          );
        }
        expect(r.url.queryParameters['chargingAvailability'], 'rapide');
        return http.Response(
          jsonEncode({
            'connectors': [
              {
                'type': 'IEC62196Type2CCS',
                'availability': {
                  'current': {'available': 2, 'occupied': 0},
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    final c = await t.aggiorna(area);
    expect(c.disponibilitaPer({TipoConnettore.ccs2}).libere, 2);
  });

  test('TomTom non la conosce: resta com\'era', () async {
    final t =
        DisponibilitaTomTom('chiave', client: MockClient((_) async => http.Response(jsonEncode({'results': []}), 200)));
    expect(identical(await t.aggiorna(area), area), isTrue);
  });

  test('il viaggio: se la sosta scelta è piena, se ne sceglie un\'altra', () async {
    // Una strada dritta verso nord, colonnine ogni 60 km.
    final punti = [for (var i = 0; i <= 500; i++) Punto(42 + i * 0.009, 12)];
    final linea = Linea(punti);
    final percorso = PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 120),
      ],
      manovre: const [],
    );
    Colonnina colonnina(int km) => Colonnina(
          id: 'c$km',
          nome: 'Area $km',
          posizione: Punto(42 + km * 0.009, 12.002),
          connettori: const [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150)],
        );
    final tutte = [for (var km = 60; km < 500; km += 60) colonnina(km)];
    final senza = await PianificatoreViaggio(
      percorsi: (_) async => percorso,
      colonnine: _Fisse(tutte),
      profilo: ProfiloVeicolo.esempio,
    ).pianifica(partenza: punti.first, arrivo: punti.last, batteria: 80);
    final prima = senza.piano!.soste.first.colonnina.id;

    final disponibilita = _TuttePieneTranne(prima);
    final con = await PianificatoreViaggio(
      percorsi: (_) async => percorso,
      colonnine: _Fisse(tutte),
      profilo: ProfiloVeicolo.esempio,
      disponibilita: disponibilita,
    ).pianifica(partenza: punti.first, arrivo: punti.last, batteria: 80);
    expect(disponibilita.chieste, contains(prima));
    expect(con.piano!.soste.map((s) => s.colonnina.id), isNot(contains(prima)));
  });

  /* ── «Stato non comunicato» su tutte le colonnine ────────────────────────
   *
   * Dal cruscotto di TomTom: Search API 2 500 / 2 500, quota finita, e il
   * 12,9% di tutte le richieste rifiutate. Lo stato di una colonnina costa
   * due richieste di ricerca: quindici colonnine sullo schermo sono trenta
   * richieste, e duemilacinquecento al mese finiscono in giorni. Da lì in poi
   * ogni richiesta è un rifiuto che costa tempo, batteria e dati, e lascia la
   * colonnina «sconosciuta» esattamente come se non l'avessimo chiesta. */
  group('quando il fornitore dice di no per la quota', () {
    // Un finto orologio, per non aspettare sei ore dentro una prova.
    var quando = DateTime(2026, 9, 28, 10);

    DisponibilitaTomTom conRisposta(int codice, List<Uri> chiesti) => DisponibilitaTomTom(
          'chiave',
          validita: Duration.zero,
          adesso: () => quando,
          client: MockClient((r) async {
            chiesti.add(r.url);
            return http.Response('', codice);
          }),
        );

    test('col 403 si smette di chiedere, e la colonnina resta com\'era', () async {
      final chiesti = <Uri>[];
      final t = conRisposta(403, chiesti);
      expect(t.inPausa, isFalse);
      await t.aggiorna(area).catchError((Object _) => area);
      expect(t.inPausa, isTrue, reason: 'il no si ricorda');
      final quante = chiesti.length;
      for (var i = 0; i < 20; i++) {
        expect(await t.aggiorna(area), same(area));
      }
      expect(chiesti, hasLength(quante), reason: 'venti colonnine, zero richieste in piu\'');
    });

    test('dopo la pausa si riprova: la quota e\' mensile', () async {
      final t = conRisposta(403, <Uri>[]);
      await t.aggiorna(area).catchError((Object _) => area);
      expect(t.inPausa, isTrue);
      quando = quando.add(const Duration(hours: 7));
      expect(t.inPausa, isFalse, reason: 'passate sei ore si torna a chiedere');
    });

    test('anche il 429 che non passa coi tentativi ferma tutto', () async {
      final t = conRisposta(429, <Uri>[]);
      await t.aggiorna(area).catchError((Object _) => area);
      expect(t.inPausa, isTrue);
    });

    test('un errore qualunque no: quello puo\' essere la rete', () async {
      final t = conRisposta(500, <Uri>[]);
      await t.aggiorna(area).catchError((Object _) => area);
      expect(t.inPausa, isFalse);
    });
  });
}

class _Fisse implements FonteColonnine {
  _Fisse(this.c);
  final List<Colonnina> c;
  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async => c;
}

/// La colonnina [guasta] ha tutte le prese fuori servizio; le altre libere.
class _TuttePieneTranne implements FonteDisponibilita {
  _TuttePieneTranne(this.guasta);
  final String guasta;
  final chieste = <String>[];

  @override
  Future<Colonnina> aggiorna(Colonnina c) async {
    chieste.add(c.id);
    final s = c.id == guasta ? StatoPresa.fuoriServizio : StatoPresa.disponibile;
    return Colonnina(
      id: c.id,
      nome: c.nome,
      posizione: c.posizione,
      connettori: [for (final p in c.connettori) p.conStato(s)],
    );
  }
}
