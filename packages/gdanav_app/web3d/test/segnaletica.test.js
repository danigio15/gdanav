// La segnaletica della vista «Corsie» (`segnaletica.js`) e la tessera con
// le corsie, su strade inventate: nessun posto vero.
import assert from 'node:assert/strict';
import test from 'node:test';
import { bordiCorsie, normalizza, preparaCorsie } from '../src/corsie.js';
import { latDaMerc, lonDaMerc, sistemaTessera } from '../src/geo.js';
import { ALTO_MARCIAPIEDE, ANGOLO, CORDOLO_M, angoloMarciapiede, lineaRicca, MARCIAPIEDI, RIGHE, SCIVOLO, costruisciSegnaletica, formaFreccia, semplificaPezzo, togli, trattini } from '../src/segnaletica.js';
import { costruisciTessera } from '../src/tessera.js';
import { cavalcavia } from './finte.js';

test('il tratteggio: dall’inizio della via, senza i buchi degli incroci', () => {
  assert.deepEqual(trattini(30, 3, 3), [
    [0, 3],
    [6, 9],
    [12, 15],
    [18, 21],
    [24, 27],
  ]);
  assert.deepEqual(trattini(30, 3, 3, [[5, 13]]), [
    [0, 3],
    [13, 15],
    [18, 21],
    [24, 27],
  ]);
  assert.deepEqual(togli([[0, 10]], [[2, 3], [9, 12]]), [
    [0, 2],
    [3, 9],
  ]);
});

/** I punti dei triangoli di una freccia, `[u, v]`. */
const punti = (tri) => tri.flat();

test('le frecce dipinte: dritta, a destra, a sinistra, insieme', () => {
  const L = 6;
  const W = 1.5;
  const dritta = punti(formaFreccia(['through'], L, W));
  assert.ok(dritta.length > 0);
  for (const [u, v] of dritta) {
    assert.ok(Math.abs(u) <= W / 2 + 1e-9 && v >= -1e-9 && v <= L + 1e-9, `${u},${v}`);
  }
  assert.ok(Math.max(...dritta.map(([, v]) => v)) > L * 0.9, 'la punta in avanti');
  const destra = punti(formaFreccia(['right'], L, W));
  assert.ok(Math.max(...destra.map(([u]) => u)) > W * 0.6, 'la punta a destra');
  assert.ok(Math.min(...destra.map(([u]) => u)) > -W * 0.2);
  const sinistra = punti(formaFreccia(['left'], L, W));
  assert.ok(Math.min(...sinistra.map(([u]) => u)) < -W * 0.6, 'la punta a sinistra');
  const insieme = formaFreccia(['left', 'through'], L, W);
  assert.equal(insieme.length, formaFreccia(['left'], L, W).length + formaFreccia(['through'], L, W).length);
  const sbieco = punti(formaFreccia(['slight_right'], L, W));
  assert.ok(Math.max(...sbieco.map(([u]) => u)) > 0.3 && Math.max(...sbieco.map(([u]) => u)) < W, 'di sbieco, non di traverso');
  assert.deepEqual(formaFreccia([], L, W), []);
});

/** Una via inventata già nei metri della tessera, a terra. */
function via(s, xy) {
  const v = normalizza({ ...s, g: xy.flat() });
  v.xy = xy;
  v.xyVia = xy;
  v.h = xy.map(() => 0);
  return v;
}

test('una strada a due sensi: asfalto largo quanto le corsie, bordi, mezzeria, strisce', () => {
  // Il nodo delle strisce è un nodo della via, come in OpenStreetMap.
  const v = via({ id: 1, hw: 'tertiary', lanes: '2' }, [
    [-200, 0],
    [0, 0],
    [200, 0],
  ]);
  const sg = costruisciSegnaletica({ strade: [v], nodi: [{ highway: 'crossing', xy: [0, 0] }], meta: 1000 });
  const ys = sg.asfalto.p.filter((_, i) => i % 3 === 1);
  // Due corsie da 3,25 e mezzo metro di banchina: ± 3,6 m.
  assert.ok(Math.abs(Math.max(...ys) - 3.6) < 0.01 && Math.abs(Math.min(...ys) + 3.6) < 0.01, `${Math.min(...ys)}..${Math.max(...ys)}`);
  assert.equal(sg.righe.get('continua'), 3, 'due bordi e la mezzeria');
  assert.equal(sg.righe.get('tratteggiata') ?? 0, 0);
  // Le strisce pedonali: rettangoli lungo la strada, attorno al nodo.
  const zebra = [];
  const p = sg.vernice.p;
  for (let i = 0; i < p.length; i += 3) if (Math.abs(p[i]) <= 1.6) zebra.push(p[i + 1]);
  assert.ok(Math.max(...zebra) > 2.5 && Math.min(...zebra) < -2.5, 'da un bordo all’altro');
  assert.equal(sg.segnali.triangoli, 0, 'niente semafori');
});

