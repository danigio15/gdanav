import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_ztl.dart' show statoBreve;
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
/// viaggio. Con le [scelte] anche le strade alternative (tranne la
/// [scelta]), con quanto fanno guadagnare o perdere; con le [tappe] i loro
/// numeri; con [passandoci] la strada dentro la ZTL di cui si chiede il
/// permesso.
///
/// La strada già fatta in guida ([GestoreGuida.traccia]): una linea sola.
Map<String, Object?> datiTraccia(List<Punto> traccia) {
  final punti = _linea(traccia);
  return _collezione([
    if (punti.length > 1) _elemento({'type': 'LineString', 'coordinates': punti}, const {}),
  ]);
}

/// Ogni sorgente per conto suo, e la linea del percorso prima di tutto: una
/// colonnina o una coda storte lasciano vuota la loro, non le altre. Prima
/// un errore qualunque qui dentro lasciava la mappa senza percorso.
///
/// [sullaMappa]: la linea del percorso appoggiata sulle strade della mappa
/// (`GestoreGuida.sullaMappa`), coi metri del percorso: la linea e le code
/// si disegnano lì sopra.
Map<String, Map<String, Object?>> datiViaggio(
  Viaggio? v, {
  List<PercorsoCalcolato> scelte = const [],
  int scelta = 0,
  List<Luogo> tappe = const [],
  bool passandoci = false,
  int? eco,
  Linea? sullaMappa,
}) {
  if (v == null) {
    return {
      sorgentePercorso: _collezione([]),
      sorgenteColonnine: _collezione([]),
      sorgenteArrivo: _collezione([]),
      sorgenteCode: _collezione([]),
      sorgenteAlternative: _collezione([]),
      sorgenteTappe: _collezione([]),
      sorgentePassandoci: _collezione([]),
    };
  }
  final mostrata = _mostrata(v.percorso, sullaMappa);
  final strada = _linea(mostrata?.punti ?? v.percorso.punti);
  return {
    sorgentePercorso: _collezione([
      if (strada.length > 1) _elemento({'type': 'LineString', 'coordinates': strada}, const {}),
    ]),
    sorgenteColonnine: _oVuota('colonnine', () => _colonnine(v)),
    sorgenteArrivo: _collezione([
      if (v.percorso.punti.lastOrNull case final fine? when _scrivibile(fine))
        _elemento({'type': 'Point', 'coordinates': _xy(fine)}, const {'arrivo': true}),
    ]),
    sorgenteCode: _oVuota('code', () => datiCode(v.percorso, sullaMappa: mostrata)),
    sorgenteAlternative: _oVuota('alternative', () => datiAlternative(scelte, scelta, eco: eco)),
    sorgenteTappe: _oVuota(
      'tappe',
      () => _collezione([
        for (final (i, t) in tappe.indexed)
          if (_scrivibile(t.posizione))
            _elemento(
              {'type': 'Point', 'coordinates': _xy(t.posizione)},
              {'numero': i + 1, 'nome': t.nome, 'tappa': true},
            ),
      ]),
    ),
    sorgentePassandoci: passandoci ? _oVuota('passandoci', () => datiPassandoci(v.percorso)) : _collezione([]),
  };
}

Map<String, Object?> _colonnine(Viaggio v) {
  final soste = {for (final (i, s) in (v.piano?.soste ?? const <Sosta>[]).indexed) s.colonnina.id: i + 1};
  final linea = Linea(v.percorso.punti);
  return _collezione([
    // Prima le colonnine comuni, poi le soste: così le soste stanno sopra.
    for (final c in [
      ...v.colonnine.where((c) => !soste.containsKey(c.id)),
      ...v.colonnine.where((c) => soste.containsKey(c.id)),
    ])
      if (c.dettaglio?.posizione ?? _lungo(linea, c.distanzaM) case final dove? when _scrivibile(dove))
        _elemento(
          {'type': 'Point', 'coordinates': _xy(dove)},
          {
            'id': c.id,
            'nome': c.nome,
            'potenza': c.potenzaKw.isFinite ? c.potenzaKw.round() : 0,
            'stato': statoDi(c.disponibilita).name,
            'sosta': soste.containsKey(c.id),
            'numero': soste[c.id] ?? 0,
          },
        ),
  ]);
}

