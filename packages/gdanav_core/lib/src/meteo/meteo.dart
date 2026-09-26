import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo/geo.dart';

/// Il tempo che fa (o farà) in un punto, a un'ora.
class Previsione {
  const Previsione({
    required this.ora,
    required this.temperaturaC,
    this.ventoMs = 0,
    this.ventoDaGradi = 0,
    this.pioggiaMm = 0,
    this.simbolo = '',
  });

  final DateTime ora;
  final double temperaturaC;
  final double ventoMs;

  /// Da dove soffia, in gradi (0 = da nord), come nei bollettini.
  final double ventoDaGradi;

  /// Nell'ora successiva.
  final double pioggiaMm;

  /// Il codice di MET Norway: `clearsky_day`, `rain`, `lightsnowshowers_night`…
  final String simbolo;

  Cielo get cielo => Cielo.da(simbolo);

  /// Il vento contro chi va in direzione [rotta] (gradi): positivo contro,
  /// negativo a favore.
  double ventoControMs(double rotta) => ventoMs * math.cos((ventoDaGradi - rotta) * math.pi / 180);

  Map<String, Object?> toJson() => {
    'ora': ora.toIso8601String(),
    'temperatura': temperaturaC,
    'vento': ventoMs,
    'vento_da': ventoDaGradi,
    'pioggia': pioggiaMm,
    'simbolo': simbolo,
  };
}

/// Il cielo, in poche famiglie: per l'icona e per dirlo a voce.
enum Cielo {
  sereno('sereno', '☀️'),
  poco('poco nuvoloso', '⛅'),
  nuvoloso('nuvoloso', '☁️'),
  nebbia('nebbia', '🌫️'),
  pioggia('pioggia', '🌧️'),
  temporale('temporale', '⛈️'),
  neve('neve', '❄️');

  const Cielo(this.nome, this.emoji);
  final String nome;
  final String emoji;

  static Cielo da(String simbolo) {
    final s = simbolo.toLowerCase();
    if (s.contains('thunder')) return temporale;
    if (s.contains('snow') || s.contains('sleet')) return neve;
    if (s.contains('rain')) return pioggia;
    if (s.contains('fog')) return nebbia;
    if (s.startsWith('cloudy')) return nuvoloso;
    if (s.startsWith('partlycloudy') || s.startsWith('fair')) return poco;
    return sereno;
  }
}

/// Da dove arrivano le previsioni.
abstract interface class FonteMeteo {
  /// Le prossime ore in [p], dalla più vicina.
  Future<List<Previsione>> previsioni(Punto p);
}

/// MET Norway (yr.no): gratuito anche per usi commerciali, con la citazione
/// «Dati meteo: MET Norway» (CC BY 4.0). Vuole un User-Agent che dica chi
/// siamo e coordinate con al massimo quattro decimali: se ne usano due
/// (un chilometro), così le richieste vicine vengono dalla cache.
class MeteoMetNorway implements FonteMeteo {
  MeteoMetNorway({http.Client? client, DateTime Function()? orologio})
    : _http = client ?? http.Client(),
      _ora = orologio ?? DateTime.now;

  static const citazione = 'Dati meteo: MET Norway';
  static const _agente = 'gdanav/1.0 github.com/danigio15/gdanav';

  final http.Client _http;
  final DateTime Function() _ora;
  final _cache = <String, (DateTime, List<Previsione>)>{};

  static const validita = Duration(minutes: 30);

  @override
  Future<List<Previsione>> previsioni(Punto p) async {
    final lat = p.lat.toStringAsFixed(2), lon = p.lon.toStringAsFixed(2);
    final chiave = '$lat,$lon';
    final gia = _cache[chiave];
    if (gia != null && _ora().difference(gia.$1) < validita) return gia.$2;
    final r = await _http.get(
      Uri.https('api.met.no', '/weatherapi/locationforecast/2.0/compact', {'lat': lat, 'lon': lon}),
      headers: {'user-agent': _agente},
    );
    if (r.statusCode != 200 && r.statusCode != 203) throw Exception('meteo: ${r.statusCode}');
    final elenco = leggi(jsonDecode(utf8.decode(r.bodyBytes)));
    _cache[chiave] = (_ora(), elenco);
    return elenco;
  }

  /// Il formato `compact` di locationforecast 2.0.
  static List<Previsione> leggi(Object? j) {
    final serie = (((j as Map?)?['properties'] as Map?)?['timeseries'] as List?) ?? const [];
    final elenco = <Previsione>[];
    for (final t in serie.whereType<Map>()) {
      final ora = DateTime.tryParse('${t['time']}');
      final dati = t['data'] as Map?;
      final adesso = ((dati?['instant'] as Map?)?['details'] as Map?) ?? const {};
      final temperatura = (adesso['air_temperature'] as num?)?.toDouble();
      if (ora == null || temperatura == null) continue;
      final prossima = (dati?['next_1_hours'] ?? dati?['next_6_hours']) as Map?;
      elenco.add(
        Previsione(
          ora: ora,
          temperaturaC: temperatura,
          ventoMs: (adesso['wind_speed'] as num?)?.toDouble() ?? 0,
          ventoDaGradi: (adesso['wind_from_direction'] as num?)?.toDouble() ?? 0,
          pioggiaMm: ((prossima?['details'] as Map?)?['precipitation_amount'] as num?)?.toDouble() ?? 0,
          simbolo: '${(prossima?['summary'] as Map?)?['symbol_code'] ?? ''}',
        ),
      );
    }
    return elenco;
  }