test('in autostrada: le righe fra le corsie tratteggiate, larghe dove la corsia esce', () => {
  const dritta = via({ id: 1, hw: 'motorway', lanes: '3' }, [
    [-300, 0],
    [0, 0],
  ]);
  const sg = costruisciSegnaletica({ strade: [dritta], meta: 1000 });
  // Due righe fra tre corsie, a 4,5 m ogni 12: 25 trattini l'una.
  assert.equal(sg.righe.get('tratteggiata'), 50);
  const uscita = via({ id: 2, hw: 'motorway', lanes: '4', 'turn:lanes': '|||slight_right' }, [
    [-120, 0],
    [0, 0],
  ]);
  const sg2 = costruisciSegnaletica({ strade: [uscita], meta: 1000 });
  // La riga larga di decelerazione, fra la terza e la quarta corsia.
  const larga = [];
  const p = sg2.vernice.p;
  for (let i = 0; i < p.length; i += 9) larga.push(p[i + 1]);
  const o = 7.5 - 3 * 3.75;
  assert.ok(
    larga.some((y) => Math.abs(y - (o + RIGHE.decelerazione / 2)) < 0.01),
    'la riga di decelerazione è larga mezzo metro',
  );
  // E la freccia sulla corsia che esce: vernice a destra della terza riga.
  let frecce = 0;
  for (let i = 0; i < p.length; i += 3) if (p[i + 1] < o - 0.5 && p[i + 1] > o - 3.5 && p[i] > -110 && p[i] < -10) frecce++;
  assert.ok(frecce > 0, 'la freccia di sbieco sulla quarta corsia');
});

test('un semaforo: la linea d’arresto, le strisce e il palo con le luci', () => {
  const a = via({ id: 1, hw: 'secondary', lanes: '2' }, [
    [-150, 0],
    [0, 0],
  ]);
  const b = via({ id: 2, hw: 'secondary', lanes: '2' }, [
    [0, 0],
    [150, 0],
  ]);
  const c = via({ id: 3, hw: 'residential' }, [
    [0, 0],
    [0, 120],
  ]);
  const sg = costruisciSegnaletica({ strade: [a, b, c], nodi: [{ highway: 'traffic_signals', xy: [0, 0] }], meta: 1000 });
  assert.ok(sg.segnali.triangoli >= 3 * 10, 'tre pali, uno per chi arriva');
  // Il bordo sinistro di [a] si apre dove arriva la strada da nord.
  const bordo = [];
  const p = sg.vernice.p;
  for (let i = 0; i < p.length; i += 3) if (p[i + 1] > 3.3 && p[i + 1] < 3.5) bordo.push(p[i]);
  assert.ok(!bordo.some((x) => Math.abs(x) < 2), 'niente bordo davanti alla strada che arriva');
  // Chi arriva da ovest (sulla sua corsia, y fra 0 e -3,25): prima la linea
  // d'arresto, poi le strisce, e niente vernice sulla strada che incrocia.
  const corsia = [];
  for (let i = 0; i < p.length; i += 3) if (p[i + 1] < -0.3 && p[i + 1] > -3) corsia.push(p[i]);
  const qui = (a, b) => corsia.some((x) => x > a && x < b);
  // La strada da nord è larga 3,35 per parte, quella di là 3,6: le strisce da -7,4 a -4,4.
  // La linea d'arresto va da un bordo all'altro delle corsie di chi arriva:
  // il suo angolo a destra sta a 3,15 m (le righe del bordo a 3,05 e 3,25).
  const arresto = [];
  for (let i = 0; i < p.length; i += 3) if (Math.abs(p[i + 1] + 3.15) < 0.01) arresto.push(p[i]);
  assert.ok(arresto.length && arresto.every((x) => x > -9 && x < -8.3), `la linea d’arresto ${arresto}`);
  assert.ok(qui(-7.4, -4.4), 'le strisce');
  assert.ok(!qui(-4.2, -0.5), 'niente strisce dentro l’incrocio');
  assert.ok(!qui(-8.2, -7.5), 'fra la linea e le strisce un metro di asfalto');
  assert.equal(sg.semafori.length, 3, 'un segno per incrocio');
});

