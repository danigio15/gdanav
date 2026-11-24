// La fascia della vista «Corsie» alle svolte (`corsieLungoIlPercorso` in
// corsie.js e `fasciaSullaCorsia` in percorso.js), su incroci inventati in
// metri: nessun posto vero. La fascia deve restare sull'asfalto (l'unione
// delle carreggiate, larghe quanto dicono le corsie), nella corsia di prima
// fin dove questa incontra quella del ramo, e poi in quella del ramo.
import assert from 'node:assert/strict';
import test from 'node:test';
import { IndiceCorsie, asfaltoDelleCorsie, bordiCorsie, centroCorsia, corsieLungoIlPercorso, infittisci, normalizza, progressive, raccordi, spostamentoRaccordo, spostata } from '../src/corsie.js';
import { fasciaDelPercorso, fasciaSullaCorsia, incontroDeiLati, quoteSullaFascia, smussaGliSpigoli } from '../src/percorso.js';

const PASSO = 2;
/** Mezza fascia (`FASCIA_CORSIA` in principale.js). */
const MEZZA_FASCIA = 1.35;

const coppie = (g) => {
  const out = [];
  for (let i = 0; i < g.length; i += 2) out.push([g[i], g[i + 1]]);
  return out;
};

/** Le vie pronte come sulla pagina: la linea vera per il percorso, quella disegnata (coi raccordi) per l'asfalto. */
function vie(grezze) {
  const strade = grezze.map(normalizza);
  for (const v of strade) {
    v.xy = coppie(v.ll);
    v.llVia = v.ll;
  }
  const rr = raccordi(strade);
  strade.forEach((v, i) => {
    v.raccordo = rr[i];
    const p = infittisci(v.xy, 4);
    const s = progressive(p);
    v.disegnata = spostata(p, (sv) => spostamentoRaccordo(rr[i], sv, s.at(-1)), s);
  });
  return strade;
}

/** Un punto ogni [passo] metri lungo la spezzata [p] (gli spigoli cadono fra un punto e l'altro, come capita). */
function campiona(p, passo = PASSO) {
  const s = progressive(p);
  const out = [];
  for (let v = 0, k = 1; v <= s.at(-1) + 1e-9; v += passo) {
    while (k < p.length - 1 && s[k] < v) k++;
    const f = (v - s[k - 1]) / (s[k] - s[k - 1]);
    out.push([p[k - 1][0] + (p[k][0] - p[k - 1][0]) * f, p[k - 1][1] + (p[k][1] - p[k - 1][1]) * f]);
  }
  return out;
}

/** Quanto [q] sta dentro l'asfalto delle [strade] (negativo: fuori). */
function dentro(strade, q) {
  let meglio = -Infinity;
  for (const v of strade) {
    const B = bordiCorsie(v);
    const lo = B.destra - v.margini[1];
    const hi = B.sinistra + v.margini[0];
    const p = v.disegnata;
    for (let k = 1; k < p.length; k++) {
      const [ax, ay] = p[k - 1];
      const l = Math.hypot(p[k][0] - ax, p[k][1] - ay);
      const tx = (p[k][0] - ax) / l;
      const ty = (p[k][1] - ay) / l;
      const u = (q[0] - ax) * tx + (q[1] - ay) * ty;
      const o = -(q[0] - ax) * ty + (q[1] - ay) * tx;
      if (u >= 0 && u <= l) meglio = Math.max(meglio, Math.min(o - lo, hi - o));
      // I capi (e i giunti): tondi, larghi quanto la strada.
      for (const [cx, cy] of [p[k - 1], p[k]]) {
        const oc = (lo + hi) / 2;
        meglio = Math.max(meglio, (hi - lo) / 2 - Math.hypot(q[0] - cx + ty * oc, q[1] - cy - tx * oc));
      }
    }
  }
  return meglio;
}

/** La distanza di [q] dalla spezzata [p]. */
function distanza(p, q) {
  let d = Infinity;
  for (let k = 1; k < p.length; k++) {
    const [ax, ay] = p[k - 1];
    const dx = p[k][0] - ax;
    const dy = p[k][1] - ay;
    const u = Math.max(0, Math.min(1, ((q[0] - ax) * dx + (q[1] - ay) * dy) / (dx * dx + dy * dy)));
    d = Math.min(d, Math.hypot(q[0] - ax - dx * u, q[1] - ay - dy * u));
  }
  return d;
}

/**
 * Il mezzo della corsia [c] della via [v] (disegnata), per chi la percorre
 * [avanti] o al contrario, allungato dritto di [oltre] metri ai due capi
 * (le due corsie possono incontrarsi dentro l'incrocio, oltre la fine della
 * via di prima o prima dell'inizio di quella di dopo).
 */
