// Le colonnine rapide di OpenStreetMap a riquadri di mezzo grado, tenute in
// cache da Cloudflare per una settimana: il telefono non chiede più a
// Overpass (che dagli indirizzi degli operatori mobili mette in coda), e lo
// stesso tratto di strada si chiede una volta sola per tutti.

export const LATO = 0.5;

/** Dopo una settimana si prova a rinfrescare; se Overpass non risponde si
 * serve la copia vecchia, che resta in cache fino a due mesi. */
export const FRESCA_MS = 7 * 24 * 3600 * 1000;
export const DURATA_CACHE_S = 60 * 24 * 3600;

/** Si riprova ancora dopo una risposta di «troppo occupato». */
export const occupato = (stato) => stato === 429 || stato === 503 || stato === 504;

export const fresca = (salvata, ora) => Number.isFinite(salvata) && ora - salvata < FRESCA_MS;

export const SERVER_OVERPASS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

// Le stesse di ClienteOverpass.retiRapide, nel motore Dart.
export const RETI_RAPIDE =
  'Ionity|Tesla|Free To X|Electra|Fastned|Ewiva|Atlante|Allego|Plenitude|Be Charge|Enel X|A2A|Neogy|Zunder|Powerdot|Duferco';

/** /v1/colonnine/<riga>/<colonna>: il riquadro [riga*0,5, colonna*0,5]. */
export function leggiRiquadro(metodo, url) {
  const m = new URL(url).pathname.match(/^\/v1\/colonnine\/(-?\d{1,3})\/(-?\d{1,3})$/);
  if (!m) return { errore: 'indirizzo sconosciuto', stato: 404 };
  if (metodo !== 'GET') return { errore: 'metodo', stato: 405 };
  const riga = Number(m[1]);
  const colonna = Number(m[2]);
  if (riga < -180 || riga >= 180 || colonna < -360 || colonna >= 360) return { errore: 'fuori dal mondo', stato: 400 };
  return { riga, colonna };
}

export function richiestaOverpass(riga, colonna) {
  const b = [riga * LATO, colonna * LATO, (riga + 1) * LATO, (colonna + 1) * LATO].join(',');
  const rapide = '[~"^socket:(type2_combo|chademo|tesla_supercharger.*)$"~"."]';
  const filtri = [
    `["amenity"="charging_station"]${rapide}`,
    `["amenity"="charging_station"]["operator"~"${RETI_RAPIDE}",i]`,
    `["amenity"="charging_station"]["brand"~"${RETI_RAPIDE}",i]`,
  ];
  return `[out:json][timeout:25];(${filtri.map((f) => `nwr${f}(${b});`).join('')});out center tags;`;
}

/** In tempo scaduto Overpass risponde 200 con un avviso e niente dati. */
export const rispostaBuona = (testo) => testo.startsWith('{') && !/"remark"\s*:\s*"[^"]*error/i.test(testo);
