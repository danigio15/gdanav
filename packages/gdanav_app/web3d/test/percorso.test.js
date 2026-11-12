import assert from 'node:assert/strict';
import test from 'node:test';
import { IndiceSegmenti, Linea, Origine, Profilo, alzataDeiNastri, lungoLaLinea, nastro, pezziDelNastro, profiloDi, quote, riempiQuote, sensiDiMarcia } from '../src/percorso.js';

/** Segmenti finti: [x0,y0,z0,x1,y1,z1,w,codice]. */
function indice(segmenti) {
  const i = new IndiceSegmenti();
  i.aggiungi('t', new Float32Array(segmenti.flat()), 0, 0, 1);
  return i;
}

// Un viadotto a 7 m sopra una strada a terra, sulla stessa linea in pianta
// (come una rampa che corre sopra la carreggiata), e la rampa che sale.
const SEG = [
  [-400, 0, 0, 0, 0, 0, 10, 1],
  [0, 0, 0, 400, 0, 0, 10, 1],
  [-400, 2, 0, -130, 2, 0, 7, 17],
  [-130, 2, 0, 0, 2, 7, 7, 17],
  [0, 2, 7, 400, 2, 7, 7, 49],
];

test('la linea: metri, punti, direzione, proiezione', () => {
  const l = new Linea([0, 0, 100, 0, 100, 100]);
  assert.equal(l.lunghezza, 200);
  assert.deepEqual(l.a(150).slice(0, 2), [100, 50]);
  assert.ok(Math.abs(l.direzione(50, 5)) < 1e-9);
  const p = l.proietta(60, 10);
  assert.equal(p.s, 60);
  assert.equal(p.d, 10);
});

test('chi sale sul viadotto ci resta; chi sta sotto resta sotto', () => {
  const i = indice(SEG);
  // Sulla rampa (y = 2): sale e resta a 7 m anche dove sotto c'è la strada.
  const su = [];
  for (let x = -300; x <= 300; x += 4) su.push([x, 2]);
  const h = quote(su, i);
  assert.ok(Math.abs(h[0]) < 0.3, 'parte da terra');
  assert.ok(Math.abs(h[h.length - 1] - 7) < 0.3, `finisce sul viadotto (${h[h.length - 1]})`);
  // Sotto (y = -1): resta a terra, anche col viadotto a tre metri.
  const giu = [];
  for (let x = -300; x <= 300; x += 4) giu.push([x, -1]);
  const g = quote(giu, i);
  assert.ok(Math.max(...g.map((v, k) => (giu[k][0] > 100 ? v : 0))) < 0.5, 'sotto il viadotto a terra');
});

test('sotto un cavalcavia di sbieco la linea resta a terra, anche cambiando carreggiata', () => {
  // La strada a terra lungo x, interrotta fra 80 e 160 (il percorso lì passa
  // di lato, da una carreggiata alla rampa); sopra, a 8 m, un cavalcavia
  // che la taglia a 35°, largo 20 m.
  const a = (35 * Math.PI) / 180;
  const i = indice([
    [-300, 0, 0, 80, 0, 0, 10, 1],
    [160, 0, 0, 400, 0, 0, 10, 1],
    [120 - 300 * Math.cos(a), -300 * Math.sin(a), 8, 120 + 300 * Math.cos(a), 300 * Math.sin(a), 8, 20, 49],
  ]);
  const punti = [];
  for (let x = -100; x <= 300; x += 4) punti.push([x, 0]);
  const h = riempiQuote(quote(punti, i));
  assert.ok(Math.max(...h) < 0.5, `la linea sale sul ponte (${Math.max(...h).toFixed(1)} m)`);
});

