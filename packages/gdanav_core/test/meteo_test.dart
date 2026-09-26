import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Una risposta di locationforecast 2.0 `compact`, ridotta: tre ore.
Map<String, Object?> _risposta(DateTime da, {double temperatura = 12, String simbolo = 'rain'}) => {
  'properties': {
    'timeseries': [
      for (var h = 0; h < 3; h++)
        {
          'time': da.add(Duration(hours: h)).toIso8601String(),
          'data': {
            'instant': {
              'details': {'air_temperature': temperatura + h, 'wind_speed': 5.0, 'wind_from_direction': 0.0},
            },
            'next_1_hours': {
              'summary': {'symbol_code': simbolo},
              'details': {'precipitation_amount': 1.2},
            },
          },
        },
    ],
  },
};

void main() {
  final ora = DateTime.utc(2026, 9, 25, 8);

  test('legge il formato compact di MET Norway', () {
    final p = MeteoMetNorway.leggi(_risposta(ora));
    expect(p, hasLength(3));
    expect(p.first.temperaturaC, 12);
    expect(p.first.ventoMs, 5);
    expect(p.first.pioggiaMm, 1.2);
    expect(p.first.cielo, Cielo.pioggia);
  });

  test('il cielo dai codici di MET Norway', () {
    expect(Cielo.da('clearsky_day'), Cielo.sereno);
    expect(Cielo.da('fair_night'), Cielo.poco);
    expect(Cielo.da('partlycloudy_day'), Cielo.poco);
    expect(Cielo.da('cloudy'), Cielo.nuvoloso);
    expect(Cielo.da('lightrainshowers_day'), Cielo.pioggia);
    expect(Cielo.da('heavysnow'), Cielo.neve);
    expect(Cielo.da('rainandthunder'), Cielo.temporale);
    expect(Cielo.da('fog'), Cielo.nebbia);
  });

  test('vento contro: da dove soffia rispetto a dove si va', () {
    final p = Previsione(ora: ora, temperaturaC: 10, ventoMs: 6, ventoDaGradi: 0);
    // Si va verso nord, il vento viene da nord: tutto contro.
    expect(p.ventoControMs(0), closeTo(6, 0.01));
    // Verso sud: tutto a favore.
    expect(p.ventoControMs(180), closeTo(-6, 0.01));
    // Di lato: niente.
    expect(p.ventoControMs(90), closeTo(0, 0.01));
  });

  test('chiede con User-Agent e due decimali, e tiene in cache', () async {
    final chieste = <Uri>[];
    final client = MockClient((r) async {
      chieste.add(r.url);
      expect(r.headers['user-agent'], contains('gdanav'));
      return http.Response(jsonEncode(_risposta(ora)), 200);
    });
    final m = MeteoMetNorway(client: client, orologio: () => ora);
    await m.previsioni(const Punto(45.46421, 9.18951));
    await m.previsioni(const Punto(45.4631, 9.1911));
    expect(chieste, hasLength(1));
    expect(chieste.single.queryParameters, {'lat': '45.46', 'lon': '9.19'});
  });

  test('lungo il viaggio: punti a distanze uguali, ognuno alla sua ora', () async {
    // Napoli → Milano in linea, circa 660 km: sette punti al massimo cinque.
    final punti = [const Punto(40.85, 14.27), const Punto(43.0, 12.0), const Punto(45.46, 9.19)];
    final richieste = <Punto>[];
    final fonte = _Finta((p) {
      richieste.add(p);
      // Più a nord, più freddo.
      return MeteoMetNorway.leggi(_risposta(ora, temperatura: 60 - p.lat));
    });
    final m = await MeteoViaggio.lungo(fonte, punti, partenza: ora, durata: const Duration(hours: 2));
    expect(m.tappe, hasLength(5));
    expect(m.tappe.first.km, 0);
    expect(m.arrivo!.punto.lat, closeTo(45.46, 0.001));
    // L'arrivo si prende alla sua ora: due ore dopo, cioè la terza previsione.
    expect(m.arrivo!.quando, ora.add(const Duration(hours: 2)));
    expect(m.arrivo!.previsione.temperaturaC, closeTo(60 - 45.46 + 2, 0.01));
    expect(m.temperaturaMediaC!, inInclusiveRange(m.arrivo!.previsione.temperaturaC, 60 - 40.85 + 2));
    expect(m.pioggia, isTrue);
    // Si va verso nord-ovest col vento da nord: un po' contro.
    expect(m.ventoControMedioMs!, greaterThan(0));
  });

  test('un punto che non risponde si salta; nessuno, meteo vuoto', () async {
    final punti = [const Punto(45.0, 9.0), const Punto(45.5, 9.0)];
    final m = await MeteoViaggio.lungo(
      _Finta((p) => p.lat > 45.2 ? throw Exception('giù') : MeteoMetNorway.leggi(_risposta(ora))),
      punti,
      partenza: ora,
      durata: const Duration(minutes: 40),
    );
    expect(m.tappe, hasLength(1));
    final nessuno = await MeteoViaggio.lungo(
      _Finta((_) => throw Exception('giù')),
      punti,
      partenza: ora,
      durata: const Duration(minutes: 40),
    );
    expect(nessuno.vuoto, isTrue);
    expect(nessuno.temperaturaMediaC, isNull);
  });

  test('previsioni troppo lontane nel tempo non valgono', () {
    final p = MeteoMetNorway.leggi(_risposta(ora));
    expect(
      MeteoViaggio.piuVicina(p, ora.add(const Duration(hours: 1, minutes: 20)))!.ora,
      ora.add(const Duration(hours: 1)),
    );
    expect(MeteoViaggio.piuVicina(p, ora.add(const Duration(hours: 6))), isNull);
  });
}

class _Finta implements FonteMeteo {
  _Finta(this.f);
  final List<Previsione> Function(Punto) f;

  @override
  Future<List<Previsione>> previsioni(Punto p) async => f(p);
}
