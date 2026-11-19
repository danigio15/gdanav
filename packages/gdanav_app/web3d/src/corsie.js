// La vista «Corsie»: le strade con le loro corsie vere, le righe bianche,
// le frecce dipinte, le strisce pedonali e il percorso sulla corsia giusta
// (come le mappe delle corsie dei navigatori cinesi, ma con le regole
// italiane: si tiene la destra, tutta la segnaletica è bianca).
//
// Le tessere vettoriali della mappa (OpenMapTiles) le corsie non le hanno:
// le corsie arrivano a parte, da OpenStreetMap, col messaggio `corsie`. Qui
// le parti pure (niente three.js, niente pagina): leggere i tag, quante e
// quanto larghe sono le corsie, le frecce, come si raccordano le vie dove
// una carreggiata si divide, e su quale corsia sta il percorso. Le usano la
// pagina (il percorso) e il lavoratore (`segnaletica.js`, le geometrie).
//
// ── Il formato dei dati (messaggio `corsie`, versione 1) ─────────────────
//
// Lo stesso JSON che dà il relay di GdANav per tessera z14,
// `GET /v1/corsie/14/<x>/<y>` (da Overpass; le strade intere, non tagliate
// sul bordo, i nodi e gli alberi fino a trenta metri fuori); nelle prove lo
// fa `collaudo/corsie-osm.mjs` dalle risposte dell'API di OpenStreetMap.
//
//   {
//     "v": 1,
//     "z": 14, "x": 8817, "y": 6123,      // la tessera (dal relay)
//     "strade": [                          // le vie guidabili ([CLASSI_CORSIE])
//       { "id": 123, "hw": "motorway",     // l'id della via e `highway`
//         "g": [lon, lat, lon, lat, …],    // i nodi in fila, 6 decimali
//         "lanes": "4", "turn:lanes": "|||slight_right", "oneway": "yes",
//         "placement": "middle_of:2", …    // i tag di [TAG_STRADE] che ci sono,
//       }, …                               // così come sono in OpenStreetMap
//     ],
//     "nodi": [                            // i nodi che si disegnano ([TIPI_NODI])
//       { "id": 456, "g": [lon, lat],
//         "highway": "crossing", "crossing:markings": "zebra", … }  // [TAG_NODI]
//     ],
//     "alberi": [[lon, lat], …],           // `natural=tree`, uno per uno
//     "filari": [{ "id": 789, "g": [lon, lat, …] }]   // `natural=tree_row`
//   }
//
// I tag restano stringhe di OpenStreetMap (il relay non deve capire niente):
// una via che manca di un tag prende quello che dice la sua classe. Due vie
// si toccano dove hanno un nodo con le stesse coordinate (i 6 decimali).
// Le strade `service` il relay le manda, ma qui non hanno corsie (restano
// fuori da [CLASSI_CORSIE]).
//
// Una tessera senza i dati veri (mai arrivati, arrivati vuoti, il relay in
// errore) le corsie le stima dalla tessera vettoriale, nello stesso formato
// (`stima.js`: le vie con la classe e il senso unico, id negativi, niente
// nodi né alberi); quando arrivano quelli veri la tessera si rifà con loro.

import { mercX, mercY } from './geo.js';

/** Le classi di strada che hanno le corsie disegnate. */
export const CLASSI_CORSIE = new Set([
  'motorway',
  'motorway_link',
  'trunk',
  'trunk_link',
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
  'living_street',
]);

/** I tag delle vie che servono (gli altri il relay li lascia). */
export const TAG_STRADE = [
  'lanes',
  'lanes:forward',
  'lanes:backward',
  'turn:lanes',
  'turn:lanes:forward',
  'turn:lanes:backward',
  'change:lanes',
  'change:lanes:forward',
  'change:lanes:backward',
  'oneway',
  'junction',
  'placement',
  'placement:forward',
  'width',
  'bridge',
  'tunnel',
  'layer',
];

/** I nodi che si disegnano: strisce, semafori, stop, precedenze, uscite. */
export const TIPI_NODI = new Set(['crossing', 'traffic_signals', 'stop', 'give_way', 'motorway_junction']);
export const TAG_NODI = ['highway', 'crossing', 'crossing:markings', 'traffic_signals:direction', 'direction', 'ref', 'name'];

const intero = (v) => {
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n >= 0 ? n : null;
};
const base = (hw) => String(hw ?? '').replace(/_link$/, '');
const raccordo = (hw) => String(hw ?? '').endsWith('_link');
const grande = (hw) => base(hw) === 'motorway' || base(hw) === 'trunk';

/**
 * Quanto è larga una corsia, in metri. Le norme italiane: 3,75 in
 * autostrada, 3,5 sulle extraurbane principali e sulle rampe, 3,25 sulle
 * strade di città che contano, 3 nelle vie di quartiere.
 */
export function larghezzaCorsia(hw) {
  const b = base(hw);
  if (b === 'motorway') return raccordo(hw) ? 3.5 : 3.75;
  if (b === 'trunk') return 3.5;
  if (b === 'primary' || b === 'secondary' || b === 'tertiary') return 3.25;
  return 3.0;
}

/**
 * Il senso unico di una via: 1 come la geometria, -1 al contrario, 0 i due
 * sensi. Le autostrade, le loro rampe e le rotatorie lo sono anche senza
 * dirlo (come vuole OpenStreetMap).
 */
export function sensoUnico(s) {
  const o = String(s.oneway ?? '');
  if (o === '-1' || o === 'reverse') return -1;
  if (o === 'yes' || o === '1' || o === 'true') return 1;
  if (o === 'no' || o === '0' || o === 'false' || o === 'reversible' || o === 'alternating') return 0;
  if (s.junction === 'roundabout' || s.junction === 'circular') return 1;
  if (s.hw === 'motorway' || s.hw === 'motorway_link') return 1;
  return 0;
}