test('la linea si appoggia sulla strada: un metro di lato torna in mezzo', () => {
  // «In alcuni punti la linea del percorso non è sulla strada.»
  const i = indice([[-400, 0, 0, 400, 0, 0, 10, 1]]);
  const l = new Linea([-300, 1.2, 300, 1.2]);
  const p = profiloDi(l, 0, 600, i);
  const [dx, dy] = p.sposta(300);
  assert.ok(Math.abs(dx) < 0.1 && Math.abs(dy + 1.2) < 0.1, `spostamento ${dx.toFixed(2)}, ${dy.toFixed(2)}`);
  const n = nastro(l, p, 250, 350, 4, 0.6);
  const ys = [];
  for (let k = 1; k < n.posizioni.length; k += 3) ys.push(n.posizioni[k]);
  const mezzo = (Math.max(...ys) + Math.min(...ys)) / 2;
  assert.ok(Math.abs(mezzo) < 0.2, `il nastro sta in mezzo alla strada (${mezzo.toFixed(2)})`);
  // Lontano dalle strade (oltre tredici metri) non si sposta: la strada
  // giusta è un'altra.
  const lontana = profiloDi(new Linea([-300, 20, 300, 20]), 0, 600, i);
  assert.deepEqual(lontana.sposta(300), [0, 0]);
});

test('il percorso di TomTom, otto metri di lato, torna sulla strada della mappa', () => {
  // «Ancora è fuori strada la linea»: via Po, la linea del percorso a otto
  // metri dalla strada, mentre la strada già fatta (il GPS) ci sta sopra. Il
  // percorso è di TomTom, la mappa di OpenStreetMap.
  const i = indice([[-400, 0, 0, 400, 0, 0, 7, 5]]);
  const l = new Linea([-300, 8, 300, 8]);
  const p = profiloDi(l, 0, 600, i);
  for (const s of [100, 300, 500]) {
    const [, dy] = p.sposta(s);
    assert.ok(Math.abs(dy + 8) < 0.2, `a ${s} m la linea resta a ${(8 + dy).toFixed(2)} m dalla strada`);
  }
});

test('fra due strade di un isolato la linea spostata resta sulla sua', () => {
  // Un isolato: due strade parallele a trenta metri. Il percorso di TomTom sta
  // otto metri verso l'altra: torna sulla sua, non salta dall'altra parte.
  const i = indice([
    [-400, 0, 0, 400, 0, 0, 7, 5],
    [-400, 30, 0, 400, 30, 0, 7, 5],
  ]);
  const l = new Linea([-300, 8, 300, 8]);
  const p = profiloDi(l, 0, 600, i);
  for (let s = 20; s <= 580; s += 20) {
    const [x, y] = l.a(s);
    const [, dy] = p.sposta(s);
    assert.ok(Math.abs(y + dy) < 0.5, `a ${x.toFixed(0)} m la linea è a ${(y + dy).toFixed(2)} m dalla sua strada`);
  }
});

test("allo svincolo, se non si esce, la linea resta diritta sulla carreggiata", () => {
  // «Agli svincoli se non devo uscire comunque la linea del percorso non è
  // diritta: va allo svincolo e poi ritorna al centro.» La carreggiata lungo
  // x; da x = 0 la rampa si stacca verso il basso. Il percorso va dritto,
  // un metro e venti sotto la carreggiata disegnata: dove la rampa si stacca
  // è lei la più vicina.
  const i = indice([
    [-400, 0, 0, 400, 0, 0, 10, 1],
    [0, -2, 0, 200, -30, 0, 7, 1],
  ]);
  const l = new Linea([-300, -1.2, 300, -1.2]);
  const p = profiloDi(l, 0, 600, i);
  for (let s = 250; s <= 350; s += 2) {
    const [, dy] = p.sposta(s);
    assert.ok(Math.abs(dy - 1.2) < 0.2, `a ${s - 300} m dalla rampa la linea va di ${dy.toFixed(2)} m invece di 1,2`);
  }
});

test('fra due strade vicine la linea non salta da una all\'altra', () => {
  // Due strade parallele a 4 m (una rotonda vista da vicino, una
  // complanare): il percorso sta su quella sotto, con un rumore che a volte
  // lo porta più vicino all'altra.
  const i = indice([
    [-400, 0, 0, 400, 0, 0, 6, 5],
    [-400, 4, 0, 400, 4, 0, 6, 5],
  ]);
  const xy = [];
  for (let x = -300; x <= 300; x += 10) xy.push(x, (x / 10) % 2 ? 2.2 : 0.4);
  const l = new Linea(xy);
  const p = profiloDi(l, 0, l.lunghezza, i);
  for (let s = 20; s < l.lunghezza - 20; s += 4) {
    const [x, y] = l.a(s);
    const [, dy] = p.sposta(s);
    // Mai sull'altra strada (a 4 m): al più il resto della levigatura.
    assert.ok(y + dy < 2.3, `a ${x.toFixed(0)} m la linea è a ${(y + dy).toFixed(2)} m dalla sua strada`);
  }
});

