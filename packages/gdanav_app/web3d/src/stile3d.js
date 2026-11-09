// Lo stile della mappa di sotto, per il 3D.
//
// È lo stesso stile dell'app (`stileMappa` in `stile.dart`, mandato
// dall'app così com'è): sorgenti, colonnine, autovelox, meta, traffico,
// tutto uguale. Da vicino però le strade, gli edifici e il percorso li
// disegna il 3D: quegli strati si spengono sopra [ZOOM_3D]. Sotto (la
// panoramica) restano quelli di sempre. I nomi delle strade stanno in piedi
// sopra il 3D, e non quelli dei ponti (che cadrebbero a terra, sotto il
// viadotto); i numeri delle strade («A4», «SS33») in un cartello.

import { GIORNO, NOTTE } from './tavolozza.js';

export const ZOOM_3D = 14.5;
export const STRATO_3D = 'gdanav-3d';

/** Gli strati che il 3D disegna da sé, da vicino. */
export const STRATI_SOSTITUITI = [
  'ferrovie',
  'servizio-bordo',
  'strade-bordo',
  'principali-bordo',
  'autostrade-bordo',
  'servizio',
  'strade',
  'principali',
  'autostrade',
  'traffico',
  'traffico-locale',
  'edifici',
  'edifici-3d',
  'edifici-immersivi',
  // La strada già fatta: da vicino la disegna il 3D, all'altezza della strada.
  'percorso-fatto',
  'risparmio-bordo',
  'risparmio',
  'percorso-alone',
  'percorso-bordo',
  'percorso',
  'code',
  'percorso-frecce',
  'manovra-bordo',
  'manovra',
  'manovra-punta',
  'corsie',
  'corsie-righe',
  'corsie-bordi',
  'io',
];

/**
 * Il percorso oltre il tratto che disegna il 3D: gli stessi strati del
 * percorso di sempre, piatti, anche da vicino, su una sorgente che ha solo
 * quel pezzo (la scrive `principale.js`).
 */
export const SORGENTE_OLTRE = 'gdanav-3d-oltre';
const STRATI_OLTRE = ['percorso-alone', 'percorso-bordo', 'percorso', 'code', 'percorso-frecce'];
const LARGO_OLTRE = 0.32;

/** Il suolo con i colori del 3D. */
const SUOLO = { sfondo: 'sfondo', abitato: 'abitato', industria: 'industria', prato: 'prato', bosco: 'bosco', parco: 'prato', acqua: 'acqua' };

