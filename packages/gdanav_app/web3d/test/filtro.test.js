// «Ci sono ancora problemi di reale posizione: trova un metodo serio per
// mantenere la posizione reale e fluida.» Il filtro di Kalman lungo il
// percorso (`filtro.js`), su un viaggio finto ma onesto: il GPS una volta al
// secondo, che dice dov'era l'auto un po' prima, con qualche metro di
// rumore, e arriva in ritardo; la velocità del cruscotto cinque volte al
// secondo.

import assert from 'node:assert/strict';
import test from 'node:test';
import { FiltroSullaStrada } from '../src/filtro.js';

/** Fermi 3 s, su a 14 m/s, costante, frenata fino a fermi, fermi. */
function viaggio(t) {
  const fasi = [
    [3, 0],
    [5.6, 2.5],
    [12, 0],
    [4.7, -3],
    [8, 0],
  ];
  let s = 0;
  let v = 0;
  let resto = t;
  for (const [d, a] of fasi) {
    const q = Math.min(resto, d);
    s += v * q + 0.5 * a * q * q;
    v = Math.max(0, v + a * q);
    resto -= q;
    if (resto <= 0) break;
  }
  return { s, v };
}

function rumore(seme) {
  let x = seme;
  const caso = () => {
    x = (x * 16807) % 2147483647;
    return x / 2147483647;
  };
  return () => Math.sqrt(-2 * Math.log(caso() + 1e-12)) * Math.cos(2 * Math.PI * caso());
}

/** Guida il filtro su [vero] e torna, fotogramma per fotogramma, dove sta la freccia e dove l'auto. */
function guida({ vero = viaggio, durata = 33, ritardoGps = 0.8, rumoreM = 3, conAuto = true, seme = 11 } = {}) {
  const g = rumore(seme);
  const f = new FiltroSullaStrada();
  const T0 = 1_000_000;
  const fotogrammi = [];
  let prossimoFix = T0;
  let prossimaAuto = T0;
  const inArrivo = [];
  for (let t = T0; t <= T0 + durata * 1000; t += 16) {
    if (t >= prossimoFix) {
      const fix = vero(Math.max(0, (prossimoFix - T0) / 1000 - ritardoGps));
      inArrivo.push({ arriva: prossimoFix + 150, metri: fix.s + g() * rumoreM, alle: prossimoFix, v: Math.max(0, fix.v + g() * 0.25) });
      prossimoFix += 1000;
    }
    while (inArrivo.length && inArrivo[0].arriva <= t) {
      const l = inArrivo.shift();
      f.misura({ metri: l.metri, alle: l.alle, v: l.v, precisione: 5 }, t);
    }
    if (conAuto && t >= prossimaAuto) {
      const c = vero(Math.max(0, (t - T0) / 1000 - 0.1));
      f.velocitaAuto(Math.max(0, c.v + g() * 0.1), t - 20, t);
      prossimaAuto += 200;
    }
    const s = f.passo(t);
    if (s !== null) fotogrammi.push({ t: (t - T0) / 1000, s, vero: vero((t - T0) / 1000).s });
  }
  return fotogrammi;
}

test('con la velocità dell\'auto la freccia sta dov\'è l\'auto, e non torna mai indietro', () => {
  const f = guida().filter((x) => x.t > 4);
  const errori = f.map((x) => x.s - x.vero);
  const media = errori.reduce((a, e) => a + Math.abs(e), 0) / errori.length;
  assert.ok(media < 1.5, `in media ${media.toFixed(1)} m`);
  assert.ok(Math.min(...errori) > -4, `al più ${Math.min(...errori).toFixed(1)} m dietro`);
  assert.ok(Math.max(...errori) < 3, `al più ${Math.max(...errori).toFixed(1)} m avanti`);
  for (let i = 1; i < f.length; i++) assert.ok(f[i].s >= f[i - 1].s - 0.01, `indietro a ${f[i].t.toFixed(2)} s`);
});