/**
 * Le corsie di una via (nel verso della sua geometria): quante [avanti],
 * quante [indietro], e se è una corsia sola per i due sensi ([condivisa]).
 * Senza `lanes`: due per senso in autostrada e sulle extraurbane, una
 * altrimenti.
 */
export function corsieDi(s) {
  const n = intero(s.lanes);
  if (sensoUnico(s) !== 0) return { avanti: n || (grande(s.hw) && !raccordo(s.hw) ? 2 : 1), indietro: 0, condivisa: false };
  const f = intero(s['lanes:forward']);
  const b = intero(s['lanes:backward']);
  if (f && b) return { avanti: f, indietro: b, condivisa: false };
  if (n) {
    if (f) return { avanti: f, indietro: Math.max(0, n - f), condivisa: false };
    if (b) return { avanti: Math.max(0, n - b), indietro: b, condivisa: false };
    if (n === 1) return { avanti: 1, indietro: 0, condivisa: true };
    return { avanti: Math.ceil(n / 2), indietro: Math.floor(n / 2), condivisa: false };
  }
  return { avanti: f || 1, indietro: b || 1, condivisa: false };
}

/** Le frecce che si dipingono. */
export const FRECCE = new Set(['left', 'slight_left', 'sharp_left', 'through', 'right', 'slight_right', 'sharp_right', 'reverse', 'merge_to_left', 'merge_to_right']);

/**
 * Le frecce di ogni corsia da `turn:lanes` (da sinistra a destra nel verso
 * di marcia): «left;through|right» → [['left', 'through'], ['right']]. Una
 * corsia vuota o «none» non ha frecce. `null` senza il tag.
 */
export function frecceCorsie(valore) {
  if (typeof valore !== 'string') return null;
  return valore.split('|').map((c) =>
    c
      .split(';')
      .map((x) => x.trim())
      .filter((x) => FRECCE.has(x)),
  );
}

/** I cambi di corsia permessi (`change:lanes`): per corsia «yes», «no», «not_left», «not_right». */
export function cambiCorsie(valore) {
  if (typeof valore !== 'string') return null;
  return valore.split('|').map((c) => (['no', 'not_left', 'not_right'].includes(c.trim()) ? c.trim() : 'yes'));
}

/**
 * Di quanto il mezzo delle corsie sta a sinistra della linea della via
 * (`placement`): «middle_of:2» su quattro corsie vuol dire che la linea
 * passa nel mezzo della seconda, e il mezzo delle corsie le sta mezza
 * corsia a destra. Senza il tag la linea è nel mezzo.
 */
export function scostamentoPosa(placement, avanti, indietro, lw) {
  const m = /^(left_of|right_of|middle_of):(\d+)$/.exec(String(placement ?? ''));
  if (!m) return 0;
  const k = Math.min(Math.max(1, +m[2]), avanti);
  const W = (avanti + indietro) * lw;
  const sinistraK = W / 2 - indietro * lw - (k - 1) * lw;
  const linea = m[1] === 'left_of' ? sinistraK : m[1] === 'middle_of' ? sinistraK - lw / 2 : sinistraK - lw;
  return -linea;
}

const ALTRO_SENSO = [
  ['forward', 'backward'],
  ['backward', 'forward'],
];

/**
 * Una via del messaggio, pronta: girata se è a senso unico al contrario (da
 * lì in poi il senso è sempre quello della geometria), con le corsie, le
 * frecce, la larghezza e i margini fuori dalle corsie (la corsia di
 * emergenza in autostrada). [ll]: `[lon, lat, …]`.
 */
export function normalizza(s) {
  let ll = Array.from(s.g ?? []);
  let t = s;
  if (sensoUnico(s) === -1) {
    const giro = [];
    for (let i = ll.length - 2; i >= 0; i -= 2) giro.push(ll[i], ll[i + 1]);
    ll = giro;
    t = { ...s, oneway: 'yes' };
    for (const [a, b] of ALTRO_SENSO) {
      for (const k of Object.keys(s)) if (k.endsWith(':' + a)) t[k.slice(0, -a.length) + b] = s[k];
    }
  }
  const senso = sensoUnico(t) ? 1 : 0;
  const c = corsieDi(t);
  const lw = larghezzaCorsia(t.hw);
  const frecce = senso ? frecceCorsie(t['turn:lanes'] ?? t['turn:lanes:forward']) : frecceCorsie(t['turn:lanes:forward']);
  const v = {
    id: t.id,
    hw: t.hw,
    ll,
    senso,
    avanti: c.avanti,
    indietro: c.indietro,
    condivisa: c.condivisa,
    lw,
    // Le frecce che non tornano col numero delle corsie non si usano.
    frecce: frecce && frecce.length === c.avanti ? frecce : null,
    frecceIndietro: (() => {
      const f = senso ? null : frecceCorsie(t['turn:lanes:backward']);
      return f && f.length === c.indietro ? f : null;
    })(),
    cambi: (() => {
      const f = cambiCorsie(senso ? (t['change:lanes'] ?? t['change:lanes:forward']) : t['change:lanes:forward']);
      return f && f.length === c.avanti ? f : null;
    })(),
    posa: scostamentoPosa(t.placement ?? t['placement:forward'], c.avanti, c.indietro, lw),
    ponte: !!t.bridge && t.bridge !== 'no',
    galleria: !!t.tunnel && t.tunnel !== 'no',
    livello: intero(t.layer) ?? 0,
  };
  v.margini = margini(v);
  return v;
}

/**
 * L'asfalto fuori dalle corsie, `[sinistra, destra]` nel verso della via:
 * in autostrada la banchina a sinistra e la corsia di emergenza a destra
 * (che non c'è dove la corsia più a destra è quella che esce: lì ne prende
 * il posto); sulle rampe e nelle strade una banchina.
 */