function corsia(v, c, avanti = true, oltre = 0) {
  const p = avanti ? v.disegnata : [...v.disegnata].reverse();
  const q = spostata(p, centroCorsia(v, c, avanti));
  const allunga = ([a, b]) => {
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    return [b[0] + ((b[0] - a[0]) / l) * oltre, b[1] + ((b[1] - a[1]) / l) * oltre];
  };
  return oltre ? [allunga([q[1], q[0]]), ...q, allunga(q.slice(-2))] : q;
}

/** Dove la corsia [a] incontra la corsia [b]: il primo punto di [a] a meno di 5 cm da [b]. */
function incontro(a, b) {
  for (const q of infittisci(a, 0.05)) if (distanza(b, q) < 0.05) return q;
  return null;
}

/**
 * La fascia lungo [rotta] sulle vie [strade]: dentro l'asfalto (il mezzo e
 * i due bordi); nella corsia [prima] fino a [svolta] metri dal punto [M] in
 * cui la corsia incontra quella del ramo, e nella corsia [dopo] da lì in poi;
 * senza zig-zag, e senza girare più di [giroMax] da un punto all'altro.
 */
function controlla(nome, strade, rotta, { prima, dopo, M, svolta = 4.5, giroMax = Math.PI / 2 }) {
  const punti = campiona(rotta);
  const r = corsieLungoIlPercorso(punti, new IndiceCorsie(strade), { passo: PASSO });
  assert.ok(r.spigoli.length >= 1, `${nome}: lo spigolo`);
  const fascia = fasciaSullaCorsia(punti, r, PASSO);
  assert.equal(fascia.length, punti.length);
  // Il punto della fascia più vicino allo spigolo delle corsie.
  let km = 0;
  fascia.forEach((q, k) => {
    if (Math.hypot(q[0] - M[0], q[1] - M[1]) < Math.hypot(fascia[km][0] - M[0], fascia[km][1] - M[1])) km = k;
  });
  for (let k = 0; k < fascia.length; k++) {
    const q = fascia[k];
    const a = fascia[Math.max(0, k - 1)];
    const b = fascia[Math.min(fascia.length - 1, k + 1)];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    const n = [-(b[1] - a[1]) / l, (b[0] - a[0]) / l];
    const d = Math.hypot(q[0] - M[0], q[1] - M[1]);
    assert.ok(dentro(strade, q) > 0.3, `${nome}: il mezzo della fascia a ${k * PASSO} m è fuori dall'asfalto (${dentro(strade, q).toFixed(2)}) ${q}`);
    for (const o of [MEZZA_FASCIA, -MEZZA_FASCIA]) {
      const e = [q[0] + n[0] * o, q[1] + n[1] * o];
      assert.ok(dentro(strade, e) > -0.3, `${nome}: il bordo della fascia a ${k * PASSO} m è fuori dall'asfalto (${dentro(strade, e).toFixed(2)})`);
    }
    if (d < svolta || d > 60) continue;
    if (k < km) assert.ok(distanza(prima, q) < 0.15, `${nome}: a ${d.toFixed(1)} m prima della svolta la fascia non è nella sua corsia (${distanza(prima, q).toFixed(2)} m)`);
    else assert.ok(distanza(dopo, q) < 0.15, `${nome}: a ${d.toFixed(1)} m dopo la svolta la fascia non è nella corsia del ramo (${distanza(dopo, q).toFixed(2)} m)`);
  }
  // Niente zig-zag: la fascia gira sempre dallo stesso lato (al più un paio
  // di gradi di là, dove una corsia piega), e mai indietro.
  const giri = [];
  for (let k = 2; k < fascia.length; k++) {
    const u = [fascia[k - 1][0] - fascia[k - 2][0], fascia[k - 1][1] - fascia[k - 2][1]];
    const w = [fascia[k][0] - fascia[k - 1][0], fascia[k][1] - fascia[k - 1][1]];
    giri.push(Math.atan2(u[0] * w[1] - u[1] * w[0], u[0] * w[0] + u[1] * w[1]));
  }
  const lato = Math.sign(giri.reduce((a, b) => a + b, 0));
  giri.forEach((g, k) => {
    assert.ok(g * lato > -0.06 && Math.abs(g) < giroMax, `${nome}: a ${(k + 2) * PASSO} m la fascia gira di ${((g * 180) / Math.PI).toFixed(1)}°`);
  });
  return { r, fascia, km };
}

test('lo spigolo di due linee spostate di lato', () => {
  // Verso nord 1,5 m a destra, poi verso est sulla linea: lo spigolo sta 1,5 m a est dell'incrocio.
  const v = incontroDeiLati([0, 1], -1.5, [1, 0], 0);
  assert.ok(Math.abs(v[0] - 1.5) < 1e-12 && Math.abs(v[1]) < 1e-12, `${v}`);
  assert.equal(incontroDeiLati([0, 1], -1.5, [0, -1], -1.5), null, "un'inversione: parallele");
});