/** Da metri della tessera z/x/y a `[lon, lat]`. */
function geo(z, x, y) {
  const sys = sistemaTessera(z, x, y);
  return (mx, my) => [lonDaMerc(sys.mx + mx * sys.s), latDaMerc(sys.my - my * sys.s)];
}

test('a un incrocio largo il semaforo è a sbraccio, con la lanterna sopra le corsie', () => {
  // Due corsie per chi arriva da ovest, e una strada larga da attraversare.
  const a = via({ id: 1, hw: 'primary', lanes: '4' }, [
    [-150, 0],
    [0, 0],
  ]);
  const b = via({ id: 2, hw: 'primary', lanes: '4' }, [
    [0, 0],
    [150, 0],
  ]);
  const c = via({ id: 3, hw: 'primary', lanes: '4' }, [
    [0, -150],
    [0, 0],
  ]);
  const d = via({ id: 4, hw: 'primary', lanes: '4' }, [
    [0, 0],
    [0, 150],
  ]);
  const largo = costruisciSegnaletica({ strade: [a, b, c, d], nodi: [{ highway: 'traffic_signals', xy: [0, 0] }], meta: 1000 });
  const p = largo.segnali.p;
  let alto = 0;
  let sopraCorsie = false;
  for (let i = 0; i < p.length; i += 3) {
    alto = Math.max(alto, p[i + 2]);
    // Sopra le due corsie di chi arriva da ovest (y fra -6,5 e 0), prima dell'incrocio, in alto.
    if (p[i] < -5 && p[i] > -30 && p[i + 1] < -1 && p[i + 1] > -6 && p[i + 2] > 5) sopraCorsie = true;
  }
  assert.ok(alto > 6, `il palo a sbraccio è alto (${alto})`);
  assert.ok(sopraCorsie, 'la lanterna appesa sopra le corsie');
  // Una via stretta: il palo da tre metri, la lanterna in cima.
  const s1 = via({ id: 5, hw: 'residential' }, [
    [-100, 0],
    [0, 0],
    [100, 0],
  ]);
  const s2 = via({ id: 6, hw: 'residential' }, [
    [0, 0],
    [0, 100],
  ]);
  const stretto = costruisciSegnaletica({ strade: [s1, s2], nodi: [{ highway: 'traffic_signals', xy: [0, 0] }], meta: 1000 });
  const zs = stretto.segnali.p.filter((_, i) => i % 3 === 2);
  assert.ok(Math.max(...zs) < 4.5 && Math.max(...zs) > 3, `palo normale (${Math.max(...zs)})`);
  // Le lenti spente: nessun colore acceso nei colori del semaforo.
  for (let i = 0; i < stretto.segnali.c.length; i += 3) {
    const [r, g, bb] = stretto.segnali.c.slice(i, i + 3);
    assert.ok(!(r > 150 && g < 100) && !(g > 150 && r < 100), 'niente rosso né verde acceso');
  }
});

test('la tessera con le corsie: le geometrie in più, i nastri coperti spenti; senza, com’era', () => {
  const X = 8605;
  const Y = 5860;
  const ll = geo(14, X, Y);
  const dati = {
    v: 1,
    strade: [
      { id: 1, hw: 'motorway', lanes: '3', 'turn:lanes': '||slight_right', g: [...ll(-800, 0), ...ll(0, 0)] },
      { id: 2, hw: 'motorway', lanes: '2', g: [...ll(0, 0), ...ll(800, 0)] },
      { id: 3, hw: 'motorway_link', g: [...ll(0, 0), ...ll(300, -80)] },
    ],
    nodi: [],
  };
  const senza = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.equal(senza.corsie, null);
  const con = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, datiCorsie: preparaCorsie(dati) });
  assert.ok(con.corsie.asfalto.indici.length > 0 && con.corsie.vernice.indici.length > 0);
  assert.ok(con.strade.motorway.indici.length < senza.strade.motorway.indici.length / 4, 'il nastro dell’autostrada sotto le corsie non c’è più');
  assert.deepEqual(Object.keys(con.strade).sort(), Object.keys(senza.strade).sort());
  assert.ok(con.conti.triangoli > senza.conti.triangoli);
});

