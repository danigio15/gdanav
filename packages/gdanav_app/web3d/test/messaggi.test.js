import assert from 'node:assert/strict';
import test from 'node:test';
import { codeOrdinate, decodifica } from '../src/messaggi.js';
import { FPS_IN_AUTO, PASSO_30, PASSO_60, PIXEL_IN_AUTO, Ritmo, fpsInAuto, intervalloPerLaSonda, livelloDiCarico, rapportoPixel, valutaPrestazioni, valutaWebgl } from '../src/capacita.js';

test('i messaggi buoni passano, quelli storti no', () => {
  assert.ok(decodifica({ v: 1, tipo: 'opzioni', notte: false, vista: 'inclinata', auto: '#d62a26' }));
  assert.ok(decodifica('{"v":1,"tipo":"pausa","si":true}'));
  assert.ok(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1, 45.1], code: [[0, 10, 2]] }));
  assert.ok(decodifica({ v: 1, tipo: 'percorso', punti: null }));
  assert.ok(decodifica({ v: 1, tipo: 'posizione', lat: 45, lon: 9, rotta: 10, metri: null, velocita: 3, quando: 1 }));
  assert.equal(decodifica({ v: 2, tipo: 'pausa', si: true }), null, 'altra versione');
  assert.equal(decodifica({ v: 1, tipo: 'boh' }), null);
  assert.equal(decodifica('{non json'), null);
  assert.equal(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1] }), null, 'coppie dispari');
  assert.equal(decodifica({ v: 1, tipo: 'posizione', lat: 95, lon: 9, rotta: 0, metri: null, velocita: 0, quando: 1 }), null);
  assert.equal(decodifica({ v: 1, tipo: 'posizione', lat: 45, lon: 9, rotta: 0, metri: null, velocita: NaN, quando: 1 }), null);
  assert.equal(decodifica({ v: 1, tipo: 'manovra', da: 20, a: 10 }), null);
  assert.ok(decodifica({ v: 1, tipo: 'manovra', da: null, a: null }));
  assert.equal(decodifica({ v: 1, tipo: 'camera', modo: 'vola' }), null);
});

test("la velocità dall'auto e gli edifici dall'app passano (prima si scartavano)", () => {
  // Come li manda l'app: `msgVelocita` e `msgEdifici` in lib/mappa/ponte_3d.dart.
  assert.ok(decodifica({ v: 1, tipo: 'velocita', ms: 13.4, alle: 1731234567890 }));
  assert.equal(decodifica({ v: 1, tipo: 'velocita', ms: -1, alle: 1 }), null);
  assert.ok(decodifica({ v: 1, tipo: 'edifici', z: 14, x: 8838, y: 6144, dati: 'GtfwBQ==' }));
  assert.ok(decodifica({ v: 1, tipo: 'edifici', z: 14, x: 8838, y: 6144, dati: null }));
  assert.equal(decodifica({ v: 1, tipo: 'edifici', z: 14, x: 1.5, y: 6144, dati: null }), null);
});

test('le code ordinate, con livelli da 1 a 4', () => {
  assert.deepEqual(codeOrdinate([[50, 60, 9], [10, 20, 1], [30, 30, 2], [5, 8, 0]]), [[10, 20, 1], [50, 60, 4]]);
});

test('WebGL: software e senza WebGL 2 non vanno', () => {
  assert.deepEqual(valutaWebgl({ webgl2: true, maxTrama: 8192, renderer: 'Adreno (TM) 619' }), { ok: true, motivo: null });
  assert.equal(valutaWebgl({ webgl2: false }).motivo, 'webgl2');
  assert.equal(valutaWebgl({ webgl2: true, maxTrama: 8192, renderer: 'Google SwiftShader' }).motivo, 'software');
  assert.equal(valutaWebgl({ webgl2: true, maxTrama: 2048, renderer: 'x' }).motivo, 'trame');
  assert.equal(valutaWebgl({ webgl2: true, maxTrama: 8192, renderer: 'Mali', memoria: 1 }).motivo, 'memoria');
});

