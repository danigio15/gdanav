/// Lo stile della mappa di gdanav, chiaro e scuro, sui dati vettoriali di
/// OpenFreeMap (schema OpenMapTiles). Un solo posto per i colori della
/// mappa: lo usa l'app, e lo usano le anteprime.
///
/// Dentro ci sono anche gli strati del viaggio (percorso, colonnine, soste,
/// arrivo) con le loro sorgenti vuote: l'app ne cambia solo i dati.
library;

import 'categorie_poi.dart';

const sorgentePercorso = 'gdanav-percorso';
const sorgenteColonnine = 'gdanav-colonnine';
const sorgenteArrivo = 'gdanav-arrivo';
const sorgenteIo = 'gdanav-io';
const sorgenteSegnalazioni = 'gdanav-segnalazioni';
const sorgenteManovra = 'gdanav-manovra';
const sorgenteDistributori = 'gdanav-distributori';
const sorgenteVicine = 'gdanav-vicine';
const sorgenteCode = 'gdanav-code';
const sorgenteAlternative = 'gdanav-alternative';
const sorgenteTappe = 'gdanav-tappe';
const stratoTraffico = 'traffico';
const stratoTrafficoLocale = 'traffico-locale';
const stratiToccabili = [
  'alternative-etichetta',
  'alternative',
  'gdanav-soste',
  'gdanav-colonnine',
  'gdanav-distributori',
  'gdanav-vicine',
  'nomi-poi',
];

/// Dall'alto gli edifici sono piatti e puliti; inclinando la mappa si
/// accendono quelli in 3D e si spengono i piatti.
const stratoEdifici2d = 'edifici';
const stratoEdifici3d = 'edifici-3d';

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
  ignota: '#64748B',
  arrivo: '#E5484D',
);

// La notte di Waze: blu notte, strade grigio ardesia, nomi chiari.
const _scuro = _Tavolozza(
  sfondo: '#1B2130',
  abitato: '#1F2636',
  industria: '#252C3C',
  prato: '#1C3027',
  bosco: '#1A2E24',
  acqua: '#1A3656',
  edificio: '#283042',
  edificioLato: '#3A4459',
  edificioBordo: '#2F384B',
  autostrada: '#56627A',
  autostradaBordo: '#141925',
  principale: '#48536A',
  principaleBordo: '#141925',
  strada: '#394356',
  stradaBordo: '#141925',
  sentiero: '#3A4457',
  ferrovia: '#3A4457',
  etichetta: '#D2D8E1',
  etichettaAlone: '#1B2130',
  luogo: '#8FB6E8',
  poi: '#7D8797',
  percorso: '#3AB0FF',
  percorsoBordo: '#0B5AA6',
  alternativa: '#4E6A86',
  alternativaBordo: '#2E4459',
  contorno: '#0F1420',
  libera: '#4ADE80',
  piena: '#FBBF24',
  guasta: '#F87171',
  ignota: '#94A3B8',
  arrivo: '#F87171',
);

/// Una larghezza in metri (alle nostre latitudini): raddoppia a ogni zoom.
List<Object> _metri(double metri) => [
  'interpolate',
  ['exponential', 2],
  ['zoom'],
  13,
  metri / 7,
  20,
  metri / 7 * 128,
];

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

const _vuota = {'type': 'FeatureCollection', 'features': <Object>[]};

