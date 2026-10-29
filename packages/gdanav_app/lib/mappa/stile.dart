/// Lo stile della mappa di GdANav, chiaro e scuro, sui dati vettoriali di
/// OpenFreeMap (schema OpenMapTiles). Un solo posto per i colori della
/// mappa: lo usa l'app, e lo usano le anteprime.
///
/// Dentro ci sono anche gli strati del viaggio (percorso, colonnine, soste,
/// arrivo) con le loro sorgenti vuote: l'app ne cambia solo i dati.
library;

import 'dart:math' as math;

import 'categorie_poi.dart';

const sorgentePercorso = 'gdanav-percorso';
const sorgenteColonnine = 'gdanav-colonnine';
const sorgenteArrivo = 'gdanav-arrivo';
const sorgenteIo = 'gdanav-io';
const sorgenteSegnalazioni = 'gdanav-segnalazioni';
const sorgenteManovra = 'gdanav-manovra';

/// Le corsie della prossima manovra disegnate sulla strada (solo nella vista
/// immersiva): vedi [datiCorsie].
const sorgenteCorsie = 'gdanav-corsie';
const sorgenteDistributori = 'gdanav-distributori';
const sorgenteVicine = 'gdanav-vicine';
const sorgenteTutte = 'gdanav-tutte';
const sorgenteCode = 'gdanav-code';
const sorgenteAlternative = 'gdanav-alternative';
const sorgenteTappe = 'gdanav-tappe';

/// Le persone di casa, quando GdANav sta dentro GdAHome (`GestorePersone`).
const sorgentePersone = 'gdanav-persone';

/// Le ZTL e le aree pedonali intorno (i contorni e, come punti, dove
/// scriverne il nome), e la strada che passerebbe dentro la ZTL di cui si
/// chiede il permesso.
const sorgenteZtl = 'gdanav-ztl';
const sorgentePassandoci = 'gdanav-passandoci';

/// La strada a risparmio (o più rapida) proposta in guida, col suo fumetto.
const sorgenteRisparmio = 'gdanav-risparmio';

/// I disegni che riempiono le zone: le righe rosse della ZTL e i puntini
/// grigi dell'area pedonale (vedi `iconePunti`).
const motivoZtl = 'ztl-righe';
const motivoPedonale = 'pedonale-puntini';

/// Solo sull'auto: il punto della scheda aperta sopra la mappa. I dati li
/// mette lo schermo dell'auto (`RendererMappa.mostra`), non il telefono.
const sorgenteEvidenza = 'gdanav-evidenza';
const stratoTraffico = 'traffico';
const stratoTrafficoLocale = 'traffico-locale';
const stratiToccabili = [
  'persone',
  'alternative-etichetta',
  'alternative',
  'gdanav-soste',
  'gdanav-colonnine',
  'gdanav-distributori',
  'gdanav-vicine',
  'gdanav-tutte-gruppi',
  'gdanav-tutte',
  'nomi-poi',
];

/// Dall'alto gli edifici sono piatti e puliti; inclinando la mappa si
/// accendono quelli in 3D e si spengono i piatti.
const stratoEdifici2d = 'edifici';
const stratoEdifici3d = 'edifici-3d';

/// Gli edifici della vista immersiva: in 3D come [stratoEdifici3d], ma sopra il
/// percorso e un po' trasparenti, così la linea passa fra le case e non sopra
/// i tetti, e dietro l'angolo si intravede.
const stratoEdificiImmersivi = 'edifici-immersivi';

class _Tavolozza {
  const _Tavolozza({
    required this.sfondo,
    required this.abitato,
    required this.industria,
    required this.prato,
    required this.bosco,
    required this.acqua,
    required this.edificio,
    required this.edificioLato,
    required this.edificioBordo,
    required this.autostrada,
    required this.autostradaBordo,
    required this.principale,
    required this.principaleBordo,
    required this.strada,
    required this.stradaBordo,
    required this.sentiero,
    required this.ferrovia,
    required this.etichetta,
    required this.etichettaAlone,
    required this.luogo,
    required this.poi,
    required this.percorso,
    required this.percorsoBordo,
    required this.alternativa,
    required this.alternativaBordo,
    required this.contorno,
    required this.libera,
    required this.piena,
    required this.guasta,
    required this.ignota,
    required this.arrivo,
  });

  final String sfondo, abitato, industria, prato, bosco, acqua, edificio, edificioLato, edificioBordo;
  final String autostrada, autostradaBordo, principale, principaleBordo, strada, stradaBordo, sentiero, ferrovia;
  final String etichetta, etichettaAlone, luogo, poi;
  final String percorso, percorsoBordo, contorno;

  /// Le strade alternative: grigio-azzurre, dietro al percorso.
  final String alternativa, alternativaBordo;
  final String libera, piena, guasta, ignota, arrivo;
}

// I colori di Waze: fondo quasi bianco, strade tutte grigie col bordo più
// scuro, nomi in grigio carbone e città in blu. Il colore lo prendono solo
// il percorso, il traffico e le colonnine.
const _chiaro = _Tavolozza(
  sfondo: '#F6F7F8',
  abitato: '#F1F2F4',
  industria: '#E4E6EA',
  prato: '#D4EDCB',
  bosco: '#C6E5BA',
  acqua: '#A9D7F6',
  edificio: '#E3E5E9',
  edificioLato: '#CDD1D7',
  edificioBordo: '#D3D7DC',
  autostrada: '#C3C9D0',
  autostradaBordo: '#98A1AB',
  principale: '#CDD2D8',
  principaleBordo: '#A6AEB7',
  strada: '#DCDFE3',
  stradaBordo: '#B8BEC5',
  sentiero: '#CBD0D6',
  ferrovia: '#B4BAC2',
  etichetta: '#3E434A',
  etichettaAlone: '#FFFFFF',
  luogo: '#4F74A3',
  poi: '#8A919A',
  percorso: '#27A2F8',
  percorsoBordo: '#0A6CC2',
  alternativa: '#A9C7E3',
  alternativaBordo: '#6F93B8',
  contorno: '#FFFFFF',
  libera: '#16A34A',
  piena: '#D97706',
  guasta: '#DC2626',
  ignota: '#4F46E5',
  arrivo: '#E5484D',
);