test('le prestazioni: lento sotto i 20 fotogrammi', () => {
  assert.equal(valutaPrestazioni([33, 33]), null, 'troppo pochi');
  const veloce = valutaPrestazioni(new Array(100).fill(33));
  assert.ok(!veloce.lento && Math.abs(veloce.fps - 30.3) < 0.1);
  assert.ok(valutaPrestazioni(new Array(100).fill(60)).lento);
  assert.ok(valutaPrestazioni([...new Array(80).fill(33), ...new Array(20).fill(200)]).lento, 'scatti');
});

test('il percorso coi metri: tanti quanti i punti', () => {
  assert.ok(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1, 45.1], metri: [0, 13000] }));
  assert.equal(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1, 45.1], metri: [0] }), null);
});

test("le opzioni dicono se la pagina è sull'auto", () => {
  assert.ok(decodifica({ v: 1, tipo: 'opzioni', notte: false, inAuto: true }));
  assert.equal(decodifica({ v: 1, tipo: 'opzioni', notte: false, inAuto: 'si' }), null);
});

test('trenta o sessanta: dal passo vero dei fotogrammi, non dal tempo dei comandi', () => {
  // Un telefono che disegna un fotogramma al più ogni [capace] ms: va al
  // passo voluto, o più piano se non ce la fa.
  const r = new Ritmo();
  let t = 0;
  const corri = (secondi, capace, v = 10) => {
    for (const fine = t + secondi * 1000; t < fine; ) {
      t += Math.max(r.intervallo(v), capace);
      r.disegnato(t, r.intervallo(v));
    }
  };
  corri(3, 10);
  assert.equal(r.intervallo(10), PASSO_60, 'ce la fa: sessanta');
  assert.equal(r.intervallo(1), PASSO_30, 'da fermi trenta');
  corri(5, 10);
  assert.equal(r.intervallo(10), PASSO_60);
  // La scheda grafica non ci sta più dietro (un fotogramma ogni 25 ms, anche
  // se i comandi costano poco): si torna a trenta, e non si riprova subito.
  corri(3, 25);
  assert.equal(r.intervallo(10), PASSO_30);
  corri(10, 25);
  assert.equal(r.intervallo(10), PASSO_30, 'si riprova più tardi');
  // Passato il tempo si riprova; va male di nuovo, e si aspetta il doppio.
  corri(12, 25);
  assert.equal(r.attesa, 80000);
  // Un telefono che non sta dietro nemmeno a trenta: trenta, sempre.
  const lento = new Ritmo();
  t = 0;
  for (let i = 0; i < 2000; i++) {
    t += 45;
    lento.disegnato(t, lento.intervallo(10));
  }
  assert.equal(lento.intervallo(10), PASSO_30);
  // Le pause (la mappa ferma) non contano.
  const p = new Ritmo();
  for (let i = 0; i < 100; i++) p.disegnato(i * 1000, PASSO_30);
  assert.equal(p.campioni, 0);
});

test("sull'auto mai sessanta: in autostrada trenta, piano di meno", () => {
  const r = new Ritmo({ fisso30: true });
  for (let i = 1; i < 300; i++) r.disegnato(i * PASSO_30, r.intervallo(20));
  assert.equal(r.intervallo(20), PASSO_30);
  assert.equal(r.svelto, false);
  assert.equal(r.intervallo(5), 1000 / 20);
  assert.equal(r.intervallo(0.5), 1000 / 15);
  // La telecamera che si muove da sé (il tasto dello zoom): fluida anche da fermi.
  assert.equal(r.intervallo(0, true), PASSO_30);
  // Col telefono caldo, o in mano: meno fotogrammi.
  r.livello = 2;
  assert.equal(r.intervallo(20), 1000 / 15);
  assert.equal(r.intervallo(0, true), 1000 / 15);
});

