import 'package:gdanav_core/gdanav_core.dart';

import 'stile.dart';

/// Come si chiama lo stato di una colonnina sulla mappa e nelle schede.
enum StatoColonnina { libera, piena, guasta, ignota }

StatoColonnina statoDi(Disponibilita d) {
  if (d.libere > 0) return StatoColonnina.libera;
  if (d.piena) return StatoColonnina.piena;
  if (d.guasta) return StatoColonnina.guasta;
  return StatoColonnina.ignota;
}

/// I dati delle sorgenti del viaggio, in GeoJSON: vuote se non c'è un
/// viaggio.
Map<String, Map<String, Object?>> datiViaggio(Viaggio? v) {
  if (v == null) {
    return {sorgentePercorso: _collezione([]), sorgenteColonnine: _collezione([]), sorgenteArrivo: _collezione([])};
  }
  final soste = {for (final (i, s) in (v.piano?.soste ?? const <Sosta>[]).indexed) s.colonnina.id: i + 1};
  final linea = Linea(v.percorso.punti);
  return {
    sorgentePercorso: _collezione([
      if (v.percorso.punti.length > 1)
        _elemento({
          'type': 'LineString',
          'coordinates': [for (final p in v.percorso.punti) _xy(p)],
        }, const {}),
    ]),
    sorgenteColonnine: _collezione([
      // Prima le colonnine comuni, poi le soste: così le soste stanno sopra.
      for (final c in [
        ...v.colonnine.where((c) => !soste.containsKey(c.id)),
        ...v.colonnine.where((c) => soste.containsKey(c.id)),
      ])
        _elemento(
          {'type': 'Point', 'coordinates': _xy(c.dettaglio?.posizione ?? _lungo(linea, c.distanzaM))},
          {
            'id': c.id,
            'nome': c.nome,
            'potenza': c.potenzaKw.round(),
            'stato': statoDi(c.disponibilita).name,
            'sosta': soste.containsKey(c.id),
            'numero': soste[c.id] ?? 0,
          },
        ),
    ]),
    sorgenteArrivo: _collezione([
      if (v.percorso.punti.isNotEmpty)
        _elemento({'type': 'Point', 'coordinates': _xy(v.percorso.punti.last)}, const {}),
    ]),
  };
}

/// Il riquadro che contiene tutto il percorso: sud-ovest e nord-est.
(Punto, Punto)? confini(Viaggio v) {
  final p = v.percorso.punti;
  if (p.isEmpty) return null;
  var s = p.first.lat, n = s, o = p.first.lon, e = o;
  for (final q in p) {
    if (q.lat < s) s = q.lat;
    if (q.lat > n) n = q.lat;
    if (q.lon < o) o = q.lon;
    if (q.lon > e) e = q.lon;
  }
  return (Punto(s, o), Punto(n, e));
}

Punto _lungo(Linea l, double metri) {
  for (var i = 1; i < l.punti.length; i++) {
    if (l.cumulate[i] >= metri) return l.punti[i];
  }
  return l.punti.last;
}

List<double> _xy(Punto p) => [p.lon, p.lat];

Map<String, Object?> _collezione(List<Map<String, Object?>> elementi) => {
  'type': 'FeatureCollection',
  'features': elementi,
};

Map<String, Object?> _elemento(Map<String, Object?> geometria, Map<String, Object?> proprieta) => {
  'type': 'Feature',
  'geometry': geometria,
  'properties': proprieta,
};
