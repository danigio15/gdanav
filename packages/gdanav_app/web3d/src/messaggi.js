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
    (m.inAuto === undefined || typeof m.inAuto === 'boolean'),
  stile: (m) => m.stile && typeof m.stile === 'object' && Array.isArray(m.stile.layers),
  immagine: (m) => typeof m.nome === 'string' && typeof m.png === 'string' && (m.ratio === undefined || numero(m.ratio)),
  sorgente: (m) => typeof m.id === 'string' && m.dati && typeof m.dati === 'object',
  percorso: (m) =>
    (m.punti === null || coppie(m.punti)) &&
    (m.metri === undefined || (Array.isArray(m.metri) && m.punti && m.metri.length === m.punti.length / 2 && m.metri.every(numero))) &&
    (m.code === undefined || (Array.isArray(m.code) && m.code.every((c) => Array.isArray(c) && c.length === 3 && c.every(numero)))),
  manovra: (m) => (m.da === null && m.a === null) || (numero(m.da) && numero(m.a) && m.a >= m.da),
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
    (m.zoom === undefined || numero(m.zoom)),
  camera: (m) =>
    ['segui', 'libera', 'panoramica'].includes(m.modo) &&
    (m.sopra === undefined || numero(m.sopra)) &&
    (m.sinistra === undefined || numero(m.sinistra)) &&
    (m.destra === undefined || numero(m.destra)) &&
    (m.pitch === undefined || (numero(m.pitch) && m.pitch >= 0 && m.pitch <= 85)) &&
    (m.riquadro === undefined || (Array.isArray(m.riquadro) && m.riquadro.length === 4 && m.riquadro.every(numero))),
  pausa: (m) => typeof m.si === 'boolean',
  velocita: (m) => numero(m.ms) && m.ms >= 0 && numero(m.alle),
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