test('anche col GPS lento e rumoroso, e la velocità dell\'auto, resta vicina', () => {
  const f = guida({ ritardoGps: 1.1, rumoreM: 5, seme: 3 }).filter((x) => x.t > 4);
  const media = f.reduce((a, x) => a + Math.abs(x.s - x.vero), 0) / f.length;
  assert.ok(media < 4, `in media ${media.toFixed(1)} m`);
});

test('non scatta: l\'accelerazione della freccia resta quella di un\'auto', () => {
  for (const conAuto of [true, false]) {
    const f = guida({ conAuto }).filter((x) => x.t > 4);
    let peggio = 0;
    for (let i = 2; i < f.length; i++) {
      const v1 = (f[i].s - f[i - 1].s) / 0.016;
      const v0 = (f[i - 1].s - f[i - 2].s) / 0.016;
      peggio = Math.max(peggio, Math.abs(v1 - v0) / 0.016);
    }
    assert.ok(peggio < 40, `${conAuto ? 'con' : 'senza'} l'auto: ${peggio.toFixed(0)} m/s²`);
  }
});

test('frenando fino al semaforo si ferma dove ci si ferma', () => {
  const f = guida();
  const fermi = f.filter((x) => x.t > 27);
  const errori = fermi.map((x) => x.s - x.vero);
  assert.ok(Math.max(...errori.map(Math.abs)) < 2, `ferma a ${Math.max(...errori.map(Math.abs)).toFixed(1)} m`);
});

test('fermi al semaforo, il GPS che balla non muove la freccia', () => {
  // Arrivati frenando, si aspetta: col cruscotto e senza.
  for (const conAuto of [true, false]) {
    const f = guida({ durata: 40, rumoreM: 4, conAuto }).filter((x) => x.t > 30);
    const quanto = Math.max(...f.map((x) => x.s)) - Math.min(...f.map((x) => x.s));
    assert.ok(quanto < 1.5, `${conAuto ? 'con' : 'senza'} l'auto si è mossa di ${quanto.toFixed(1)} m`);
  }
});

test('ripartendo col solo GPS non si inventa una frenata', () => {
  const f = new FiltroSullaStrada();
  const T0 = 1_000_000;
  const vero = (t) => (t < 3 ? { s: 0, v: 0 } : { s: 1.25 * (t - 3) ** 2, v: 2.5 * (t - 3) });
  for (let k = 0; k <= 6; k++) {
    const g = vero(Math.max(0, k - 0.8));
    f.misura({ metri: g.s, alle: T0 + k * 1000, v: g.v, precisione: 5 }, T0 + k * 1000 + 150);
    // Prima la prima lettura in moto azzerava la velocità: il filtro, sicuro
    // del semaforo, si inventava una frenata e la freccia restava ferma.
    if (k >= 5) assert.ok(f.velocita > 1.5, `a ${k} s velocità ${f.velocita.toFixed(2)}`);
  }
  assert.ok(f.velocita > 4, `a 6 s va a ${f.velocita.toFixed(1)} m/s`);
});

test('un percorso nuovo (i metri ripartono da capo) non trascina la freccia', () => {
  const f = new FiltroSullaStrada();
  f.misura({ metri: 800, alle: 1000, v: 10 }, 1100);
  f.passo(1200);
  f.misura({ metri: 5, alle: 2000, v: 10 }, 2100);
  const s = f.passo(2116);
  assert.ok(s < 30, `riparte da ${s.toFixed(0)} m`);
});

test('una velocità del cruscotto vecchia non si usa', () => {
  const f = new FiltroSullaStrada();
  f.misura({ metri: 100, alle: 10_000, v: 0 }, 10_100);
  // Home Assistant che dice 20 m/s di cinque secondi fa: la freccia resta.
  f.velocitaAuto(20, 5_000, 10_200);
  assert.equal(f.velocita, 0);
  f.velocitaAuto(5, 10_150, 10_200);
  assert.ok(f.velocita > 3);
});

