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

/// Cosa è successo agli ultimi controlli dei sensi unici, per la pagina di
/// diagnosi: «ancora sbagliato st'incrocio» e non si sapeva se le strade
/// non erano arrivate, se il controllo era partito tardi o se non aveva
/// trovato il ramo giusto. Le ultime [quante] righe, la più nuova in cima.
class DiarioSensi {
  DiarioSensi({this.quante = 20, DateTime Function()? ora}) : _ora = ora ?? DateTime.now;

  final int quante;
  final DateTime Function() _ora;
  final _voci = <String>[];

  List<String> get voci => List.unmodifiable(_voci);

  void scrivi(String cosa) {
    final o = _ora();
    String due(int v) => v.toString().padLeft(2, '0');
    _voci.insert(0, '${due(o.hour)}:${due(o.minute)}:${due(o.second)} $cosa');
    if (_voci.length > quante) _voci.removeLast();
  }
}

/// Il diario di questo telefono.
final diarioSensi = DiarioSensi();

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
      final r = await _chiedi(z, x, y);
      if (r == null) return null;
      // «Ancora sbagliato st'incrocio»: l'indirizzo delle tessere cambia a
      // ogni aggiornamento della mappa (una volta a settimana, più o meno), e
      // si leggeva una volta sola. GdAHome e l'auto restano accese per
      // giorni: dopo l'aggiornamento ogni tessera rispondeva «non c'è», il
      // navigatore restava senza strade e il contromano non si correggeva
      // più. Un «non c'è» fa rileggere l'indirizzo, e si riprova una volta.
      if (r.statusCode == 404 || r.statusCode == 410) {
        final vecchio = _modello;
        _modello = null;
        final di = await _chiedi(z, x, y);
        if (di == null) return null;
        // L'indirizzo è quello di adesso e la tessera non c'è: lì la mappa
        // non ha niente, come una tessera vuota.
        if (_modello == vecchio && (di.statusCode == 404 || di.statusCode == 410)) return Uint8List(0);
        return _contenuto(di);
      }
      return _contenuto(r);
    } catch (e) {
      debugPrint('tessera strade $z/$x/$y: $e');
      return null;
    }
  }

  Future<http.Response?> _chiedi(int z, int x, int y) async {
    _modello ??= await _leggiModello();
    final m = _modello;
    if (m == null) return null;
    return _http
        .get(
          Uri.parse(m.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y')),
          headers: _intestazioni,
        )
        .timeout(const Duration(seconds: 10));
  }

  /// I byte di una tessera arrivata; una tessera vuota (204: lì non c'è
  /// niente, il mare) è una tessera senza strade, non una tessera mancata.
  static Uint8List? _contenuto(http.Response r) => switch (r.statusCode) {
    200 => r.bodyBytes,
    204 => Uint8List(0),
    _ => null,
  };

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
  final _inArrivo = <({int x, int y}), Future<List<TrattoStrada>?>>{};

  /// Le strade attorno ai [punti] (un percorso, un pezzo di percorso).
  ///
  /// Tutte o niente: se una tessera non arriva si risponde vuoto, e chi
  /// chiede riprova fra poco. Con una tessera sì e una no il pezzo di strada
  /// sembrava guardato, e un incrocio nella tessera mancata restava
  /// contromano finché l'auto non era lì.
  Future<List<TrattoStrada>> attorno(List<Punto> punti) async {
    final tessere = tessereAttorno(punti, marginiM: 300);
    final liste = await Future.wait([for (final t in tessere) _tessera(t)]);
    final mancano = liste.where((l) => l == null).length;
    if (mancano > 0) {
      diarioSensi.scrivi('strade: $mancano tessere su ${liste.length} non arrivate, si riprova');
      return const [];
    }
    return [for (final l in liste) ...?l];
  }

  /// Le strade di una tessera; `null` se non è arrivata (non si tiene: la
  /// prossima volta si richiede).
  Future<List<TrattoStrada>?> _tessera(({int x, int y}) t) {
    final gia = _lette.remove(t);
    if (gia != null) {
      _lette[t] = gia; // in fondo: l'ultima usata
      return Future.value(gia);
    }
    return _inArrivo[t] ??= () async {
      try {
        var dati = await _fonte(zoomTessereStrade, t.x, t.y);
        if (dati == null) return null;
        if (dati.length > 2 && dati[0] == 0x1f && dati[1] == 0x8b) dati = Uint8List.fromList(gzip.decode(dati));
        final strade = dati.isEmpty ? const <TrattoStrada>[] : stradeDaTessera(dati, zoomTessereStrade, t.x, t.y);
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