/// Lo stile completo. [scuro] per la sera; le sorgenti del viaggio partono
/// vuote.
///
/// Con [chiaveTraffico] (una chiave gratuita di TomTom) sulle strade si
/// vedono le code, come in Waze: solo dove si va più piano del solito, e
/// gli incidenti e i lavori.
Map<String, Object> stileMappa({required bool scuro, String chiaveTraffico = '', bool perAuto = false}) {
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
      sorgenteColonnine: {'type': 'geojson', 'data': _vuota},
      sorgenteArrivo: {'type': 'geojson', 'data': _vuota},
      sorgenteIo: {'type': 'geojson', 'data': _vuota},
      sorgenteSegnalazioni: {'type': 'geojson', 'data': _vuota},
      sorgenteManovra: {'type': 'geojson', 'data': _vuota},
      sorgenteDistributori: {'type': 'geojson', 'data': _vuota},
      sorgenteVicine: {'type': 'geojson', 'data': _vuota},
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
      _strada('servizio-bordo', classi['servizio']!, t.stradaBordo, _largo(1.2, 12), minzoom: 14),
      _strada('strade-bordo', classi['strada']!, t.stradaBordo, _largo(2.4, 24)),
      _strada('principali-bordo', classi['principale']!, t.principaleBordo, _largo(3.6, 32)),
      _strada('autostrade-bordo', classi['autostrada']!, t.autostradaBordo, _largo(4.6, 38)),
      _strada('servizio', classi['servizio']!, t.strada, _largo(0.6, 9), minzoom: 14),
      _strada('strade', classi['strada']!, t.strada, _largo(1.6, 20)),
      _strada('principali', classi['principale']!, t.principale, _largo(2.6, 27)),
      _strada('autostrade', classi['autostrada']!, t.autostrada, _largo(3.4, 32)),
      // Il traffico come in Waze: solo dove si rallenta, arancio se lento e
      // rosso se quasi fermi; da lontano solo sulle strade principali.
      if (traffico.isNotEmpty) ...[
        _coda(stratoTraffico, principali: true, minzoom: 7),
        _coda(stratoTrafficoLocale, principali: false, minzoom: 13),
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
        'paint': {
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
          'fill-extrusion-opacity': 0.94,
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
      // si sceglie quella.
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
        'paint': {'line-color': t.alternativaBordo, 'line-width': _largo(7.5, 20)},
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
        'paint': {'line-color': t.alternativa, 'line-width': _largo(5, 15)},
      },
      // Il percorso: un alone morbido, il bordo blu scuro, la linea blu e le
      // frecce della direzione. Sempre blu: nessuna strada ha quel colore.
      {
        'id': 'percorso-alone',
        'type': 'line',
        'source': sorgentePercorso,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': t.percorso, 'line-width': _largo(16, 40), 'line-blur': 10, 'line-opacity': 0.22},
      },
      {
        'id': 'percorso-bordo',
        'type': 'line',
        'source': sorgentePercorso,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': t.percorsoBordo, 'line-width': _largo(8.5, 24)},
      },
      {
        'id': 'percorso',
        'type': 'line',
        'source': sorgentePercorso,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': t.percorso, 'line-width': _largo(5.5, 18)},
      },
      // Le code di adesso sopra il percorso: dal giallo (rallenta) al rosso
      // (fermo), bordeaux se è chiusa.
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
          'line-width': _largo(5.5, 18),
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
      // bordo blu scuro, larga sempre uguale in metri (come la strada), così
      // allo svincolo si vede esattamente la rampa da prendere.
      {
        'id': 'manovra-bordo',
        'type': 'line',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': '#0B3C78', 'line-width': _metri(8.5)},
      },
      {
        'id': 'manovra-punta-bordo',
        'type': 'line',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': [
          '==',
          ['geometry-type'],
          'Polygon',
        ],
        'layout': {'line-join': 'round'},
        'paint': {'line-color': '#0B3C78', 'line-width': _metri(2.9)},
      },
      {
        'id': 'manovra',
        'type': 'line',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': [
          '==',
          ['geometry-type'],
          'LineString',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': '#FFFFFF', 'line-width': _metri(5.6)},
      },
      {
        'id': 'manovra-punta',
        'type': 'fill',
        'source': sorgenteManovra,
        'minzoom': 13,
        'filter': [
          '==',
          ['geometry-type'],
          'Polygon',
        ],
        'paint': {'fill-color': '#FFFFFF', 'fill-antialias': true},
      },
      // Intorno a te: i distributori col prezzo (auto termica) o le
      // colonnine rapide col colore dello stato (auto elettrica).
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
        'paint': {'text-color': '#FFFFFF', 'text-halo-color': t.alternativaBordo, 'text-halo-width': 6},
      },
      {
        'id': 'arrivo',
        'type': 'circle',
        'source': sorgenteArrivo,
        'paint': {
          'circle-radius': 11,
          'circle-color': t.arrivo,
          'circle-stroke-color': t.contorno,
          'circle-stroke-width': 3.5,
        },
      },
      {
        // Le segnalazioni: i fumetti colorati di Waze, in piedi anche con la
        // mappa inclinata.
        'id': 'segnalazioni',
        'type': 'symbol',
        'source': sorgenteSegnalazioni,
        'layout': {
          'icon-image': [
            'concat',
            'segnala-',
            ['get', 'tipo'],
          ],
          'icon-anchor': 'bottom',
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            9,
            0.45,
            15,
            0.7,
            18,
            0.9,
          ],
          'icon-allow-overlap': true,
        },
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
          'icon-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            0.45,
            15,
            0.6,
            17,
            0.85,
            19,
            1.0,
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

/// Le strade dove TomTom misura una coda. `traffic_level` è la velocità
/// rispetto a quella libera: sotto 0,6 si rallenta, sotto 0,3 si è fermi.
Map<String, Object> _coda(String id, {required bool principali, required double minzoom}) {
  const grandi = ['Motorway', 'International road', 'Major road', 'Secondary road'];
  return {
    'id': id,
    'type': 'line',
    'source': 'traffico',
    'source-layer': 'Traffic flow',
    'minzoom': minzoom,
    'filter': [
      'all',
      [
        '<',
        [
          'to-number',
          ['get', 'traffic_level'],
          1,
        ],
        0.6,
      ],
      principali
          ? [
              'in',
              ['get', 'road_type'],
              ['literal', grandi],
            ]
          : [
              '!',
              [
                'in',
                ['get', 'road_type'],
                ['literal', grandi],
              ],
            ],
    ],
    'layout': {'line-cap': 'round', 'line-join': 'round'},
    'paint': {
      'line-color': [
        'step',
        [
          'to-number',
          ['get', 'traffic_level'],
          1,
        ],
        '#E5302A',
        0.3,
        '#F5A623',
      ],
      'line-width': [
        'interpolate',
        ['linear'],
        ['zoom'],
        7,
        1.2,
        12,
        2.5,
        16,
        5,
      ],
      'line-opacity': 0.9,
    },
  };
}