test('gli alberi della vista «Corsie»: solo quelli veri, mai sull’asfalto', () => {
  const X = 8605;
  const Y = 5860;
  const ll = geo(14, X, Y);
  const strade = [{ id: 1, hw: 'motorway', lanes: '3', g: [...ll(-800, 0), ...ll(800, 0)] }];
  const base = preparaCorsie({ v: 1, strade });
  const con = preparaCorsie({
    v: 1,
    strade,
    // Un albero nel prato, uno in mezzo all'autostrada (un nodo messo male), e un filare di 80 m.
    alberi: [ll(300, 300), ll(100, 0)],
    filari: [{ id: 9, g: [...ll(-400, 200), ...ll(-320, 200)] }],
  });
  assert.equal(con.alberi.length, 2);
  assert.equal(con.filari.length, 1);
  const prima = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, datiCorsie: base, vistaCorsie: true });
  const dopo = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, datiCorsie: con, vistaCorsie: true });
  // L'albero nel prato e gli 11 del filare (uno ogni otto metri, i due capi compresi); quello sull'autostrada no.
  assert.equal(dopo.conti.alberi - prima.conti.alberi, 12);
});

// ── Dove non va il marciapiede ─────────────────────────────────────────
// «Guarda questo incrocio, i marciapiedi in mezzo alla strada.»

/** La linea da [a] a [b] con un punto ogni [passo] metri (così il marciapiede ha i vertici anche in mezzo). */
const fitta = (a, b, passo = 2) => {
  const n = Math.round(Math.hypot(b[0] - a[0], b[1] - a[1]) / passo);
  return Array.from({ length: n + 1 }, (_, k) => [a[0] + ((b[0] - a[0]) * k) / n, a[1] + ((b[1] - a[1]) * k) / n]);
};

/** I punti `[x, y]` del marciapiede (il piano in cima, senza il cordolo). */
function marciapiede(sg) {
  const p = sg.marciapiedi.p;
  const out = [];
  for (let i = 0; i < p.length; i += 3) if (p[i + 2] > ALTO_MARCIAPIEDE + 0.1) out.push([p[i], p[i + 1]]);
  return out;
}

test('una via di città ha il marciapiede dai due lati, per tutta la via', () => {
  const v = via({ id: 1, hw: 'residential' }, [
    [-100, 0],
    [100, 0],
  ]);
  const m = marciapiede(costruisciSegnaletica({ strade: [v], meta: 1000 }));
  assert.ok(m.some(([, y]) => y > 3) && m.some(([, y]) => y < -3), 'dai due lati');
  assert.ok(Math.min(...m.map(([x]) => x)) < -99 && Math.max(...m.map(([x]) => x)) > 99, 'da un capo all’altro');
});

test('due carreggiate divise: il marciapiede solo fuori, niente nello spartitraffico', () => {
  // Due sensi unici a due corsie (3,25 m e mezzo metro di banchina: 3,6 m
  // per parte), coi bordi interni a tre metri: lo spartitraffico.
  const nord = via({ id: 1, hw: 'primary', lanes: '2', oneway: 'yes' }, fitta([-200, 5.1], [200, 5.1], 10));
  const sud = via({ id: 2, hw: 'primary', lanes: '2', oneway: 'yes' }, fitta([200, -5.1], [-200, -5.1], 10));
  const m = marciapiede(costruisciSegnaletica({ strade: [nord, sud], meta: 1000 }));
  assert.ok(m.length > 0);
  assert.ok(!m.some(([, y]) => Math.abs(y) < 8.7 - 0.01), 'niente fra le due carreggiate');
  assert.ok(m.some(([, y]) => y > 8.7) && m.some(([, y]) => y < -8.7), 'fuori sì, dai due lati');
});

