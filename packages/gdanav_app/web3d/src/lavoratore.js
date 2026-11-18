// Il lavoratore: fa le tessere 3D fuori dal thread del disegno, così la
// mappa non si ferma mentre nasce un viadotto. Riceve i byte delle tessere
// vettoriali (quella di mezzo e le vicine), restituisce le geometrie.

import { VectorTile } from '@mapbox/vector-tile';
import Pbf from 'pbf';
import { corsieStimate, preparaStimate } from './stima.js';
import { bufferDellaTessera, costruisciTessera } from './tessera.js';

/** Le tessere già decodificate (le vicine servono a più lavori). */
const decodificate = new Map();
const MAX_DECODIFICATE = 30;

function decodifica(chiave, dati) {
  const c = decodificate.get(chiave);
  if (c && c.n === dati.byteLength) {
    decodificate.delete(chiave);
    decodificate.set(chiave, c);
    return c.layers;
  }
  const layers = new VectorTile(new Pbf(new Uint8Array(dati))).layers;
  decodificate.set(chiave, { n: dati.byteLength, layers });
  while (decodificate.size > MAX_DECODIFICATE) decodificate.delete(decodificate.keys().next().value);
  return layers;
}

self.onmessage = (e) => {
  const { id, z, x, y, tessere, dettaglio, edifici, corsie, vistaCorsie, stimaCorsie } = e.data;
  try {
    const livelli = {};
    for (const [off, { chiave, dati }] of Object.entries(tessere)) livelli[off] = decodifica(chiave, dati);
    // Gli edifici di Overture dall'app, al posto di quelli di sempre (vedi
    // `chiedi` in principale.js). Una copia: le tessere decodificate si tengono.
    if (edifici && livelli['0,0']) {
      const veri = new VectorTile(new Pbf(new Uint8Array(edifici))).layers.building;
      if (veri) livelli['0,0'] = { ...livelli['0,0'], building: veri };
    }
    // Le vie con le corsie, nella vista «Corsie» (vedi `segnaletica.js`).
    // Senza le corsie vere della tessera, quelle stimate dalle tessere
    // vettoriali (vedi `stima.js`): solo le strade, senza nodi né alberi.
    let datiCorsie = corsie;
    let stimate = null;
    if (vistaCorsie === true && stimaCorsie === true && !corsie?.strade?.length) {
      const dati = corsieStimate({ z, x, y, livelli });
      datiCorsie = dati.strade.length ? preparaStimate(dati) : null;
      // I pezzi di questa tessera, per la pagina (il percorso sulla corsia).
      const qui = `${z}/${x}/${y}`;
      stimate = dati.strade.filter((s) => s.t === qui);
    }
    const t = costruisciTessera({ z, x, y, livelli, dettaglio, datiCorsie, vistaCorsie: vistaCorsie === true });
    self.postMessage({ id, tessera: t, stimate }, bufferDellaTessera(t));
  } catch (err) {
    self.postMessage({ id, errore: String(err?.stack ?? err) });
  }
};