export function margini(v) {
  const b = base(v.hw);
  const ultima = v.frecce?.[v.frecce.length - 1] ?? [];
  const esce = ultima.some((f) => f.includes('right'));
  if (v.senso && !raccordo(v.hw) && b === 'motorway') return [0.7, esce ? 0.6 : 3.0];
  if (v.senso && !raccordo(v.hw) && b === 'trunk') return [0.5, esce ? 0.6 : 1.5];
  if (raccordo(v.hw) && grande(v.hw)) return [0.6, 1.0];
  return [0.35, 0.35];
}

/** La larghezza delle sole corsie. */
export const larghezzaCorsie = (v) => (v.avanti + v.indietro) * v.lw;

/**
 * Il mezzo della corsia [i] (da sinistra, nel suo verso) a sinistra della
 * linea della via, in metri, per chi va nel verso della geometria
 * ([avanti]) o al contrario (allora a sinistra di chi va al contrario).
 */
export function centroCorsia(v, i, avanti = true) {
  if (v.condivisa) return avanti ? v.posa : -v.posa;
  const W = larghezzaCorsie(v);
  if (avanti) return v.posa + W / 2 - v.indietro * v.lw - (i + 0.5) * v.lw;
  return -v.posa + W / 2 - v.avanti * v.lw - (i + 0.5) * v.lw;
}

/** I bordi delle corsie a sinistra della linea (nel verso della via): sinistro, destro, e la riga di mezzo fra i due sensi. */
export function bordiCorsie(v) {
  const W = larghezzaCorsie(v);
  return { sinistra: v.posa + W / 2, destra: v.posa - W / 2, mezzeria: v.posa + W / 2 - v.indietro * v.lw };
}

// ── Geometria piana ─────────────────────────────────────────────────────

/** I metri progressivi lungo una linea `[[x, y], …]`. */
export function progressive(p) {
  const s = [0];
  for (let k = 1; k < p.length; k++) s.push(s[k - 1] + Math.hypot(p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1]));
  return s;
}

/** La normale a sinistra in ogni punto (media dei due tratti attorno). */
export function normali(p) {
  const n = p.length;
  return p.map((_, k) => {
    const a = p[Math.max(0, k - 1)];
    const b = p[Math.min(n - 1, k + 1)];
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const l = Math.hypot(dx, dy) || 1;
    return [-dy / l, dx / l];
  });
}

/** La linea con un punto almeno ogni [passo] metri (gli angoli restano). */
export function infittisci(p, passo) {
  const out = [p[0]];
  for (let k = 1; k < p.length; k++) {
    const a = p[k - 1];
    const b = p[k];
    const n = Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / passo);
    for (let j = 1; j < n; j++) out.push(a.map((v, i) => v + ((b[i] - v) * j) / n));
    out.push(b);
  }
  return out;
}

const morbido = (u) => {
  const t = Math.max(0, Math.min(1, u));
  return t * t * (3 - 2 * t);
};

/**
 * La linea spostata di lato, punto per punto, di [spost(s)] metri (a
 * sinistra positivo): i bordi, le righe, le corsie.
 */
export function spostata(p, spost, s = progressive(p), nn = normali(p)) {
  return p.map((q, k) => {
    const o = typeof spost === 'function' ? spost(s[k], k) : spost;
    return [q[0] + nn[k][0] * o, q[1] + nn[k][1] * o, ...q.slice(2)];
  });
}

// ── I raccordi dove le carreggiate si dividono e si uniscono ─────────────

/** Quanto è lungo, al più, il raccordo all'inizio o alla fine di una via. */
const RACCORDO_M = { grande: 90, altro: 35 };

/**
 * Dove una carreggiata a senso unico si divide (uno svincolo) o due si
 * uniscono, le vie di OpenStreetMap partono tutte dallo stesso nodo, sulla
 * linea della via di prima: la rampa d'uscita nascerebbe in mezzo alla
 * seconda corsia e tagliherebbe le altre di traverso. Ogni ramo prende
 * invece le corsie di prima che gli toccano — il più a sinistra quelle a
 * sinistra, il più a destra quelle a destra — e la sua linea parte da lì,
 * per tornare piano (in [RACCORDO_M]) dov'è disegnata. Lo stesso dove una
 * corsia nasce o finisce (la corsia di decelerazione): le corsie di sinistra
 * restano dritte, quella di destra si aggiunge.
 *
 * [strade]: le vie normalizzate ([normalizza]) con `xy` (metri, `[[x, y],
 * …]`). Restituisce per ogni via `{o0, t0, o1, t1}`: lo spostamento (a
 * sinistra positivo) all'inizio e alla fine, e su quanti metri si spegne.
 */