test('il traffico lungo il percorso non si disegna una seconda volta', () => {
  // «La linea del traffico non segue la linea del percorso ma è decentrata.»
  const percorso = new Linea([0, 0, 500, 0]);
  const accanto = [];
  for (let x = 50; x <= 300; x += 5) accanto.push([x, 6]);
  assert.equal(lungoLaLinea(percorso, accanto, 0, 500), true, 'a sei metri, lungo il percorso');
  const traversa = [];
  for (let y = -200; y <= 200; y += 5) traversa.push([250, y]);
  assert.equal(lungoLaLinea(percorso, traversa, 0, 500), false, 'una strada che lo incrocia resta');
  const lontana = accanto.map(([x]) => [x, 40]);
  assert.equal(lungoLaLinea(percorso, lontana, 0, 500), false, 'una strada parallela lontana resta');
});

test('i buchi: corti si riempiono, lunghi tornano a terra', () => {
  const h = riempiQuote([7, NaN, NaN, 7]);
  assert.ok(h.every((v) => Math.abs(v - 7) < 0.01));
  const lungo = riempiQuote([7, ...new Array(100).fill(NaN)], 50);
  assert.ok(lungo[lungo.length - 1] < 0.01);
});

test('il profilo e il nastro: quote, larghezza, code nette', () => {
  const l = new Linea([-300, 2, 300, 2]);
  const p = profiloDi(l, 0, 600, indice(SEG));
  assert.ok(p.quota(500) > 6.5);
  assert.ok(p.quota(10) < 0.5);
  const n = nastro(l, p, 0, 600, 4, 0.6, { code: [[100, 200, 3]] });
  assert.equal(n.posizioni.length / 3, n.uv.length / 2);
  // A ogni cambio di coda due stazioni: il colore cambia netto.
  const livelli = [...n.livelli];
  assert.ok(livelli.includes(3) && livelli.includes(0));
  const cambio = n.uv.findIndex((v, k) => k % 2 === 1 && v === 100);
  assert.ok(cambio > 0);
  for (let k = 0; k < n.indici.length; k += 3) {
    const lv = [n.indici[k], n.indici[k + 1], n.indici[k + 2]].map((v) => n.livelli[v]);
    assert.ok(lv.every((v) => v === lv[0]), 'un triangolo ha un livello solo');
  }
  // Largo 4 m.
  assert.ok(Math.abs(Math.hypot(n.posizioni[0] - n.posizioni[3], n.posizioni[1] - n.posizioni[4]) - 4) < 1e-4);
});

test('il profilo fuori dalla finestra tiene il capo', () => {
  const p = new Profilo(100, 4, Float64Array.from([1, 2, 3]));
  assert.equal(p.quota(0), 1);
  assert.equal(p.quota(106), 2.5);
  assert.equal(p.quota(1000), 3);
});

test("l'origine: metri e ritorno", () => {
  const o = new Origine(9.087, 45.517);
  const [x, y] = o.daLonLat(9.1, 45.52);
  assert.ok(x > 900 && x < 1100 && y > 300 && y < 360);
  const [lon, lat] = o.lonLat(x, y);
  assert.ok(Math.abs(lon - 9.1) < 1e-9 && Math.abs(lat - 45.52) < 1e-9);
});

test("l'indice: si toglie una tessera", () => {
  const i = indice(SEG);
  assert.ok(i.candidati(100, 0, 1, 0).length > 0);
  assert.ok(i.copre(0, 0));
  i.togli('t');
  assert.equal(i.candidati(100, 0, 1, 0).length, 0);
  assert.ok(i.vuoto);
});

test('la linea coi metri della guida: le posizioni seguono quelli', () => {
  const l = new Linea([0, 0, 100, 0, 200, 0], [0, 104, 208]);
  assert.equal(l.lunghezza, 208);
  assert.deepEqual(l.a(52).slice(0, 2), [50, 0]);
  assert.deepEqual(l.a(156).slice(0, 2), [150, 0]);
});

