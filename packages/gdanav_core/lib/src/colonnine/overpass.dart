import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'colonnina.dart';

/// Le colonnine di OpenStreetMap, attraverso Overpass: gratis e senza
/// chiave. Meno dettagli di Open Charge Map (lo stato non c'è mai), ma le
/// prese e le potenze sì, quando i mappatori le hanno scritte. I dati vanno
/// citati: «© OpenStreetMap contributors» (ODbL).
class ClienteOverpass implements FonteColonnine {
  ClienteOverpass({
    http.Client? client,
    List<Uri>? server,
    this.scaglione = const Duration(seconds: 12),
    this.attesa = const Duration(seconds: 50),
  }) : _http = client ?? http.Client(),
       server =
           server ??
           [
             Uri.parse('https://overpass-api.de/api/interpreter'),
             Uri.parse('https://overpass.private.coffee/api/interpreter'),
             Uri.parse('https://overpass.kumi.systems/api/interpreter'),
           ];

  /// Si chiede al primo; se dopo [scaglione] non ha risposto (dal telefono,
  /// con l'indirizzo condiviso dell'operatore, capita che ci metta in coda)
  /// si chiede anche al successivo, e vince chi risponde prima. Se uno
  /// sbaglia, si passa subito al prossimo.
  final List<Uri> server;
  final Duration scaglione;

  /// Quanto si aspetta ciascun server.
  final Duration attesa;
  final http.Client _http;

  /// Le reti di ricarica rapida: le loro colonnine valgono anche se i
  /// mappatori non hanno scritto le prese.
  static const retiRapide =
      'Ionity|Tesla|Free To X|Electra|Fastned|Ewiva|Atlante|Allego|Plenitude|Be Charge|Enel X|A2A|Neogy|Zunder|Powerdot|Duferco';