/// Una sorgente che non si riesce a fare resta vuota, e le altre si fanno lo
/// stesso.
Map<String, Object?> _oVuota(String nome, Map<String, Object?> Function() fai) {
  try {
    return fai();
  } catch (e) {
    debugPrint('dati del viaggio, $nome: $e');
    return _collezione([]);
  }
}

/// Un punto che si può scrivere. Il JSON non sa cosa sia NaN: un punto solo
/// così, e la mappa rifiutava la sorgente intera.
bool _scrivibile(Punto p) => p.lat.isFinite && p.lon.isFinite;

/// Le coordinate di una linea, senza i punti che non si possono scrivere.
List<List<double>> _linea(Iterable<Punto> punti) => [
  for (final p in punti)
    if (_scrivibile(p)) _xy(p),
];

/// La strada che passerebbe dentro la ZTL di cui si chiede il permesso, con
/// quanto si guadagnerebbe: «-3 min» dove si stacca di più dal percorso.
Map<String, Object?> datiPassandoci(PercorsoCalcolato p) {
  final z = p.ztl;
  final dentro = z?.puntiPassandoci ?? const <Punto>[];
  if (z?.daChiedere == null || dentro.length < 2) return _collezione([]);
  final durata = z!.durataPassandoci;
  final diff = durata == null ? null : ((durata.inSeconds - p.durata.inSeconds) / 60).round();
  final linea = Linea(p.punti);
  var lontano = dentro[dentro.length ~/ 2];
  var massimo = -1.0;
  for (var k = 0; k < dentro.length; k += math.max(1, dentro.length ~/ 60)) {
    final d = linea.proietta(dentro[k]).lontanoM;
    if (d > massimo) {
      massimo = d;
      lontano = dentro[k];
    }
  }
  return _collezione([
    _elemento({'type': 'LineString', 'coordinates': _linea(dentro)}, const {}),
    if (diff != null && _scrivibile(lontano))
      _elemento(
        {'type': 'Point', 'coordinates': _xy(lontano)},
        // Il trattino normale: il segno meno non c'è in tutti i caratteri della mappa.
        {'etichetta': diff == 0 ? 'Uguale' : '${diff > 0 ? '+' : '-'}${diff.abs()} min'},
      ),
  ]);
}

/// La strada proposta in guida, [p]: verde sotto il percorso [adesso], così
/// si vede dove se ne stacca, col fumetto dove ne è più lontana — «-1,8 kWh
/// · +4 min». Senza proposta, niente.
Map<String, Object?> datiRisparmio(PropostaStrada? p, PercorsoCalcolato? adesso, String etichetta) {
  final punti = p?.percorso.punti ?? const <Punto>[];
  if (punti.length < 2) return _collezione([]);
  var lontano = punti[punti.length ~/ 2];
  if (adesso != null && adesso.punti.length > 1) {
    final linea = Linea(adesso.punti);
    var massimo = -1.0;
    for (var k = 0; k < punti.length; k += math.max(1, punti.length ~/ 80)) {
      final d = linea.proietta(punti[k]).lontanoM;
      if (d > massimo) {
        massimo = d;
        lontano = punti[k];
      }
    }
  }
  return _collezione([
    _elemento({
      'type': 'LineString',
      'coordinates': [for (final q in punti) _xy(q)],
    }, const {}),
    if (etichetta.isNotEmpty) _elemento({'type': 'Point', 'coordinates': _xy(lontano)}, {'etichetta': etichetta}),
  ]);
}

/// Le ZTL e le aree pedonali di [zone] sulla mappa, com'erano a [ora]: ogni
/// contorno un poligono (la ZTL col suo «attiva»), e per ogni zona il punto
/// dove scriverne il nome: «ZTL · attiva fino alle 18», «Area pedonale».
Map<String, Object?> datiZtl(Iterable<ZonaLimitata> zone, DateTime ora) => _collezione([
  for (final z in zone) ...[
    for (final a in z.anelli)
      if (a.length >= 3)
        _elemento(
          {
            'type': 'Polygon',
            'coordinates': [
              [
                for (final p in [...a, a.first]) _xy(p),
              ],
            ],
          },
          {'tipo': z.tipo.name, 'attiva': z.attivaAlle(ora)},
        ),
    _elemento(
      {'type': 'Point', 'coordinates': _xy(z.puntoDentro)},
      {'tipo': z.tipo.name, 'etichetta': z.tipo == TipoZona.ztl ? 'ZTL · ${statoBreve(z, ora)}' : 'Area pedonale'},
    ),
  ],
]);