export function adattaStile(stile, { notte = false } = {}) {
  const t = notte ? NOTTE : GIORNO;
  const s = JSON.parse(JSON.stringify(stile));
  const layers = [];
  for (const l of s.layers) {
    // In 3D niente nomi di negozi, bar e uffici: guidando sono rumore. Restano
    // i nomi delle strade, e i punti di GdANav (colonnine, distributori,
    // segnalazioni, meta).
    if (l.id === 'nomi-poi') continue;
    if (STRATI_SOSTITUITI.includes(l.id)) {
      // Gli edifici in 3D di MapLibre non servono mai: da lontano bastano i piatti.
      if (l.id === 'edifici-3d' || l.id === 'edifici-immersivi') continue;
      l.maxzoom = Math.min(l.maxzoom ?? 24, ZOOM_3D);
      if (l.layout) delete l.layout.visibility;
    }
    if (SUOLO[l.id] && l.paint) {
      const colore = t[SUOLO[l.id]];
      if (l.type === 'background') l.paint['background-color'] = colore;
      else if (l.type === 'fill') l.paint['fill-color'] = colore;
    }
    if (l.id === 'corsi-acqua' && l.paint) l.paint['line-color'] = t.acqua;
    if (l.id === 'nomi-strade') {
      // Né i ponti (i loro nomi li scrive il 3D sull'impalcato) né le
      // gallerie (il nome finirebbe sopra quello che le copre).
      l.filter = FILTRO_NOMI;
      l.layout = {
        ...l.layout,
        'text-pitch-alignment': 'viewport',
        'text-rotation-alignment': 'map',
        'text-size': ['interpolate', ['linear'], ['zoom'], 13, 12, 16, 14.5, 19, 17],
        'text-padding': 12,
        'symbol-spacing': 320,
      };
      if (l.paint) l.paint['text-halo-width'] = 2.4;
      layers.push(l);
      layers.push(scudi());
      continue;
    }
    if (l.id === 'luoghi' && l.layout) l.layout['text-pitch-alignment'] = 'viewport';
    layers.push(l);
    if (STRATI_OLTRE.includes(l.id) && (l.source === 'gdanav-percorso' || l.source === 'gdanav-code')) {
      const oltre = JSON.parse(JSON.stringify(l));
      oltre.id = `${l.id}-oltre`;
      oltre.source = SORGENTE_OLTRE;
      // Sulla stessa sorgente il percorso e le code: le code hanno il livello.
      oltre.filter = l.source === 'gdanav-code' ? ['has', 'livello'] : ['!', ['has', 'livello']];
      oltre.minzoom = ZOOM_3D;
      delete oltre.maxzoom;
      // Largo quanto il nastro del 3D, non quanto la linea della mappa di sempre.
      const w = oltre.paint?.['line-width'];
      if (Array.isArray(w) && w[0] === 'interpolate') {
        oltre.paint['line-width'] = w.map((v, i) => (i >= 4 && i % 2 === 0 && typeof v === 'number' ? +(v * LARGO_OLTRE).toFixed(2) : v));
      }
      layers.push(oltre);
    }
  }
  if (s.sources?.['gdanav-percorso']) {
    s.sources[SORGENTE_OLTRE] = { type: 'geojson', data: { type: 'FeatureCollection', features: [] } };
  }
  // Il traffico da vicino lo disegna il 3D, ma le tessere di TomTom le
  // scarica MapLibre solo se uno strato le usa: uno invisibile.
  if (s.sources?.traffico) {
    const i = layers.findIndex((l) => l.id === 'nomi-strade');
    layers.splice(i < 0 ? layers.length : i, 0, {
      id: 'traffico-fonte-3d',
      type: 'line',
      source: 'traffico',
      'source-layer': 'Traffic flow',
      minzoom: ZOOM_3D,
      paint: { 'line-opacity': 0, 'line-width': 1 },
    });
  }
  s.layers = layers;
  return s;
}

/**
 * I numeri delle strade in un cartello: verde le autostrade, blu le altre,
 * come in Italia. Le immagini `scudo-verde` e `scudo-blu` le disegna la
 * mappa (`cartelli`).
 */
/** I nomi che scrive MapLibre: né i ponti né le gallerie (vedi [filtroNomi]). */
export const FILTRO_NOMI = ['match', ['coalesce', ['get', 'brunnel'], ''], ['bridge', 'tunnel'], false, true];

/**
 * Il filtro dei nomi delle strade, senza quelli che scrive il 3D: le strade
 * con un pezzo in galleria o in quota (rampe, viadotti) che le tessere
 * uniscono al resto, e MapLibre scriverebbe a terra o sopra la galleria.
 */
export function filtroNomi(nascosti) {
  if (!nascosti.length) return FILTRO_NOMI;
  return ['all', FILTRO_NOMI, ['!', ['in', ['coalesce', ['get', 'name'], ''], ['literal', nascosti]]]];
}

export function scudi() {
  return {
    id: 'scudi',
    type: 'symbol',
    source: 'openmaptiles',
    'source-layer': 'transportation_name',
    minzoom: 12,
    filter: [
      'all',
      ['has', 'ref'],
      ['match', ['coalesce', ['get', 'brunnel'], ''], ['bridge', 'tunnel'], false, true],
      ['<=', ['coalesce', ['get', 'ref_length'], 9], 7],
      ['match', ['get', 'class'], ['motorway', 'trunk', 'primary', 'secondary'], true, false],
    ],
    layout: {
      'symbol-placement': 'line',
      'symbol-spacing': 1400,
      'text-field': ['get', 'ref'],
      'text-font': ['Noto Sans Bold'],
      'text-size': 13,
      'text-rotation-alignment': 'viewport',
      'text-pitch-alignment': 'viewport',
      'icon-rotation-alignment': 'viewport',
      'icon-pitch-alignment': 'viewport',
      'icon-image': ['match', ['get', 'class'], 'motorway', 'scudo-verde', 'scudo-blu'],
      'icon-text-fit': 'both',
      'icon-text-fit-padding': [3, 7, 3, 7],
      'text-padding': 40,
      'symbol-avoid-edges': true,
    },
    paint: { 'text-color': '#FFFFFF' },
  };
}
