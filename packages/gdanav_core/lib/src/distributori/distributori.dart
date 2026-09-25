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

/// Un prezzo alla pompa.
class Prezzo {
  const Prezzo({required this.carburante, required this.euro, required this.self, this.nome = ''});

  final Carburante carburante;

  /// Euro al litro (al kg per il metano).
  final double euro;

  /// Self service o servito.
  final bool self;

  /// Come lo chiama il distributore («Benzina», «Blue Diesel»…).
  final String nome;
}

/// Un distributore di carburante: da OpenStreetMap, o in Italia
/// dall'Osservaprezzi del Ministero con i prezzi.
class Distributore {
  const Distributore({
    required this.id,
    required this.nome,
    required this.posizione,
    this.marca,
    this.carburanti = const {},
    this.orari,
    this.self,
    this.prezzi = const [],
    this.aggiornato,
    this.indirizzo,
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

  /// I prezzi comunicati dal gestore; vuoto se non si sanno.
  final List<Prezzo> prezzi;

  /// Quando il gestore li ha comunicati l'ultima volta.
  final DateTime? aggiornato;
  final String? indirizzo;

  bool get sempreAperto => orari == '24/7';

  /// Il prezzo più basso di [c] (di solito il self), se c'è.
  Prezzo? prezzoDi(Carburante c) {
    Prezzo? migliore;
    for (final p in prezzi) {
      if (p.carburante == c && (migliore == null || p.euro < migliore.euro)) migliore = p;
    }
    return migliore;
  }
}

/// Da dove arrivano i distributori.
abstract interface class FonteDistributori {
  /// Dal più vicino, entro [km]; al massimo [quanti].
  Future<List<Distributore>> vicino(Punto qui, {double km = 5, int quanti = 20});
}

/// I distributori intorno a un punto, da Overpass (OpenStreetMap). Senza
/// chiavi né costi. Si prova un server dopo l'altro.
class ClienteDistributori implements FonteDistributori {
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

  @override
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

/// I prezzi dall'Osservaprezzi carburanti del Ministero (MIMIT): i gestori
/// devono comunicarli a ogni cambio. Pubblico, senza chiave; solo in Italia.
class ClientePrezziMimit implements FonteDistributori {
  ClientePrezziMimit({http.Client? client, Uri? indirizzo, this.attesa = const Duration(seconds: 15)})
      : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://carburanti.mise.gov.it/ospzApi/search/zone');

  final http.Client _http;
  final Uri indirizzo;
  final Duration attesa;

  /// Il riquadro dell'Italia (con San Marino e il Vaticano).
  static bool inItalia(Punto p) => p.lat > 35.2 && p.lat < 47.2 && p.lon > 6.5 && p.lon < 18.7;

  @override
  Future<List<Distributore>> vicino(Punto qui, {double km = 5, int quanti = 20}) async {
    final r = await _http
        .post(
          indirizzo,
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
            'user-agent': 'gdanav (github.com/danigio15/gdanav)',
          },
          body: jsonEncode({
            'points': [
              {'lat': qui.lat, 'lng': qui.lon},
            ],
            // Il Ministero non va oltre 10 km.
            'radius': km.clamp(1, 10),
            'fuelType': '0-x',
            'priceOrder': 'asc',
          }),
        )
        .timeout(attesa);
    if (r.statusCode != 200) throw Exception('prezzi: HTTP ${r.statusCode}');
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    final tutti = leggi(json)..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
    return tutti.take(quanti).toList();
  }

  static List<Distributore> leggi(Map<String, Object?> json) => [
        for (final e in ((json['results'] as List?) ?? const []).whereType<Map>())
          if (_distributore(e.cast<String, Object?>()) case final d?) d,
      ];

  /// Il tipo dal codice del Ministero (1 benzina, 2 gasolio, 3 metano, 4 GPL,
  /// 323/324 GNC/GNL) o, per le varianti «premium», dal nome.
  static Carburante? carburante(int? id, String nome) {
    switch (id) {
      case 1:
        return Carburante.benzina;
      case 2:
        return Carburante.diesel;
      case 3 || 323 || 324:
        return Carburante.metano;
      case 4:
        return Carburante.gpl;
    }
    final n = nome.toLowerCase();
    if (n.contains('gpl')) return Carburante.gpl;
    if (n.contains('metano') || n.contains('gnc') || n.contains('gnl') || n.contains('lng')) return Carburante.metano;
    if (n.contains('gasolio') || n.contains('diesel')) return Carburante.diesel;
    if (n.contains('benzina') || n.contains('super') || n.contains('senza piombo')) return Carburante.benzina;
    return null;
  }

  static Distributore? _distributore(Map<String, Object?> e) {
    final dove = (e['location'] as Map?)?.cast<String, Object?>();
    final lat = (dove?['lat'] as num?)?.toDouble(), lon = (dove?['lng'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final prezzi = <Prezzo>[];
    for (final f in ((e['fuels'] as List?) ?? const []).whereType<Map>()) {
      final nome = '${f['name'] ?? ''}';
      final c = carburante((f['fuelId'] as num?)?.toInt(), nome);
      final euro = (f['price'] as num?)?.toDouble();
      // Prezzi assurdi (0, o un refuso da 17 euro) non si mostrano.
      if (c == null || euro == null || euro < 0.3 || euro > 5) continue;
      prezzi.add(Prezzo(carburante: c, euro: euro, self: f['isSelf'] == true, nome: nome));
    }
    final marca = '${e['brand'] ?? ''}'.trim();
    final nome = '${e['name'] ?? ''}'.trim();
    return Distributore(
      id: 'mimit-${e['id']}',
      nome: marca.isNotEmpty && marca.toLowerCase() != 'pompe bianche' ? marca : (nome.isEmpty ? 'Distributore' : nome),
      marca: marca.isEmpty ? null : marca,
      posizione: Punto(lat, lon),
      carburanti: {for (final p in prezzi) p.carburante},
      prezzi: prezzi,
      aggiornato: DateTime.tryParse('${e['insertDate'] ?? ''}'),
      indirizzo: '${e['address'] ?? ''}'.trim().isEmpty ? null : '${e['address']}'.trim(),
    );
  }
}

/// In Italia i distributori coi prezzi del Ministero; altrove, o se il
/// Ministero non risponde, quelli di OpenStreetMap senza prezzi.
class DistributoriConPrezzi implements FonteDistributori {
  DistributoriConPrezzi({FonteDistributori? prezzi, FonteDistributori? mappa})
      : prezzi = prezzi ?? ClientePrezziMimit(),
        mappa = mappa ?? ClienteDistributori();

  final FonteDistributori prezzi;
  final FonteDistributori mappa;

  @override
  Future<List<Distributore>> vicino(Punto qui, {double km = 5, int quanti = 20}) async {
    if (ClientePrezziMimit.inItalia(qui)) {
      try {
        final d = await prezzi.vicino(qui, km: km, quanti: quanti);
        if (d.isNotEmpty) return d;
      } catch (_) {
        // Si ripiega su OpenStreetMap.
      }
    }
    return mappa.vicino(qui, km: km, quanti: quanti);
  }
}