test('in galleria: i punti lo sanno, e il nastro lì ha il livello +10', () => {
  const i = new IndiceSegmenti();
  i.aggiungi('t', new Float32Array([-300, 0, 0, -50, 0, 0, 10, 3, -50, 0, 0.06, 50, 0, 0.06, 10, 3 + 64, 50, 0, 0, 300, 0, 0, 10, 3]), 0, 0, 1);
  const l = new Linea([-300, 0, 300, 0]);
  const p = profiloDi(l, 0, 600, i);
  assert.equal(p.gallerie.length, 1);
  const [da, a] = p.gallerie[0];
  assert.ok(Math.abs(da - 250) < 5 && Math.abs(a - 350) < 5, `${da}..${a}`);
  const n = nastro(l, p, 0, 600, 4, 0.6);
  assert.ok([...n.livelli].some((v) => v >= 10) && [...n.livelli].some((v) => v === 0));
});

test("sulla strada a due carreggiate la linea va su quella del suo senso, non sull'altra", () => {
  // SS7bis: TomTom passa nel mezzo, la carreggiata contromano (a 5 m) era più
  // vicina di quella giusta (a 9 m) e la linea ci finiva sopra.
  const i = indice([
    [300, 5, 0, -100, 5, 0, 8, 2 + 128], // verso -x: contromano
    [-100, -9, 0, 300, -9, 0, 8, 2 + 128], // verso +x: la nostra
  ]);
  const punti = [];
  for (let x = 0; x <= 200; x += 4) punti.push([x, 0]);
  const h = quote(punti, i);
  for (let k = 0; k < punti.length; k++) assert.ok(Math.abs(h.dy[k] + 9) < 0.5, `al punto ${k} dy=${h.dy[k]}`);
  // Senza senso unico (strada a doppio senso) vale ancora la più vicina.
  const d = quote(punti, indice([[300, 5, 0, -100, 5, 0, 8, 2], [-100, -9, 0, 300, -9, 0, 8, 2]]));
  assert.ok(Math.abs(d.dy[10] - 5) < 0.5);
  // E con -1 (senso contrario alla linea) si gira.
  const r = quote(punti, indice([[-100, 5, 0, 300, 5, 0, 8, 2 + 256], [300, -9, 0, -100, -9, 0, 8, 2 + 256]]));
  assert.ok(Math.abs(r.dy[10] + 9) < 0.5);
});

test('sul viadotto, con una stradina più vicina sotto, la linea resta su', () => {
  // SP335: il percorso (di TomTom) sta a 7 m dalla carreggiata sul viadotto
  // (8 m di quota) e a 2 m da una stradina a terra che le corre sotto per
  // seicento metri. Si parte da terra, sulla stessa strada prima del ponte.
  const i = indice([
    [-200, 7, 0, 0, 7, 0, 8, 2 + 128],
    [0, 7, 0, 100, 7, 8, 8, 2 + 128],
    [100, 7, 8, 1000, 7, 8, 8, 2 + 32 + 128],
    [300, -2, 0, 900, -2, 0, 5, 6],
  ]);
  const punti = [];
  for (let x = -100; x <= 950; x += 4) punti.push([x, 0]);
  const h = quote(punti, i);
  for (let k = 0; k < punti.length; k++) if (punti[k][0] > 150) assert.ok(Math.abs(h[k] - 8) < 0.3, `a x=${punti[k][0]} h=${h[k]}`);
  // Il tratto si rifà più avanti, tutto sopra la stradina: da solo sceglierebbe
  // quella (più vicina), con l'àncora dell'auto resta sul viadotto.
  const l = new Linea([0, 0, 1000, 0]);
  const solo = profiloDi(l, 320, 880, i);
  assert.ok(solo.quota(600) < 1, 'senza àncora scende (è il caso che si corregge)');
  const con = profiloDi(l, 320, 880, i, 4, { s: 400, h: 8 });
  assert.ok(Math.abs(con.quota(600) - 8) < 0.3 && Math.abs(con.quota(860) - 8) < 0.3, `con l'àncora resta su (${con.quota(600)})`);
  assert.equal(con.quotaVera(600) !== null, true);
  assert.equal(profiloDi(l, 0, 100, indice([])).quotaVera(50), null);
});

