import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'pedaggi.dart';
import 'valhalla.dart';

/// I pedaggi veri, casello per casello, da HERE Routing v8.
///
/// Il percorso resta quello di TomTom (il traffico, le ZTL, le soste): a HERE
/// si dà la sua geometria e HERE dice quanto si paga **su quella strada**,
/// non su una sua. Sono due chiamate, come dice la documentazione di HERE
/// («Get toll cost with route import service»):
///  1. `POST /v8/import` coi punti del percorso, che ridà un `routeHandle`;
///  2. `GET /v8/routes/{routeHandle}` con `return=tolls`, che ridà i
///     pedaggi di ogni sezione: quanto (`fares`) e dove si paga
///     (`tollCollectionLocations`).
///
/// Il prezzo dei pedaggi conta come una richiesta in più nel piano di HERE.
/// Per questo si chiede solo per i percorsi che passano da pedaggi, una
/// volta per percorso (lo stesso percorso non si richiede: [_giaChiesti]).
///
/// Se HERE non risponde, o non sa il prezzo, si torna alla stima
/// ([TariffaPedaggio.stima]): `null`.
class PedaggiHere {
  PedaggiHere(
    this.chiave, {
    http.Client? client,
    Uri? indirizzo,
    this.attesa = const Duration(seconds: 6),
  })  : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://router.hereapi.com/v8/');

  final String chiave;
  final Uri indirizzo;
  final http.Client _http;

  /// Quanto si aspetta HERE, per le due chiamate insieme: il percorso intanto
  /// è pronto, e si mostra con la stima.
  final Duration attesa;

  /// Quanti punti al massimo si mandano a HERE: abbastanza da non sbagliare
  /// strada agli svincoli, non tanti da fare un corpo enorme.
  static const puntiMassimi = 1000;

  /// Un punto ogni tanti metri, almeno: più fitti non servono.
  static const passoMinimoM = 80.0;

  final _giaChiesti = <String, List<PagamentoPedaggio>?>{};

  /// I pedaggi veri del [percorso] per la [classe]; `null` se non si sanno.
  /// Le classi dei mezzi pesanti (3, 4, 5) HERE le vuole come camion: lì si
  /// resta alla stima.
  Future<List<PagamentoPedaggio>?> di(PercorsoCalcolato percorso, ClassePedaggio classe) async {
    if (chiave.isEmpty || !percorso.conPedaggi || percorso.punti.length < 2) return null;
    if (classe != ClassePedaggio.a && classe != ClassePedaggio.b) return null;
    final quale = _impronta(percorso, classe);
    if (_giaChiesti.containsKey(quale)) return _giaChiesti[quale];
    try {
      final pagamenti = await _chiedi(percorso, classe).timeout(attesa);
      if (_giaChiesti.length > 20) _giaChiesti.remove(_giaChiesti.keys.first);
      return _giaChiesti[quale] = pagamenti;
    } catch (_) {
      // Una rete che manca, un piano finito: la prossima volta si riprova.
      return null;
    }
  }

