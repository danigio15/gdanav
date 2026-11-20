// I messaggi fra l'app (Flutter) e la mappa 3D.
//
// L'app chiama `gdanav3d.ricevi({...})` con un oggetto `{v: 1, tipo, ...}`;
// la mappa risponde sul canale `Gdanav3d` con una stringa JSON `{tipo, ...}`.
// Qui solo il controllo di quello che arriva: un messaggio storto si scarta
// (e si dice), non rompe la mappa. Il formato è lo stesso di
// `lib/mappa/ponte_3d.dart`, che ha le sue prove.

export const VERSIONE = 1;

const numero = (v) => typeof v === 'number' && Number.isFinite(v);
const coppie = (a) => Array.isArray(a) && a.length % 2 === 0 && a.every(numero);

const CONTROLLI = {
  opzioni: (m) =>
    typeof m.notte === 'boolean' &&
    (m.vista === undefined || ['inclinata', 'immersiva'].includes(m.vista)) &&
    (m.auto === undefined || /^#[0-9a-fA-F]{6}$/.test(m.auto)) &&
    (m.inAuto === undefined || typeof m.inAuto === 'boolean') &&
    (m.corsie === undefined || typeof m.corsie === 'boolean'),
  stile: (m) => m.stile && typeof m.stile === 'object' && Array.isArray(m.stile.layers),
  immagine: (m) => typeof m.nome === 'string' && typeof m.png === 'string' && (m.ratio === undefined || numero(m.ratio)),
  sorgente: (m) => typeof m.id === 'string' && m.dati && typeof m.dati === 'object',
  percorso: (m) =>
    (m.punti === null || coppie(m.punti)) &&
    (m.metri === undefined || (Array.isArray(m.metri) && m.punti && m.metri.length === m.punti.length / 2 && m.metri.every(numero))) &&
    (m.code === undefined || (Array.isArray(m.code) && m.code.every((c) => Array.isArray(c) && c.length === 3 && c.every(numero)))) &&
    (m.suStrada === undefined || (Array.isArray(m.suStrada) && m.suStrada.every((c) => Array.isArray(c) && c.length === 3 && c.every(numero)))),
  manovra: (m) =>
    ((m.da === null && m.a === null) || (numero(m.da) && numero(m.a) && m.a >= m.da)) &&
    (m.corsie === undefined || (Array.isArray(m.corsie) && m.corsie.length <= 16)) &&
    (m.dove === undefined || numero(m.dove)),
  // La vista «Corsie»: le vie con le corsie e i nodi (il formato è in `corsie.js`).
  corsie: (m) =>
    m.dati &&
    typeof m.dati === 'object' &&
    (m.dati.v === undefined || m.dati.v === 1) &&
    Array.isArray(m.dati.strade) &&
    m.dati.strade.every((st) => st && typeof st.hw === 'string' && coppie(st.g)) &&
    (m.dati.nodi === undefined || (Array.isArray(m.dati.nodi) && m.dati.nodi.every((n) => n && Array.isArray(n.g) && n.g.length === 2 && n.g.every(numero)))) &&
    (m.dati.alberi === undefined || (Array.isArray(m.dati.alberi) && m.dati.alberi.every((a) => Array.isArray(a) && a.length >= 2 && a.every(numero)))) &&
    (m.dati.filari === undefined || (Array.isArray(m.dati.filari) && m.dati.filari.every((f) => f && coppie(f.g)))),
  risparmio: (m) => m.punti === null || coppie(m.punti),
  posizione: (m) =>
    numero(m.lat) &&
    numero(m.lon) &&
    Math.abs(m.lat) <= 90 &&
    Math.abs(m.lon) <= 180 &&
    numero(m.rotta) &&
    (m.metri === null || numero(m.metri)) &&
    numero(m.velocita) &&
    numero(m.quando) &&
    (m.zoom === undefined || numero(m.zoom)) &&
    (m.rottaIncerta === undefined || typeof m.rottaIncerta === 'boolean') &&
    (m.zoomScelto === undefined || numero(m.zoomScelto)),
  camera: (m) =>
    ['segui', 'libera', 'panoramica'].includes(m.modo) &&
    (m.sopra === undefined || numero(m.sopra)) &&
    (m.sinistra === undefined || numero(m.sinistra)) &&
    (m.destra === undefined || numero(m.destra)) &&
    (m.pitch === undefined || (numero(m.pitch) && m.pitch >= 0 && m.pitch <= 85)) &&
    (m.riquadro === undefined || (Array.isArray(m.riquadro) && m.riquadro.length === 4 && m.riquadro.every(numero))),
  pausa: (m) => typeof m.si === 'boolean',
  // Dall'auto (Android Auto): un dito che trascina la mappa, in pixel dello
  // schermo dell'auto; e «Centra», che torna a seguire.
  sposta: (m) => numero(m.dx) && numero(m.dy),
  riprendi: () => true,
  // Dal telefono, sull'auto (`CaricoScena3d.kt`, `RendererMappa.kt`).
  carico: (m) => Number.isInteger(m.livello) && m.livello >= 0 && m.livello <= 3 && (m.telefono === undefined || typeof m.telefono === 'boolean'),
  nascosta: (m) => typeof m.si === 'boolean',
  // Dall'app, sul telefono: sull'auto gira un'altra scena (`Regia3d.sullAuto`).
  leggera: (m) => typeof m.si === 'boolean',
  velocita: (m) => numero(m.ms) && m.ms >= 0 && numero(m.alle),
  // L'accelerazione di marcia dal telefono (`AccelerazioneDiMarcia`): m/s².
  accelerazione: (m) => numero(m.a) && Math.abs(m.a) <= 15 && numero(m.alle) && (m.ritardo === undefined || numero(m.ritardo)),
  edifici: (m) =>
    [m.z, m.x, m.y].every((n) => Number.isInteger(n) && n >= 0) && (m.dati === null || m.dati === undefined || typeof m.dati === 'string'),
};

/** Il messaggio se è buono, altrimenti null. */
export function decodifica(m) {
  if (typeof m === 'string') {
    try {
      m = JSON.parse(m);
    } catch {
      return null;
    }
  }
  if (!m || typeof m !== 'object' || m.v !== VERSIONE) return null;
  const c = CONTROLLI[m.tipo];
  if (!c) return null;
  try {
    return c(m) ? m : null;
  } catch {
    return null;
  }
}

/** Le code del percorso, come intervalli ordinati `[da, a, livello]`. */
export function codeOrdinate(code = []) {
  return code
    .filter(([da, a, l]) => a > da && l > 0)
    .map(([da, a, l]) => [da, a, Math.min(4, Math.max(1, Math.round(l)))])
    .sort((p, q) => p[0] - q[0]);
}