test('tante stradine sotto il viadotto non tolgono la carreggiata dalle candidate', () => {
  // Sette strade a terra più vicine della carreggiata (a 7 e a 11 m, in quota).
  const seg = [[-200, 7, 8, 600, 7, 8, 8, 2 + 32 + 128]];
  for (let k = 0; k < 7; k++) seg.push([100, -3 + k * 0.9 - 2.7, 0, 500, -3 + k * 0.9 - 2.7, 0, 4, 6]);
  // (le strade a terra distano fra loro meno di un metro e mezzo: se ne
  // fondono alcune; mettiamole più larghe)
  const larghe = [[-200, 11, 8, 600, 11, 8, 8, 2 + 32 + 128]];
  for (let k = 0; k < 7; k++) larghe.push([100, -6 + k * 1.7, 0, 500, -6 + k * 1.7, 0, 4, 6]);
  for (const s of [seg, larghe]) {
    const punti = [];
    for (let x = -100; x <= 550; x += 4) punti.push([x, 0]);
    const h = quote(punti, indice(s));
    for (let k = 0; k < punti.length; k++) assert.ok(Math.abs(h[k] - 8) < 0.3, `a x=${punti[k][0]} h=${h[k]}`);
  }
});

test('se in fondo il viadotto finisce (il bordo delle tessere) la linea resta su fin lì', () => {
  // La carreggiata in quota finisce a x=600; la stradina a terra, più vicina
  // al percorso, continua. Prima un punto solo a terra in fondo tirava giù
  // la linea per centinaia di metri.
  const i = indice([
    [-200, 7, 8, 600, 7, 8, 8, 2 + 32 + 128],
    [100, -2, 0, 700, -2, 0, 5, 6],
  ]);
  const punti = [];
  for (let x = -100; x <= 640; x += 4) punti.push([x, 0]);
  const h = quote(punti, i);
  for (let k = 0; k < punti.length; k++) if (punti[k][0] < 590) assert.ok(Math.abs(h[k] - 8) < 0.3, `a x=${punti[k][0]} h=${h[k]}`);
  assert.ok(h[punti.length - 1] < 1, 'in fondo, dove resta solo quella, a terra');
});

test('a undici, dodici metri dalla strada la linea non va a zig zag', () => {
  // La tangenziale: il percorso di TomTom corre a 11,5 m dal mezzo della
  // carreggiata, un metro più qua e uno più là. Lo spostamento si spegneva
  // fra dieci e tredici metri, e la linea ballava di tre, quattro metri.
  const i = indice([[-200, 0, 0, 900, 0, 0, 14, 1 + 128]]);
  const l = new Linea(
    Array.from({ length: 141 }, (_, k) => [k * 5, 11.5 + Math.sin((2 * Math.PI * k * 5) / 40)]).flat(),
  );
  const p = profiloDi(l, 0, 700, i);
  let peggio = 0;
  let salto = 0;
  let prima = null;
  for (let s = 60; s <= 640; s += 4) {
    const [, y] = l.a(s);
    const finale = y + p.sposta(s)[1];
    peggio = Math.max(peggio, Math.abs(finale));
    if (prima !== null) salto = Math.max(salto, Math.abs(finale - prima));
    prima = finale;
  }
  assert.ok(peggio < 0.6, `la linea sta sulla strada (al più ${peggio.toFixed(2)} m dal mezzo)`);
  assert.ok(salto < 0.4, `e non fa scalini (${salto.toFixed(2)} m fra due punti)`);
});