// La notte di Waze: blu notte, strade grigio ardesia, nomi chiari.
//
// Dal campo: «appena tramontato il sole è troppo scura, non si vede bene la
// strada». Il fondo era quasi nero e le strade poco più chiare: adesso il
// fondo è un blu ardesia più chiaro, e le strade spiccano di più (più chiare,
// col bordo scuro), come le notti di TomTom e Maps.
const _scuro = _Tavolozza(
  sfondo: '#28324A',
  abitato: '#2D3850',
  industria: '#333E57',
  prato: '#26413A',
  bosco: '#233D34',
  acqua: '#22496F',
  edificio: '#36415A',
  edificioLato: '#4A5672',
  edificioBordo: '#3F4A63',
  autostrada: '#8592AD',
  autostradaBordo: '#1A2132',
  principale: '#73809B',
  principaleBordo: '#1A2132',
  strada: '#5F6B84',
  stradaBordo: '#1E2537',
  sentiero: '#56617A',
  ferrovia: '#56617A',
  etichetta: '#E8ECF2',
  etichettaAlone: '#28324A',
  luogo: '#A5C6F0',
  poi: '#97A1B3',
  percorso: '#3AB0FF',
  percorsoBordo: '#0B5AA6',
  alternativa: '#5D7C9B',
  alternativaBordo: '#2E4459',
  contorno: '#141A28',
  libera: '#4ADE80',
  piena: '#FBBF24',
  guasta: '#F87171',
  ignota: '#818CF8',
  arrivo: '#F87171',
);

/// [verde] per la strada che risparmia energia (`eco` nelle proprietà),
/// [altro] per le altre.
List<Object> _seEco(String verde, String altro) => [
  'case',
  [
    '==',
    ['get', 'eco'],
    true,
  ],
  verde,
  altro,
];

/// Le larghezze del percorso a zoom 12 e a zoom 18: il bordo, la linea
/// celeste e, dentro, la striscia della coda (vedi lo stile del percorso).
/* «Se c'è il rosso, la linea celeste all'esterno deve essere ancora un po'
 * più larga: si deve vedere.» Il celeste ai lati della coda era 1,25 px per
 * parte a zoom 12 e 3,5 a zoom 18: adesso 2,25 e 7. */
const larghezzaBordo = (12.0, 35.0);
const larghezzaPercorso = (9.5, 29.0);
const larghezzaCoda = (5.0, 15.0);

/// L'icona della punta della freccia di manovra, e quanto è larga (in punti)
/// a grandezza 1: la disegna `puntaManovraPng`.
const immaginePuntaManovra = 'manovra-punta';
const larghezzaPuntaManovra = 48.0;

/// La bandiera a scacchi sulla meta, e quanto è larga (in punti) a
/// grandezza 1: la disegna `bandieraArrivoPng`.
const immagineBandieraArrivo = 'arrivo-bandiera';
const larghezzaBandieraArrivo = 48.0;

/// Larghezza che cresce con lo zoom, come fanno le strade vere.
List<Object> _largo(double a12, double a18) => [
  'interpolate',
  ['exponential', 1.6],
  ['zoom'],
  12,
  a12,
  18,
  a18,
];

Map<String, Object> _strada(String id, List<Object> filtro, String colore, List<Object> larghezza, {double? minzoom}) =>
    {
      'id': id,
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'filter': filtro,
      'minzoom': ?minzoom,
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {'line-color': colore, 'line-width': larghezza},
    };

/// Come si dipingono gli edifici in 3D: il colore sale con l'altezza, e
/// crescono da terra fra lo zoom 14 e il 15,5.
Map<String, Object> _pitturaEdifici(_Tavolozza t) => {
  'fill-extrusion-color': [
    'interpolate',
    ['linear'],
    ['get', 'render_height'],
    0,
    t.edificio,
    60,
    t.edificioLato,
  ],
  'fill-extrusion-height': [
    'interpolate',
    ['linear'],
    ['zoom'],
    14,
    0,
    15.5,
    ['get', 'render_height'],
  ],
  'fill-extrusion-base': [
    'coalesce',
    ['get', 'render_min_height'],
    0,
  ],
};

const _vuota = {'type': 'FeatureCollection', 'features': <Object>[]};

/// I contorni di un tipo di zona («ztl», «pedonale») nella [sorgenteZtl].
List<Object> _zona(String tipo) => [
  'all',
  [
    '==',
    ['geometry-type'],
    'Polygon',
  ],
  [
    '==',
    ['get', 'tipo'],
    tipo,
  ],
];

/// Lo stile completo. [scuro] per la sera; le sorgenti del viaggio partono
/// vuote.
///
/// Con [chiaveTraffico] (una chiave gratuita di TomTom) sulle strade si
/// vedono le code, come in Waze: solo dove si va più piano del solito, e
/// gli incidenti e i lavori.
/* ─── La vista immersiva ─────────────────────────────────────────────────
 *
 * Nella vista immersiva le strade sono larghe quanto sono davvero, in metri
 * e non in pixel: da vicino e inclinata, una strada in pixel resta sottile
 * come vista dall'alto, e le corsie disegnate sopra (3,5 m l'una) ne
 * uscirebbero. In Italia il coseno della latitudine sta fra 0,73 e 0,81: si
 * prende 0,77, e l'errore resta sotto il 6%. */
const _cosenoItalia = 0.77;

/// Quale tratto della freccia di manovra disegnare: nella vista immersiva
/// quello che parte dalla corsia giusta, se c'è (vedi `datiManovra`); nelle
/// altre quello sulla linea del percorso, dove le corsie non si disegnano.
List<Object> _filtroFrecciaManovra(bool immersiva) => [
  'all',
  [
    '==',
    ['geometry-type'],
    'LineString',
  ],
  if (immersiva)
    [
      '!',
      [
        'to-boolean',
        ['get', 'sostituibile'],
      ],
    ]
  else
    [
      '!=',
      ['get', 'vista'],
      'immersiva',
    ],
];

/// Quanti pixel fa un metro allo zoom [z].
double pixelPerMetro(double z) => 512 * math.pow(2, z) / (40075016.686 * _cosenoItalia);

/// Una larghezza di [metri] metri a ogni zoom.
List<Object> _metri(double metri) => [
  'interpolate',
  ['exponential', 2],
  ['zoom'],
  12,
  metri * pixelPerMetro(12),
  22,
  metri * pixelPerMetro(22),
];

/// Uno spostamento in metri preso dalla proprietà [chiave] di ogni elemento.
List<Object> _metriDa(String chiave) => [
  'interpolate',
  ['exponential', 2],
  ['zoom'],
  12,
  [
    '*',
    ['get', chiave],
    pixelPerMetro(12),
  ],
  22,
  [
    '*',
    ['get', chiave],
    pixelPerMetro(22),
  ],
];

/// Le larghezze vere delle strade, in metri: una carreggiata di autostrada
/// ha tre o quattro corsie (14 m), una strada di città due (7 m).
const larghezzeVere = {
  'servizio-bordo': 5.0,
  'strade-bordo': 8.2,
  'principali-bordo': 11.5,
  'autostrade-bordo': 15.5,
  'servizio': 4.0,
  'strade': 7.0,
  'principali': 10.0,
  'autostrade': 14.0,
};

