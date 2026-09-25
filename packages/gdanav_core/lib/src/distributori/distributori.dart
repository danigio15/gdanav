import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';

/// Cosa si trova alla pompa.
enum Carburante {
  benzina('Benzina'),
  diesel('Diesel'),
  gpl('GPL'),
  metano('Metano');

  const Carburante(this.nome);
  final String nome;
}

/// Un distributore di carburante, da OpenStreetMap.
class Distributore {
  const Distributore({
    required this.id,
    required this.nome,
    required this.posizione,
    this.marca,
    this.carburanti = const {},
    this.orari,
    this.self,
  });

  final String id;
  final String nome;
  final Punto posizione;

  /// Eni, Q8, IP, Tamoil…, se si sa.
  final String? marca;

  /// I carburanti scritti su OpenStreetMap; vuoto se non li ha scritti nessuno.
  final Set<Carburante> carburanti;

  /// L'orario come su OpenStreetMap («24/7», «Mo-Sa 07:00-20:00»…).
  final String? orari;

  /// Self service: sì, no o non si sa.
  final bool? self;

  bool get sempreAperto => orari == '24/7';
}

/// I distributori intorno a un punto, da Overpass (OpenStreetMap). Senza
/// chiavi né costi. Si prova un server dopo l'altro.
class ClienteDistributori {
  ClienteDistributori({http.Client? client, List<Uri>? server, this.attesa = const Duration(seconds: 25)})
      : _http = client ?? http.Client(),
        server = server ??
            [
              Uri.parse('https://overpass-api.de/api/interpreter'),
              Uri.parse('https://overpass.private.coffee/api/interpreter'),
              Uri.parse('https://overpass.kumi.systems/api/interpreter'),
            ];

  final http.Client _http;
  final List<Uri> server;
  final Duration attesa;

  static String richiesta(Punto qui, double km) =>
      '[out:json][timeout:25];nwr["amenity"="fuel"](around:${(km * 1000).round()},'
      '${qui.lat.toStringAsFixed(5)},${qui.lon.toStringAsFixed(5)});out center tags;';

  /// Dal più vicino; al massimo [quanti].
  Future<List<Distributore>> vicino(Punto qui, {double km = 5, int quanti = 20}) async {
    final errori = <String>[];
    for (final s in server) {
      try {
        final r = await _http.post(
          s,
          body: {'data': richiesta(qui, km)},
          headers: {'user-agent': 'gdanav (github.com/danigio15/gdanav)'},
        ).timeout(attesa);
        if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
        final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
        final avviso = json['remark'];
        if (avviso is String && avviso.contains('error')) throw avviso;
        final tutti = leggi(json)..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
        return tutti.take(quanti).toList();
      } catch (e) {
        errori.add('${s.host}: $e');
      }
    }
    throw Exception('distributori: ${errori.join('; ')}');
  }

  static List<Distributore> leggi(Map<String, Object?> json) => [
        for (final e in ((json['elements'] as List?) ?? const []).cast<Map<String, Object?>>())
          if (_distributore(e) case final d?) d,
      ];

  static Distributore? _distributore(Map<String, Object?> e) {
    final tag = ((e['tags'] as Map?) ?? const {}).cast<String, Object?>();
    if (tag['access'] == 'private' || tag['access'] == 'no') return null;
    // Solo barche o solo camion: non per l'auto.
    if (tag['boat'] == 'yes' && tag['motorcar'] == null) return null;
    if (tag['hgv'] == 'only') return null;
    final centro = (e['center'] as Map?)?.cast<String, Object?>();
    final lat = ((e['lat'] ?? centro?['lat']) as num?)?.toDouble();
    final lon = ((e['lon'] ?? centro?['lon']) as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    bool si(String chiave) => tag[chiave] == 'yes';
    final carburanti = {
      if (si('fuel:octane_95') || si('fuel:octane_98') || si('fuel:octane_100') || si('fuel:e10') || si('fuel:e5'))
        Carburante.benzina,
      if (si('fuel:diesel') || si('fuel:GTL_diesel') || si('fuel:HVO100')) Carburante.diesel,
      if (si('fuel:lpg')) Carburante.gpl,
      if (si('fuel:cng') || si('fuel:lng') || si('fuel:biogas')) Carburante.metano,
    };
    final marca = (tag['brand'] ?? tag['operator']) as String?;
    final self = switch (tag['self_service']) {
      'yes' => true,
      'no' => false,
      _ => null,
    };
    return Distributore(
      id: 'osm-${e['type']}-${e['id']}',
      nome: (tag['name'] as String?) ?? marca ?? 'Distributore',
      marca: marca,
      posizione: Punto(lat, lon),
      carburanti: carburanti,
      orari: tag['opening_hours'] as String?,
      self: self,
    );
  }
}