test('bivio a 30°: la fascia resta nella corsia di destra fin dove il ramo comincia, poi lo segue', () => {
  // Una strada a due corsie per senso verso nord; a 300 m un ramo a senso unico a 30° a destra.
  const s = Math.sin(Math.PI / 6);
  const c = Math.cos(Math.PI / 6);
  const strade = vie([
    { id: 1, hw: 'primary', lanes: '4', g: [0, -300, 0, 0] },
    { id: 2, hw: 'primary', lanes: '4', g: [0, 0, 0, 300] },
    { id: 3, hw: 'tertiary', oneway: 'yes', g: [0, 0, 200 * s, 200 * c] },
  ]);
  const [a, , ramo] = strade;
  // La corsia più a destra delle due verso nord, e il ramo (una corsia, che parte da lì: vedi raccordi).
  const prima = corsia(a, 1, true, 20);
  const dopo = corsia(ramo, 0, true, 20);
  const M = incontro(prima, dopo);
  assert.ok(M && Math.abs(M[0] - 4.875) < 0.01 && Math.abs(M[1]) < 1, `il ramo comincia dalla corsia di destra: ${M}`);
  const { r } = controlla('bivio', strade, [
    [0, -300],
    [0, 0],
    [200 * s, 200 * c],
  ], { prima, dopo, M });
  assert.equal(r.manovre[0].dir, 'slight_right');
});

test('incrocio a 90°: a destra e a sinistra in una via a senso unico, la curva piccola dove le corsie si incontrano', () => {
  for (const [nome, verso] of [
    ['a destra', 1],
    ['a sinistra', -1],
  ]) {
    const strade = vie([
      { id: 1, hw: 'secondary', lanes: '4', g: [0, -300, 0, 0] },
      { id: 2, hw: 'secondary', lanes: '4', g: [0, 0, 0, 300] },
      { id: 3, hw: 'residential', oneway: 'yes', lanes: '2', g: [0, 0, 300 * verso, 0] },
      { id: 4, hw: 'residential', g: [0, 0, -300 * verso, 0] },
    ]);
    const [a, , ramo] = strade;
    // A destra la corsia più a destra, a sinistra la più a sinistra; nel ramo la più a destra.
    const prima = corsia(a, verso > 0 ? 1 : 0, true, 20);
    const dopo = corsia(ramo, 1, true, 20);
    const M = incontro(prima, dopo);
    assert.ok(M, nome);
    // Il percorso del calcolatore gira sull'incrocio delle linee di mezzo, o
    // lo supera di qualche metro, o taglia l'angolo: la fascia è la stessa.
    for (const [come, rotta] of [
      ['sullo spigolo', [[0, -300], [0, 0], [300 * verso, 0]]],
      ['oltre', [[0, -300], [0, 6], [8 * verso, 0], [300 * verso, 0]]],
      ["tagliando l'angolo", [[0, -300], [0, -7], [7 * verso, 0], [300 * verso, 0]]],
    ]) {
      const { fascia } = controlla(`${nome}, ${come}`, strade, rotta, { prima, dopo, M });
      // La curva passa vicino allo spigolo (un raggio di corsia: meno di un metro e otto, coi punti ogni due metri), non lo taglia.
      const vicina = Math.min(...fascia.map((q) => Math.hypot(q[0] - M[0], q[1] - M[1])));
      assert.ok(vicina < 1.8 && vicina > 0.3, `${nome}, ${come}: la curva passa a ${vicina.toFixed(2)} m dallo spigolo`);
    }
  }
});

test('la via di prima piega proprio prima del nodo: lo spigolo dove la corsia, piegata, incontra il ramo', () => {
  // Verso nord, e negli ultimi sei metri dieci gradi a destra; poi a destra in una via a senso unico.
  const strade = vie([
    { id: 1, hw: 'secondary', lanes: '4', g: [0, -300, 0, -6, 1, 0] },
    { id: 2, hw: 'secondary', lanes: '4', g: [1, 0, 1, 300] },
    { id: 3, hw: 'residential', oneway: 'yes', g: [1, 0, 300, 0] },
  ]);
  const [a, , ramo] = strade;
  const prima = corsia(a, 1, true, 20);
  const dopo = corsia(ramo, 0, true, 20);
  const M = incontro(prima, dopo);
  assert.ok(M, 'le corsie si incontrano');
  controlla('piega', strade, [
    [0, -300],
    [0, -6],
    [1, 0],
    [300, 0],
  ], { prima, dopo, M });
});