test('due vie che si incrociano senza un nodo in comune: nessun marciapiede sull’asfalto dell’altra', () => {
  const a = via({ id: 1, hw: 'secondary', lanes: '2' }, fitta([-150, 0], [150, 0]));
  const b = via({ id: 2, hw: 'residential' }, fitta([0, -150], [0, 150]).map(([x, y]) => [x, y + 1]));
  const sg = costruisciSegnaletica({ strade: [a, b], meta: 1000 });
  const m = marciapiede(sg);
  // L'asfalto di [a]: |y| < 3,6; quello di [b]: |x| < 3,35.
  assert.ok(!m.some(([x, y]) => Math.abs(y) < 3.6 - 0.05 && Math.abs(x) < 120), 'niente sull’asfalto di a');
  assert.ok(!m.some(([x, y]) => Math.abs(x) < 3.35 - 0.05 && Math.abs(y) < 120), 'niente sull’asfalto di b');
  // Ma lontano dall'incrocio c'è, per tutte e due.
  assert.ok(m.some(([x, y]) => x > 50 && y > 3.6));
  assert.ok(m.some(([x, y]) => y > 50 && x > 3.35));
});

test('niente marciapiede sulle rampe, né sui pezzi corti a senso unico dentro l’incrocio', () => {
  const rampa = via({ id: 1, hw: 'primary_link', oneway: 'yes' }, [
    [-100, 0],
    [100, 0],
  ]);
  assert.equal(costruisciSegnaletica({ strade: [rampa], meta: 1000 }).marciapiedi.triangoli, 0);
  // Una svolta a destra di trentacinque metri, a senso unico, fra due vie: dentro l'incrocio.
  const a = via({ id: 2, hw: 'secondary', lanes: '2' }, [
    [-200, 0],
    [0, 0],
  ]);
  const b = via({ id: 3, hw: 'secondary', lanes: '2' }, [
    [25, -25],
    [25, -200],
  ]);
  const svolta = via({ id: 4, hw: 'secondary', lanes: '1', oneway: 'yes' }, [
    [0, 0],
    [15, -8],
    [25, -25],
  ]);
  const sg = costruisciSegnaletica({ strade: [a, b, svolta], meta: 1000 });
  const m = marciapiede(sg);
  assert.ok(!m.some(([x, y]) => x > 2 && x < 18 && y < -2 && y > -24), 'niente marciapiede lungo la svolta');
  // Lo stesso senso unico lungo, una via vera: il marciapiede ce l'ha.
  const lungo = via({ id: 5, hw: 'secondary', lanes: '1', oneway: 'yes' }, [
    [0, 0],
    [0, -300],
  ]);
  assert.ok(costruisciSegnaletica({ strade: [a, lungo], meta: 1000 }).marciapiedi.triangoli > 0);
});

// ── Come si vede il marciapiede ────────────────────────────────────────
// «Non si capisce che sono marciapiedi.»

/** I triangoli del piano in cima ai marciapiedi (non le facce del cordolo): `[[x, y, z] × 3]`. */
function pianiMarciapiede(sg) {
  const { p, n, i } = sg.marciapiedi;
  const out = [];
  for (let t = 0; t < i.length; t += 3) {
    const v = [i[t], i[t + 1], i[t + 2]];
    if (v.some((k) => n[3 * k + 2] < 0.9)) continue;
    out.push(v.map((k) => [p[3 * k], p[3 * k + 1], p[3 * k + 2]]));
  }
  return out;
}

/** Se il punto (x, y) sta sotto uno dei triangoli [tri] (visti dall'alto). */
function sotto(tri, x, y) {
  return tri.some(([a, b, c]) => {
    const s1 = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]);
    const s2 = (c[0] - b[0]) * (y - b[1]) - (c[1] - b[1]) * (x - b[0]);
    const s3 = (a[0] - c[0]) * (y - c[1]) - (a[1] - c[1]) * (x - c[0]);
    return (s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0);
  });
}

/** L'incrocio di due vie di quartiere in un nodo, e mezza larghezza dell'asfalto. */
function incrocio() {
  const a = via({ id: 1, hw: 'residential' }, fitta([-120, 0], [120, 0], 4));
  const b = via({ id: 2, hw: 'residential' }, fitta([0, -120], [0, 120], 4));
  return { a, b, m: bordiCorsie(a).sinistra + a.margini[0] };
}

