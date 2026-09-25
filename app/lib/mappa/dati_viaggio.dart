import 'dart:math' as math;

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

/// La freccia sul percorso compare a questa distanza dalla manovra.
const frecciaDaMetri = 1000.0;

/// Quale freccia mostrare sul percorso: la prossima manovra, se è vicina.
/// Il valore cambia solo quando cambiano viaggio o manovra: allora si
/// ridisegna con [datiManovra].
(int, int)? chiaveFreccia(Viaggio? v, Manovra? m, double? metri, {bool ricalcolo = false}) {
  if (v == null || m == null || metri == null || metri > frecciaDaMetri || ricalcolo) return null;
  return (identityHashCode(v), m.inizio);
}

/// Le manovre senza freccia sul percorso: partenza, arrivo, «prosegui».
const _senzaFreccia = {0, 1, 2, 3, 4, 5, 6, 7, 8};

/// La freccia della prossima manovra disegnata sul percorso, come nei
/// navigatori: il tratto da poco prima a poco dopo, bianco e bordato, che
/// segue esatto la rampa, e la punta dove si va.
Map<String, Object?> datiManovra(Viaggio? v, Manovra? m, {double primaM = 60, double dopoM = 45}) {
  if (v == null || m == null || _senzaFreccia.contains(m.tipo) || v.percorso.punti.length < 2) {
    return _collezione([]);
  }
  final l = Linea(v.percorso.punti);
  final centro = l.cumulate[m.inizio.clamp(0, l.punti.length - 1)];
  final fine = math.min(centro + dopoM, l.lunghezzaM);
  final tratto = [
    _aMetri(l, math.max(0, centro - primaM)),
    for (var i = 0; i < l.punti.length; i++)
      if (l.cumulate[i] > centro - primaM && l.cumulate[i] < fine) l.punti[i],
    _aMetri(l, fine),
  ];
  if (tratto.length < 2 || fine - centro < 5) return _collezione([]);
  // La punta: un triangolo sulla direzione dell'ultimo pezzo.
  final rotta = rottaGradi(_aMetri(l, fine - 4), tratto.last) * math.pi / 180;
  final base = tratto.last;
  final punta = [
    _sposta(base, rotta - math.pi / 2, 8),
    _sposta(base, rotta, 13),
    _sposta(base, rotta + math.pi / 2, 8),
  ];
  return _collezione([
    _elemento({
      'type': 'LineString',
      'coordinates': [for (final p in tratto) _xy(p)],
    }, const {}),
    _elemento({
      'type': 'Polygon',
      'coordinates': [
        [
          for (final p in [...punta, punta.first]) _xy(p),
        ],
      ],
    }, const {}),
  ]);
}

/// Il punto del percorso a tanti metri dalla partenza.
Punto _aMetri(Linea l, double metri) {
  for (var i = 1; i < l.punti.length; i++) {
    if (l.cumulate[i] >= metri) {
      final tratto = l.cumulate[i] - l.cumulate[i - 1];
      final f = tratto == 0 ? 0.0 : (metri - l.cumulate[i - 1]) / tratto;
      final a = l.punti[i - 1], b = l.punti[i];
      return Punto(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f);
    }
  }
  return l.punti.last;
}

/// Spostarsi di pochi metri in una direzione (in radianti, da nord).
Punto _sposta(Punto p, double rotta, double metri) => Punto(
  p.lat + metri * math.cos(rotta) / 111320,
  p.lon + metri * math.sin(rotta) / (111320 * math.cos(p.lat * math.pi / 180)),
);

/// I distributori sulla mappa, col prezzo del [carburante] sotto l'icona.
Map<String, Object?> datiDistributori(List<Distributore> elenco, Carburante carburante) => _collezione([
  for (final d in elenco)
    _elemento(
      {'type': 'Point', 'coordinates': _xy(d.posizione)},
      {
        'id': d.id,
        'tipo': 'distributore',
        'nome': d.nome,
        'etichetta': switch (d.prezzoDi(carburante)) {
          final p? => p.euro.toStringAsFixed(3).replaceAll('.', ','),
          null => d.nome,
        },
      },
    ),
]);

/// Le colonnine rapide intorno, col colore dello stato e la potenza.
Map<String, Object?> datiColonnineVicine(List<Colonnina> elenco, Set<TipoConnettore> connettori) => _collezione([
  for (final c in elenco)
    _elemento(
      {'type': 'Point', 'coordinates': _xy(c.posizione)},
      {
        'id': c.id,
        'tipo': 'colonnina',
        'nome': c.nome,
        'stato': statoDi(c.disponibilitaPer(connettori)).name,
        'etichetta': '${c.potenzaNominalePer(connettori).round()} kW',
      },
    ),
]);

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
