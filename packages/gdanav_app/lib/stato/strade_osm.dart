import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;

/* ─── Le strade di OpenStreetMap lungo il percorso ─────────────────────────
 *
 * Per non portare mai contromano ([correggiContromano], in gdanav_core) il
 * navigatore guarda le strade vere che il percorso sta per fare: le tessere
 * vettoriali di OpenFreeMap, le stesse che la mappa disegna (zoom 14, un paio
 * di chilometri per lato). Si chiedono da sé, senza passare dalla mappa: in
 * auto lo schermo del telefono può essere spento, o la mappa guardare
 * altrove. Le ultime restano in memoria. */

/// Chi dà le tessere: i byte della tessera [z]/[x]/[y] (anche in gzip), o
/// `null` se non c'è o non si può.
typedef FonteTessere = Future<Uint8List?> Function(int z, int x, int y);

/// Le tessere di OpenFreeMap, via rete.
class TessereOpenFreeMap {
  TessereOpenFreeMap({http.Client? client, this.indice = 'https://tiles.openfreemap.org/planet'})
    : _http = client ?? http.Client();

  final http.Client _http;
  final String indice;
  String? _modello;

  static const _intestazioni = {'User-Agent': 'GdANav (navigatore)'};

  Future<Uint8List?> call(int z, int x, int y) async {
    try {
      _modello ??= await _leggiModello();
      final m = _modello;
      if (m == null) return null;
      final r = await _http
          .get(
            Uri.parse(m.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y')),
            headers: _intestazioni,
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return r.bodyBytes;
    } catch (e) {
      debugPrint('tessera strade $z/$x/$y: $e');
      return null;
    }
  }

  /// Il modello degli indirizzi delle tessere, dal TileJSON (cambia a ogni
  /// aggiornamento della mappa).
  Future<String?> _leggiModello() async {
    final r = await _http.get(Uri.parse(indice), headers: _intestazioni).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final tiles = j is Map ? j['tiles'] : null;
    return tiles is List && tiles.isNotEmpty ? '${tiles.first}' : null;
  }
}

/// Le strade delle tessere che servono, lette una volta e tenute a parte.
class StradeOsm {
  StradeOsm(this._fonte, {this.tessereTenute = 48});

  final FonteTessere _fonte;
  final int tessereTenute;
  final _lette = <({int x, int y}), List<TrattoStrada>>{};
  final _inArrivo = <({int x, int y}), Future<List<TrattoStrada>>>{};

  /// Le strade attorno ai [punti] (un percorso, un pezzo di percorso).
  Future<List<TrattoStrada>> attorno(List<Punto> punti) async {
    final tessere = tessereAttorno(punti, marginiM: 300);
    final liste = await Future.wait([for (final t in tessere) _tessera(t)]);
    return [for (final l in liste) ...l];
  }

  Future<List<TrattoStrada>> _tessera(({int x, int y}) t) {
    final gia = _lette.remove(t);
    if (gia != null) {
      _lette[t] = gia; // in fondo: l'ultima usata
      return Future.value(gia);
    }
    return _inArrivo[t] ??= () async {
      try {
        var dati = await _fonte(zoomTessereStrade, t.x, t.y);
        if (dati == null) return const <TrattoStrada>[];
        if (dati.length > 2 && dati[0] == 0x1f && dati[1] == 0x8b) dati = Uint8List.fromList(gzip.decode(dati));
        final strade = stradeDaTessera(dati, zoomTessereStrade, t.x, t.y);
        _lette[t] = strade;
        while (_lette.length > tessereTenute) {
          _lette.remove(_lette.keys.first);
        }
        return strade;
      } finally {
        unawaited(_inArrivo.remove(t));
      }
    }();
  }
}