/// Le code sul percorso, per colorarlo: gialle i rallentamenti, arancioni
/// le code, rosse le code ferme, bordeaux le strade chiuse.
Map<String, Object?> datiCode(PercorsoCalcolato p, {Linea? sullaMappa}) {
  if (p.code.isEmpty || p.punti.length < 2) return _collezione([]);
  final linea = _mostrata(p, sullaMappa) ?? Linea(p.punti);
  return _collezione([
    for (final c in p.code)
      if (_linea(_tratto(linea, c.daM, c.aM)) case final pezzo when pezzo.length > 1)
        _elemento({'type': 'LineString', 'coordinates': pezzo}, {'livello': c.livello}),
  ]);
}

/// Le strade alternative (tutte tranne la [scelta]), ognuna con un'etichetta
/// dove si separa di più: «+6 min», «−3 min», «uguale». Quella [eco], che
/// risparmia energia, si disegna verde.
Map<String, Object?> datiAlternative(List<PercorsoCalcolato> scelte, int scelta, {int? eco}) {
  if (scelte.length < 2) return _collezione([]);
  final base = scelte[scelta.clamp(0, scelte.length - 1)];
  final lineaBase = Linea(base.punti);
  final elementi = <Map<String, Object?>>[];
  for (final (i, a) in scelte.indexed) {
    if (i == scelta || a.punti.length < 2) continue;
    final diff = ((a.durata.inSeconds - base.durata.inSeconds) / 60).round();
    // Il trattino normale: il segno meno non c'è in tutti i caratteri della mappa.
    final etichetta = diff == 0 ? 'Uguale' : '${diff > 0 ? '+' : '-'}${diff.abs()} min';
    elementi.add(
      _elemento({'type': 'LineString', 'coordinates': _linea(a.punti)}, {'alternativa': i, if (i == eco) 'eco': true}),
    );
    // L'etichetta dove l'alternativa è più lontana dal percorso scelto.
    var lontano = a.punti[a.punti.length ~/ 2];
    var massimo = -1.0;
    for (var k = 0; k < a.punti.length; k += math.max(1, a.punti.length ~/ 60)) {
      final d = lineaBase.proietta(a.punti[k]).lontanoM;
      if (d > massimo) {
        massimo = d;
        lontano = a.punti[k];
      }
    }
    if (!_scrivibile(lontano)) continue;
    elementi.add(
      _elemento(
        {'type': 'Point', 'coordinates': _xy(lontano)},
        {'alternativa': i, 'etichetta': '${durataBreve(a.durata)}\n$etichetta', if (i == eco) 'eco': true},
      ),
    );
  }
  return _collezione(elementi);
}

/// «1 h 05», «45 min».
String durataBreve(Duration d) {
  final ore = d.inHours, minuti = d.inMinutes % 60;
  return ore == 0 ? '$minuti min' : '$ore h ${minuti.toString().padLeft(2, '0')}';
}