test("inversione stretta: dalla corsia di destra a una via a senso unico che torna indietro", () => {
  // Una via a doppio senso verso nord che finisce a un nodo; da lì una via a
  // senso unico che torna verso sud-sud-est (un tornante di 165°).
  const s = Math.sin((15 * Math.PI) / 180);
  const c = Math.cos((15 * Math.PI) / 180);
  const strade = vie([
    { id: 1, hw: 'residential', g: [0, -300, 0, 0] },
    { id: 2, hw: 'residential', oneway: 'yes', g: [0, 0, 250 * s, -250 * c] },
  ]);
  const [a, ramo] = strade;
  const prima = corsia(a, 0, true, 20);
  const dopo = corsia(ramo, 0);
  const M = incontro(prima, dopo);
  assert.ok(M && M[1] < -4, `le due corsie si incontrano prima del nodo: ${M}`);
  // (Nel tornante la curva è stretta: da un punto all'altro, due metri, può girare quasi tutta.)
  controlla('tornante', strade, [
    [0, -300],
    [0, 0],
    [250 * s, -250 * c],
  ], { prima, dopo, M, giroMax: Math.PI });
});

test("rotonda: la fascia gira con l'anello, non lo taglia", () => {
  // Un anello di 12 m (in senso antiorario, a senso unico), un braccio da
  // sud e uno verso ovest: tre quarti di giro.
  const R = 12;
  const anello = [];
  for (let j = 0; j <= 24; j++) {
    const a = -Math.PI / 2 + (j * Math.PI) / 12;
    anello.push(+(R * Math.cos(a)).toFixed(9), +(R * Math.sin(a)).toFixed(9));
  }
  const strade = vie([
    { id: 1, hw: 'tertiary', g: [0, -300, 0, -R] },
    { id: 2, hw: 'tertiary', junction: 'roundabout', g: anello },
    { id: 3, hw: 'tertiary', g: [-R, 0, -300, 0] },
  ]);
  const pezzi = [[0, -300]];
  for (let j = 0; j <= 18; j++) pezzi.push([anello[2 * j], anello[2 * j + 1]]);
  pezzi.push([-300, 0]);
  const punti = campiona(pezzi);
  const r = corsieLungoIlPercorso(punti, new IndiceCorsie(strade), { passo: PASSO });
  const fascia = fasciaSullaCorsia(punti, r, PASSO);
  const giro = corsia(strade[1], 0);
  for (const q of fascia) {
    assert.ok(dentro(strade, q) > 0.3, `fuori dall'asfalto: ${q.map((v) => v.toFixed(2))}`);
    // Sull'anello, nel mezzo della sua corsia (lontano dai due bracci).
    const a = Math.atan2(q[1], q[0]);
    if (Math.hypot(q[0], q[1]) < 2 * R && a > -1.1 && a < 2.7) assert.ok(distanza(giro, q) < 0.3, `fuori dall'anello: ${q.map((v) => v.toFixed(2))} (${distanza(giro, q).toFixed(2)} m)`);
  }
});

test("inversione sulla stessa strada: un mezzo giro fra le due corsie, dove il percorso torna indietro", () => {
  const strade = vie([{ id: 1, hw: 'residential', g: [0, -300, 0, 100] }]);
  const [a] = strade;
  const punti = campiona([
    [0, -300],
    [0, 0],
    [0, -300],
  ]);
  const r = corsieLungoIlPercorso(punti, new IndiceCorsie(strade), { passo: PASSO });
  assert.equal(r.spigoli.length, 1);
  const fascia = fasciaSullaCorsia(punti, r, PASSO);
  const andata = corsia(a, 0, true);
  const ritorno = corsia(a, 0, false);
  let cima = -Infinity;
  for (const q of fascia) {
    assert.ok(dentro(strade, q) > 0.3, `fuori dall'asfalto: ${q}`);
    cima = Math.max(cima, q[1]);
    // Lontano dalla punta, nelle due corsie.
    if (q[1] < -6 && q[1] > -100) assert.ok(Math.min(distanza(andata, q), distanza(ritorno, q)) < 0.15, `fuori dalle corsie: ${q}`);
  }
  // Il mezzo giro arriva fin dove torna indietro il percorso, non oltre.
  assert.ok(cima <= 0.05 && cima > -1, `la punta a ${cima}`);
  // Sempre avanti: nessun punto della fascia torna sui suoi passi.
  for (let k = 2; k < fascia.length; k++) {
    const u = [fascia[k - 1][0] - fascia[k - 2][0], fascia[k - 1][1] - fascia[k - 2][1]];
    const w = [fascia[k][0] - fascia[k - 1][0], fascia[k][1] - fascia[k - 1][1]];
    assert.ok(u[0] * w[0] + u[1] * w[1] > -0.5, `torna indietro a ${k}`);
  }
});