test('all’incrocio gli angoli sono tondi: il marciapiede gira da una via all’altra, senza buchi', () => {
  const { a, b, m } = incrocio();
  const sg = costruisciSegnaletica({ strade: [a, b], meta: 1000 });
  const piani = pianiMarciapiede(sg);
  const w = MARCIAPIEDI.residential;
  const R = w + ANGOLO.raggio;
  for (const [sx, sy] of [
    [1, 1],
    [-1, 1],
    [-1, -1],
    [1, -1],
  ]) {
    // Lungo le due vie, fin dove comincia la curva, e intorno alla curva.
    for (let d = m + R + 0.2; d < 60; d += 2) {
      assert.ok(sotto(piani, sx * d, sy * (m + w / 2)), `lungo a, ${sx},${sy} a ${d}`);
      assert.ok(sotto(piani, sx * (m + w / 2), sy * d), `lungo b, ${sx},${sy} a ${d}`);
    }
    // Il centro della curva è a (m + R, m + R): il mezzo del marciapiede a R - w/2 da lì.
    for (const ang of [0.15, 0.5, 0.85]) {
      const t = (Math.PI / 2) * ang;
      const x = m + R - Math.cos(t) * (R - w / 2);
      const y = m + R - Math.sin(t) * (R - w / 2);
      assert.ok(sotto(piani, sx * x, sy * y), `sulla curva ${sx},${sy} ${ang}`);
    }
    // Lo spigolo vero, fra la curva e l'asfalto: asfalto, non marciapiede.
    const spigolo = m + 0.4;
    assert.ok(!sotto(piani, sx * spigolo, sy * spigolo), `niente marciapiede nello spigolo ${sx},${sy}`);
    assert.ok(sotto(triangoliDi(sg.asfalto), sx * spigolo, sy * spigolo), `l’asfalto riempie lo spigolo ${sx},${sy}`);
  }
  // Mai sull'asfalto delle due vie.
  for (const tri of piani) {
    const cx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3;
    const cy = (tri[0][1] + tri[1][1] + tri[2][1]) / 3;
    assert.ok(Math.abs(cx) > m - 0.01 && Math.abs(cy) > m - 0.01, `sull’asfalto: ${cx},${cy}`);
  }
});

/** I triangoli di un costruttore, visti dall'alto. */
function triangoliDi(c) {
  const out = [];
  for (let t = 0; t < c.i.length; t += 3) out.push([c.i[t], c.i[t + 1], c.i[t + 2]].map((k) => [c.p[3 * k], c.p[3 * k + 1], c.p[3 * k + 2]]));
  return out;
}

test('l’angolo tondo non si fa dove passa un’altra via (la svolta a destra che taglia l’angolo)', () => {
  const { a, b, m } = incrocio();
  // La svolta da a (verso est) a b (verso sud), corta e a senso unico: dentro l'incrocio.
  const svolta = via({ id: 3, hw: 'residential', oneway: 'yes' }, fitta([14, 0], [0, -14], 2));
  a.xy = a.xyVia = [...fitta([-120, 0], [0, 0], 4), ...fitta([0, 0], [14, 0], 2).slice(1), ...fitta([14, 0], [120, 0], 4).slice(1)];
  a.h = a.xy.map(() => 0);
  b.xy = b.xyVia = [...fitta([0, -120], [0, -14], 4), ...fitta([0, -14], [0, 0], 2).slice(1), ...fitta([0, 0], [0, 120], 4).slice(1)];
  b.h = b.xy.map(() => 0);
  const sg = costruisciSegnaletica({ strade: [a, b, svolta], meta: 1000 });
  const piani = pianiMarciapiede(sg);
  const mezza = bordiCorsie(svolta).sinistra + svolta.margini[0];
  const sv = svolta.xy;
  for (const tri of piani) {
    const cx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3;
    const cy = (tri[0][1] + tri[1][1] + tri[2][1]) / 3;
    for (let k = 1; k < sv.length; k++) {
      const [p, q] = [sv[k - 1], sv[k]];
      const dx = q[0] - p[0];
      const dy = q[1] - p[1];
      const t = Math.max(0, Math.min(1, ((cx - p[0]) * dx + (cy - p[1]) * dy) / (dx * dx + dy * dy)));
      assert.ok(Math.hypot(cx - p[0] - dx * t, cy - p[1] - dy * t) > mezza - 0.05, `marciapiede sulla svolta: ${cx},${cy}`);
    }
  }
  // Quell'angolo non c'è; gli altri tre restano tondi.
  const R = MARCIAPIEDI.residential + ANGOLO.raggio;
  const x = m + R - Math.cos(Math.PI / 4) * (R - 0.9);
  assert.ok(!sotto(piani, x, -x), 'niente curva sulla svolta');
  assert.ok(sotto(piani, x, x) && sotto(piani, -x, x) && sotto(piani, -x, -x));
});