test('un punto che si aggancia altrove non fa una gobba; nel parcheggio niente salti di corsia', () => {
  // Una strada a 6 m di lato; per due punti soli c'è una stradina dall'altra parte, più vicina.
  const i = indice([
    [-100, 6, 0, 600, 6, 0, 7, 5],
    [196, -2, 0, 204, -2, 0, 4, 7],
  ]);
  const l = new Linea([0, 0, 500, 0]);
  const p = profiloDi(l, 0, 500, i);
  for (let s = 100; s <= 300; s += 4) assert.ok(Math.abs(p.sposta(s)[1] - 6) < 0.6, `a ${s} m: ${p.sposta(s)[1].toFixed(2)}`);
  // Due corsie di parcheggio, a 4 m di qua e di là, a pezzi alterni di 12 m.
  const pezzi = [];
  for (let x = 0; x < 400; x += 24) pezzi.push([x, 4, 0, x + 12, 4, 0, 4, 7], [x + 12, -4, 0, x + 24, -4, 0, 4, 7]);
  const q = profiloDi(l, 0, 400, indice(pezzi));
  let salto = 0;
  for (let s = 40; s <= 360; s += 4) salto = Math.max(salto, Math.abs(q.sposta(s + 4)[1] - q.sposta(s)[1]));
  assert.ok(salto < 0.8, `fra due punti la linea si sposta di ${salto.toFixed(2)} m`);
});

test('il nastro va nella scena a pezzi, ognuno contato da un punto vicino', () => {
  // «I punti per strada non sono corretti, soprattutto gli svincoli»: un
  // percorso lontano dall'origine della scena (qui 150 km: la mappa appena
  // aperta sta su Roma, e chi guida è a Napoli). I numeri che arrivano alla
  // scheda grafica devono restare piccoli, e il nastro lo stesso di prima.
  const x0 = 148600;
  const y0 = -114300;
  const xy = [];
  for (let k = 0; k <= 300; k++) xy.push(x0 + k * 10, y0 + Math.sin(k / 20) * 200);
  const linea = new Linea(xy);
  const h = new Float64Array(Math.ceil(linea.lunghezza / 4) + 2).fill(8.24);
  const profilo = new Profilo(0, 4, h);
  const intero = nastro(linea, profilo, 0, linea.lunghezza, 4.6, 0.62, { code: [[500, 900, 2]] });
  const pezzi = pezziDelNastro(intero);
  assert.ok(pezzi.length >= 3, `un nastro di ${Math.round(linea.lunghezza)} m in più pezzi: ${pezzi.length}`);
  // Nessun triangolo perso, e ogni vertice dov'era (a meno della precisione
  // dei numeri a sette cifre da cui si parte: un centimetro e mezzo a 150 km).
  assert.equal(pezzi.reduce((n, p) => n + p.indici.length, 0), intero.indici.length);
  let grande = 0;
  let t = 0;
  for (const p of pezzi) {
    assert.ok(Number.isInteger(p.ancora[0]) && Number.isInteger(p.ancora[1]));
    assert.equal(p.uv.length / 2, p.posizioni.length / 3);
    assert.equal(p.livelli.length, p.posizioni.length / 3);
    for (let k = 0; k < p.posizioni.length; k += 3) grande = Math.max(grande, Math.abs(p.posizioni[k]), Math.abs(p.posizioni[k + 1]));
    for (let k = 0; k < p.indici.length; k++, t++) {
      const v = p.indici[k];
      const w = intero.indici[t];
      assert.ok(v < p.posizioni.length / 3);
      assert.ok(Math.abs(p.ancora[0] + p.posizioni[3 * v] - intero.posizioni[3 * w]) < 0.02);
      assert.ok(Math.abs(p.ancora[1] + p.posizioni[3 * v + 1] - intero.posizioni[3 * w + 1]) < 0.02);
      assert.equal(p.posizioni[3 * v + 2], intero.posizioni[3 * w + 2]);
      assert.equal(p.uv[2 * v + 1], intero.uv[2 * w + 1]);
      assert.equal(p.livelli[v], intero.livelli[w]);
    }
  }
  assert.ok(grande <= 830, `coordinate piccole in ogni pezzo: ${grande}`);
  // Il nastro intero aveva numeri da centocinquantamila.
  assert.ok(Math.abs(intero.posizioni[0]) > 100000);
});