  /// La richiesta: il percorso a riquadri di una cinquantina di chilometri
  /// (Overpass li cerca in un attimo; la linea intera lo manda in tempo
  /// scaduto), solo le colonnine rapide. La distanza vera dalla strada la
  /// misura poi colonnineSulPercorso.
  static String richiesta(List<Punto> percorso, double distanzaKm) {
    final margine = distanzaKm / 111.0 + 0.01;
    final riquadri = <String>[];
    final pezzi = semplifica(percorso, 1000);
    const passo = 50; // punti a 1 km: riquadri da ~50 km
    for (var i = 0; i < pezzi.length; i += passo) {
      final tratto = pezzi.sublist(i, math.min(i + passo + 1, pezzi.length));
      final lat = tratto.map((p) => p.lat), lon = tratto.map((p) => p.lon);
      final coseno = math.cos(tratto.first.lat * math.pi / 180).abs().clamp(0.2, 1.0);
      riquadri.add(
        [
          (lat.reduce(math.min) - margine).toStringAsFixed(4),
          (lon.reduce(math.min) - margine / coseno).toStringAsFixed(4),
          (lat.reduce(math.max) + margine).toStringAsFixed(4),
          (lon.reduce(math.max) + margine / coseno).toStringAsFixed(4),
        ].join(','),
      );
    }
    const rapide = '[~"^socket:(type2_combo|chademo|tesla_supercharger.*)\$"~"."]';
    final filtri = [
      '["amenity"="charging_station"]$rapide',
      '["amenity"="charging_station"]["operator"~"$retiRapide",i]',
      '["amenity"="charging_station"]["brand"~"$retiRapide",i]',
    ];
    final corpo = [
      for (final r in riquadri)
        for (final f in filtri) 'nwr$f($r);',
    ].join();
    return '[out:json][timeout:60];($corpo);out center tags;';
  }

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) {
    final corpo = {'data': richiesta(percorso, distanzaKm)};
    final esito = Completer<List<Colonnina>>();
    final errori = <String>[];
    var prossimo = 0;
    Timer? sveglia;

    void parti() {
      sveglia?.cancel();
      if (esito.isCompleted || prossimo >= server.length) return;
      final s = server[prossimo++];
      sveglia = Timer(scaglione, parti);
      _chiedi(s, corpo).then(
        (c) {
          if (esito.isCompleted) return;
          sveglia?.cancel();
          esito.complete(c);
        },
        onError: (Object e) {
          errori.add('${s.host}: $e');
          if (esito.isCompleted) return;
          if (errori.length == server.length) {
            sveglia?.cancel();
            esito.completeError(Exception('colonnine: ${errori.join('; ')}'));
          } else {
            parti();
          }
        },
      );
    }

    parti();
    return esito.future;
  }

  Future<List<Colonnina>> _chiedi(Uri s, Map<String, String> corpo) async {
    final r = await _http
        .post(s, body: corpo, headers: {'user-agent': 'gdanav (github.com/danigio15/gdanav)'})
        .timeout(attesa);
    if (r.statusCode != 200) throw 'Overpass: ${r.statusCode}';
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    // In tempo scaduto Overpass risponde 200 con un avviso e niente dati:
    // non è «non ci sono colonnine».
    final avviso = json['remark'];
    if (avviso is String && avviso.contains('error')) throw 'Overpass: $avviso';
    return leggi(json);
  }

  static List<Colonnina> leggi(Map<String, Object?> json) => [
    for (final e in ((json['elements'] as List?) ?? const []).cast<Map<String, Object?>>())
      if (_colonnina(e) case final c?) c,
  ];

  static Colonnina? _colonnina(Map<String, Object?> e) {
    final tag = ((e['tags'] as Map?) ?? const {}).cast<String, Object?>();
    // Solo per le auto: niente bici né monopattini.
    if (tag['motorcar'] == 'no' || tag['bicycle'] == 'yes' && tag['motorcar'] == null) return null;
    if (tag['access'] == 'private' || tag['access'] == 'no') return null;
    final centro = (e['center'] as Map?)?.cast<String, Object?>();
    final lat = ((e['lat'] ?? centro?['lat']) as num?)?.toDouble();
    final lon = ((e['lon'] ?? centro?['lon']) as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final connettori = <Connettore>[
      ..._prese(tag, 'type2_combo', TipoConnettore.ccs2, 50),
      ..._prese(tag, 'chademo', TipoConnettore.chademo, 50),
      ..._prese(tag, 'type2', TipoConnettore.tipo2, 22),
      ..._prese(tag, 'type2_cable', TipoConnettore.tipo2, 22),
      ..._prese(tag, 'tesla_supercharger_ccs', TipoConnettore.ccs2, 150),
    ];
    final operatore = (tag['operator'] ?? tag['brand'] ?? tag['network']) as String?;
    // Senza prese scritte: una rapida CCS se è di una rete rapida, altrimenti
    // una Tipo 2, la più comune; con la potenza se c'è.
    if (connettori.isEmpty) {
      final rapida = RegExp(retiRapide, caseSensitive: false).hasMatch('${tag['operator']} ${tag['brand']}');
      connettori.add(
        Connettore(
          tipo: rapida ? TipoConnettore.ccs2 : TipoConnettore.tipo2,
          potenzaKw: _kw(tag['charging_station:output']) ?? (rapida ? 150 : 22),
        ),
      );
    }
    return Colonnina(
      id: 'osm-${e['type']}-${e['id']}',
      nome: (tag['name'] as String?) ?? operatore ?? 'Colonnina',
      operatore: operatore,
      posizione: Punto(lat, lon),
      connettori: connettori,
      fonte: 'osm',
    );
  }

  static List<Connettore> _prese(Map<String, Object?> tag, String chiave, TipoConnettore tipo, double potenza) {
    final valore = tag['socket:$chiave'];
    if (valore == null || valore == 'no' || valore == '0') return const [];
    final quante = int.tryParse('$valore') ?? 1;
    final kw = _kw(tag['socket:$chiave:output']) ?? potenza;
    return [for (var i = 0; i < quante.clamp(1, 20); i++) Connettore(tipo: tipo, potenzaKw: kw)];
  }

  /// «150 kW», «22kW», «50000 W», «11 kVA», «50;150 kW» (il più alto).
  static double? _kw(Object? testo) {
    if (testo is! String) return null;
    double? massimo;
    for (final m in RegExp(r'(\d+(?:[.,]\d+)?)\s*(kw|kva|w)?', caseSensitive: false).allMatches(testo)) {
      var v = double.parse(m.group(1)!.replaceAll(',', '.'));
      final unita = (m.group(2) ?? 'kw').toLowerCase();
      if (unita == 'w') v /= 1000;
      if (v > 0 && v <= 1000 && (massimo == null || v > massimo)) massimo = v;
    }
    return massimo;
  }
}

/// Più fonti in fila: la prima che risponde vince (Open Charge Map con la
/// chiave, poi OpenStreetMap).
class FonteColonnineConRiserva implements FonteColonnine {
  const FonteColonnineConRiserva(this.fonti);

  final List<FonteColonnine> fonti;

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    Object? ultimo;
    for (final f in fonti) {
      try {
        return await f.lungo(percorso, distanzaKm: distanzaKm);
      } catch (e) {
        ultimo = e;
      }
    }
    throw Exception('colonnine: $ultimo');
  }
}