test('senza svolte la fascia è lo spostamento di lato, levigato come prima', () => {
  const strade = vie([{ id: 1, hw: 'secondary', lanes: '4', g: [0, -300, 0, 300] }]);
  const punti = campiona([
    [0, -300],
    [0, 300],
  ]);
  const r = corsieLungoIlPercorso(punti, new IndiceCorsie(strade), { passo: PASSO });
  assert.equal(r.spigoli.length, 0);
  const fascia = fasciaSullaCorsia(punti, r, PASSO);
  for (const [k, q] of fascia.entries()) {
    assert.ok(Math.abs(q[0] - -r.sposta[k]) < 1e-9 && Math.abs(q[1] - punti[k][1]) < 1e-9);
  }
});

// ── La fascia sul mezzo della corsia, non sulle pieghe del percorso ──────

/** Di quanto gira la spezzata [f] al punto [k], in gradi. */
function giro(f, k) {
  const [a, b, c] = [f[k - 1], f[k], f[k + 1]];
  const u = [b[0] - a[0], b[1] - a[1]];
  const w = [c[0] - b[0], c[1] - b[1]];
  if (Math.hypot(...u) < 1e-6 || Math.hypot(...w) < 1e-6) return 0;
  return (Math.atan2(u[0] * w[1] - u[1] * w[0], u[0] * w[0] + u[1] * w[1]) * 180) / Math.PI;
}

/** La fascia come la fa la pagina (`sullaCorsia` in principale.js), senza altro asfalto che quello delle vie. */
function fasciaFinita(punti, strade, linea = punti) {
  const indice = new IndiceCorsie(strade);
  const r = corsieLungoIlPercorso(punti, indice, { passo: PASSO });
  const fascia = fasciaDelPercorso(linea, punti, r, new Array(punti.length).fill(0), (x, y) => asfaltoDelleCorsie(indice, x, y), PASSO);
  return { r, fascia };
}

test('il percorso del calcolatore fa un dente in mezzo a una corsia dritta: la fascia no', () => {
  // Una carreggiata a senso unico a due corsie, dritta verso nord. La linea
  // del calcolatore le sta sopra, ma a metà scatta di lato di un metro e
  // mezzo in due metri, poi torna piano (una corda), e più avanti ondeggia.
  const strade = vie([{ id: 1, hw: 'trunk', oneway: 'yes', lanes: '2', g: [0, -200, 0, 200] }]);
  const punti = [];
  for (let y = -200; y <= 200; y += PASSO) {
    let x = 0;
    if (y >= -40 && y < -38) x = 1.5;
    else if (y >= -38 && y < 0) x = 1.5 * (1 - (y + 38) / 38);
    else if (y > 60 && y < 120) x = 1.2 * Math.sin(((y - 60) / 60) * 2 * Math.PI);
    punti.push([x, y]);
  }
  const { fascia } = fasciaFinita(punti, strade);
  const mezzo = -centroCorsia(strade[0], 1);
  for (let k = 3; k < fascia.length - 3; k++) {
    assert.ok(Math.abs(fascia[k][0] - mezzo) < 0.05, `a ${punti[k][1]} m la fascia sta a ${fascia[k][0].toFixed(2)}, il mezzo della corsia a ${mezzo.toFixed(2)}`);
    assert.ok(Math.abs(giro(fascia, k)) < 1, `a ${punti[k][1]} m la fascia piega di ${giro(fascia, k).toFixed(1)}°`);
  }
});

test('da una via alla successiva con la corsia più in là: un passaggio morbido, e prima e dopo sul mezzo', () => {
  // Una corsia sola che diventa tre: la via nuova parte con la corsia di
  // sinistra su quella di prima (il raccordo), e chi va dritto tiene la
  // destra, due corsie più in là. Niente scalino, niente onde.
  const strade = vie([
    { id: 1, hw: 'primary', oneway: 'yes', lanes: '1', g: [0, -200, 0, 0] },
    { id: 2, hw: 'primary', oneway: 'yes', lanes: '3', g: [0, 0, 0, 300] },
  ]);
  const punti = campiona([
    [0, -200],
    [0, 300],
  ]);
  const { fascia } = fasciaFinita(punti, strade);
  const dopo = -centroCorsia(strade[1], 2);
  let segno = 0;
  for (let k = 1; k < fascia.length; k++) {
    const passo = fascia[k][0] - fascia[k - 1][0];
    assert.ok(Math.abs(passo) < 0.5, `a ${punti[k][1]} m uno scatto di lato di ${passo.toFixed(2)} m`);
    if (Math.abs(passo) > 0.02) {
      assert.ok(!segno || Math.sign(passo) === segno, `a ${punti[k][1]} m la fascia torna indietro di lato`);
      segno = Math.sign(passo);
    }
    if (punti[k][1] < -60) assert.ok(Math.abs(fascia[k][0]) < 0.05, `prima, sul mezzo della corsia (${fascia[k][0].toFixed(2)})`);
    if (punti[k][1] > 100) assert.ok(Math.abs(fascia[k][0] - dopo) < 0.05, `dopo, sul mezzo della corsia di destra (${fascia[k][0].toFixed(2)})`);
  }
});

