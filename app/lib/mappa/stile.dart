/// Lo stile della mappa di gdanav, chiaro e scuro, sui dati vettoriali di
/// OpenFreeMap (schema OpenMapTiles). Un solo posto per i colori della
/// mappa: lo usa l'app, e lo usano le anteprime.
///
/// Dentro ci sono anche gli strati del viaggio (percorso, colonnine, soste,
/// arrivo) con le loro sorgenti vuote: l'app ne cambia solo i dati.
library;

const sorgentePercorso = 'gdanav-percorso';
const sorgenteColonnine = 'gdanav-colonnine';
const sorgenteArrivo = 'gdanav-arrivo';
const stratiToccabili = ['gdanav-soste', 'gdanav-colonnine'];

/// Dall'alto gli edifici sono piatti e puliti; inclinando la mappa si
/// accendono quelli in 3D e si spengono i piatti.
const stratoEdifici2d = 'edifici';
const stratoEdifici3d = 'edifici-3d';

class _Tavolozza {
  const _Tavolozza({
    required this.sfondo,
    required this.abitato,
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
    required this.percorso,
    required this.percorsoBordo,
    required this.contorno,
    required this.libera,
    required this.piena,
    required this.guasta,
    required this.ignota,
    required this.arrivo,
  });

  final String sfondo, abitato, prato, bosco, acqua, edificio, edificioLato, edificioBordo;
  final String autostrada, autostradaBordo, principale, principaleBordo, strada, stradaBordo, sentiero, ferrovia;
  final String etichetta, etichettaAlone, luogo;
  final String percorso, percorsoBordo, contorno;
  final String libera, piena, guasta, ignota, arrivo;
}

const _chiaro = _Tavolozza(
  sfondo: '#F6F4F0',
  abitato: '#F0ECE6',
  prato: '#D6EACB',
  bosco: '#C2DEB2',
  acqua: '#A3CFF2',
  edificio: '#E7E1D9',
  edificioLato: '#D9D1C6',
  edificioBordo: '#D8CFC3',
  autostrada: '#F9B866',
  autostradaBordo: '#D98D3A',
  principale: '#FFE39A',
  principaleBordo: '#DDBB62',
  strada: '#FFFFFF',
  stradaBordo: '#D9D1C6',
  sentiero: '#C9C0B4',
  ferrovia: '#B8B0A6',
  etichetta: '#475467',
  etichettaAlone: '#FFFFFF',
  luogo: '#1F2937',
  percorso: '#2F6BFF',
  percorsoBordo: '#1638A8',
  contorno: '#FFFFFF',
  libera: '#16A34A',
  piena: '#D97706',
  guasta: '#DC2626',
  ignota: '#64748B',
  arrivo: '#DC2626',
);

const _scuro = _Tavolozza(
  sfondo: '#0E1520',
  abitato: '#111B28',
  prato: '#132A1E',
  bosco: '#11261A',
  acqua: '#0C3050',
  edificio: '#243044',
  edificioLato: '#34445E',
  edificioBordo: '#2C3A50',
  autostrada: '#A2622A',
  autostradaBordo: '#5B3514',
  principale: '#6F6031',
  principaleBordo: '#3B321A',
  strada: '#2E3B4E',
  stradaBordo: '#0A111B',
  sentiero: '#3A4659',
  ferrovia: '#3A4659',
  etichetta: '#B8C4D6',
  etichettaAlone: '#0E1520',
  luogo: '#E5ECF5',
  percorso: '#4C8DFF',
  percorsoBordo: '#0B2A73',
  contorno: '#0B1220',
  libera: '#4ADE80',
  piena: '#FBBF24',
  guasta: '#F87171',
  ignota: '#94A3B8',
  arrivo: '#F87171',
);

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
Map<String, Object> stileMappa({required bool scuro}) {
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
      sorgenteColonnine: {'type': 'geojson', 'data': _vuota},
      sorgenteArrivo: {'type': 'geojson', 'data': _vuota},
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
      _strada('servizio-bordo', classi['servizio']!, t.stradaBordo, _largo(0.8, 9), minzoom: 14),
      _strada('strade-bordo', classi['strada']!, t.stradaBordo, _largo(1.6, 19)),
      _strada('principali-bordo', classi['principale']!, t.principaleBordo, _largo(2.6, 26)),
      _strada('autostrade-bordo', classi['autostrada']!, t.autostradaBordo, _largo(3.4, 30)),
      _strada('servizio', classi['servizio']!, t.strada, _largo(0.4, 7), minzoom: 14),
      _strada('strade', classi['strada']!, t.strada, _largo(1, 16)),
      _strada('principali', classi['principale']!, t.principale, _largo(1.8, 22)),
      _strada('autostrade', classi['autostrada']!, t.autostrada, _largo(2.4, 26)),
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
        'minzoom': 14,
        'layout': {
          'symbol-placement': 'line',
          'text-field': ['get', 'name'],
          'text-font': ['Noto Sans Regular'],
          'text-size': 12,
          'text-max-angle': 30,
        },
        'paint': {'text-color': t.etichetta, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 1.5},
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
            18,
            'town',
            15,
            13,
          ],
        },
        'paint': {'text-color': t.luogo, 'text-halo-color': t.etichettaAlone, 'text-halo-width': 2},
      },
    ],
  };
}