export function raccordi(strade) {
  const chiave = (q) => Math.round(q[0] * 5) + ',' + Math.round(q[1] * 5);
  const capi = new Map();
  const out = strade.map(() => ({ o0: 0, t0: 0, o1: 0, t1: 0 }));
  strade.forEach((v, i) => {
    if (!v.senso || v.xy.length < 2) return;
    for (const fine of [0, 1]) {
      const k = chiave(fine ? v.xy[v.xy.length - 1] : v.xy[0]);
      if (!capi.has(k)) capi.set(k, { entrano: [], escono: [] });
      capi.get(k)[fine ? 'entrano' : 'escono'].push(i);
    }
  });
  const lunghezza = (v) => progressive(v.xy).at(-1);
  // La direzione di una via vista dal nodo, a una ventina di metri.
  const verso = (v, dallInizio) => {
    const p = dallInizio ? v.xy : [...v.xy].reverse();
    let k = 1;
    let d = 0;
    while (k < p.length - 1 && d < 20) {
      d += Math.hypot(p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1]);
      if (d < 20) k++;
    }
    return Math.atan2(p[k][1] - p[0][1], p[k][0] - p[0][0]);
  };
  const giro = (a) => Math.atan2(Math.sin(a), Math.cos(a));
  const centro = (v, da, n) => {
    let c = 0;
    for (let j = da; j < da + n; j++) c += centroCorsia(v, Math.min(v.avanti - 1, Math.max(0, j)));
    return c / n;
  };
  // A [unica] (una via) toccano [rami] (più vie): le corsie di [unica] in
  // fila da sinistra, ogni ramo un blocco. Restituisce lo spostamento di ognuno.
  const blocchi = (unica, rami, angolo) => {
    const ordinati = rami.map((j) => ({ j, a: angolo(j) })).sort((p, q) => q.a - p.a);
    const n = unica.avanti;
    const res = new Map();
    let dopo = 0;
    ordinati.forEach(({ j }, r) => {
      const ramo = strade[j];
      const m = Math.min(ramo.avanti, n);
      // Il primo a sinistra, l'ultimo a destra, quelli in mezzo in fila.
      const da = r === ordinati.length - 1 && r > 0 ? n - m : Math.min(dopo, n - m);
      dopo = da + m;
      const blocco = centro(unica, da, m);
      // Il blocco del ramo: le sue m corsie a sinistra (se ne ha di più, la
      // nuova nasce a destra).
      const suo = centro(ramo, 0, m);
      res.set(j, blocco - suo);
    });
    return res;
  };
  for (const { entrano, escono } of capi.values()) {
    if (!entrano.length || !escono.length) continue;
    if (entrano.length === 1) {
      const a = strade[entrano[0]];
      const dirA = verso(a, false) + Math.PI;
      const sp = blocchi(a, escono, (j) => giro(verso(strade[j], true) - dirA));
      for (const [j, o] of sp) {
        const v = strade[j];
        if (Math.abs(o) < 0.05) continue;
        out[j].o0 = o;
        out[j].t0 = Math.min(grande(v.hw) ? RACCORDO_M.grande : RACCORDO_M.altro, lunghezza(v) * 0.6);
      }
    } else if (escono.length === 1) {
      const b = strade[escono[0]];
      const dirB = verso(b, true);
      // Chi entra da sinistra prende le corsie di sinistra.
      const sp = blocchi(b, entrano, (j) => giro(verso(strade[j], false) + Math.PI - dirB) * -1);
      for (const [j, o] of sp) {
        const v = strade[j];
        if (Math.abs(o) < 0.05) continue;
        out[j].o1 = o;
        out[j].t1 = Math.min(grande(v.hw) ? RACCORDO_M.grande : RACCORDO_M.altro, lunghezza(v) * 0.6);
      }
    }
  }
  // Un ramo a senso unico che si stacca da una strada a doppio senso (la
  // svolta a destra che taglia l'angolo) o ci arriva: in OpenStreetMap parte
  // dalla linea di mezzo della strada, e lì sotto c'è l'altro senso di
  // marcia. Parte invece dalla corsia di chi lo prende (la più a destra, se
  // si stacca a destra), e arriva sulla corsia in cui entra.
  const tutti = new Map();
  strade.forEach((v, i) => {
    v.xy.forEach((q, k) => {
      const kk = chiave(q);
      if (!tutti.has(kk)) tutti.set(kk, []);
      tutti.get(kk).push({ i, k });
    });
  });
  // La direzione di chi va sulla via [a] dal punto [k] verso [passo] (o ci arriva, con [arriva]).
  const versoSu = (a, k, passo, arriva) => {
    const p = a.xy;
    let j = k;
    let d = 0;
    while (j + passo >= 0 && j + passo < p.length && d < 15) {
      d += Math.hypot(p[j + passo][0] - p[j][0], p[j + passo][1] - p[j][1]);
      j += passo;
    }
    if (j === k) return null;
    const ang = Math.atan2(p[j][1] - p[k][1], p[j][0] - p[k][0]);
    return arriva ? ang + Math.PI : ang;
  };
  strade.forEach((v, j) => {
    if (!v.senso || v.xy.length < 2) return;
    for (const fine of [0, 1]) {
      if (fine ? out[j].t1 : out[j].t0) continue;
      const q = fine ? v.xy[v.xy.length - 1] : v.xy[0];
      // Come va il ramo al nodo: partendo, o arrivando.
      const dirV = fine ? verso(v, false) + Math.PI : verso(v, true);
      let meglio = null;
      for (const { i, k } of tutti.get(chiave(q)) ?? []) {
        const a = strade[i];
        if (a.senso || i === j) continue;
        for (const avanti of [true, false]) {
          // Staccandosi: chi arriva al nodo su [a]; arrivando: chi riparte da lì.
          const d = fine ? versoSu(a, k, avanti ? 1 : -1, false) : versoSu(a, k, avanti ? -1 : 1, true);
          if (d === null) continue;
          const ang = giro(dirV - d);
          if (Math.abs(ang) < Math.PI / 3.2 && (!meglio || Math.abs(ang) < Math.abs(meglio.ang))) meglio = { a, avanti, ang };
        }
      }
      if (!meglio) continue;
      const { a, avanti, ang } = meglio;
      const n = avanti ? a.avanti : a.indietro;
      if (!n) continue;
      // Il ramo a destra di chi va su [a] prende (o arriva su) la corsia più a destra.
      const corsia = ang < 0 ? n - 1 : 0;
      const o = centroCorsia(a, corsia, avanti) * Math.cos(ang) - centro(v, 0, v.avanti);
      if (Math.abs(o) < 0.05) continue;
      const t = Math.min(RACCORDO_M.altro, lunghezza(v) * 0.6);
      if (fine) Object.assign(out[j], { o1: o, t1: t });
      else Object.assign(out[j], { o0: o, t0: t });
    }
  });
  return out;
}

/** Lo spostamento di raccordo a [s] metri di una via lunga [L] (vedi [raccordi]). */
export function spostamentoRaccordo(r, s, L) {
  let o = 0;
  if (r.t0 > 0) o += r.o0 * (1 - morbido(s / r.t0));
  if (r.t1 > 0) o += r.o1 * (1 - morbido((L - s) / r.t1));
  return o;
}