test('la corsia per svoltare a sinistra nasce a sinistra: chi va dritto non fa una S', () => {
  // Due corsie, poi tre per quaranta metri (`left|through|through`: una in
  // più per svoltare), poi di nuovo due. Le due corsie che vanno dritte
  // sono sempre le stesse: la via a tre si allarga a sinistra.
  const strade = vie([
    { id: 1, hw: 'primary', oneway: 'yes', lanes: '2', 'turn:lanes': 'through|through', g: [0, -200, 0, 0] },
    { id: 2, hw: 'primary', oneway: 'yes', lanes: '3', 'turn:lanes': 'left|through|through', g: [0, 0, 0, 40] },
    { id: 3, hw: 'primary', oneway: 'yes', lanes: '2', g: [0, 40, 0, 240] },
    { id: 4, hw: 'residential', g: [0, 40, -100, 40] },
  ]);
  const lw = strade[0].lw;
  const r3 = strade[1].raccordo;
  assert.ok(Math.abs(r3.o0 - lw / 2) < 1e-9 && Math.abs(r3.o1 - lw / 2) < 1e-9, `la via a tre corsie sta mezza corsia a sinistra, da un capo all'altro (${r3.o0}, ${r3.o1})`);
  for (const s of [0, 10, 20, 30, 40]) assert.ok(Math.abs(spostamentoRaccordo(r3, s, 40) - lw / 2) < 1e-9, `anche a ${s} m`);
  assert.equal(strade[2].raccordo.t0, 0, 'e quella dopo parte dritta');
  const punti = campiona([
    [0, -200],
    [0, 240],
  ]);
  const { fascia } = fasciaFinita(punti, strade);
  const destra = -centroCorsia(strade[0], 1);
  // Sempre nel mezzo della stessa corsia, quella di destra.
  for (let k = 1; k < fascia.length; k++) assert.ok(Math.abs(fascia[k][0] - destra) < 0.05, `a ${punti[k][1]} m la fascia sta a ${fascia[k][0].toFixed(2)} (la corsia a ${destra.toFixed(2)})`);
});

test('la linea del calcolatore si stacca dalla galleria e la ritrova: in mezzo la fascia segue la galleria', () => {
  // Una galleria a senso unico che gira (un quarto di cerchio di 60 m) da
  // una strada verso sud a una verso est; un'altra galleria arriva allo
  // stesso nodo da sud-ovest. La linea del calcolatore taglia venti metri
  // più in là, sul prato, e passa proprio sopra l'altra.
  const arco = [];
  for (let a = 0; a <= 90; a += 5) arco.push(60 - 60 * Math.cos((a * Math.PI) / 180), -60 * Math.sin((a * Math.PI) / 180));
  const strade = vie([
    { id: 1, hw: 'secondary', oneway: 'yes', g: [0, 150, 0, 0] },
    { id: 2, hw: 'secondary', oneway: 'yes', tunnel: 'yes', g: arco },
    { id: 3, hw: 'secondary', oneway: 'yes', g: [60, -60, 260, -60] },
    { id: 4, hw: 'tertiary', oneway: 'yes', tunnel: 'yes', g: [-20, -95, 20, -72, 60, -60] },
  ]);
  // La linea: dritta a sud fin oltre la curva, poi verso est lungo l'altra galleria.
  const punti = campiona([
    [0, 150],
    [0, -22],
    [4, -52],
    [34, -66],
    [60, -60],
    [260, -60],
  ]);
  const { r, fascia } = fasciaFinita(punti, strade);
  const mezzo = corsia(strade[1], 0, true);
  let inGalleria = 0;
  punti.forEach((p, k) => {
    assert.notEqual(r.vie[k], 3, `a ${k * PASSO} m il percorso sta sull'altra galleria`);
    if (r.vie[k] !== 1) return;
    inGalleria++;
    assert.ok(distanza(mezzo, fascia[k]) < 0.3, `a ${k * PASSO} m la fascia è a ${distanza(mezzo, fascia[k]).toFixed(1)} m dalla galleria`);
  });
  assert.ok(inGalleria * PASSO > 80, `la galleria si fa tutta (${inGalleria * PASSO} m)`);
  // E mai un dente.
  for (let k = 2; k < fascia.length - 2; k++) {
    const [a, b] = [giro(fascia, k), giro(fascia, k + 1)];
    assert.ok(Math.sign(a) === Math.sign(b) || Math.min(Math.abs(a), Math.abs(b)) < 12, `un dente a ${k * PASSO} m (${a.toFixed(0)}°, ${b.toFixed(0)}°)`);
  }
});

