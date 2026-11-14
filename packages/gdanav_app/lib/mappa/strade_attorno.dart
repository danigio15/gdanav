import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/* ─── Le strade attorno all'auto, dalla mappa ──────────────────────────────
 *
 * Per mettere l'auto sulla strada anche senza percorso ([AggancioStrada], in
 * gdanav_core) servono le strade che ci sono attorno: le stesse che la mappa
 * sta disegnando (le tessere di OpenFreeMap), chieste a lei nel riquadro
 * attorno all'auto. Niente da scaricare. */

/// Gli strati della mappa con le strade su cui un'auto può stare.
const stratiStrade = ['autostrade', 'principali', 'strade', 'servizio'];

/// Quanto è largo il riquadro attorno all'auto, in punti dello schermo per
/// parte: allo zoom della guida (17) sono una settantina di metri.
const mezzoRiquadroPx = 80.0;

/// Le strade attorno a [qui] che la mappa [m] sta disegnando.
Future<List<TrattoStrada>> stradeAttorno(MapLibreMapController m, Punto qui) async {
  final p = await m.toScreenLocation(LatLng(qui.lat, qui.lon));
  final x = p.x.toDouble(), y = p.y.toDouble();
  final trovate = await m.queryRenderedFeaturesInRect(
    Rect.fromLTRB(x - mezzoRiquadroPx, y - mezzoRiquadroPx, x + mezzoRiquadroPx, y + mezzoRiquadroPx),
    stratiStrade,
    null,
  );
  return trattiDaFeatures(trovate);
}

/// Le linee delle [features] (GeoJSON, già decodificate o come testo) come
/// pezzi di strada col loro senso unico (`oneway` di OpenMapTiles: 1 come la
/// linea, -1 al contrario). I binari e le gallerie dei pedoni non ci sono
/// negli strati delle strade.
List<TrattoStrada> trattiDaFeatures(List<Object?> features) {
  final out = <TrattoStrada>[];
  for (final f in features) {
    final mappa = f is String ? jsonDecode(f) : f;
    if (mappa is! Map) continue;
    final props = mappa['properties'];
    final senso = switch (props is Map ? props['oneway'] : null) {
      final num n when n > 0 => 1,
      final num n when n < 0 => -1,
      _ => 0,
    };
    final g = mappa['geometry'];
    if (g is! Map) continue;
    final linee = switch (g['type']) {
      'LineString' => [g['coordinates']],
      'MultiLineString' => (g['coordinates'] as List?) ?? const [],
      _ => const [],
    };
    for (final l in linee) {
      if (l is! List) continue;
      final punti = <Punto>[
        for (final c in l)
          if (c is List && c.length >= 2 && c[0] is num && c[1] is num)
            Punto((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (punti.length >= 2) out.add(TrattoStrada(punti, senso: senso));
    }
  }
  return out;
}