  void chiudi() => _http.close();
}

/// Il meteo in un punto del viaggio, all'ora in cui ci si passa.
class MeteoTappa {
  const MeteoTappa({
    required this.punto,
    required this.km,
    required this.quando,
    required this.previsione,
    this.rotta = 0,
  });

  final Punto punto;
  final double km;
  final DateTime quando;
  final Previsione previsione;

  /// La direzione di marcia lì, per il vento contro.
  final double rotta;

  double get ventoControMs => previsione.ventoControMs(rotta);
}

/// Il meteo lungo un viaggio: qualche punto dalla partenza all'arrivo, ognuno
/// all'ora in cui ci si arriva.
class MeteoViaggio {
  const MeteoViaggio(this.tappe);

  final List<MeteoTappa> tappe;

  bool get vuoto => tappe.isEmpty;
  MeteoTappa? get arrivo => tappe.lastOrNull;

  /// La media lungo la strada, pesata sui chilometri: quella che conta per
  /// il consumo.
  double? get temperaturaMediaC => _media((t) => t.previsione.temperaturaC);
  double? get ventoControMedioMs => _media((t) => t.ventoControMs);

  bool get pioggia => tappe.any((t) => t.previsione.pioggiaMm >= 0.3 || t.previsione.cielo == Cielo.pioggia);

  double? _media(double Function(MeteoTappa) f) {
    if (tappe.isEmpty) return null;
    if (tappe.length == 1) return f(tappe.first);
    var somma = 0.0, peso = 0.0;
    for (var i = 0; i < tappe.length; i++) {
      // Ogni punto vale per metà del tratto prima e metà di quello dopo.
      final prima = i == 0 ? 0.0 : (tappe[i].km - tappe[i - 1].km) / 2;
      final dopo = i == tappe.length - 1 ? 0.0 : (tappe[i + 1].km - tappe[i].km) / 2;
      final w = math.max(prima + dopo, 0.001);
      somma += f(tappe[i]) * w;
      peso += w;
    }
    return somma / peso;
  }

  /// La previsione più vicina all'ora [quando]; `null` se sono tutte a più
  /// di tre ore.
  static Previsione? piuVicina(List<Previsione> elenco, DateTime quando) {
    Previsione? migliore;
    Duration? scarto;
    for (final p in elenco) {
      final d = p.ora.difference(quando).abs();
      if (scarto == null || d < scarto) {
        migliore = p;
        scarto = d;
      }
    }
    return scarto != null && scarto <= const Duration(hours: 3) ? migliore : null;
  }

  /// Da [punti] del percorso lungo [lunghezzaM], partendo alle [partenza] e
  /// arrivando dopo [durata]: al massimo [quanti] punti a distanze uguali.
  /// I punti che non rispondono si saltano.
  static Future<MeteoViaggio> lungo(
    FonteMeteo fonte,
    List<Punto> punti, {
    required DateTime partenza,
    required Duration durata,
    int quanti = 5,
  }) async {
    if (punti.length < 2) return const MeteoViaggio([]);
    final linea = Linea(punti);
    final totale = linea.lunghezzaM;
    // Uno ogni 60 km circa, almeno partenza e arrivo.
    final n = math.max(2, math.min(quanti, (totale / 60000).ceil() + 1));
    final scelti = <(Punto, double, double)>[];
    var j = 1;
    for (var k = 0; k < n; k++) {
      final m = totale * k / (n - 1);
      while (j < punti.length - 1 && linea.cumulate[j] < m) {
        j++;
      }
      final a = punti[j - 1], b = punti[j];
      final tratto = linea.cumulate[j] - linea.cumulate[j - 1];
      final t = tratto <= 0 ? 0.0 : ((m - linea.cumulate[j - 1]) / tratto).clamp(0.0, 1.0);
      final p = Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      scelti.add((p, m, rottaGradi(a, b)));
    }
    final tappe = await Future.wait([
      for (final (p, m, rotta) in scelti)
        () async {
          final quando = partenza.add(Duration(seconds: totale <= 0 ? 0 : (durata.inSeconds * m / totale).round()));
          try {
            final prev = piuVicina(await fonte.previsioni(p), quando);
            if (prev == null) return null;
            return MeteoTappa(punto: p, km: m / 1000, quando: quando, previsione: prev, rotta: rotta);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    return MeteoViaggio(tappe.whereType<MeteoTappa>().toList());
  }
}