test('dentro un incrocio qualunque il percorso che taglia l’angolo di poco non si rimette sulle vie', () => {
  // Come sempre: lì «non si sa», e la curva la fa la svolta.
  const s = Math.sin((2 * Math.PI) / 3);
  const c = Math.cos((2 * Math.PI) / 3);
  const strade = vie([
    { id: 1, hw: 'secondary', oneway: 'yes', g: [0, -200, 0, 0] },
    { id: 2, hw: 'secondary', oneway: 'yes', g: [0, 0, 200 * s, 200 * c] },
  ]);
  const punti = campiona([
    [0, -200],
    [0, -12],
    [12 * s, 12 * c],
    [200 * s, 200 * c],
  ]);
  const r = corsieLungoIlPercorso(punti, new IndiceCorsie(strade), { passo: PASSO });
  assert.ok([...r.vie].some((v, k) => v < 0 && k > 90 && k < 110), 'in mezzo all’incrocio non si sa');
  assert.equal(r.spigoli.length, 1);
});

test('un sottopasso di dieci metri fra due pezzi all’aperto è una via del percorso anche lui', () => {
  const strade = vie([
    { id: 1, hw: 'secondary', oneway: 'yes', g: [0, -100, 0, 0] },
    { id: 2, hw: 'secondary', oneway: 'yes', tunnel: 'yes', g: [0, 0, 0, 10] },
    { id: 3, hw: 'secondary', oneway: 'yes', g: [0, 10, 0, 110] },
    // (E una rampa che parte dallo stesso nodo del sottopasso: di lei si fanno solo i primi metri.)
    { id: 4, hw: 'secondary_link', oneway: 'yes', g: [0, 0, 8, 30, 60, 60] },
  ]);
  const punti = campiona([
    [0.4, -100],
    [0.4, 110],
  ]);
  const { r, fascia } = fasciaFinita(punti, strade);
  const sotto = punti.map((p, k) => (p[1] > 1 && p[1] < 9 ? r.vie[k] : 1)).filter((v) => v !== 1);
  assert.deepEqual(sotto, [], `sotto il sottopasso: ${[...r.vie].slice(48, 58)}`);
  for (let k = 3; k < fascia.length - 3; k++) assert.ok(Math.abs(fascia[k][0]) < 0.05 && Math.abs(giro(fascia, k)) < 1, `a ${punti[k][1]} m la fascia balla (${fascia[k][0].toFixed(2)})`);
});

test('la fascia in galleria è quella sopra una via in galleria; e la quota è quella della strada sotto di lei', () => {
  const strade = vie([
    { id: 1, hw: 'secondary', oneway: 'yes', g: [0, 0, 0, 40] },
    { id: 2, hw: 'secondary', oneway: 'yes', tunnel: 'yes', g: [0, 40, 0, 80] },
  ]);
  const n = 41;
  const punti = Array.from({ length: n }, (_, k) => [0, k * PASSO]);
  // La fascia: sulla via fino a 60 m, poi sei metri di lato (su un'altra strada, a tre metri di quota, in galleria).
  const fascia = punti.map(([x, y]) => [y > 60 ? 6 : 0, y]);
  const vie2 = Int32Array.from(punti, ([, y]) => (y <= 40 ? 0 : y <= 60 ? 1 : -1));
  // Il profilo veniva dalla mappa: tutto all'aperto, a terra.
  const pr = { h: new Float64Array(n), galleria: new Uint8Array(n) };
  const indice = { candidati: (x) => (x > 3 ? [{ h: 3, d: 0.5, galleria: true }] : [{ h: 0, d: 0.2, galleria: false }]) };
  quoteSullaFascia(pr, punti, fascia, indice, vie2, strade);
  punti.forEach(([, y], k) => {
    assert.equal(pr.galleria[k], y > 40 ? 1 : 0, `in galleria a ${y} m`);
    assert.ok(Math.abs(pr.h[k] - (y > 60 ? 3 : 0)) < 1e-9, `la quota a ${y} m: ${pr.h[k]}`);
  });
});

