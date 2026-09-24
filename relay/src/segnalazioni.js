// Le segnalazioni della comunità, come in Waze: chi guida dice «c'è la
// polizia», «incidente», «traffico», e chi passa dopo le vede e conferma
// o smentisce. Qui solo le regole, senza Cloudflare intorno: così si
// provano con node.
//
// La mappa è divisa in zone di 0,2° (circa 20 km): ogni zona è un Durable
// Object che tiene le sue segnalazioni. Nessun dato di chi segnala.

export const LATO_ZONA = 0.2;

/** Quanto vive una segnalazione senza conferme, per tipo. */
export const DURATA_MIN = {
  traffico: 45,
  polizia: 60,
  incidente: 90,
  pericolo: 120,
  lavori: 24 * 60,
  chiusura: 12 * 60,
  autovelox: 7 * 24 * 60,
};

export const TIPI = Object.keys(DURATA_MIN);

/** Ogni conferma allunga la vita di metà della durata del tipo. */
const PROROGA = 0.5;

/** Chi smentisce due volte più di chi conferma la toglie. */
const SMENTITE_PER_TOGLIERE = 2;

/** Massimo di segnalazioni per zona e per indirizzo in dieci minuti. */
export const MASSIMO_PER_FINESTRA = 10;
export const FINESTRA_MS = 10 * 60 * 1000;

// Un pelo di tolleranza: 18,4 / 0,2 in virgola mobile fa 91,999…
const riga = (x) => Math.floor(x / LATO_ZONA + 1e-9);

/** La zona di un punto: "ilat_ilon" sulla griglia di LATO_ZONA. */
export function zona(lat, lon) {
  return `${riga(lat)}_${riga(lon)}`;
}

/** La zona di un punto e le otto intorno: chi è vicino al bordo vede oltre. */
export function zoneVicine(lat, lon) {
  const i = riga(lat);
  const j = riga(lon);
  const zone = [];
  for (const di of [-1, 0, 1]) for (const dj of [-1, 0, 1]) zone.push(`${i + di}_${j + dj}`);
  return zone;
}

const ZONA = /^-?\d{1,4}_-?\d{1,4}$/;
export const zonaValida = (z) => typeof z === 'string' && ZONA.test(z);

/** Legge una segnalazione nuova. Restituisce `{tipo, lat, lon}` o `{errore}`. */
export function leggiNuova(corpo) {
  if (!corpo || typeof corpo !== 'object') return { errore: 'corpo mancante' };
  const { tipo, lat, lon } = corpo;
  if (!TIPI.includes(tipo)) return { errore: 'tipo sconosciuto' };
  if (typeof lat !== 'number' || typeof lon !== 'number') return { errore: 'posizione mancante' };
  if (!(lat >= -85 && lat <= 85 && lon >= -180 && lon <= 180)) return { errore: 'posizione fuori dal mondo' };
  // Cinque decimali bastano (un metro): di più direbbe troppo del telefono.
  return { tipo, lat: Math.round(lat * 1e5) / 1e5, lon: Math.round(lon * 1e5) / 1e5 };
}

/** Una segnalazione nuova, pronta da salvare. */
export function crea({ tipo, lat, lon }, ora, id) {
  return { id, tipo, lat, lon, creata: ora, scade: ora + DURATA_MIN[tipo] * 60_000, conferme: 0, smentite: 0 };
}

/** Il voto di chi passa: `ancora` vero se c'è ancora. Restituisce la nuova, o null se va tolta. */
export function vota(s, ancora, ora) {
  const n = { ...s };
  if (ancora) {
    n.conferme += 1;
    n.scade = Math.max(n.scade, ora) + DURATA_MIN[s.tipo] * 60_000 * PROROGA;
  } else {
    n.smentite += 1;
    if (n.smentite >= SMENTITE_PER_TOGLIERE + n.conferme) return null;
  }
  return n;
}

export const viva = (s, ora) => s.scade > ora;

/** Cosa vede il telefono: niente che non serva. */
export const pubblica = (s) => ({
  id: s.id,
  tipo: s.tipo,
  lat: s.lat,
  lon: s.lon,
  creata: s.creata,
  conferme: s.conferme,
});

/**
 * L'indirizzo `/v1/segnalazioni[/<zona>~<id>/voto]`. Restituisce
 * `{azione: 'elenco'|'nuova'|'voto', zona?, id?}` o `{errore, stato}`.
 */
export function leggiIndirizzo(metodo, url) {
  const u = new URL(url);
  if (u.pathname === '/v1/segnalazioni') {
    if (metodo === 'GET') {
      const lat = Number(u.searchParams.get('lat') ?? NaN);
      const lon = Number(u.searchParams.get('lon') ?? NaN);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return { errore: 'lat e lon', stato: 400 };
      return { azione: 'elenco', lat, lon };
    }
    if (metodo === 'POST') return { azione: 'nuova' };
    return { errore: 'metodo', stato: 405 };
  }
  const m = u.pathname.match(/^\/v1\/segnalazioni\/([^/~]+)~([A-Za-z0-9_-]{8,32})\/voto$/);
  if (m && metodo === 'POST') {
    if (!zonaValida(m[1])) return { errore: 'zona non valida', stato: 400 };
    return { azione: 'voto', zona: m[1], id: `${m[1]}~${m[2]}` };
  }
  return { errore: 'indirizzo sconosciuto', stato: 404 };
}
