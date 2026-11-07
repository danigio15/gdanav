// Quante tessere costruire, con che dettaglio, e quali buttare.
//
// Il telefono regge un numero di triangoli: vicino all'auto tutto (alberi,
// lampioni), più in là solo strade ed edifici, oltre la nebbia niente.
// Le tessere costruite restano finché stanno entro [TENUTA_M]: senza rete
// la scena resta quella di prima, non sparisce.

export const BUDGET = {
  /** Triangoli al più, in tutto. */
  triangoli: 900000,
  /** Entro questa distanza dall'auto (dal bordo della tessera) il dettaglio è pieno. */
  pienoM: 900,
  /** Oltre questa non si costruisce. */
  lontanoM: 3200,
  /** Le tessere costruite si tengono fino a qui (poi si buttano). */
  tenutaM: 6000,
  /** Tessere costruite al più, tenute comprese. */
  tessere: 16,
};

/** La distanza da [x, y] al quadrato centrato in [cx, cy] di lato [lato]. */
export function distanzaTessera(x, y, cx, cy, lato) {
  const dx = Math.max(0, Math.abs(x - cx) - lato / 2);
  const dy = Math.max(0, Math.abs(y - cy) - lato / 2);
  return Math.hypot(dx, dy);
}

/**
 * Il piano: per ogni tessera disponibile (`{chiave, cx, cy, lato}` in metri
 * della scena) che dettaglio serve ([dettaglio] «pieno», «ridotto» o null),
 * e quali delle [costruite] (`{chiave, cx, cy, lato, dettaglio, triangoli}`)
 * buttare. Le richieste vanno in ordine: prima le più vicine.
 */
export function pianoTessere(disponibili, costruite, x, y, budget = BUDGET) {
  const voluto = new Map();
  for (const t of disponibili) {
    const d = distanzaTessera(x, y, t.cx, t.cy, t.lato);
    if (d > budget.lontanoM) continue;
    voluto.set(t.chiave, { ...t, d, dettaglio: d <= budget.pienoM ? 'pieno' : 'ridotto' });
  }
  const richieste = [...voluto.values()]
    .filter((t) => {
      const c = costruite.get(t.chiave);
      // Una tessera piena va bene anche se ne basterebbe una ridotta.
      return !c || (c.dettaglio === 'ridotto' && t.dettaglio === 'pieno');
    })
    .sort((a, b) => a.d - b.d);
  // Le costruite: lontane, o oltre il numero e i triangoli, si buttano
  // (prima le più lontane).
  const tenute = [...costruite.values()]
    .map((c) => ({ ...c, d: distanzaTessera(x, y, c.cx, c.cy, c.lato) }))
    .sort((a, b) => a.d - b.d);
  const butta = [];
  let tri = 0;
  let n = 0;
  for (const c of tenute) {
    const serve = voluto.has(c.chiave);
    if (c.d > budget.tenutaM || n >= budget.tessere || (tri + c.triangoli > budget.triangoli && !serve)) {
      butta.push(c.chiave);
      continue;
    }
    tri += c.triangoli;
    n++;
  }
  // Senza posto, le richieste lontane aspettano.
  const posto = budget.tessere - n;
  return { richieste: richieste.slice(0, Math.max(0, posto + butta.length)), butta, triangoli: tri };
}

/**
 * Quali tessere disegnare: le costruite entro la nebbia, finché i triangoli
 * stanno nel budget (prima le vicine). Le altre restano pronte, spente.
 */
export function daDisegnare(costruite, x, y, budget = BUDGET) {
  const ordinate = [...costruite.values()]
    .map((c) => ({ chiave: c.chiave, triangoli: c.triangoli, d: distanzaTessera(x, y, c.cx, c.cy, c.lato) }))
    .sort((a, b) => a.d - b.d);
  const si = new Set();
  let tri = 0;
  for (const c of ordinate) {
    if (c.d > budget.lontanoM + 400) break;
    if (tri + c.triangoli > budget.triangoli && si.size) break;
    tri += c.triangoli;
    si.add(c.chiave);
  }
  return { si, triangoli: tri };
}