/// La larghezza di una corsia, in metri.
const larghezzaCorsia = 3.5;

/// [immersiva]: la vista immersiva (strade in metri, edifici sopra il
/// percorso, corsie sulla strada). Si sceglie col tasto 2D · 3D · Immersiva.
Map<String, Object> stileMappa({
  required bool scuro,
  String chiaveTraffico = '',
  bool perAuto = false,
  bool immersiva = false,
}) {
  final traffico = chiaveTraffico.trim();
  final t = scuro ? _scuro : _chiaro;
  final classi = {
    'autostrada': [
      'match',
      ['get', 'class'],
      ['motorway', 'trunk'],
      true,
      false,
    ],
    'principale': [
      'match',
      ['get', 'class'],
      ['primary', 'secondary'],
      true,
      false,
    ],
    'strada': [
      'match',
      ['get', 'class'],
      ['tertiary', 'minor'],
      true,
      false,
    ],
    'servizio': [
      '==',
      ['get', 'class'],
      'service',
    ],
    'sentiero': [
      'match',
      ['get', 'class'],
      ['path', 'track'],
      true,
      false,
    ],
    'ferrovia': [
      '==',
      ['get', 'class'],
      'rail',
    ],
  };
  final statoColore = [
    'match',
    ['get', 'stato'],
    'libera',
    t.libera,
    'piena',
    t.piena,
    'guasta',
    t.guasta,
    t.ignota,
  ];
  return {
    'version': 8,
    'name': scuro ? 'gdanav scuro' : 'gdanav chiaro',
    'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
    // La luce che dà volume agli edifici in 3D: da sud-ovest, morbida.
    'light': {
      'anchor': 'viewport',
      'color': '#FFFFFF',
      'intensity': scuro ? 0.25 : 0.32,
      'position': [1.2, 200, 35],
    },
    'sources': {
      'openmaptiles': {'type': 'vector', 'url': 'https://tiles.openfreemap.org/planet'},
      sorgentePercorso: {'type': 'geojson', 'data': _vuota},
      sorgenteCode: {'type': 'geojson', 'data': _vuota},
      sorgenteAlternative: {'type': 'geojson', 'data': _vuota},
      sorgenteTappe: {'type': 'geojson', 'data': _vuota},
      sorgenteZtl: {'type': 'geojson', 'data': _vuota},
      sorgentePassandoci: {'type': 'geojson', 'data': _vuota},
      sorgenteRisparmio: {'type': 'geojson', 'data': _vuota},
      sorgenteColonnine: {'type': 'geojson', 'data': _vuota},
      sorgenteArrivo: {'type': 'geojson', 'data': _vuota},
      sorgenteIo: {'type': 'geojson', 'data': _vuota},
      sorgenteSegnalazioni: {'type': 'geojson', 'data': _vuota},
      sorgenteManovra: {'type': 'geojson', 'data': _vuota},
      sorgenteCorsie: {'type': 'geojson', 'data': _vuota},
      sorgenteDistributori: {'type': 'geojson', 'data': _vuota},
      sorgenteVicine: {'type': 'geojson', 'data': _vuota},
      sorgentePersone: {'type': 'geojson', 'data': _vuota},
      if (perAuto) sorgenteEvidenza: {'type': 'geojson', 'data': _vuota},
      // Raggruppate da MapLibre: da lontano un cerchio col numero, da vicino
      // una per una. Il numero del cerchio sono le prese, sommate dentro il
      // gruppo, non le colonnine.
      sorgenteTutte: {
        'type': 'geojson',
        'data': _vuota,
        'cluster': true,
        'clusterRadius': 50,
        'clusterMaxZoom': 12,
        'clusterProperties': {
          'prese': [
            '+',
            ['get', 'prese'],
          ],
        },
      },
      if (traffico.isNotEmpty)
        'traffico': {
          'type': 'vector',
          'maxzoom': 22,
          'attribution': '© TomTom',
          'tiles': [
            'https://api.tomtom.com/traffic/map/4/tile/flow/relative/{z}/{x}/{y}.pbf'
                '?key=${Uri.encodeQueryComponent(traffico)}',
          ],
        },
    },
    'layers': [
      {
        'id': 'sfondo',
        'type': 'background',
        'paint': {'background-color': t.sfondo},
      },
      {
        'id': 'abitato',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          'match',
          ['get', 'class'],
          ['residential', 'suburb', 'neighbourhood', 'commercial', 'retail'],
          true,
          false,
        ],
        'paint': {'fill-color': t.abitato},
      },
      {
        'id': 'industria',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          'match',
          ['get', 'class'],
          ['industrial', 'railway', 'garages', 'military', 'hospital', 'school', 'university'],
          true,
          false,
        ],
        'paint': {'fill-color': t.industria},
      },
      {
        'id': 'bosco',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'filter': [
          '==',
          ['get', 'class'],
          'wood',
        ],
        'paint': {'fill-color': t.bosco},
      },
      {
        'id': 'prato',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'filter': [
          'match',
          ['get', 'class'],
          ['grass', 'farmland'],
          true,
          false,
        ],
        'paint': {'fill-color': t.prato, 'fill-opacity': 0.8},
      },
      {
        'id': 'parco',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'park',
        'paint': {'fill-color': t.prato},
      },
      {
        'id': 'acqua',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'water',
        'paint': {'fill-color': t.acqua},
      },
      {
        'id': 'corsi-acqua',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'waterway',
        'paint': {'line-color': t.acqua, 'line-width': _largo(1, 8)},
      },
      _strada('sentieri', classi['sentiero']!, t.sentiero, _largo(0.4, 2), minzoom: 14),
      _strada('ferrovie', classi['ferrovia']!, t.ferrovia, _largo(0.8, 3)),
      // Prima tutti i bordi, poi tutti i riempimenti: gli incroci restano puliti.
      _strada(
        'servizio-bordo',
        classi['servizio']!,
        t.stradaBordo,
        immersiva ? _metri(larghezzeVere['servizio-bordo']!) : _largo(1.2, 12),
        minzoom: 14,
      ),
      _strada(
        'strade-bordo',
        classi['strada']!,
        t.stradaBordo,
        immersiva ? _metri(larghezzeVere['strade-bordo']!) : _largo(2.4, 24),
      ),
      _strada(
        'principali-bordo',
        classi['principale']!,
        t.principaleBordo,
        immersiva ? _metri(larghezzeVere['principali-bordo']!) : _largo(3.6, 32),
      ),
      _strada(
        'autostrade-bordo',
        classi['autostrada']!,
        t.autostradaBordo,
        immersiva ? _metri(larghezzeVere['autostrade-bordo']!) : _largo(4.6, 38),
      ),
      _strada(
        'servizio',
        classi['servizio']!,
        t.strada,
        immersiva ? _metri(larghezzeVere['servizio']!) : _largo(0.6, 9),
        minzoom: 14,
      ),
      _strada('strade', classi['strada']!, t.strada, immersiva ? _metri(larghezzeVere['strade']!) : _largo(1.6, 20)),
      _strada(
        'principali',
        classi['principale']!,
        t.principale,
        immersiva ? _metri(larghezzeVere['principali']!) : _largo(2.6, 27),
      ),
      _strada(
        'autostrade',
        classi['autostrada']!,
        t.autostrada,
        immersiva ? _metri(larghezzeVere['autostrade']!) : _largo(3.4, 32),
      ),
      // Il traffico come in Waze: solo dove si rallenta, arancio se lento e
      // rosso se quasi fermi; da lontano solo sulle strade principali.
      // Sull'auto più spesse: lo schermo si guarda da un braccio di
      // distanza, di sfuggita, e la mappa è sempre vicina.
      if (traffico.isNotEmpty) ...[
        _coda(stratoTraffico, principali: true, minzoom: 7, spessore: perAuto ? 1.6 : 1),
        _coda(stratoTrafficoLocale, principali: false, minzoom: 13, spessore: perAuto ? 1.6 : 1),
      ],
      {
        'id': stratoEdifici2d,
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'building',
        'minzoom': 14,
        'paint': {'fill-color': t.edificio, 'fill-outline-color': t.edificioBordo},
      },
      {
        'id': stratoEdifici3d,
        'type': 'fill-extrusion',
        'source': 'openmaptiles',
        'source-layer': 'building',
        'minzoom': 14,
        'layout': {'visibility': 'none'},
        'paint': {..._pitturaEdifici(t), 'fill-extrusion-opacity': 0.94},
      },
      // Le ZTL e le aree pedonali (OpenStreetMap), sopra le strade e sotto i
      // loro nomi: la ZTL tratteggiata di rosso, più tenue quando è spenta;
      // l'area pedonale a puntini grigi.
      {
        'id': 'pedonali',
        'type': 'fill',
        'source': sorgenteZtl,
        'minzoom': 13,
        'filter': _zona('pedonale'),
        'paint': {'fill-pattern': motivoPedonale},
      },
      {
        'id': 'pedonali-bordo',
        'type': 'line',
        'source': sorgenteZtl,
        'minzoom': 13,
        'filter': _zona('pedonale'),
        'layout': {'line-join': 'round'},
        'paint': {'line-color': '#6B7280', 'line-width': 1.5, 'line-opacity': 0.8},
      },
      {
        'id': 'ztl',
        'type': 'fill',
        'source': sorgenteZtl,
        'minzoom': 10,
        'filter': _zona('ztl'),
        'paint': {
          'fill-pattern': motivoZtl,
          'fill-opacity': [
            'case',
            ['get', 'attiva'],
            1.0,
            0.4,
          ],
        },
      },
      {
        'id': 'ztl-bordo',
        'type': 'line',
        'source': sorgenteZtl,
        'minzoom': 10,
        'filter': _zona('ztl'),
        'layout': {'line-join': 'round'},
        'paint': {
          'line-color': '#DC2626',
          'line-width': perAuto ? 3.5 : 2.5,
          'line-dasharray': [3, 1.7],
          'line-opacity': [
            'case',
            ['get', 'attiva'],
            1.0,
            0.45,
          ],
        },
      },
      {
        'id': 'nomi-strade',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'transportation_name',
        'minzoom': 13,
        'layout': {
          'symbol-placement': 'line',
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Bold'],
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            13,
            11,
            16,
            13.5,
            19,
            16,
          ],
          'text-max-angle': 30,
          'text-padding': 8,
        },
        'paint': {'text-color': t.etichetta, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 2},
      },
      // I punti di interesse come in Google Maps: il bollino colorato della
      // categoria col simbolo, e il nome dello stesso colore accanto.
      {
        'id': 'nomi-poi',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'poi',
        'minzoom': 14.5,
        'filter': [
          '<=',
          [
            'coalesce',
            ['get', 'rank'],
            99,
          ],
          // Sull'auto meno punti: chi guida vede solo i più importanti.
          perAuto
              ? [
                  'step',
                  ['zoom'],
                  8,
                  16,
                  14,
                  17,
                  20,
                  18,
                  40,
                ]
              : [
                  'step',
                  ['zoom'],
                  6,
                  15.5,
                  14,
                  16.5,
                  30,
                  17.5,
                  99,
                ],
        ],
        'layout': {
          'icon-image': esprPoi((c) => c.immagine),
          'icon-size': 0.62,
          'icon-allow-overlap': false,
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Regular'],
          'text-size': 11.5,
          'text-max-width': 8,
          'text-variable-anchor': ['left', 'right', 'top', 'bottom'],
          'text-radial-offset': 1.0,
          'text-justify': 'auto',
          'text-optional': true,
          'text-padding': 3,
        },
        'paint': {
          'text-color': scuro ? t.poi : esprPoi((c) => c.colore),
          'text-halo-color': t.etichettaAlone,
          'text-halo-width': 1.5,
        },
      },
      // Le strade alternative, sotto il percorso: grigio-azzurre, toccandole
      // si sceglie quella. Quella che risparmia energia è verde.
      {
        'id': 'alternative-bordo',
        'type': 'line',
        'source': sorgenteAlternative,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': _seEco('#166534', t.alternativaBordo), 'line-width': _largo(7.5, 20)},
      },
      {
        'id': 'alternative',
        'type': 'line',
        'source': sorgenteAlternative,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': _seEco('#4ADE80', t.alternativa), 'line-width': _largo(5, 15)},
      },
      // La strada che passa dentro la ZTL di cui si chiede il permesso: a
      // puntini grigi, sotto il percorso.
      {
        'id': 'passandoci',
        'type': 'line',
        'source': sorgentePassandoci,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#94A3B8',
          'line-width': _largo(5, 12),
          'line-dasharray': [0.1, 1.8],
        },
      },
      // La strada a risparmio proposta in guida: verde, sotto il percorso,
      // così si vede dove se ne stacca.
      {
        'id': 'risparmio-bordo',
        'type': 'line',
        'source': sorgenteRisparmio,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': '#166534', 'line-width': _largo(8.5, 24)},
      },
      {
        'id': 'risparmio',
        'type': 'line',
        'source': sorgenteRisparmio,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': '#4ADE80', 'line-width': _largo(5.5, 18)},
      },
      /* Il percorso: un alone morbido, il bordo blu scuro, la linea celeste e
       * le frecce della direzione. Sempre blu: nessuna strada ha quel colore.
       *
       * Col traffico, come in Waze: la coda è una striscia DENTRO la linea,
       * più stretta e in mezzo, e ai lati resta il celeste. Prima la coda
       * era larga quanto la linea e ci si posava sopra: nei tratti in coda il
       * percorso spariva, e una strada rossa sulla mappa non diceva più se
       * era la propria o una qualunque. Per questo la linea è un po' più
       * larga di prima ([larghezzaPercorso]) e la coda circa la metà
       * ([larghezzaCoda]): «la linea del percorso è leggermente più larga,
       * quindi si vede al centro striscia rossa e ai lati striscia celeste».
       * Il celeste è un bordo, non una seconda strada accanto al rosso. */
      {
        'id': 'percorso-alone',
        'type': 'line',
        'source': sorgentePercorso,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': t.percorso, 'line-width': _largo(18, 46), 'line-blur': 10, 'line-opacity': 0.22},
      },
      {
        'id': 'percorso-bordo',
        'type': 'line',
        'source': sorgentePercorso,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': t.percorsoBordo, 'line-width': _largo(larghezzaBordo.$1, larghezzaBordo.$2)},
      },
      {
        'id': 'percorso',
        'type': 'line',
        'source': sorgentePercorso,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': t.percorso, 'line-width': _largo(larghezzaPercorso.$1, larghezzaPercorso.$2)},
      },
      // Le code di adesso dentro il percorso: dal giallo (rallenta) al rosso
      // (fermo), bordeaux se è chiusa. Sopra la linea, sotto le frecce.
      {
        'id': 'code',
        'type': 'line',
        'source': sorgenteCode,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': [
            'match',
            ['get', 'livello'],
            1,
            '#F9A825',
            2,
            '#EF6C00',
            3,
            '#D32F2F',
            '#7B1F1F',
          ],
          'line-width': _largo(larghezzaCoda.$1, larghezzaCoda.$2),
        },
      },
      {
        'id': 'percorso-frecce',
        'type': 'symbol',
        'source': sorgentePercorso,
        'minzoom': 13,
        'layout': {
          'symbol-placement': 'line',
          'symbol-spacing': 110,
          'text-field': '›',
          'text-font': ['Noto Sans Bold'],
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            14,
            18,
            26,
          ],
          'text-keep-upright': false,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
          'text-offset': [0, -0.1],
        },
        'paint': {'text-color': '#FFFFFF', 'text-opacity': 0.9},
      },
      // La freccia della prossima manovra, sopra il percorso: bianca col
      // bordo blu scuro, larga quanto la linea del percorso (in pixel, come
      // lei: in metri a zoom alto era il doppio e sbordava), così allo
      // svincolo si vede esattamente la rampa da prendere. La punta è
      // un'icona ([immaginePuntaManovra]) posata sulla fine del tratto.
      {
        'id': 'manovra-bordo',
        'type': 'line',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': _filtroFrecciaManovra(immersiva),
        'layout': {'line-cap': 'butt', 'line-join': 'round'},
        // Nella vista immersiva larga quanto una corsia, in metri come le
        // strade: in pixel, da vicino, sbordava dalla corsia giusta.
        'paint': {
          'line-color': '#0B3C78',
          'line-width': immersiva ? _metri(larghezzaCorsia * 0.94) : _largo(larghezzaBordo.$1, larghezzaBordo.$2),
        },
      },
      {
        'id': 'manovra',
        'type': 'line',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': _filtroFrecciaManovra(immersiva),
        'layout': {'line-cap': 'butt', 'line-join': 'round'},
        'paint': {
          'line-color': '#FFFFFF',
          'line-width': immersiva
              ? _metri(larghezzaCorsia * 0.6)
              : _largo(larghezzaPercorso.$1 * 0.75, larghezzaPercorso.$2 * 0.75),
        },
      },
      {
        'id': 'manovra-punta',
        'type': 'symbol',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': [
          '==',
          ['geometry-type'],
          'Point',
        ],
        'layout': {
          'icon-image': immaginePuntaManovra,
          'icon-rotate': ['get', 'rotta'],
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          // La base della punta sulla fine del tratto: la punta va avanti.
          'icon-anchor': 'bottom',
          // Larga poco più del doppio della linea, a ogni zoom (l'icona è
          // larga [larghezzaPuntaManovra] a grandezza 1).
          'icon-size': _largo(
            larghezzaPercorso.$1 * 2.2 / larghezzaPuntaManovra,
            larghezzaPercorso.$2 * 2.2 / larghezzaPuntaManovra,
          ),
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
      /* La vista immersiva: le corsie della prossima manovra sulla strada
       * (quella giusta del colore del percorso, le altre grigie, le righe
       * bianche), sopra la freccia della manovra: prima dello svincolo la
       * strada la dicono le corsie, dopo la freccia. Poi gli edifici, sopra
       * il percorso e un po' trasparenti; i segnaposto restano sopra tutto. */
      if (immersiva) ...[
        {
          'id': 'corsie',
          'type': 'line',
          'source': sorgenteCorsie,
          'filter': [
            '==',
            ['get', 'tipo'],
            'corsia',
          ],
          'layout': {'line-cap': 'butt', 'line-join': 'round'},
          'paint': {
            // Piene: sotto ci sono la linea del percorso e il grigio della
            // strada, e una corsia trasparente li lascerebbe vedere.
            'line-color': [
              'case',
              ['get', 'giusta'],
              t.percorso,
              t.strada,
            ],
            'line-width': _metri(larghezzaCorsia * 0.94),
            'line-offset': _metriDa('spostamento'),
          },
        },
        {
          'id': 'corsie-righe',
          'type': 'line',
          'source': sorgenteCorsie,
          'filter': [
            '==',
            ['get', 'tipo'],
            'riga',
          ],
          'layout': {'line-cap': 'butt', 'line-join': 'round'},
          'paint': {
            'line-color': '#FFFFFF',
            'line-opacity': 0.9,
            'line-width': _metri(0.2),
            'line-dasharray': [3, 3],
            'line-offset': _metriDa('spostamento'),
          },
        },
        {
          'id': 'corsie-bordi',
          'type': 'line',
          'source': sorgenteCorsie,
          'filter': [
            '==',
            ['get', 'tipo'],
            'bordo',
          ],
          'layout': {'line-cap': 'butt', 'line-join': 'round'},
          'paint': {
            'line-color': '#FFFFFF',
            'line-opacity': 0.9,
            'line-width': _metri(0.25),
            'line-offset': _metriDa('spostamento'),
          },
        },
        {
          'id': stratoEdificiImmersivi,
          'type': 'fill-extrusion',
          'source': 'openmaptiles',
          'source-layer': 'building',
          'minzoom': 14,
          'paint': {..._pitturaEdifici(t), 'fill-extrusion-opacity': 0.6},
        },
      ],
      // Sull'auto, il punto della scheda aperta: un alone e un anello del
      // colore del suo stato, sotto la sua icona.
      if (perAuto) ...[
        {
          'id': 'evidenza-alone',
          'type': 'circle',
          'source': sorgenteEvidenza,
          'paint': {'circle-radius': 34, 'circle-color': _coloreEvidenza(t), 'circle-opacity': 0.2},
        },
        {
          'id': 'evidenza',
          'type': 'circle',
          'source': sorgenteEvidenza,
          'paint': {
            'circle-radius': 23,
            'circle-opacity': 0,
            'circle-stroke-color': _coloreEvidenza(t),
            'circle-stroke-width': 4,
          },
        },
      ],
      // Tutte le colonnine d'Italia, dall'archivio: da lontano in gruppi col
      // numero, avvicinandosi una per una. Sotto quelle intorno a te, che
      // hanno il colore dello stato di adesso.
      {
        'id': 'gdanav-tutte-gruppi',
        'type': 'circle',
        'source': sorgenteTutte,
        'filter': ['has', 'point_count'],
        'paint': {
          'circle-color': '#4F46E5',
          'circle-opacity': 0.92,
          'circle-radius': [
            'step',
            ['get', 'prese'],
            14,
            100,
            18,
            1000,
            23,
            10000,
            28,
          ],
          'circle-stroke-width': 2,
          'circle-stroke-color': '#FFFFFF',
        },
      },
      {
        'id': 'gdanav-tutte-numeri',
        'type': 'symbol',
        'source': sorgenteTutte,
        'filter': ['has', 'point_count'],
        'layout': {
          'text-field': _numeroCorto(['get', 'prese']),
          'text-font': ['Noto Sans Bold'],
          'text-size': 12,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': '#FFFFFF'},
      },
      {
        'id': 'gdanav-tutte',
        'type': 'symbol',
        'source': sorgenteTutte,
        'filter': [
          '!',
          ['has', 'point_count'],
        ],
        'layout': {
          // Col colore dello stato di tutta Italia, quando si sa.
          'icon-image': ['concat', 'punto-colonnina-', _statoOIgnota()],
          'icon-size': 0.8,
          'icon-allow-overlap': true,
          'text-field': [
            'step',
            ['zoom'],
            '',
            13,
            [
              'concat',
              [
                'to-string',
                ['get', 'kw'],
              ],
              ' kW',
            ],
          ],
          'text-font': ['Noto Sans Bold'],
          'text-size': 11,
          'text-anchor': 'top',
          'text-offset': [0, 1.1],
          'text-optional': true,
        },
        'paint': {'text-color': t.etichetta, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 1.6},
      },
      ..._bollinoPrese('gdanav-tutte', sorgenteTutte, _coloreDelloStato(_statoOIgnota()), sfusa: true),
      // Intorno a te: i distributori col prezzo (auto termica) o le
      // colonnine col colore dello stato (auto elettrica).
      {
        'id': 'gdanav-vicine',
        'type': 'symbol',
        'source': sorgenteVicine,
        'minzoom': 10,
        'layout': {
          'icon-image': [
            'concat',
            'punto-colonnina-',
            ['get', 'stato'],
          ],
          'icon-size': 0.8,
          'icon-allow-overlap': true,
          'text-field': [
            'step',
            ['zoom'],
            '',
            13,
            ['get', 'etichetta'],
          ],
          'text-font': ['Noto Sans Bold'],
          'text-size': 11,
          'text-anchor': 'top',
          'text-offset': [0, 1.1],
          'text-optional': true,
        },
        'paint': {'text-color': t.etichetta, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 1.6},
      },
      ..._bollinoPrese('gdanav-vicine', sorgenteVicine, _coloreDelloStato(['get', 'stato']), minzoom: 10),
      {
        'id': 'gdanav-distributori',
        'type': 'symbol',
        'source': sorgenteDistributori,
        'minzoom': 10,
        'layout': {
          'icon-image': 'punto-distributore',
          'icon-size': 0.8,
          'icon-allow-overlap': true,
          'text-field': [
            'step',
            ['zoom'],
            '',
            12.5,
            ['get', 'etichetta'],
          ],
          'text-font': ['Noto Sans Bold'],
          'text-size': 11.5,
          'text-anchor': 'top',
          'text-offset': [0, 1.1],
          'text-optional': true,
        },
        'paint': {'text-color': t.etichetta, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 1.6},
      },
      {
        'id': 'gdanav-colonnine',
        'type': 'circle',
        'source': sorgenteColonnine,
        'filter': [
          '!',
          ['get', 'sosta'],
        ],
        'paint': {
          'circle-radius': 6.5,
          'circle-color': statoColore,
          'circle-stroke-color': t.contorno,
          'circle-stroke-width': 2,
        },
      },
      {
        'id': 'gdanav-soste',
        'type': 'circle',
        'source': sorgenteColonnine,
        'filter': ['get', 'sosta'],
        'paint': {
          'circle-radius': 14,
          'circle-color': statoColore,
          'circle-stroke-color': t.contorno,
          'circle-stroke-width': 3,
        },
      },
      {
        'id': 'gdanav-soste-numero',
        'type': 'symbol',
        'source': sorgenteColonnine,
        'filter': ['get', 'sosta'],
        'layout': {
          'text-field': [
            'to-string',
            ['get', 'numero'],
          ],
          'text-font': ['Noto Sans Bold'],
          'text-size': 14,
          'text-allow-overlap': true,
        },
        'paint': {'text-color': '#FFFFFF'},
      },
      // Le tappe: un cerchio bianco col numero, bordo blu.
      {
        'id': 'tappe',
        'type': 'circle',
        'source': sorgenteTappe,
        'paint': {
          'circle-radius': 12,
          'circle-color': '#FFFFFF',
          'circle-stroke-color': t.percorsoBordo,
          'circle-stroke-width': 3.5,
        },
      },
      {
        'id': 'tappe-numeri',
        'type': 'symbol',
        'source': sorgenteTappe,
        'layout': {
          'text-field': [
            'to-string',
            ['get', 'numero'],
          ],
          'text-font': ['Noto Sans Bold'],
          'text-size': 13,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': t.percorsoBordo},
      },
      // Il nome della ZTL col suo stato, «ZTL · attiva fino alle 18»; più
      // da vicino anche «Area pedonale».
      {
        'id': 'ztl-etichetta',
        'type': 'symbol',
        'source': sorgenteZtl,
        'minzoom': 12,
        'filter': [
          'all',
          [
            '==',
            ['geometry-type'],
            'Point',
          ],
          [
            'any',
            [
              '==',
              ['get', 'tipo'],
              'ztl',
            ],
            [
              '>=',
              ['zoom'],
              16,
            ],
          ],
        ],
        'layout': {
          'text-field': ['get', 'etichetta'],
          'text-font': ['Noto Sans Bold'],
          'text-size': perAuto ? 14 : 12,
          'text-max-width': 12,
          'text-padding': 4,
        },
        'paint': {
          'text-color': [
            'match',
            ['get', 'tipo'],
            'ztl',
            '#991B1B',
            '#374151',
          ],
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 3,
        },
      },
      // Quanto si guadagnerebbe passandoci: «−3 min», sulla strada a puntini.
      {
        'id': 'passandoci-etichetta',
        'type': 'symbol',
        'source': sorgentePassandoci,
        'filter': [
          '==',
          ['geometry-type'],
          'Point',
        ],
        'layout': {
          'text-field': ['get', 'etichetta'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 12,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': '#FFFFFF', 'text-halo-color': '#475569', 'text-halo-width': 6},
      },
      // Quanto fa risparmiare la strada proposta: il fumetto verde.
      {
        'id': 'risparmio-etichetta',
        'type': 'symbol',
        'source': sorgenteRisparmio,
        'filter': [
          '==',
          ['geometry-type'],
          'Point',
        ],
        'layout': {
          'text-field': ['get', 'etichetta'],
          'text-font': ['Noto Sans Bold'],
          'text-size': perAuto ? 15 : 13,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': '#FFFFFF', 'text-halo-color': '#15803D', 'text-halo-width': 6},
      },
      // Quanto fa guadagnare o perdere ogni alternativa: il fumetto sulla
      // strada, da toccare per sceglierla.
      {
        'id': 'alternative-etichetta',
        'type': 'symbol',
        'source': sorgenteAlternative,
        'filter': [
          '==',
          ['geometry-type'],
          'Point',
        ],
        'layout': {
          'text-field': ['get', 'etichetta'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 13,
          'text-line-height': 1.15,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': _seEco('#15803D', t.alternativaBordo),
          'text-halo-width': 6,
        },
      },
      {
        // La meta: una bandiera a scacchi in piedi (anche con la mappa
        // inclinata), posata con la base dell'asta sul punto. Era un punto
        // rosso, che in mezzo a tutto il resto non si capiva cosa fosse.
        'id': 'arrivo',
        'type': 'symbol',
        'source': sorgenteArrivo,
        'layout': {
          'icon-image': immagineBandieraArrivo,
          'icon-anchor': 'bottom',
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            1.0,
            15,
            1.4,
            18,
            1.9,
          ],
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
      {
        // Le segnalazioni: i fumetti colorati di Waze, in piedi anche con la
        // mappa inclinata.
        'id': 'segnalazioni',
        'type': 'symbol',
        'source': sorgenteSegnalazioni,
        'layout': {
          // L'immagine la sceglie chi scrive i dati (`nomeIconaDi`): gli
          // autovelox col loro disegno, fisso, mobile o semaforo, e il
          // cartello del limite accanto, come in TomTom.
          'icon-image': ['get', 'icona'],
          'icon-anchor': 'bottom',
          // Gli autovelox piu' grandi delle altre: «si devono notare bene».
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            9,
            [
              'match',
              ['get', 'tipo'],
              'autovelox',
              0.7,
              0.45,
            ],
            15,
            [
              'match',
              ['get', 'tipo'],
              'autovelox',
              1.0,
              0.7,
            ],
            18,
            [
              'match',
              ['get', 'tipo'],
              'autovelox',
              1.2,
              0.9,
            ],
          ],
          // Gli autovelox sopra le altre segnalazioni.
          'symbol-sort-key': [
            'match',
            ['get', 'tipo'],
            'autovelox',
            1,
            0,
          ],
          'icon-allow-overlap': true,
        },
      },
      // Le persone di casa: un tondo viola con le iniziali, e il nome sotto.
      {
        'id': 'persone',
        'type': 'circle',
        'source': sorgentePersone,
        'paint': {
          'circle-radius': 15,
          'circle-color': '#7C3AED',
          'circle-stroke-color': '#FFFFFF',
          'circle-stroke-width': 3,
        },
      },
      {
        'id': 'persone-iniziali',
        'type': 'symbol',
        'source': sorgentePersone,
        'layout': {
          'text-field': ['get', 'iniziali'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 13,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': '#FFFFFF'},
      },
      {
        'id': 'persone-nome',
        'type': 'symbol',
        'source': sorgentePersone,
        'layout': {
          'text-field': ['get', 'nome'],
          'text-font': ['Noto Sans Bold'],
          'text-size': 13,
          'text-anchor': 'top',
          'text-offset': [0, 1.5],
          'text-allow-overlap': true,
        },
        'paint': {'text-color': t.etichetta, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 2},
      },
      {
        // Dove sei: la freccia o l'auto scelta, girata come vai, distesa sulla
        // mappa anche quando è inclinata.
        'id': 'io',
        'type': 'symbol',
        'source': sorgenteIo,
        'layout': {
          'icon-image': ['get', 'icona'],
          'icon-rotate': ['get', 'rotta'],
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          // Un terzo più grande di prima («aumenta ancora la grandezza della
          // freccia»). Le stesse grandezze le usano Android Auto
          // (`RendererMappa.dimensioneIcona`) e CarPlay
          // (`MotoCarPlay.dimensioneIcona`), che il segnaposto lo disegnano
          // sopra la mappa.
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            0.6,
            15,
            0.8,
            17,
            1.15,
            19,
            1.35,
          ],
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
      {
        'id': 'luoghi',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'filter': [
          'match',
          ['get', 'class'],
          ['city', 'town', 'village', 'suburb'],
          true,
          false,
        ],
        'layout': {
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Bold'],
          'text-size': [
            'match',
            ['get', 'class'],
            'city',
            22,
            'town',
            18,
            'village',
            15,
            14,
          ],
        },
        'paint': {'text-color': t.luogo, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 2},
      },
    ],
  };
}

/* Quanto si va piano, rispetto a strada libera: 1 libera, 0 fermi.
 *
 * Un campo che non c'e' vale 1 — strada libera — e quindi non si disegna
 * niente: un nome di campo sbagliato si vede identico a «non c'e' traffico».
 * Per questo si accettano tutte e due le forme che TomTom ha usato, e per
 * questo la prova di rete `tomtom_tessera_test.dart` va a leggere un riquadro
 * vero e dice in chiaro come si chiamano i campi. */
List<Object> _quantoSiVaPiano() => [
  'to-number',
  [
    'coalesce',
    ['get', 'traffic_level'],
    ['get', 'trafficLevel'],
  ],
  1,
];

/* E' una strada grande, di quelle che si disegnano anche da lontano?
 *
 * TomTom la famiglia della strada la dice in `road_type`, a parole. Non si
 * tira a indovinare: `tools/sonda_traffico.py` scarica un riquadro vero in CI
 * e stampa i nomi che ci trova — «Major road», «Secondary road»,
 * «Connecting road», «Major local road».
 *
 * Si sceglie con `match` e non con `in`: `match` e' nel formato da sempre e
 * lo capiscono tutte le versioni di MapLibre, mentre un'espressione che una
 * versione non conosce le fa buttare via lo strato intero — senza dire
 * niente, e sullo schermo si vede una citta' che scorre.
 *
 * Si elencano le strade piccole, non le grandi: cosi' una parola nuova, o un
 * campo che un domani cambia nome, finisce fra le grandi e si vede da zoom 7.
 * Sbagliare da quella parte vuol dire vedere una coda di paese da lontano;
 * sbagliare dall'altra vuol dire non vedere una coda in tangenziale. */
List<Object> _eUnaGrande() => [
  'match',
  [
    'to-string',
    ['get', 'road_type'],
  ],
  ['Connecting road', 'Major local road', 'Local road', 'Minor local road', 'Other'],
  false,
  true,
];

/// Le strade dove TomTom misura una coda: sotto 0,6 si rallenta, sotto 0,3 si
/// è fermi.
Map<String, Object> _coda(String id, {required bool principali, required double minzoom, double spessore = 1}) {
  return {
    'id': id,
    'type': 'line',
    'source': 'traffico',
    'source-layer': 'Traffic flow',
    'minzoom': minzoom,
    'filter': [
      'all',
      ['<', _quantoSiVaPiano(), 0.6],
      principali ? _eUnaGrande() : ['!', _eUnaGrande()],
    ],
    'layout': {'line-cap': 'round', 'line-join': 'round'},
    'paint': {
      'line-color': ['step', _quantoSiVaPiano(), '#E5302A', 0.3, '#F5A623'],
      'line-width': [
        'interpolate',
        ['linear'],
        ['zoom'],
        7,
        1.2 * spessore,
        12,
        2.5 * spessore,
        16,
        5 * spessore,
      ],
      'line-opacity': 0.9,
    },
  };
}

/// I colori delle icone delle colonnine, uno per stato: gli stessi di
/// `coloriColonnina` (componenti/icone_punti.dart), che le disegna. Qui e
/// non dal tema, perché il bollino deve avere il colore dell'icona su cui
/// sta, che è uguale col chiaro e con lo scuro.
const _coloriIcona = {'libera': '#16A34A', 'piena': '#D97706', 'guasta': '#DC2626', 'ignota': '#4F46E5'};

/// Il numero delle prese in un bollino bianco, fuori dall'icona in alto a
/// destra: «fai vedere il numero all'esterno». Solo dove le prese sono più
/// di una — una presa sola è l'icona stessa.
///
/// Un cerchio e un testo spostati di qualche punto sullo schermo
/// (`translate` sulla vista, non sulla mappa: il bollino resta in alto a
/// destra anche girando la mappa). Il cerchio cresce con le cifre.
/// Lo stato scritto sulla colonnina, o «ignota» se non c'è: sulla mappa di
/// tutta Italia lo stato che non si sa non si scrive, per non pesare.
List<Object> _statoOIgnota() => [
  'coalesce',
  ['get', 'stato'],
  'ignota',
];

/// L'evidenza del punto toccato sull'auto: il colore dello stato per una
/// colonnina, quello del percorso per il resto (distributori, ristoranti…).
List<Object> _coloreEvidenza(_Tavolozza t) => [
  'match',
  [
    'coalesce',
    ['get', 'stato'],
    '',
  ],
  for (final MapEntry(:key, :value) in _coloriIcona.entries) ...[key, value],
  t.percorsoBordo,
];

/// Il colore dell'icona per lo stato: lo stesso del bollino delle prese.
List<Object> _coloreDelloStato(List<Object> stato) => [
  'match',
  stato,
  for (final MapEntry(:key, :value) in _coloriIcona.entries)
    if (key != 'ignota') ...[key, value],
  _coloriIcona['ignota']!,
];

List<Map<String, Object>> _bollinoPrese(
  String strato,
  String sorgente,
  Object colore, {
  bool sfusa = false,
  double? minzoom,
}) {
  const spostamento = [15, -15];
  final filtro = [
    'all',
    if (sfusa)
      [
        '!',
        ['has', 'point_count'],
      ],
    [
      '>',
      ['get', 'prese'],
      1,
    ],
  ];
  return [
    {
      'id': '$strato-prese-fondo',
      'type': 'circle',
      'source': sorgente,
      'minzoom': ?minzoom,
      'filter': filtro,
      'paint': {
        'circle-radius': [
          'step',
          ['get', 'prese'],
          8,
          10,
          9.5,
          100,
          11.5,
          1000,
          13,
        ],
        'circle-color': '#FFFFFF',
        'circle-stroke-color': colore,
        'circle-stroke-width': 1.6,
        'circle-translate': spostamento,
        'circle-translate-anchor': 'viewport',
        'circle-pitch-alignment': 'viewport',
      },
    },
    {
      'id': '$strato-prese',
      'type': 'symbol',
      'source': sorgente,
      'minzoom': ?minzoom,
      'filter': filtro,
      'layout': {
        'text-field': _numeroCorto(['get', 'prese']),
        'text-font': ['Noto Sans Bold'],
        'text-size': 9.5,
        'text-allow-overlap': true,
        'text-ignore-placement': true,
      },
      'paint': {'text-color': colore, 'text-translate': spostamento, 'text-translate-anchor': 'viewport'},
    },
  ];
}

/// Un numero da scrivere in un cerchio: intero fino a 9999, poi in migliaia
/// («12k»).
List<Object> _numeroCorto(List<Object> numero) => [
  'case',
  ['>=', numero, 10000],
  [
    'concat',
    [
      'to-string',
      [
        'round',
        ['/', numero, 1000],
      ],
    ],
    'k',
  ],
  ['to-string', numero],
];