test('il carico dal telefono: il calore, e il telefono in uso vale almeno uno', () => {
  assert.equal(livelloDiCarico(null), 0);
  assert.equal(livelloDiCarico({ livello: 0, telefono: false }), 0);
  assert.equal(livelloDiCarico({ livello: 0, telefono: true }), 1);
  assert.equal(livelloDiCarico({ livello: 2, telefono: true }), 2);
  assert.equal(livelloDiCarico({ livello: 9 }), 3);
  assert.deepEqual(FPS_IN_AUTO.map((_, l) => fpsInAuto(30, l)), [30, 20, 15, 10]);
  assert.equal(fpsInAuto(NaN), 15);
  assert.ok(decodifica({ v: 1, tipo: 'carico', livello: 1, telefono: true }));
  assert.equal(decodifica({ v: 1, tipo: 'carico', livello: 4 }), null);
  assert.equal(decodifica({ v: 1, tipo: 'carico', livello: 1.5 }), null);
  assert.ok(decodifica({ v: 1, tipo: 'nascosta', si: true }));
  assert.equal(decodifica({ v: 1, tipo: 'nascosta' }), null);
  // Sul telefono, con un'altra scena sull'auto (`msgLeggera` in ponte_3d.dart).
  assert.ok(decodifica({ v: 1, tipo: 'leggera', si: true }));
  assert.equal(decodifica({ v: 1, tipo: 'leggera', si: 1 }), null);
});

test('i fotogrammi voluti in meno non sono un telefono lento', () => {
  // Sull'auto a passo d'uomo se ne vogliono quindici: la sonda non deve
  // dire «lento» (sotto i venti) e spegnere la scena.
  const passo = 1000 / fpsInAuto(1);
  const tenuti = Array.from({ length: 200 }, () => intervalloPerLaSonda(passo, passo));
  assert.equal(valutaPrestazioni(tenuti).lento, false);
  assert.equal(valutaPrestazioni(tenuti).fps, 30);
  // Senza quel conto sì: è il guasto che si evita.
  assert.equal(valutaPrestazioni(Array.from({ length: 200 }, () => passo)).lento, true);
  // Chi non tiene nemmeno i quindici (un fotogramma ogni 110 ms) resta lento.
  assert.equal(valutaPrestazioni(Array.from({ length: 200 }, () => intervalloPerLaSonda(110, passo))).lento, true);
  // A trenta e a sessanta gli intervalli restano quelli veri.
  assert.equal(intervalloPerLaSonda(40, PASSO_30), 40);
  assert.equal(intervalloPerLaSonda(18, PASSO_60), 18);
  // Col telefono caldo (dieci voluti) lo stesso.
  assert.equal(valutaPrestazioni(Array.from({ length: 200 }, () => intervalloPerLaSonda(100, 1000 / fpsInAuto(30, 3)))).lento, false);
});

test("la risoluzione: sul telefono quella dello schermo, sull'auto con un tetto di pixel", () => {
  // Il telefono: come prima (al più due).
  assert.equal(rapportoPixel({ dpr: 3, larghezza: 390, altezza: 844 }), 2);
  assert.equal(rapportoPixel({ dpr: 1.5, larghezza: 390, altezza: 844 }), 1.5);
  // L'auto da 2000×1100 pixel, a densità 1 e 2: la stessa tela, sotto il tetto.
  for (const dpr of [1, 2]) {
    const w = 2000 / dpr;
    const h = 1100 / dpr;
    const r = rapportoPixel({ dpr, larghezza: w, altezza: h, inAuto: true });
    assert.ok(w * r * h * r <= PIXEL_IN_AUTO[0], `dpr ${dpr}: ${r}`);
    assert.ok(w * r * h * r > PIXEL_IN_AUTO[0] * 0.85, `dpr ${dpr}: non troppo poco`);
    const caldo = rapportoPixel({ dpr, larghezza: w, altezza: h, inAuto: true, livello: 3 });
    assert.ok(caldo < r && w * caldo * h * caldo <= PIXEL_IN_AUTO[3]);
  }
  // Uno schermo piccolo dell'auto resta pieno.
  assert.equal(rapportoPixel({ dpr: 1, larghezza: 1280, altezza: 720, inAuto: true }), 1);
});