test('più nastri uniti (le code) si tagliano anche dove saltano lontano', () => {
  const striscia = (x) => ({
    posizioni: new Float32Array([x, 0, 1, x, 4, 1, x + 10, 0, 1, x + 10, 4, 1]),
    uv: new Float32Array([0, 0, 1, 0, 0, 10, 1, 10]),
    livelli: new Float32Array([2, 2, 2, 2]),
    indici: [0, 1, 3, 0, 3, 2],
  });
  const a = striscia(50000);
  const b = striscia(56000);
  const uniti = {
    posizioni: new Float32Array([...a.posizioni, ...b.posizioni]),
    uv: new Float32Array([...a.uv, ...b.uv]),
    livelli: new Float32Array([...a.livelli, ...b.livelli]),
    indici: new Uint16Array([...a.indici, ...b.indici.map((i) => i + 4)]),
  };
  const pezzi = pezziDelNastro(uniti);
  assert.equal(pezzi.length, 2);
  assert.deepEqual(pezzi.map((p) => p.ancora), [[50000, 0], [56000, 0]]);
  assert.deepEqual([...pezzi[1].indici], [0, 1, 3, 0, 3, 2]);
  assert.deepEqual([...pezzi[1].posizioni.slice(0, 6)], [0, 0, 1, 0, 4, 1]);
  assert.deepEqual(pezziDelNastro({ posizioni: new Float32Array(0), uv: new Float32Array(0), livelli: new Float32Array(0), indici: new Uint16Array(0) }), []);
});

test('guardando da lontano i nastri si alzano, quanto basta e non di più', () => {
  // Da vicino niente: i sessanta centimetri bastano.
  assert.equal(alzataDeiNastri(18.4), 0);
  assert.equal(alzataDeiNastri(17), 0);
  // Sotto lo zoom 17 lo stacco sullo schermo resta quello dello zoom 17.
  for (const zoom of [16.5, 16, 15.5]) {
    const metri = 0.62 + alzataDeiNastri(zoom);
    assert.ok(Math.abs(metri * 2 ** (zoom - 17) - 0.62) < 1e-9, `zoom ${zoom}: ${metri}`);
  }
  // Mai più di tre metri: sotto un cavalcavia il percorso ci deve passare.
  assert.ok(alzataDeiNastri(14.5) > 2.8 && alzataDeiNastri(14.5) <= 3);
  assert.equal(alzataDeiNastri(13), 3);
  assert.equal(alzataDeiNastri(Number.NaN), 0);
});

test("alla svolta lo spigolo della linea sta sull'incrocio, non prima né dopo", () => {
  // «I punti per strada non sono corretti, soprattutto gli svincoli»: il
  // percorso del calcolatore sta sei metri a ovest e cinque a nord delle
  // strade della mappa. Gira quindi sei metri prima dell'incrocio vero.
  const i = indice([
    [-300, 0, 0, 0, 0, 0, 7, 5],
    [0, 0, 0, 0, 300, 0, 7, 5],
  ]);
  const l = new Linea([-306, 5, -6, 5, -6, 305]);
  const p = profiloDi(l, 0, l.lunghezza, i);
  const dove = (s) => {
    const [x, y] = l.a(s);
    const [dx, dy] = p.sposta(s);
    return [x + dx, y + dy];
  };
  // Lo spigolo (a 300 m) sull'incrocio.
  const [cx, cy] = dove(300);
  assert.ok(Math.hypot(cx, cy) < 1, `lo spigolo a ${Math.hypot(cx, cy).toFixed(2)} m dall'incrocio`);
  // Prima della svolta sulla prima strada (y = 0), dopo sulla seconda (x = 0):
  // anche nei venti metri attorno, dove prima i due lati si mescolavano.
  for (const s of [100, 250, 280, 292]) assert.ok(Math.abs(dove(s)[1]) < 0.8, `a ${s} m: ${dove(s)[1].toFixed(2)} m dalla prima strada`);
  for (const s of [308, 320, 350, 500]) assert.ok(Math.abs(dove(s)[0]) < 0.8, `a ${s} m: ${dove(s)[0].toFixed(2)} m dalla seconda strada`);
  // E la linea non torna indietro attorno allo spigolo.
  for (let s = 260; s < 300; s += 4) assert.ok(dove(s + 4)[0] > dove(s)[0] - 0.01, `a ${s} m la linea torna indietro`);
});