/**
 * I dati del messaggio `corsie`, pronti: le vie normalizzate, coi raccordi
 * già fatti nella geometria (`ll`, fitta: un punto ogni quattro metri), e i
 * nodi. Si fa una volta sola per tutti i dati, sulla pagina: ogni tessera
 * poi ne riceve un pezzo, e i raccordi devono essere gli stessi in tutte.
 */
export function preparaCorsie(dati) {
  const strade = (dati?.strade ?? []).filter((s) => CLASSI_CORSIE.has(s.hw) && Array.isArray(s.g) && s.g.length >= 4).map(normalizza);
  // Un piano in metri attorno al primo punto (per i raccordi bastano).
  const lon0 = strade[0]?.ll[0] ?? 0;
  const lat0 = strade[0]?.ll[1] ?? 0;
  const mLat = 111195;
  const mLon = mLat * Math.cos((lat0 * Math.PI) / 180);
  for (const v of strade) {
    v.xy = [];
    for (let i = 0; i < v.ll.length; i += 2) v.xy.push([(v.ll[i] - lon0) * mLon, (v.ll[i + 1] - lat0) * mLat]);
  }
  const rr = raccordi(strade);
  strade.forEach((v, i) => {
    const r = rr[i];
    v.raccordo = r;
    // La geometria vera resta per i nodi (chi tocca chi) e per agganciare il
    // percorso, che segue le vie di sempre; `ll` è quella da disegnare.
    v.llVia = v.ll;
    if (!r.t0 && !r.t1) {
      delete v.xy;
      return;
    }
    const p = infittisci(v.xy, 4);
    const s = progressive(p);
    const L = s.at(-1);
    const q = spostata(p, (sv) => spostamentoRaccordo(r, sv, L), s);
    v.ll = q.flatMap(([x, y]) => [lon0 + x / mLon, lat0 + y / mLat]);
    delete v.xy;
  });
  const nodi = (dati?.nodi ?? []).filter((n) => TIPI_NODI.has(n.highway) && Array.isArray(n.g));
  // Gli alberi veri: solo quelli che la mappa ha.
  const alberi = (dati?.alberi ?? []).filter((a) => Array.isArray(a) && a.length >= 2);
  const filari = (dati?.filari ?? []).filter((f) => Array.isArray(f?.g) && f.g.length >= 4);
  return { strade, nodi, alberi, filari };
}

/**
 * Le tessere z14 (`"14/x/y"`) di cui il messaggio `corsie` [dati] porta le
 * corsie vere: quella che dice il relay (`z`, `x`, `y`), o senza, quelle dove
 * stanno le sue vie. Nessuna se non ha vie: una tessera arrivata vuota (o
 * mai arrivata) si stima (vedi `stima.js`).
 */
export function tessereConCorsieVere(dati) {
  const strade = dati?.strade ?? [];
  if (!strade.length) return [];
  if (Number.isInteger(dati.x) && Number.isInteger(dati.y) && (dati.z ?? 14) === 14) return [`14/${dati.x}/${dati.y}`];
  const out = new Set();
  for (const st of strade) {
    for (let i = 0; i + 1 < (st.g?.length ?? 0); i += 2) out.add(`14/${Math.floor(mercX(st.g[i]) * 2 ** 14)}/${Math.floor(mercY(st.g[i + 1]) * 2 ** 14)}`);
  }
  return [...out];
}

/** Il riquadro `[ovest, sud, est, nord]` dei punti `[lon, lat, …]`. */
export function riquadroLonLat(ll) {
  let [a, b, c, d] = [Infinity, Infinity, -Infinity, -Infinity];
  for (let i = 0; i + 1 < ll.length; i += 2) {
    a = Math.min(a, ll[i]);
    b = Math.min(b, ll[i + 1]);
    c = Math.max(c, ll[i]);
    d = Math.max(d, ll[i + 1]);
  }
  return [a, b, c, d];
}

/**
 * Fin dove arriva quello che il messaggio `corsie` [dati] disegna (le vie, i
 * nodi, gli alberi): `[ovest, sud, est, nord]`, o `null` se non ha niente.
 * Le tessere costruite che lo toccano si rifanno; le altre restano.
 */
export function riquadroCorsie(dati) {
  const ll = [];
  for (const s of dati?.strade ?? []) if (Array.isArray(s.g)) ll.push(...s.g);
  for (const n of dati?.nodi ?? []) if (Array.isArray(n.g)) ll.push(n.g[0], n.g[1]);
  for (const a of dati?.alberi ?? []) if (Array.isArray(a)) ll.push(a[0], a[1]);
  for (const f of dati?.filari ?? []) if (Array.isArray(f?.g)) ll.push(...f.g);
  const r = riquadroLonLat(ll);
  return Number.isFinite(r[0]) ? r : null;
}

// ── La corsia dell'auto, senza percorso ─────────────────────────────────

/**
 * Di quanto spostare di lato (a sinistra positivo, rispetto a [rotta],
 * gradi da nord) l'auto in [x, y] perché stia nella sua corsia: la più a
 * destra del suo senso di marcia, come si guida in Italia (senza percorso
 * non si sa dove girerà). `null` se sotto non c'è una via con le corsie
 * che vada come l'auto. [indice]: un [IndiceCorsie] nei metri della scena.
 *
 * «Va al contrario»: senza percorso l'auto stava sulla riga di mezzo, a
 * cavallo dei due sensi, e nella vista «Corsie» pareva sulla corsia di chi
 * viene incontro.
 */