test('l’asfalto di una via col raccordo arriva fin dove è disegnata', () => {
  // La via a tre corsie parte spostata di una corsia (vedi sopra): la sua
  // corsia di destra, lì, sta fuori dalla larghezza contata sulla linea.
  const strade = vie([
    { id: 1, hw: 'primary', oneway: 'yes', lanes: '1', g: [0, -200, 0, 0] },
    { id: 2, hw: 'primary', oneway: 'yes', lanes: '3', g: [0, 0, 0, 300] },
  ]);
  const indice = new IndiceCorsie(strade);
  const lw = strade[1].lw;
  const a = asfaltoDelleCorsie(indice, 0, 2).find((q) => q.qy > 1);
  assert.ok(a.meta > 2.5 * lw, `larga ${a.meta.toFixed(2)} dalla linea, la corsia di destra sta a ${(2 * lw).toFixed(2)}`);
});

test('la partenza da un piazzale che la mappa non ha: dritti fino alla strada, e l’angolo è una curva', () => {
  // Quaranta metri di piazzale verso est, poi a sinistra su una strada a
  // doppio senso verso nord. Altre vie, più in là lungo la strada, non
  // devono tirare di lato gli ultimi metri prima dell'asfalto.
  const strade = vie([
    { id: 1, hw: 'tertiary', g: [0, -150, 0, -20] },
    { id: 2, hw: 'tertiary', g: [0, -20, 0, 14] },
    { id: 3, hw: 'tertiary', g: [0, 14, 0, 200] },
  ]);
  const punti = campiona([
    [-40, 0],
    [0, 0],
    [0, 200],
  ]);
  const { fascia } = fasciaFinita(punti, strade);
  const destra = -centroCorsia(strade[0], 0, true);
  fascia.forEach((q, k) => {
    if (punti[k][0] < -6) assert.ok(Math.abs(q[1]) < 0.3, `nel piazzale, a ${-punti[k][0]} m dalla strada, la fascia va di lato di ${q[1].toFixed(2)} m`);
    if (punti[k][1] > 8) assert.ok(Math.abs(q[0] - destra) < 0.05, `sulla strada, a ${punti[k][1]} m, non è nella corsia (${q[0].toFixed(2)})`);
    if (k > 0 && k < fascia.length - 1) assert.ok(Math.abs(giro(fascia, k)) < 45, `uno spigolo di ${giro(fascia, k).toFixed(0)}° a ${k * PASSO} m`);
  });
});

test('uno spigolo vivo diventa una curva; quello che curva già resta com’è', () => {
  const spigolo = [...Array.from({ length: 10 }, (_, k) => [k * 2 - 18, 0]), ...Array.from({ length: 10 }, (_, k) => [0, (k + 1) * 2])];
  const liscia = smussaGliSpigoli(spigolo);
  for (let k = 1; k < liscia.length - 1; k++) assert.ok(Math.abs(giro(liscia, k)) < 45, `a ${k} gira ancora di ${giro(liscia, k).toFixed(0)}°`);
  // Lontano dallo spigolo, niente; e la curva resta dentro l'angolo.
  assert.deepEqual(liscia.slice(0, 7), spigolo.slice(0, 7));
  assert.deepEqual(liscia.slice(13), spigolo.slice(13));
  for (const [x, y] of liscia) assert.ok(x <= 1e-9 && y >= -1e-9);
  // Una curva di tre metri di raggio, un punto ogni due: è già una curva.
  const curva = Array.from({ length: 12 }, (_, k) => [3 * Math.sin(k / 1.6), 3 - 3 * Math.cos(k / 1.6)]);
  assert.deepEqual(smussaGliSpigoli(curva), curva);
});

test('tornante a un bivio a «V»: una curva stretta dalla parte giusta, non una punta', () => {
  // Una strada sale verso nord e finisce su un'altra che passa di lì: viene
  // da nord e riparte verso sud-sud-est. Il percorso sale e gira a destra di
  // centocinquanta gradi. Il primo punto dopo il nodo cade sul pezzo di
  // nord dell'altra via (al contrario di come si arriva): pareva
  // un'inversione, e la fascia faceva una punta girata a sinistra.
  const strade = vie([
    { id: 1, hw: 'residential', g: [0, -200, 0, 0] },
    { id: 2, hw: 'unclassified', g: [2, 100, 0, 0, 60, -150] },
  ]);
  const punti = campiona([
    [0, -200],
    [0.6, 0.3],
    [60, -150],
  ]);
  const { fascia } = fasciaFinita(punti, strade);
  let tutto = 0;
  for (let k = 1; k < fascia.length - 1; k++) {
    const g = giro(fascia, k);
    tutto += g;
    assert.ok(g < 3, `a ${k * PASSO} m la fascia gira a sinistra di ${g.toFixed(0)}°`);
    assert.ok(g > -60, `a ${k * PASSO} m uno spigolo di ${g.toFixed(0)}°`);
    assert.ok(dentro(strade, fascia[k]) > 0, `a ${k * PASSO} m fuori dall'asfalto`);
  }
  assert.ok(Math.abs(tutto + 158) < 6, `in tutto gira di ${tutto.toFixed(0)}°`);
});