/// I punti della [l] fra [da] e [a] metri, con gli estremi interpolati.
/// Metri che non sono numeri (una coda arrivata storta) non sono un tratto.
List<Punto> _tratto(Linea l, double da, double a) {
  if (!da.isFinite || !a.isFinite || a <= da || l.punti.isEmpty) return const [];
  Punto a0(double m) {
    for (var i = 1; i < l.punti.length; i++) {
      if (l.cumulate[i] >= m) {
        final seg = l.cumulate[i] - l.cumulate[i - 1];
        final t = seg <= 0 ? 0.0 : (m - l.cumulate[i - 1]) / seg;
        final p = l.punti[i - 1], q = l.punti[i];
        return Punto(p.lat + (q.lat - p.lat) * t, p.lon + (q.lon - p.lon) * t);
      }
    }
    return l.punti.last;
  }

  return [
    a0(da),
    for (var i = 0; i < l.punti.length; i++)
      if (l.cumulate[i] > da && l.cumulate[i] < a) l.punti[i],
    a0(a),
  ];
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
///
/// «La freccia è grande, va oltre la linea blu»: era larga in metri (otto e
/// mezzo, la punta sedici) e la linea in pixel, così a zoom alto in città la
/// freccia era il doppio della linea; e la punta stava tredici metri OLTRE
/// la fine del tratto, che a un incrocio subito dopo finiva fuori strada.
/// Adesso la larghezza è quella della linea (vedi lo stile), la punta è
/// un'icona in pixel posata sulla fine del tratto (un punto con la sua
/// [rotta]), e il tratto si ferma dieci metri prima della manovra dopo.
Map<String, Object?> datiManovra(
  Viaggio? v,
  Manovra? m, {
  double primaM = 60,
  double dopoM = 45,
  Linea? sullaMappa,
  bool corsie = false,
}) {
  if (v == null || m == null || _senzaFreccia.contains(m.tipo) || v.percorso.punti.length < 2) {
    return _collezione([]);
  }
  final l = Linea(v.percorso.punti);
  final centro = l.cumulate[m.inizio.clamp(0, l.punti.length - 1)];
  final fine = _fineFreccia(v, m, l, centro, dopoM);
  // I metri dal percorso, i punti dalla linea che si disegna.
  final g = _mostrata(v.percorso, sullaMappa) ?? l;
  /* La freccia sta sulla linea blu del percorso, in tutte le viste.
   *
   * «La linea bianca non combacia con quella blu, e sul continuo del
   * percorso»: nella vista immersiva la freccia partiva dalla corsia giusta,
   * spostata di lato, e la teneva finché il percorso non la raggiungeva. A
   * un bivio dove si tiene la sinistra (l'uscita di corso Malta venendo da
   * Pomigliano) il percorso non la raggiungeva mai: correva parallela a
   * quella blu, a qualche metro. Con le corsie disegnate ([corsie], vista
   * immersiva) la linea blu stessa entra nella corsia giusta ([datiCorsie]):
   * la freccia parte da lì, dove la linea è, e in [uscitaCorsiaM] metri dopo
   * la manovra torna sul percorso. */
  final c = corsie ? _corsieDi(v, m, sullaMappa: sullaMappa) : null;
  final tratto = _trattoSpostato(g, math.max(0, centro - primaM), fine, c?.latoA);
  if (tratto.length < 2 || fine - centro < 5) return _collezione([]);
  // La punta guarda come l'ultimo pezzo del tratto.
  final rotta = rottaGradi(_trattoSpostato(g, fine - 4, fine, c?.latoA).first, tratto.last);
  return _collezione([
    _elemento({
      'type': 'LineString',
      'coordinates': [for (final p in tratto) _xy(p)],
    }, const {}),
    _elemento({'type': 'Point', 'coordinates': _xy(tratto.last)}, {'rotta': rotta}),
  ]);
}

/// Dove finisce la freccia: poco dopo la manovra, mai fin sulla manovra dopo
/// (la punta ci arriverebbe sopra, e sembrerebbe di dover girare lì).
///
/// «Deve esserci la freccia che esce»: a un'uscita la rampa corre accanto
/// alla strada per un bel pezzo, e la freccia, finita [dopoM] metri dopo,
/// puntava dritta: sembrava di dover tirare dritto. Se la strada gira più in
/// là (entro [_allungoMaxM]), la freccia arriva fin dove ha girato di
/// [_giratoGradi]: la punta guarda dove si va.
double _fineFreccia(Viaggio v, Manovra m, Linea l, double centro, double dopoM) {
  final manovre = v.percorso.manovre;
  final k = manovre.indexWhere((x) => x.inizio > m.inizio);
  final dopo = k < 0 ? l.lunghezzaM : l.cumulate[manovre[k].inizio.clamp(0, l.punti.length - 1)];
  var voluta = centro + dopoM;
  final prima = _aMetri(l, math.max(0, centro - 30)), qui = _aMetri(l, centro);
  if (distanzaM(prima, qui) > 5) {
    final verso = rottaGradi(prima, qui);
    // Girata già entro [dopoM] (una svolta a un incrocio): resta com'era.
    if (_girata(l, verso, centro + dopoM) == null) {
      for (var s = centro + dopoM + 5; s <= math.min(centro + _allungoMaxM, l.lunghezzaM); s += 5) {
        if (_girata(l, verso, s) != null) {
          voluta = s;
          break;
        }
      }
    }
  }
  return math.min(math.max(centro + 10, math.min(voluta, dopo - _primaDellaDopoM)), l.lunghezzaM);
}

/// Fin dove si allunga la freccia di un'uscita, al più.
const _allungoMaxM = 250.0;

/// Di quanto deve aver girato la strada perché la freccia lo mostri.
const _giratoGradi = 20.0;

/// [s] se a [s] metri la strada va a più di [_giratoGradi] da [verso].
double? _girata(Linea l, double verso, double s) {
  final a = _aMetri(l, math.max(0, s - 15)), b = _aMetri(l, s);
  if (distanzaM(a, b) < 5) return null;
  return diQuantoSiGira(verso, rottaGradi(a, b)).abs() >= _giratoGradi ? s : null;
}

/// Il tratto della freccia della manovra [m] in metri lungo il percorso (da,
/// a), lo stesso di [datiManovra]: per la mappa 3D, che la disegna
/// all'altezza della strada. `null` dove la freccia non c'è.
(double, double)? trattoManovraM(Viaggio? v, Manovra? m, {double primaM = 60, double dopoM = 45}) {
  if (v == null || m == null || _senzaFreccia.contains(m.tipo) || v.percorso.punti.length < 2) return null;
  final l = Linea(v.percorso.punti);
  final centro = l.cumulate[m.inizio.clamp(0, l.punti.length - 1)];
  final fine = _fineFreccia(v, m, l, centro, dopoM);
  if (fine - centro < 5) return null;
  return (math.max(0, centro - primaM), fine);
}

/// Le corsie della prossima manovra disegnate sulla strada, nella vista
/// immersiva: negli ultimi [primaM] metri prima della manovra la linea del
/// percorso si stringe ed entra nella corsia giusta (larga quanto lei), con
/// le righe bianche tratteggiate fra una corsia e l'altra; alla manovra
/// prosegue con la freccia ([datiManovra] con `corsie`).
///
/// «Secondo te è corretto?»: prima le corsie erano un riquadro a parte
/// appoggiato sulla strada — tre strisce grigie bordate di bianco, la giusta
/// blu e stretta, di lato alla linea larga del percorso che finiva lì sotto e
/// ricominciava dopo. Adesso c'è una linea sola: quella del percorso.
///
/// Le corsie vanno da sinistra a destra e la linea corre nel mezzo della
/// carreggiata: la corsia `i` di `n` sta a `(i - (n-1)/2)` corsie dal centro
/// (a destra il segno è più, come per `line-offset`). Solo quando servono
/// ([Manovra.corsieUtili]): se vanno bene tutte non c'è niente da dire.
///
/// Gli elementi: `copertura` (lungo la linea, larga quanto il percorso, del
/// colore della strada [classe]: sotto il percorso largo non si vede più),
/// `raccordo` (la linea del percorso che si stringe e si sposta: `f` da 0 a
/// 1, `largo` le corsie giuste in metri) e `riga` (le righe, `spostamento`).
Map<String, Object?> datiCorsie(
  Viaggio? v,
  Manovra? m, {
  double primaM = 160,
  Linea? sullaMappa,
  String Function(double metri)? classe,
}) {
  final c = _corsieDi(v, m, primaM: primaM, sullaMappa: sullaMappa);
  if (c == null) return _collezione([]);
  final g = c.linea;
  final inizio = math.max(0.0, c.da - entrataCorsiaM);
  Map<String, Object?> linea(double da, double a, [double Function(double)? lato]) => {
    'type': 'LineString',
    'coordinates': [for (final p in _trattoSpostato(g, da, a, lato)) _xy(p)],
  };
  final classeCorsie = classe?.call(math.max(c.da, c.centro - 40)) ?? '';
  // La linea che entra nella corsia: a pezzi, ognuno col suo `f`.
  const pezzi = 8;
  final passo = (c.da - inizio) / pezzi;
  final fine = math.min(g.lunghezzaM, c.centro + uscitaCorsiaM);
  final uscita = (fine - c.centro) / pezzi;
  return _collezione([
    _elemento(linea(inizio, fine), {'tipo': 'copertura', 'classe': classeCorsie}),
    if (passo > 0.5)
      for (var k = 0; k < pezzi; k++)
        _elemento(linea(inizio + k * passo, inizio + (k + 1) * passo + 0.5, c.latoA), {
          'tipo': 'raccordo',
          'f': _liscio((k + 0.5) / pezzi),
          'largo': c.largo,
        }),
    _elemento(linea(c.da, c.centro, c.latoA), {'tipo': 'raccordo', 'f': 1.0, 'largo': c.largo}),
    // E dopo la manovra torna larga, nel mezzo: senza scalino.
    for (var k = 0; k < pezzi; k++)
      _elemento(linea(c.centro + k * uscita - 0.5, c.centro + (k + 1) * uscita, c.latoA), {
        'tipo': 'raccordo',
        'f': 1 - _liscio((k + 0.5) / pezzi),
        'largo': c.largo,
      }),
    for (var i = 1; i < c.n; i++)
      _elemento(linea(c.da, c.centro), {'tipo': 'riga', 'spostamento': (i - c.n / 2) * larghezzaCorsia}),
  ]);
}

/// In quanti metri, prima delle corsie, la linea del percorso entra nella corsia giusta.
const entrataCorsiaM = 40.0;

/// In quanti metri, dopo la manovra, la freccia torna dalla corsia al mezzo.
const uscitaCorsiaM = 25.0;

typedef _Corsie = ({
  Linea linea,
  double da,
  double centro,
  int n,
  double lato,
  double largo,
  double Function(double metri) latoA,
});

/// Il tratto delle corsie di [m]: da dove a dove (metri del percorso), quante
/// sono, di quanto sta a destra la corsia giusta ([lato], la media se sono
/// più di una) e quanto è larga ([largo]); [latoA]: di quanto è spostata la
/// linea a tanti metri (zero prima, [lato] dentro, morbido fra i due).
_Corsie? _corsieDi(Viaggio? v, Manovra? m, {double primaM = 160, Linea? sullaMappa}) {
  if (v == null || m == null || !m.corsieUtili || v.percorso.punti.length < 2) return null;
  final l = Linea(v.percorso.punti);
  final centro = l.cumulate[m.inizio.clamp(0, l.punti.length - 1)];
  final da = math.max(0.0, centro - primaM);
  if (centro - da < 20) return null;
  final n = m.corsie.length;
  final giuste = [
    for (var i = 0; i < n; i++)
      if (m.corsie[i].giusta) (i - (n - 1) / 2) * larghezzaCorsia,
  ];
  final lato = giuste.reduce((a, b) => a + b) / giuste.length;
  final largo = (giuste.reduce(math.max) - giuste.reduce(math.min)) + larghezzaCorsia;
  final inizio = math.max(0.0, da - entrataCorsiaM);
  double latoA(double s) {
    if (s <= inizio) return 0;
    if (s < da) return lato * _liscio((s - inizio) / (da - inizio));
    if (s <= centro) return lato;
    if (s < centro + uscitaCorsiaM) return lato * (1 - _liscio((s - centro) / uscitaCorsiaM));
    return 0;
  }

  return (
    linea: _mostrata(v.percorso, sullaMappa) ?? l,
    da: da,
    centro: centro,
    n: n,
    lato: lato,
    largo: largo,
    latoA: latoA,
  );
}

/// Da 0 a 1 senza scalini ai capi.
double _liscio(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// Il pezzo di [g] da [da] ad [a] metri, ogni tre metri, spostato a destra di
/// [lato] metri (se c'è).
List<Punto> _trattoSpostato(Linea g, double da, double a, double Function(double)? lato) {
  if (a <= da) return const [];
  final metri = <double>[da];
  for (var i = 0; i < g.punti.length; i++) {
    if (g.cumulate[i] > da && g.cumulate[i] < a) metri.add(g.cumulate[i]);
  }
  if (lato != null) {
    for (var s = da + 3; s < a; s += 3) {
      metri.add(s);
    }
  }
  metri
    ..add(a)
    ..sort();
  final out = <Punto>[];
  for (final s in metri) {
    final p = _aMetri(g, s);
    final o = lato?.call(s) ?? 0;
    if (o.abs() < 0.01) {
      out.add(p);
      continue;
    }
    // A destra del verso di marcia, misurato fra un poco prima e un poco dopo.
    final p0 = _aMetri(g, math.max(0, s - 3)), p1 = _aMetri(g, math.min(g.lunghezzaM, s + 3));
    final kx = 111195.08 * math.cos(p.lat * math.pi / 180);
    final ex = (p1.lon - p0.lon) * kx, ny = (p1.lat - p0.lat) * 111195.08;
    final lungo = math.sqrt(ex * ex + ny * ny);
    if (lungo < 0.01) {
      out.add(p);
      continue;
    }
    // La destra di (ex, ny) è (ny, -ex).
    out.add(Punto(p.lat + (-ex / lungo) * o / 111195.08, p.lon + (ny / lungo) * o / kx));
  }
  return out;
}

/// La linea [sullaMappa] se è di questo percorso (coi suoi metri: la stessa
/// lunghezza), se no `null`.
Linea? _mostrata(PercorsoCalcolato p, Linea? sullaMappa) {
  if (sullaMappa == null || sullaMappa.punti.length < 2 || p.punti.length < 2) return null;
  final l = Linea(p.punti).lunghezzaM;
  return (sullaMappa.lunghezzaM - l).abs() < 0.5 ? sullaMappa : null;
}

/// Quanto prima della manovra dopo si ferma il tratto della freccia.
const _primaDellaDopoM = 10.0;

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

/// Le colonnine intorno, col colore dello stato e la potenza.
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
        'prese': preseAdatte(c, connettori),
      },
    ),
]);