test('l’arco dell’angolo: tangente ai due cordoli, e niente se sotto passa un’altra via', () => {
  const { a, b, m } = incrocio();
  const strade = [a, b];
  for (const v of strade) v.sVia = v.xyVia.map((_, k) => k * 4);
  const ricche = strade.map((v) => lineaRicca(v.xy, v.h));
  const bordi = strade.map((v) => [bordiCorsie(v).sinistra + v.margini[0], bordiCorsie(v).destra - v.margini[1]]);
  const k = a.xy.findIndex(([x, y]) => x === 0 && y === 0);
  // Da a verso est a b verso nord: l'angolo a nord-est.
  const A = { i: 0, k, passo: 1 };
  const B = { i: 1, k, passo: 1 };
  const ang = angoloMarciapiede(A, B, strade, ricche, bordi, () => 0.2, null);
  assert.ok(ang);
  const R = MARCIAPIEDI.residential + ANGOLO.raggio;
  assert.ok(Math.abs(ang.a.sT - (120 + m + R)) < 1e-6 && Math.abs(ang.b.sT - (120 + m + R)) < 1e-6, 'i dritti finiscono dove comincia la curva');
  const [p0, pN] = [ang.punti[0], ang.punti[ang.punti.length - 1]];
  assert.ok(Math.hypot(p0.x - (m + R), p0.y - m) < 1e-6 && Math.hypot(pN.x - m, pN.y - (m + R)) < 1e-6);
  // Il marciapiede verso l'isolato (nord-est), e ai capi proprio come i dritti.
  assert.ok(Math.abs(p0.nx) < 1e-9 && Math.abs(p0.ny - 1) < 1e-9 && Math.abs(pN.nx - 1) < 1e-9 && Math.abs(pN.ny) < 1e-9);
  // Il cordolo sull'arco: a R dal centro (m + R, m + R).
  for (const q of ang.punti) assert.ok(Math.abs(Math.hypot(q.x - m - R, q.y - m - R) - R) < 0.02, `fuori dal cerchio: ${q.x},${q.y}`);
  // Un'altra via sotto l'arco: niente angolo.
  assert.equal(angoloMarciapiede(A, B, strade, ricche, bordi, () => 0.2, { sotto: () => ({ i: 9 }) }), null);
  // Due vie quasi dritte: niente angolo.
  assert.equal(angoloMarciapiede(A, { i: 0, k, passo: -1 }, strade, ricche, bordi, () => 0.2, null), null);
});

test('alle strisce pedonali il marciapiede scende: lo scivolo, senza il cordolo', () => {
  const v = via({ id: 1, hw: 'residential' }, fitta([-100, 0], [100, 0], 4));
  const sg = costruisciSegnaletica({ strade: [v], nodi: [{ highway: 'crossing', xy: [0, 0] }], meta: 1000 });
  const { p, n, t } = sg.marciapiedi;
  const z0 = 0.2;
  let bassi = 0;
  for (let k = 0; k < p.length / 3; k++) {
    if (n[3 * k + 2] < 0.9) continue;
    const x = p[3 * k];
    const z = p[3 * k + 2] - z0;
    if (Math.abs(x) <= SCIVOLO.mezzo + 1e-6) {
      assert.ok(Math.abs(z - SCIVOLO.alto) < 1e-6, `sulle strisce il marciapiede è basso: ${x} ${z}`);
      bassi++;
      // Il cordolo non c'è: la sua fascia (u < CORDOLO_M) comincia più in là.
      assert.ok(t[2 * k] >= CORDOLO_M);
    } else if (Math.abs(x) >= SCIVOLO.mezzo + SCIVOLO.rampa - 1e-6) assert.ok(Math.abs(z - ALTO_MARCIAPIEDE) < 1e-6, `fuori dalle strisce è alto: ${x} ${z}`);
  }
  assert.ok(bassi >= 4, 'lo scivolo dai due lati');
  // Lontano dalle strisce il cordolo comincia dal bordo della strada.
  assert.ok([...Array(p.length / 3).keys()].some((k) => n[3 * k + 2] > 0.9 && Math.abs(p[3 * k]) > 50 && t[2 * k] === 0));
});