export function corsiaDellAuto(indice, x, y, rotta) {
  if (!indice || !Number.isFinite(rotta)) return null;
  const r = (rotta * Math.PI) / 180;
  const dx = Math.sin(r);
  const dy = Math.cos(r);
  let meglio = null;
  let bv = Infinity;
  for (const [i, k] of indice.vicini(x, y)) {
    const v = indice.strade[i];
    const t = sulTratto(v, k, x, y);
    if (t.d > 9) continue;
    const cos = t.tx * dx + t.ty * dy;
    if (Math.abs(cos) < 0.7 || (v.senso && cos < 0)) continue;
    const voto = t.d + 15 * (1 - Math.abs(cos));
    if (voto < bv) {
      bv = voto;
      meglio = { v, t, av: cos > 0 };
    }
  }
  if (!meglio) return null;
  const { v, t, av } = meglio;
  const nc = av ? v.avanti : v.indietro;
  if (!nc) return null;
  const o = centroCorsia(v, v.condivisa ? 0 : nc - 1, av) + (v.raccordo && v.sxy ? spostamentoRaccordo(v.raccordo, t.s, v.sxy.at(-1)) : 0) * (av ? 1 : -1);
  // Il mezzo della corsia, e quanto sta a sinistra dell'auto.
  const cx = t.qx + (av ? -t.ty : t.ty) * o - x;
  const cy = t.qy + (av ? t.tx : -t.tx) * o - y;
  return cx * -dy + cy * dx;
}

// ── La corsia del percorso ──────────────────────────────────────────────

/** Le frecce buone per una manovra (le famiglie di frecce). */
const BUONE = {
  through: ['through', 'merge_to_left', 'merge_to_right'],
  slight_right: ['slight_right', 'right'],
  right: ['right', 'slight_right', 'sharp_right'],
  sharp_right: ['sharp_right', 'right'],
  slight_left: ['slight_left', 'left'],
  left: ['left', 'slight_left', 'sharp_left'],
  sharp_left: ['sharp_left', 'left'],
  reverse: ['reverse', 'left', 'sharp_left'],
};

const aSinistra = (dir) => dir.includes('left') || dir === 'reverse';

/**
 * Le corsie buone per la manovra [dir] (indici da sinistra), dalle frecce di
 * ogni corsia. Una corsia senza frecce va dritta. Se nessuna va bene (le
 * frecce dicono altro) si torna alle corsie dritte.
 */
export function corsieAdatte(frecce, dir) {
  const buone = BUONE[dir] ?? BUONE.through;
  let out = [];
  frecce.forEach((f, i) => {
    if ((f.length ? f : ['through']).some((x) => buone.includes(x))) out.push(i);
  });
  if (!out.length) frecce.forEach((f, i) => (!f.length || f.includes('through')) && out.push(i));
  if (!out.length) out = frecce.map((_, i) => i);
  return out;
}

/**
 * La corsia da prendere fra [n] per la manovra [dir]: fra le [adatte]
 * (indici), la più a destra (in Italia si tiene la destra; e per girare a
 * destra), la più a sinistra per girare a sinistra.
 */
export function scegliCorsia(n, dir, adatte = null) {
  const c = adatte && adatte.length ? adatte : Array.from({ length: n }, (_, i) => i);
  return aSinistra(dir) ? Math.min(...c) : Math.max(...c);
}

/**
 * La manovra a un incrocio: [a] è l'angolo del ramo del percorso (in gradi,
 * a sinistra positivo, rispetto a come si arriva), [altri] quelli degli
 * altri rami da cui si può uscire. Conta l'ordine dei rami, non solo
 * l'angolo: una rampa d'uscita parte di dieci gradi, ma è il ramo di destra.
 */
export function direzioneManovra(a, altri) {
  if (Math.abs(a) > 160) return 'reverse';
  if (a < -120) return 'sharp_right';
  if (a > 120) return 'sharp_left';
  if (a < -50) return 'right';
  if (a > 50) return 'left';
  const piuADestra = altri.some((x) => x < a - 3);
  const piuASinistra = altri.some((x) => x > a + 3);
  // Il ramo più a destra che piega anche di poco: tenersi a destra (la
  // rampa d'uscita). Chi resta dritto, con un ramo che si stacca a lato, va
  // dritto: sulla corsia dritta più a destra, non su quella che esce.
  if (piuASinistra && !piuADestra) return a < -5 ? 'slight_right' : 'through';
  if (piuADestra && !piuASinistra) return a > 5 ? 'slight_left' : 'through';
  if (a < -20) return 'slight_right';
  if (a > 20) return 'slight_left';
  return 'through';
}

/**
 * Le vie messe in una griglia, coi tratti: per trovare in fretta quelle
 * sotto un punto del percorso. [strade]: con `xy` nei metri della scena (la
 * geometria vera, `llVia`: i raccordi si aggiungono a parte).
 */
export class IndiceCorsie {
  constructor(strade, cella = 30) {
    this.strade = strade;
    this.cella = cella;
    this.griglia = new Map();
    // I capi e i nodi in mezzo, per contare i rami agli incroci.
    this.nodi = new Map();
    strade.forEach((v, i) => {
      const p = v.xy;
      v.sxy = progressive(p);
      for (let k = 0; k < p.length; k++) {
        const kn = this.chiaveNodo(p[k]);
        if (!this.nodi.has(kn)) this.nodi.set(kn, []);
        this.nodi.get(kn).push([i, k]);
        if (!k) continue;
        const a = p[k - 1];
        const b = p[k];
        for (let cx = Math.floor(Math.min(a[0], b[0]) / cella); cx <= Math.floor(Math.max(a[0], b[0]) / cella); cx++) {
          for (let cy = Math.floor(Math.min(a[1], b[1]) / cella); cy <= Math.floor(Math.max(a[1], b[1]) / cella); cy++) {
            const kk = cx + ',' + cy;
            if (!this.griglia.has(kk)) this.griglia.set(kk, []);
            this.griglia.get(kk).push([i, k]);
          }
        }
      }
    });
  }
  chiaveNodo(q) {
    return Math.round(q[0] * 2) + ',' + Math.round(q[1] * 2);
  }
  /** I tratti vicini a [x, y]: `[via, k]` (il tratto da k-1 a k). */
  vicini(x, y) {
    const c = this.cella;
    const out = [];
    const visti = new Set();
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const t of this.griglia.get(Math.floor(x / c) + ax + ',' + (Math.floor(y / c) + ay)) ?? []) {
          const k = t[0] * 1e6 + t[1];
          if (visti.has(k)) continue;
          visti.add(k);
          out.push(t);
        }
      }
    }
    return out;
  }
}

