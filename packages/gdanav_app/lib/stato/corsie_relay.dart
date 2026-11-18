import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;

import '../servizi.dart';

/* ─── Le corsie dal relay ─────────────────────────────────────────────────
 *
 * La vista «Corsie» disegna le corsie vere: quante sono, le frecce dipinte,
 * le strisce, i semafori. Le tessere della mappa non le hanno; le dà il
 * relay di GdANav, una tessera z14 alla volta (`GET /v1/corsie/14/<x>/<y>`,
 * il JSON scritto in `web3d/src/corsie.js`), prese da OpenStreetMap. Qui le
 * tessere lungo i prossimi chilometri del percorso, e quella dove si è;
 * le ultime restano in memoria (come [StradeOsm]). Non serve averle tutte:
 * ognuna va alla pagina appena arriva, e una che manca si richiede dopo. */

/// Il JSON delle corsie di una tessera z14.
typedef DatiCorsie = Map<String, Object?>;

class CorsieRelay {
  CorsieRelay(this.relay, {http.Client? client, this.tenute = 64, this.attesa = const Duration(seconds: 35)})
    : _http = client ?? http.Client();

  /// Quello dell'app (lo stesso delle colonnine e delle segnalazioni).
  static CorsieRelay? _attuale;
  static CorsieRelay get attuale => _attuale ??= CorsieRelay(Uri.parse(Servizi.segnalazioni));

  final Uri relay;
  final http.Client _http;

  /// Quante tessere restano in memoria (le ultime usate).
  final int tenute;

  /// Una tessera mai chiesta il relay la va a prendere da Overpass: fino a
  /// venticinque secondi.
  final Duration attesa;

  final _lette = <({int x, int y}), DatiCorsie>{};
  final _inArrivo = <({int x, int y}), Future<DatiCorsie?>>{};

  /// Le tessere lette e tenute, adesso (per le prove).
  int get inMemoria => _lette.length;

  Uri indirizzo(int x, int y) {
    final base = relay.path.endsWith('/') ? relay.path : '${relay.path}/';
    return relay.replace(path: '${base}v1/corsie/$zoomTessereStrade/$x/$y');
  }

  /// Le corsie della tessera [x]/[y] (z14), o `null` se non sono arrivate
  /// (allora non si tengono: la prossima volta si richiedono).
  Future<DatiCorsie?> tessera(int x, int y) {
    final t = (x: x, y: y);
    final gia = _lette.remove(t);
    if (gia != null) {
      _lette[t] = gia; // in fondo: l'ultima usata
      return Future.value(gia);
    }
    return _inArrivo[t] ??= () async {
      try {
        final r = await _http.get(indirizzo(x, y)).timeout(attesa);
        if (r.statusCode != 200) {
          debugPrint('corsie $x/$y: relay ${r.statusCode}');
          return null;
        }
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is! Map || j['strade'] is! List) return null;
        final dati = j.cast<String, Object?>();
        _lette[t] = dati;
        while (_lette.length > tenute) {
          _lette.remove(_lette.keys.first);
        }
        return dati;
      } catch (e) {
        debugPrint('corsie $x/$y: $e');
        return null;
      } finally {
        unawaited(_inArrivo.remove(t));
      }
    }();
  }

  /// Le tessere da avere: quella di [qui] e quelle lungo il [percorso] da
  /// [daM] metri per [avantiM] metri (con un margine attorno), prima le più
  /// vicine.
  static List<({int x, int y})> tessereDavanti({
    required List<Punto> percorso,
    required double? daM,
    Punto? qui,
    double avantiM = 3000,
  }) {
    final out = <({int x, int y})>[];
    void metti(Iterable<({int x, int y})> tt) {
      for (final t in tt) {
        if (!out.contains(t)) out.add(t);
      }
    }

    if (qui != null) metti(tessereAttorno([qui], marginiM: 100));
    if (percorso.length >= 2 && daM != null) {
      final cum = Linea(percorso).cumulate;
      final pezzo = <Punto>[];
      for (var i = 0; i < percorso.length; i++) {
        if (cum[i] < daM - 100) continue;
        if (cum[i] > daM + avantiM) break;
        pezzo.add(percorso[i]);
      }
      // I punti del percorso possono essere radi: uno ogni duecento metri.
      final fitti = <Punto>[];
      for (var i = 0; i < pezzo.length; i++) {
        if (i > 0) {
          final a = pezzo[i - 1], b = pezzo[i];
          final d = distanzaM(a, b);
          for (var k = 1; k * 200 < d; k++) {
            final t = k * 200 / d;
            fitti.add(Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t));
          }
        }
        fitti.add(pezzo[i]);
      }
      metti(tessereAttorno(fitti, marginiM: 150));
    }
    return out;
  }
}