  Future<List<PagamentoPedaggio>?> _chiedi(PercorsoCalcolato percorso, ClassePedaggio classe) async {
    final traccia = puntiDaMandare(percorso.punti);
    final importa = await _http.post(
      indirizzo.resolve('import').replace(queryParameters: {
        'apiKey': chiave,
        'transportMode': 'car',
        'return': 'routeHandle',
      }),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'trace': [
          for (final p in traccia) {'lat': p.lat, 'lng': p.lon},
        ],
      }),
    );
    if (importa.statusCode != 200) return null;
    final maniglia = leggiManiglia(jsonDecode(utf8.decode(importa.bodyBytes)));
    if (maniglia == null) return null;
    final pedaggi = await _http.get(
      indirizzo.resolve('routes/${Uri.encodeComponent(maniglia)}').replace(queryParameters: {
        'apiKey': chiave,
        'transportMode': 'car',
        'return': 'summary,tolls',
        'currency': 'EUR',
        // La classe B: due assi più alti di 1,30 m all'asse anteriore.
        if (classe == ClassePedaggio.b) 'vehicle[height]': '200',
      }),
    );
    if (pedaggi.statusCode != 200) return null;
    return leggiPedaggi(jsonDecode(utf8.decode(pedaggi.bodyBytes)), percorso.punti);
  }

  /// Lo stesso percorso, la stessa classe: inizio, fine, lunghezza.
  static String _impronta(PercorsoCalcolato p, ClassePedaggio c) {
    final a = p.punti.first, b = p.punti.last;
    final m = Linea(p.punti).cumulate.last;
    return '${c.name}:${a.lat.toStringAsFixed(4)},${a.lon.toStringAsFixed(4)}:'
        '${b.lat.toStringAsFixed(4)},${b.lon.toStringAsFixed(4)}:${(m / 50).round()}';
  }

  /// I punti da mandare: il primo, l'ultimo, e in mezzo uno ogni
  /// [passoMinimoM] almeno, al massimo [puntiMassimi].
  static List<Punto> puntiDaMandare(List<Punto> punti) {
    if (punti.length <= 2) return punti;
    final cumulate = Linea(punti).cumulate;
    final passo = math.max(passoMinimoM, cumulate.last / (puntiMassimi - 1));
    final scelti = <Punto>[punti.first];
    var ultimo = 0.0;
    for (var i = 1; i < punti.length - 1; i++) {
      if (cumulate[i] - ultimo >= passo) {
        scelti.add(punti[i]);
        ultimo = cumulate[i];
      }
    }
    scelti.add(punti.last);
    return scelti;
  }

  static String? leggiManiglia(Object? j) {
    if (j is! Map) return null;
    final rotte = j['routes'];
    if (rotte is! List || rotte.isEmpty) return null;
    final r = rotte.first;
    return r is Map && r['routeHandle'] is String ? r['routeHandle'] as String : null;
  }

  /// I pagamenti della risposta di `/routes` con `return=tolls`: per ogni
  /// pedaggio la prima tariffa in euro, nel punto del percorso più vicino a
  /// dove si paga (l'ultimo posto di riscossione: l'uscita, nel sistema
  /// chiuso italiano). `null` se nella risposta non c'è nessun prezzo.
  static List<PagamentoPedaggio>? leggiPedaggi(Object? j, List<Punto> punti) {
    if (j is! Map) return null;
    final rotte = j['routes'];
    if (rotte is! List || rotte.isEmpty || rotte.first is! Map) return null;
    final sezioni = (rotte.first as Map)['sections'];
    if (sezioni is! List) return null;
    final linea = Linea(punti);
    final pagamenti = <PagamentoPedaggio>[];
    var conPedaggi = false;
    for (final s in sezioni.whereType<Map>()) {
      for (final t in (s['tolls'] as List? ?? const []).whereType<Map>()) {
        conPedaggi = true;
        final euro = _prezzo(t['fares']);
        if (euro == null) return null;
        final dove = (t['tollCollectionLocations'] as List? ?? const []).whereType<Map>().toList();
        final ultimo = dove.isEmpty ? null : dove.last;
        final posto = ultimo?['location'];
        final aM = posto is Map && posto['lat'] is num && posto['lng'] is num
            ? _metriSulla(linea, Punto((posto['lat'] as num).toDouble(), (posto['lng'] as num).toDouble()))
            : linea.cumulate.last;
        pagamenti.add(PagamentoPedaggio(euro: euro, aM: aM, nome: '${ultimo?['name'] ?? ''}'));
      }
    }
    if (!conPedaggi) return const [];
    pagamenti.sort((a, b) => a.aM.compareTo(b.aM));
    return pagamenti;
  }

  /// La prima tariffa in euro: `price` se è in euro, se no `convertedPrice`
  /// (chiesto con `currency=EUR`).
  static double? _prezzo(Object? tariffe) {
    if (tariffe is! List) return null;
    for (final f in tariffe.whereType<Map>()) {
      for (final campo in const ['price', 'convertedPrice']) {
        final p = f[campo];
        if (p is Map && p['currency'] == 'EUR' && p['value'] is num) return (p['value'] as num).toDouble();
      }
    }
    return null;
  }

  static double _metriSulla(Linea linea, Punto p) {
    var migliore = 0, distanza = double.infinity;
    for (var i = 0; i < linea.punti.length; i++) {
      final d = distanzaM(linea.punti[i], p);
      if (d < distanza) {
        distanza = d;
        migliore = i;
      }
    }
    return linea.cumulate[migliore];
  }
}