/** Il tratto [k-1, k] della via [v] più vicino a [x, y]: distanza, punto, direzione, normale, scostamento. */
function sulTratto(v, k, x, y) {
  const a = v.xy[k - 1];
  const b = v.xy[k];
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const l2 = dx * dx + dy * dy || 1e-9;
  const u = Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / l2));
  const qx = a[0] + dx * u;
  const qy = a[1] + dy * u;
  const l = Math.sqrt(l2);
  // [s]: i metri lungo la via (per il raccordo).
  const s = v.sxy ? v.sxy[k - 1] + u * l : 0;
  return { d: Math.hypot(x - qx, y - qy), qx, qy, tx: dx / l, ty: dy / l, s };
}

/**
 * Su quale corsia sta il percorso, punto per punto: di quanto spostarlo di
 * lato (a sinistra positivo, rispetto al suo verso).
 *
 * [punti]: `[x, y]` della linea del percorso già sulla strada, uno ogni
 * [passo] metri da [s0]; [indice]: un [IndiceCorsie]. Per ogni punto la via
 * sotto (vicina e nel verso giusto); dove il percorso passa da una via a
 * un'altra con altri rami attorno c'è una manovra, e la sua direzione (vedi
 * [direzioneManovra]). La corsia: per la prossima manovra entro
 * [orizzonte] metri (in autostrada di più), dalle frecce della via se le ha
 * (`turn:lanes`), o dai suggerimenti di chi calcola il percorso
 * ([suggerimenti]: `{s, giuste: [bool, …]}` da sinistra, come le corsie di
 * TomTom), altrimenti la più a destra (o la più a sinistra per girare a
 * sinistra). Il cambio di corsia si fa piano, in una trentina di metri.
 *
 * Restituisce `{sposta, vie, corsie, manovre}`: lo spostamento di ogni punto,
 * la via e la corsia sotto (-1 dove non si sa), le manovre trovate.
 */
export function corsieLungoIlPercorso(punti, indice, { passo = 4, s0 = 0, orizzonte = 300, orizzonteGrande = 1200, suggerimenti = [], morbidezza = 32 } = {}) {
  const n = punti.length;
  const strade = indice.strade;
  const dir = punti.map((_, k) => {
    const a = punti[Math.max(0, k - 1)];
    const b = punti[Math.min(n - 1, k + 1)];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    return [(b[0] - a[0]) / l, (b[1] - a[1]) / l];
  });
  // 1. La via sotto ogni punto.
  const via = new Int32Array(n).fill(-1);
  const avanti = new Uint8Array(n);
  const sul = new Array(n).fill(null);
  for (let k = 0; k < n; k++) {
    const [x, y] = punti[k];
    let meglio = null;
    let bv = Infinity;
    for (const [i, kk] of indice.vicini(x, y)) {
      const v = strade[i];
      const t = sulTratto(v, kk, x, y);
      if (t.d > 9) continue;
      const cos = t.tx * dir[k][0] + t.ty * dir[k][1];
      if (Math.abs(cos) < 0.7 || (v.senso && cos < 0)) continue;
      const voto = t.d + 15 * (1 - Math.abs(cos)) - (k && via[k - 1] === i ? 1.5 : 0);
      if (voto < bv) {
        bv = voto;
        meglio = { i, t, av: cos > 0 };
      }
    }
    if (meglio) {
      via[k] = meglio.i;
      avanti[k] = meglio.av ? 1 : 0;
      sul[k] = meglio.t;
    }
  }
  // Un pezzo di via di un paio di punti fra due altre (dove due vie partono
  // dallo stesso nodo, una rampa e la strada che continua) non è la via
  // del percorso: lì non si sa.
  for (let k = 0; k < n; ) {
    let j = k;
    while (j < n && via[j] === via[k]) j++;
    if (via[k] >= 0 && j - k < 3 && k > 0 && j < n) via.fill(-1, k, j);
    k = j;
  }
  // 2. Le manovre: dove si cambia via, con altri rami da cui uscire. E per
  // ogni punto quante corsie ha la via dopo, se ci si arriva senza manovra:
  // chi va dritto non prende una corsia che finisce (quella d'accelerazione).
  const manovre = [];
  const corsieDopo = new Float64Array(n).fill(Infinity);
  let ultimo = -1;
  let inizioTratto = 0;
  for (let k = 0; k < n; k++) {
    if (via[k] < 0) continue;
    if (ultimo >= 0 && via[k] !== via[ultimo]) {
      const m = manovraFra(punti, dir, indice, via[ultimo], via[k], ultimo, k, avanti[ultimo]);
      if (m) manovre.push({ ...m, s: s0 + m.k * passo });
      else {
        const b = strade[via[k]];
        corsieDopo.fill(avanti[k] ? b.avanti : b.indietro, inizioTratto, k);
      }
      inizioTratto = k;
    }
    ultimo = k;
  }
  // 3. La corsia, punto per punto, per la prossima manovra.
  const corsie = new Int32Array(n).fill(-1);
  const sposta = new Float64Array(n).fill(NaN);
  let mi = 0;
  for (let k = 0; k < n; k++) {
    if (via[k] < 0) continue;
    while (mi < manovre.length && manovre[mi].k <= k) mi++;
    const v = strade[via[k]];
    const av = avanti[k] === 1;
    const nc = av ? v.avanti : v.indietro;
    if (!nc) continue;
    const m = manovre[mi];
    const lontano = grande(v.hw) ? orizzonteGrande : orizzonte;
    const d = m && (m.k - k) * passo <= lontano ? m.dir : 'through';
    let adatte = null;
    const frecce = av ? v.frecce : v.frecceIndietro;
    if (frecce && m && d !== 'through') adatte = corsieAdatte(frecce, d);
    else if (frecce) adatte = corsieAdatte(frecce, 'through');
    const sugg = m && suggerimenti.find((g) => Math.abs(g.s - m.s) < 80 && g.giuste?.length === nc && g.giuste.some(Boolean));
    if (sugg) adatte = sugg.giuste.map((g, i) => (g ? i : -1)).filter((i) => i >= 0);
    let c = v.condivisa ? 0 : scegliCorsia(nc, d, adatte);
    if (corsieDopo[k] < nc) c = Math.min(c, Math.max(0, corsieDopo[k] - 1));
    corsie[k] = c;
    // Il mezzo della corsia (col raccordo della via, vedi [raccordi]), e
    // quanto sta di lato rispetto al percorso.
    const t = sul[k];
    const o = centroCorsia(v, c, av) + (v.raccordo && v.sxy ? spostamentoRaccordo(v.raccordo, t.s, v.sxy.at(-1)) : 0) * (av ? 1 : -1);
    const nx = (av ? -t.ty : t.ty) * o;
    const ny = (av ? t.tx : -t.tx) * o;
    const cx = t.qx + nx - punti[k][0];
    const cy = t.qy + ny - punti[k][1];
    sposta[k] = cx * -dir[k][1] + cy * dir[k][0];
  }
  // 4. Dove non si sa (dentro gli incroci) si va dritti fra prima e dopo; poi piano.
  riempi(sposta);
  return { sposta: liscia(sposta, Math.max(1, Math.round(morbidezza / passo / 2))), vie: via, corsie, manovre };
}