/// Tutte le colonnine dell'archivio sulla mappa. Sono decine di migliaia,
/// quindi solo quello che serve a disegnarle e a riconoscerle al tocco:
/// dove, quale, quanti kW, quante prese e — se si sa — lo stato. Il nome e
/// il resto si prendono dall'archivio quando se ne tocca una — con anche
/// quelli i dati passavano da quattro a otto megabyte. Lo stato che non si
/// sa non si scrive: la mappa lo legge come «ignota».
Map<String, Object?> datiColonnineTutte(List<Colonnina> elenco, Set<TipoConnettore> connettori) => _collezione([
  for (final c in elenco)
    _elemento(
      {'type': 'Point', 'coordinates': _xy(c.posizione)},
      {
        'id': c.id,
        'kw': c.potenzaNominalePer(connettori).round(),
        'prese': preseAdatte(c, connettori),
        if (statoDi(c.disponibilitaPer(connettori)) case final s when s != StatoColonnina.ignota) 'stato': s.name,
      },
    ),
]);

/// Quante prese di questa colonnina può usare l'auto: il numero nel bollino
/// fuori dall'icona, e quello che sommano i cerchi dei gruppi.
///
/// «Al Centro Direzionale è 1, ma sono 200 prese.» Un'icona è un posto, e un
/// posto può avere una presa o duecento: contare le icone diceva quanti
/// posti, non quante auto ci si possono attaccare.
int preseAdatte(Colonnina c, Set<TipoConnettore> connettori) =>
    c.connettori.where((p) => connettori.contains(p.tipo)).length;

/// Il riquadro che contiene tutto il percorso: sud-ovest e nord-est.
(Punto, Punto)? confini(Viaggio v, {List<PercorsoCalcolato> anche = const []}) {
  final p = [...v.percorso.punti, for (final a in anche) ...a.punti];
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

/// Il punto del percorso a tanti metri dalla partenza; `null` se il percorso
/// non ha punti (prima, lì, un errore portava via tutte le colonnine).
/// Il punto del percorso a [metri] dalla partenza (il vertice dopo).
Punto? puntoLungo(Linea l, double metri) => _lungo(l, metri);

Punto? _lungo(Linea l, double metri) {
  for (var i = 1; i < l.punti.length; i++) {
    if (l.cumulate[i] >= metri) return l.punti[i];
  }
  return l.punti.lastOrNull;
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