test('il marciapiede di una via dritta: quattro vertici, con le uv e i colori di giorno e di notte', () => {
  const v = via({ id: 1, hw: 'residential' }, fitta([-100, 0], [100, 0], 2));
  const sg = costruisciSegnaletica({ strade: [v], meta: 1000 });
  // Due lati, ognuno il piano (2 triangoli) e la faccia del cordolo (2).
  assert.equal(sg.marciapiedi.triangoli, 8);
  const g = sg.marciapiedi.fatto();
  assert.equal(g.uv.length, (g.posizioni.length / 3) * 2);
  assert.equal(g.colori.length, g.posizioni.length);
  assert.equal(g.coloriNotte.length, g.posizioni.length);
  // La faccia del cordolo è più scura del piano.
  const c = sg.marciapiedi.c;
  const nn = sg.marciapiedi.n;
  const faccia = [...Array(nn.length / 3).keys()].find((k) => Math.abs(nn[3 * k + 2]) < 0.1);
  const piano = [...Array(nn.length / 3).keys()].find((k) => nn[3 * k + 2] > 0.9);
  assert.ok(c[3 * faccia] < c[3 * piano]);
});

test('semplificare un pezzo: sulle vie dritte restano i capi, in curva no, i fissi sempre', () => {
  const dritta = fitta([0, 0], [100, 0], 4).map(([x, y], k) => [x, y, 0, 0, 1, k * 4]);
  assert.equal(semplificaPezzo(dritta, 3, 5).length, 2);
  const fissi = new Set([dritta[10]]);
  assert.deepEqual(semplificaPezzo(dritta, 3, 5, 0.04, fissi), [dritta[0], dritta[10], dritta[dritta.length - 1]]);
  // Un arco di raggio 30: il cordolo a 3 m e il filo a 5 m restano entro 4 cm.
  const arco = Array.from({ length: 40 }, (_, k) => {
    const a = (k / 39) * (Math.PI / 2);
    return [30 * Math.cos(a), 30 * Math.sin(a), 0, -Math.cos(a), -Math.sin(a), 30 * a];
  });
  const pochi = semplificaPezzo(arco, 3, 5);
  assert.ok(pochi.length > 4 && pochi.length < arco.length);
});

/** Le strisce di sbieco della zebratura: i quadrilateri lunghi più di 80 cm di traverso. */
function zebrature(sg) {
  const p = sg.vernice.p;
  const out = [];
  for (let i = 0; i + 11 < p.length; i += 12) {
    const dy = p[i + 7] - p[i + 4];
    const dx = p[i + 6] - p[i + 3];
    if (Math.abs(dy) > 0.8 && Math.abs(dy) > Math.abs(dx) * 0.5) out.push([(p[i] + p[i + 6]) / 2, (p[i + 1] + p[i + 7]) / 2]);
  }
  return out;
}

test('la zebratura dove la carreggiata si divide: nel triangolo, mai sulle corsie', () => {
  const arriva = via({ id: 1, hw: 'motorway', lanes: '3', oneway: 'yes' }, [
    [-200, 0],
    [0, 0],
  ]);
  const dritta = via({ id: 2, hw: 'motorway', lanes: '2', oneway: 'yes' }, [
    [0, 0],
    [300, 0],
  ]);
  const esce = via({ id: 3, hw: 'motorway_link', lanes: '1', oneway: 'yes' }, [
    [0, 0],
    [300, -60],
  ]);
  const z = zebrature(costruisciSegnaletica({ strade: [arriva, dritta, esce], meta: 1000 }));
  assert.ok(z.length >= 3, `le strisce nel triangolo (${z.length})`);
  // Nei dati la rampa resta sovrapposta alla carreggiata per sessanta metri:
  // lì niente strisce, che andavano di traverso sulle corsie.
  const sovrapposta = via({ id: 3, hw: 'motorway_link', lanes: '1', oneway: 'yes' }, [
    [0, 0],
    [60, -3],
    [300, -60],
  ]);
  const z2 = zebrature(costruisciSegnaletica({ strade: [arriva, dritta, sovrapposta], meta: 1000 }));
  const sulleCorsie = z2.filter(([, y]) => y > -3.75);
  assert.deepEqual(sulleCorsie, [], `strisce sulle corsie: ${JSON.stringify(sulleCorsie)}`);
});
