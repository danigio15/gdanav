// La segnaletica della vista «Corsie» (`segnaletica.js`) e la tessera con
// le corsie, su strade inventate: nessun posto vero.
import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizza, preparaCorsie } from '../src/corsie.js';
import { latDaMerc, lonDaMerc, sistemaTessera } from '../src/geo.js';
import { ALTO_MARCIAPIEDE, RIGHE, costruisciSegnaletica, formaFreccia, togli, trattini } from '../src/segnaletica.js';
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