/** Le direzioni dei rami da cui si esce dal nodo [q], in radianti, senza quello da cui si arriva. */
function ramiDa(indice, q, arrivo) {
  const out = [];
  for (const [i, k] of indice.nodi.get(indice.chiaveNodo(q)) ?? []) {
    const v = indice.strade[i];
    const p = v.xy;
    // In avanti (verso la fine), e indietro se la via è a doppio senso.
    for (const [passo, ok] of [
      [1, k < p.length - 1],
      [-1, k > 0 && !v.senso],
    ]) {
      if (!ok) continue;
      let j = k;
      let d = 0;
      while (j + passo >= 0 && j + passo < p.length && d < 20) {
        d += Math.hypot(p[j + passo][0] - p[j][0], p[j + passo][1] - p[j][1]);
        j += passo;
      }
      const a = Math.atan2(p[j][1] - q[1], p[j][0] - q[0]);
      // Il ramo da cui si arriva (all'indietro) non è un'uscita.
      if (Math.cos(a - arrivo - Math.PI) > 0.94) continue;
      out.push({ i, a });
    }
  }
  return out;
}

/** La manovra fra la via [ia] (fino al punto [ka]) e la via [ib] (dal punto [kb]), se è un incrocio. */
function manovraFra(punti, dir, indice, ia, ib, ka, kb, av) {
  const b = indice.strade[ib];
  // Il nodo: il punto della via [ib] più vicino a dove il percorso ci arriva.
  let q = null;
  let bd = Infinity;
  for (const p of b.xy) {
    const d = Math.hypot(p[0] - punti[kb][0], p[1] - punti[kb][1]) + Math.hypot(p[0] - punti[ka][0], p[1] - punti[ka][1]);
    if (d < bd && (indice.nodi.get(indice.chiaveNodo(p)) ?? []).some(([i]) => i === ia)) {
      bd = d;
      q = p;
    }
  }
  if (!q) return null;
  // Come si arriva: la direzione del percorso una ventina di metri prima.
  const prima = Math.max(0, ka - 5);
  const arrivo = Math.atan2(punti[ka][1] - punti[prima][1], punti[ka][0] - punti[prima][0]) || Math.atan2(dir[ka][1], dir[ka][0]);
  const rami = ramiDa(indice, q, arrivo);
  if (rami.length < 2) return null;
  const dopo = Math.min(punti.length - 1, kb + 5);
  const uscita = Math.atan2(punti[dopo][1] - punti[kb][1], punti[dopo][0] - punti[kb][0]);
  const gradi = (x) => (Math.atan2(Math.sin(x - arrivo), Math.cos(x - arrivo)) * 180) / Math.PI;
  // Il ramo del percorso: quello che va più come il percorso dopo il nodo.
  let mio = rami[0];
  for (const r of rami) if (Math.cos(r.a - uscita) > Math.cos(mio.a - uscita)) mio = r;
  const altri = rami.filter((r) => r !== mio).map((r) => gradi(r.a));
  return { k: kb, dir: direzioneManovra(gradi(mio.a), altri), nodo: q, angolo: gradi(mio.a), altri, av };
}

/** I buchi (NaN) riempiti in linea retta fra i valori attorno; ai capi il più vicino. */
export function riempi(a) {
  const n = a.length;
  let prima = -1;
  for (let k = 0; k <= n; k++) {
    if (k < n && Number.isNaN(a[k])) continue;
    if (k - prima > 1) {
      for (let j = prima + 1; j < k; j++) {
        if (prima < 0 && k >= n) a[j] = 0;
        else if (prima < 0) a[j] = a[k];
        else if (k >= n) a[j] = a[prima];
        else a[j] = a[prima] + ((a[k] - a[prima]) * (j - prima)) / (k - prima);
      }
    }
    prima = k;
  }
  return a;
}

/** Una media mobile di ±[r] punti (due volte: il cambio di corsia è una S morbida). */
export function liscia(a, r) {
  let x = Float64Array.from(a);
  for (let giro = 0; giro < 2; giro++) {
    const y = new Float64Array(x.length);
    for (let k = 0; k < x.length; k++) {
      let s = 0;
      let c = 0;
      for (let j = Math.max(0, k - r); j <= Math.min(x.length - 1, k + r); j++) {
        s += x[j];
        c++;
      }
      y[k] = s / c;
    }
    x = y;
  }
  return x;
}