test('fermandosi col GPS in ritardo la freccia frena e resta lì: mai indietro', () => {
  // «Quando mi fermo la freccia va avanti e poi ritorna indietro.» Il GPS
  // dice che ci si è fermati un secondo dopo, quando la freccia è già oltre.
  const f = new FiltroSullaStrada();
  let ultima = null;
  let indietro = 0;
  for (let t = 0; t <= 20000; t += 33) {
    if (t % 1000 < 33) {
      const k = t / 1000;
      // 12 m/s per 6 s, poi una frenata di 3 s fino a 90 m; il GPS (posizione
      // e velocità) arriva un secondo in ritardo, come quello del telefono.
      const pos = (q) => (q <= 6 ? 12 * q : q >= 9 ? 90 : 72 + 12 * (q - 6) - 2 * (q - 6) ** 2);
      const vel = (q) => (q <= 6 ? 12 : Math.max(0, 12 - 4 * (q - 6)));
      const metri = pos(Math.max(0, k - 1));
      const v = vel(Math.max(0, k - 1));
      f.misura({ metri, alle: t, v, precisione: 5 }, t);
    }
    const s = f.passo(t);
    if (ultima !== null) indietro = Math.max(indietro, ultima - s);
    ultima = s;
  }
  assert.ok(indietro < 0.01, `è tornata indietro di ${indietro.toFixed(2)} m`);
  assert.ok(ultima - 90 < 8 && ultima >= 90 - 1, `ferma a 90 o poco oltre: ${ultima.toFixed(1)} m`);
});

test('con l\'accelerometro del telefono la freccia frena con l\'auto: si ferma lì, né oltre né indietro', () => {
  // «Deve avere la posizione reale sempre.» Solo il GPS del telefono, un
  // secondo in ritardo; l'accelerometro tarato (al 93%, rumoroso) dice la
  // frenata quando comincia.
  let seme = 11;
  const rnd = () => (seme = (seme * 16807) % 2147483647) / 2147483647;
  const rumore = () => (rnd() - 0.5) * 0.8;
  for (const frenata of [2.5, 4, 6]) {
    const f = new FiltroSullaStrada();
    const tb = 6, v0 = 12, ts = tb + v0 / frenata, fermo = v0 * tb + (v0 * v0) / (2 * frenata);
    const acc = (q) => (q > tb && q < ts ? -frenata : 0);
    const pos = (q) => (q <= tb ? v0 * q : q >= ts ? fermo : v0 * tb + v0 * (q - tb) - 0.5 * frenata * (q - tb) ** 2);
    const vel = (q) => (q <= tb ? v0 : Math.max(0, v0 - frenata * (q - tb)));
    let ultima = null, indietro = 0, oltre = 0, crociera = 0;
    for (let t = 0; t <= 20000; t += 16) {
      const k = t / 1000;
      if (t % 1000 < 16) f.misura({ metri: pos(Math.max(0, k - 1)), alle: t, v: vel(Math.max(0, k - 1)), precisione: 5 }, t);
      if (t % 64 < 16) f.accelerazione(acc(k - 0.1) * 0.93 + rumore(), t, t, 1);
      const s = f.passo(t);
      if (ultima !== null) indietro = Math.max(indietro, ultima - s);
      if (k > 3) oltre = Math.max(oltre, s - pos(k));
      if (k > 4 && k < 5.5) crociera = Math.max(crociera, Math.abs(s - pos(k)));
      ultima = s;
    }
    assert.ok(indietro < 0.01, `${frenata} m/s²: indietro di ${indietro.toFixed(2)} m`);
    // Mezza auto, anche frenando forte (senza accelerometro: fino a otto metri).
    assert.ok(oltre < 3, `${frenata} m/s²: oltre di ${oltre.toFixed(1)} m`);
    assert.ok(ultima - fermo > -2.5, `${frenata} m/s²: ferma ${(ultima - fermo).toFixed(1)} m prima`);
    assert.ok(crociera < 2, `${frenata} m/s²: andando a ${crociera.toFixed(1)} m`);
  }
});

test('senza accelerometro da un po\', il ritardo misurato non conta più', () => {
  const f = new FiltroSullaStrada();
  f.misura({ metri: 0, alle: 0, v: 10 }, 0);
  f.accelerazione(0, 100, 100, 1.2);
  assert.equal(f.accelerometroVivo(500), true);
  assert.equal(f.accelerometroVivo(2000), false);
});