test('una curva larga non è una svolta: lì la linea si sposta solo di lato', () => {
  // Un arco di raggio 150 m, col percorso tre metri più interno della strada.
  const strada = [];
  const rotta = [];
  for (let k = 0; k <= 60; k++) {
    const a = (k / 60) * (Math.PI / 2);
    const b = ((k + 1) / 60) * (Math.PI / 2);
    if (k < 60) strada.push([150 * Math.sin(a), 150 - 150 * Math.cos(a), 0, 150 * Math.sin(b), 150 - 150 * Math.cos(b), 0, 7, 5]);
    rotta.push(147 * Math.sin(a), 150 - 147 * Math.cos(a));
  }
  const l = new Linea(rotta);
  const p = profiloDi(l, 0, l.lunghezza, indice(strada));
  for (let s = 30; s < l.lunghezza - 30; s += 20) {
    const [x, y] = l.a(s);
    const [dx, dy] = p.sposta(s);
    const r = Math.hypot(x + dx, y + dy - 150);
    assert.ok(Math.abs(r - 150) < 0.6, `a ${s} m la linea sta a ${(r - 150).toFixed(2)} m dal mezzo della strada`);
  }
});

test('in galleria la linea non segue le pieghe della strada disegnata a mano', () => {
  // «La linea ancora la vedo non diritta»: sotto il centro direzionale le
  // strade interrate della mappa sono a spigoli, un metro di qua e uno di là.
  // Sopra non si vedono: la linea che le seguiva faceva scalini nel vuoto.
  const pieghe = (codice) => {
    const seg = [];
    for (let k = 0; k < 30; k++) seg.push([k * 20, k % 2 ? 1 : -1, 0.06, (k + 1) * 20, k % 2 ? -1 : 1, 0.06, 7, codice]);
    return seg;
  };
  const l = new Linea([0, 0, 600, 0]);
  const escursione = (p) => {
    let minimo = Infinity;
    let massimo = -Infinity;
    for (let s = 100; s <= 500; s += 2) {
      const dy = p.sposta(s)[1];
      minimo = Math.min(minimo, dy);
      massimo = Math.max(massimo, dy);
    }
    return massimo - minimo;
  };
  const inGalleria = escursione(profiloDi(l, 0, 600, indice(pieghe(5 + 64))));
  const allAperto = escursione(profiloDi(l, 0, 600, indice(pieghe(5))));
  assert.ok(inGalleria < 0.3, `in galleria la linea balla di ${inGalleria.toFixed(2)} m`);
  // All'aperto la strada si vede, e la linea le sta sopra: lì le pieghe si seguono.
  assert.ok(allAperto > 0.8, `all'aperto segue la strada: ${allAperto.toFixed(2)} m`);
});

// «Guarda le linee del traffico»: TomTom manda una linea per senso, sulla
// stessa strada. Appoggiate sulla strada finivano una sopra l'altra.
test('i due sensi di una strada vanno ognuno nella sua metà', () => {
  const dritta = (da, a, scarto = 0) => Array.from({ length: 21 }, (_, k) => [scarto + Math.sin(k) * 0.4, da + ((a - da) * k) / 20]);
  // Andata e ritorno sulla stessa strada, con qualche decimetro di scarto.
  const [andata, ritorno] = sensiDiMarcia([dritta(0, 100), dritta(100, 0, 0.6)]);
  assert.ok(andata > 1 && andata < 2, `andata ${andata}`);
  assert.equal(ritorno, andata);
  // Un senso unico resta in mezzo alla strada.
  assert.deepEqual(sensiDiMarcia([dritta(0, 100)]), [0]);
  // Due code nello stesso verso non sono due sensi.
  assert.deepEqual(sensiDiMarcia([dritta(0, 100), dritta(0, 100, 0.5)]), [0, 0]);
  // Due strade parallele lontane nemmeno.
  assert.deepEqual(sensiDiMarcia([dritta(0, 100), dritta(100, 0, 30)]), [0, 0]);
  // Il ritorno su un pezzo solo dell'andata: la parte lunga è sola.
  const [lunga, corta] = sensiDiMarcia([dritta(0, 400), dritta(60, 40)]);
  assert.equal(lunga, 0);
  assert.ok(corta > 1);
});
