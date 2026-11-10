// La mappa 3D di GdANav in guida: MapLibre GL JS per il suolo, i nomi e le
// icone (lo stile dell'app), three.js per le strade in quota, gli edifici,
// gli alberi, il percorso e l'auto. La guida la comanda l'app (Flutter) coi
// messaggi di `messaggi.js`; sopra resta il cruscotto di Flutter.

import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import * as THREE from 'three';
import codiceLavoratore from 'gdanav:lavoratore';
import { BUDGET, daDisegnare, pianoTessere } from './budget.js';
import { valutaPrestazioni, valutaWebgl } from './capacita.js';
import { chiave as chiaveTessera, daChiave, mercPerMetro, latDaMerc } from './geo.js';
import { codeOrdinate, decodifica } from './messaggi.js';
import { angoloVerso, Moto, smorza } from './moto.js';
import { IndiceSegmenti, Linea, nastro, Origine, Profilo, profiloDi, quote, riempiQuote } from './percorso.js';
import { BIT_OMBRA, Scena } from './scena.js';
import { SORGENTE_OLTRE, STRATO_3D, ZOOM_3D, adattaStile, filtroNomi } from './stile3d.js';
import { GIORNO, NOTTE } from './tavolozza.js';
import './gdanav3d.css';

/** Gli strati da toccare (come `stratiToccabili` in stile.dart). */
const TOCCABILI = ['persone', 'alternative-etichetta', 'alternative', 'gdanav-soste', 'gdanav-colonnine', 'gdanav-distributori', 'gdanav-vicine', 'gdanav-tutte-gruppi', 'gdanav-tutte', 'nomi-poi', 'segnalazioni', 'tappe', 'arrivo'];

/** Le viste: inclinazione e zoom di partenza (il prototipo approvato). */
const VISTE = { inclinata: { pitch: 70, zoom: 17.9 }, immersiva: { pitch: 74, zoom: 18.3 } };

/** Al più un fotogramma ogni tanto: trenta al secondo bastano. */
const FOTOGRAMMA_MS = 1000 / 30;

/** Fin dove davanti all'auto si fa il percorso in 3D, e da quanto dietro. */
const FINESTRA_AVANTI = 2600;
const FINESTRA_DIETRO = 80;

/** L'angolo verticale dell'obiettivo della mappa, in gradi (MapLibre: 36,87). */
const OBIETTIVO_GRADI = 16;

const S = {
  mappa: null,
  stileCaricato: false,
  stileGrezzo: null,
  notte: false,
  vista: 'inclinata',
  colorAuto: '#d62a26',
  icona: 'freccia',
  sorgenti: new Map(),
  immagini: new Map(),
  coda: [],
  origine: null,
  percorso: null,
  manovra: null,
  risparmio: null,
  posizione: null,
  zoomVoluto: null,
  camera: { modo: 'segui', sopra: 0, sinistra: 0, riquadro: null },
  pausa: false,
  grezze: new Map(),
  costruite: new Map(),
  lavoro: null,
  numeroLavoro: 0,
  sporco: { profilo: true, traffico: true, segni: true },
  bitmap: new Map(),
  intervalli: [],
  sondato: false,
  log: [],
};

const scena = new Scena();
const indice = new IndiceSegmenti();
const moto = new Moto();

// ─── Il ponte con l'app ──────────────────────────────────────────────────

function manda(tipo, dati = {}) {
  const testo = JSON.stringify({ tipo, ...dati });
  try {
    if (window.Gdanav3d?.postMessage) window.Gdanav3d.postMessage(testo);
  } catch {
    // L'app non c'è (le prove nel browser): pazienza.
  }
  if (window.__ascolta) window.__ascolta(testo);
}

function annota(...a) {
  const riga = a.join(' ');
  S.log.push(riga);
  if (S.log.length > 200) S.log.shift();
}

window.addEventListener('error', (e) => {
  annota('errore', e.message);
  if (!S.mappa) manda('errore', { motivo: 'script', dettaglio: String(e.message).slice(0, 300) });
});

/** Un messaggio dall'app. */
function ricevi(grezzo) {
  const m = decodifica(grezzo);
  if (!m) {
    annota('messaggio scartato', typeof grezzo === 'string' ? grezzo.slice(0, 120) : JSON.stringify(grezzo)?.slice(0, 120));
    return false;
  }
  // Prima dello stile non c'è la mappa: si tiene da parte.
  if (!S.mappa && !['stile', 'opzioni', 'pausa'].includes(m.tipo)) {
    S.coda.push(m);
    return true;
  }
  try {
    GESTORI[m.tipo](m);
  } catch (e) {
    annota('errore su', m.tipo, e?.stack ?? e);
  }
  return true;
}

const GESTORI = {
  opzioni(m) {
    const cambiaNotte = m.notte !== S.notte;
    S.notte = m.notte;
    if (m.vista) S.vista = m.vista;
    if (m.icona) S.icona = m.icona;
    // La freccia, se è quella scelta; l'auto del suo colore, altrimenti.
    const forma = S.icona === 'freccia' ? 'freccia' : 'auto';
    if ((m.auto && m.auto !== S.colorAuto) || forma !== (scena.formaAuto ?? 'auto')) {
      if (m.auto) S.colorAuto = m.auto;
      scena.creaAuto(S.colorAuto, forma);
    }
    if (cambiaNotte) {
      // Lo stile della notte lo manda l'app subito dopo (è un altro stile).
      scena.impostaNotte(S.notte);
      S.sporco.profilo = true;
      S.sporco.traffico = true;
    }
    sveglia();
  },
  stile(m) {
    S.stileGrezzo = m.stile;
    if (!S.mappa) creaMappa(m.stile);
    else caricaStile(m.stile);
  },
  immagine(m) {
    S.immagini.set(m.nome, m);
    if (S.stileCaricato) aggiungiImmagine(m);
  },
  sorgente(m) {
    S.sorgenti.set(m.id, m.dati);
    if (m.id === SORGENTE_FATTO) {
      // La strada già fatta anche in 3D, all'altezza della strada: piatta a
      // terra, dove la rampa è in quota, finiva sotto il viadotto («controlla
      // ancora le linee del percorso»).
      const c = (m.dati?.features ?? []).find((f) => f.geometry?.type === 'LineString')?.geometry.coordinates ?? [];
      const lonlat = c.flat();
      S.fatto = lonlat.length >= 4 && S.origine ? { lonlat, linea: lineaDi(lonlat) } : null;
      S.sporco.profilo = true;
      sveglia();
    }
    if (IN_QUOTA[m.id]) S.sporco.segni = true;
    scriviSorgente(m.id, sulSuolo(m.id, m.dati));
  },
  percorso(m) {
    if (m.punti === null) {
      S.percorso = null;
    } else {
      if (!S.origine) S.origine = new Origine(m.punti[0], m.punti[1]);
      // Un percorso nuovo (un ricalcolo, non le code aggiornate): i metri
      // ripartono da capo, e il filtro della posizione con loro.
      const quale = `${m.punti.length}:${m.punti[0]}:${m.punti[1]}:${m.punti[m.punti.length - 2]}`;
      if (quale !== S.qualePercorso) moto.nuovoPercorso();
      S.qualePercorso = quale;
      S.percorso = { lonlat: m.punti, metri: m.metri ?? null, linea: lineaDi(m.punti, m.metri), code: codeOrdinate(m.code), profilo: null, da: null };
    }
    S.sporco.profilo = true;
    sveglia();
  },
  manovra(m) {
    S.manovra = m.da === null ? null : [m.da, m.a];
    S.sporco.profilo = true;
    sveglia();
  },
  risparmio(m) {
    S.risparmio = m.punti === null ? null : { lonlat: m.punti, linea: lineaDi(m.punti) };
    S.sporco.profilo = true;
    sveglia();
  },
  posizione(m) {
    if (!S.origine) S.origine = new Origine(m.lon, m.lat);
    riorigina(m.lon, m.lat);
    const [x, y] = S.origine.daLonLat(m.lon, m.lat);
    S.posizione = m;
    if (m.zoom !== undefined) S.zoomVoluto = m.zoom;
    moto.posizione({
      metri: S.percorso ? m.metri : null,
      v: m.velocita,
      x,
      y,
      rotta: m.rotta,
      quando: m.quando,
      lettura: S.percorso && m.lettura ? m.lettura : null,
      adesso: S.orologioProva ?? Date.now(),
    });
    sveglia();
  },
  /** La velocità dell'auto dal cruscotto (Android Auto, il dongle): più volte al secondo. */
  velocita(m) {
    moto.velocitaAuto(m.ms, m.alle, S.orologioProva ?? Date.now());
    sveglia();
  },
  camera(m) {
    const prima = S.camera.modo;
    S.camera = { modo: m.modo, sopra: m.sopra ?? S.camera.sopra, sinistra: m.sinistra ?? S.camera.sinistra ?? 0, pitch: m.pitch ?? null, riquadro: m.riquadro ?? null };
    if (m.modo === 'segui' && prima !== 'segui') S.transizione = { da: performance.now(), dur: 900, partenza: null };
    if (m.modo === 'panoramica' && m.riquadro && S.mappa) {
      const [s, o, n, e] = m.riquadro;
      const H = S.mappa.getCanvas().clientHeight;
      S.mappa.fitBounds(
        [
          [o, s],
          [e, n],
        ],
        { padding: { top: 200, bottom: H * 0.4, left: 48, right: 72 }, pitch: 0, bearing: 0, duration: 1000 },
      );
    }
    sveglia();
  },
  pausa(m) {
    S.pausa = m.si;
    if (!m.si) sveglia();
    else S.mappa?.stop();
  },
};

window.gdanav3d = {
  ricevi,
  diagnosi,
  /** Per il collaudo: un tempo finto (i video, un fotogramma alla volta) e dove sta l'auto. */
  prova: {
    passo(t, dt = 40) {
      S.orologioProva = t;
      aggiornaPercorso(t);
      aggiornaTraffico(t);
      aggiornaSegni(t);
      muovi(t, dt);
      S.mappa?.triggerRepaint();
    },
    /** L'auto sullo schermo (in punti), col tetto un metro e mezzo sopra la strada. */
    /** I segni in quota toccabili, dove stanno sullo schermo (in punti). */
    segniSulloSchermo() {
      const cam = S.camera3d;
      if (!cam || !scena.segni) return [];
      const c = S.mappa.getCanvas();
      const v = new THREE.Vector3();
      const out = [];
      for (const sp of scena.segni.values()) {
        const el = sp.userData.elemento;
        if (!el) continue;
        sp.getWorldPosition(v).project(cam);
        const x = ((v.x + 1) / 2) * c.clientWidth;
        const y = ((1 - v.y) / 2) * c.clientHeight - sp.userData.h * (0.5 - sp.center.y);
        out.push({ x, y, strato: el.layer, proprieta: el.properties });
      }
      return out;
    },
    schermoAuto() {
      if (!S.auto || !S.camera3d) return null;
      const v = new THREE.Vector3(S.auto.x, S.auto.y, S.auto.z + 2.5).project(S.camera3d);
      const c = S.mappa.getCanvas();
      return { x: ((v.x + 1) / 2) * c.clientWidth, y: ((1 - v.y) / 2) * c.clientHeight, dietro: v.z > 1 };
    },
    /** Le quote delle strade sopra e sotto l'auto, per la luce sotto i cavalcavia. */
    quoteQui() {
      if (!S.auto) return null;
      return { auto: S.auto.z, strade: indice.candidati(S.auto.x, S.auto.y, 0, 0, 12).map((c) => c.h) };
    },
  },
  /** Per le prove: fra quanto è tutto pronto (tessere fatte, niente in corso). */
  pronta: () => S.stileCaricato && !S.lavoro && S.costruite.size > 0 && (S.mappa?.areTilesLoaded() ?? false),
};

// ─── La mappa ────────────────────────────────────────────────────────────

function infoWebgl() {
  const c = document.createElement('canvas');
  const gl = c.getContext('webgl2');
  if (!gl) return { webgl2: false };
  const dbg = gl.getExtension('WEBGL_debug_renderer_info');
  const info = {
    webgl2: true,
    maxTrama: gl.getParameter(gl.MAX_TEXTURE_SIZE),
    renderer: dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
    memoria: navigator.deviceMemory,
    software: new URLSearchParams(location.search).get('software') === '1',
  };
  gl.getExtension('WEBGL_lose_context')?.loseContext();
  return info;
}

function creaMappa(stile) {
  const info = infoWebgl();
  const esito = valutaWebgl(info);
  annota('webgl', JSON.stringify(info), JSON.stringify(esito));
  if (!esito.ok) {
    manda('errore', { motivo: esito.motivo, gpu: `${info.renderer ?? ''}` });
    return;
  }
  const vista = VISTE[S.vista];
  let mappa;
  try {
    mappa = new maplibregl.Map({
      container: 'mappa',
      style: adattaStile(stile, { notte: S.notte }),
      center: [12.5, 41.9],
      zoom: vista.zoom,
      pitch: vista.pitch,
      maxPitch: 80,
      attributionControl: false,
      pixelRatio: Math.min(window.devicePixelRatio || 1, 2),
      canvasContextAttributes: { antialias: true, preserveDrawingBuffer: new URLSearchParams(location.search).has('prova') },
      fadeDuration: 150,
    });
  } catch (e) {
    manda('errore', { motivo: 'mappa', dettaglio: String(e).slice(0, 300) });
    return;
  }
  // Un teleobiettivo (16° invece di 37°): la telecamera sta più lontana e
  // più alta, a parità di strada inquadrata. Da vicino le torri di cento
  // metri arrivavano quasi all'altezza della telecamera: il tetto enorme, le
  // pareti che si stringevano verso terra, il palazzo «vuoto», come visto
  // da dentro.
  mappa.setVerticalFieldOfView(OBIETTIVO_GRADI);
  S.mappa = mappa;
  window.__mappa = mappa;
  window.__scena = scena;
  mappa.addControl(new maplibregl.AttributionControl({ compact: true }), 'top-left');
  mappa.on('style.load', alloStile);
  // L'attribuzione chiusa: si apre toccando la «i».
  mappa.once('load', () => mappa.getContainer().querySelector('.maplibregl-ctrl-attrib')?.classList.remove('maplibregl-compact-show'));
  mappa.on('webglcontextlost', () => manda('errore', { motivo: 'contesto' }));
  // Senza rete le tessere non arrivano: resta la scena che c'è, senza rumore.
  mappa.on('error', (e) => annota('mappa', e?.error?.message ?? e));
  mappa.on('sourcedata', (e) => {
    if (e.sourceId === 'openmaptiles' && e.tile) pianificaPresto();
    if (e.sourceId === 'traffico' && e.tile) S.sporco.traffico = true;
  });
  mappa.on('moveend', pianificaPresto);
  for (const evento of ['dragstart', 'zoomstart', 'rotatestart', 'pitchstart']) {
    mappa.on(evento, (e) => {
      if (!e.originalEvent) return;
      // Un dito sulla mappa: la si lascia lì (l'app torna a seguire dopo un po').
      if (S.camera.modo === 'segui') S.camera.modo = 'libera';
      manda('toccata');
    });
  }
  mappa.on('click', (e) => {
    // Prima i segni in quota (sui viadotti): lì MapLibre non ha più niente.
    const segno = segnoToccato(e.point.x, e.point.y);
    if (segno) {
      manda('tocco', { elementi: [segno] });
      return;
    }
    const strati = TOCCABILI.filter((id) => mappa.getLayer(id));
    const trovati = strati.length ? mappa.queryRenderedFeatures(e.point, { layers: strati }) : [];
    if (trovati.length) {
      manda('tocco', { elementi: trovati.slice(0, 8).map((f) => ({ type: 'Feature', geometry: f.geometry, properties: f.properties, layer: f.layer?.id })) });
    }
  });
  setInterval(pianifica, 700);
  setInterval(() => {
    S.sporco.traffico = true;
  }, 30000);
}

function caricaStile(stile) {
  S.stileCaricato = false;
  // Lo stile nuovo ha il filtro dei nomi di partenza: si rimette.
  S.nomiNascosti = null;
  S.sporco.segni = true;
  S.mappa.setStyle(adattaStile(stile, { notte: S.notte }), { diff: false });
}

/** Lo stile è pronto: motivi del suolo, cartelli, immagini, sorgenti, lo strato 3D. */
function alloStile() {
  const m = S.mappa;
  motiviSuolo(m);
  cartelli(m);
  for (const img of S.immagini.values()) aggiungiImmagine(img);
  const prima = m.getLayer('nomi-strade') ? 'nomi-strade' : undefined;
  if (!m.getLayer(STRATO_3D)) m.addLayer(strato3d(), prima);
  // L'auto in cima a tutto, anche ai nomi e ai cartelli di MapLibre (come il
  // segnaposto di ogni navigatore): un cartello non la copre mai.
  if (!m.getLayer(STRATO_AUTO)) m.addLayer(stratoAuto());
  S.stileCaricato = true;
  for (const [id, dati] of S.sorgenti) scriviSorgente(id, sulSuolo(id, dati));
  aggiornaIo(true);
  const coda = S.coda;
  S.coda = [];
  for (const msg of coda) GESTORI[msg.tipo](msg);
  aggiornaCielo(true);
  manda('pronto', { versione: 1 });
  sveglia();
}

function scriviSorgente(id, dati) {
  if (!S.stileCaricato) return;
  const s = S.mappa.getSource(id);
  if (s?.setData) s.setData(dati);
}

async function aggiungiImmagine({ nome, png, ratio }) {
  try {
    const byte = Uint8Array.from(atob(png), (c) => c.charCodeAt(0));
    const bmp = await createImageBitmap(new Blob([byte], { type: 'image/png' }));
    const m = S.mappa;
    if (!m || !S.stileCaricato) return;
    S.bitmap.set(nome, { bmp, ratio: ratio ?? 3 });
    S.sporco.segni = true;
    if (m.hasImage(nome)) m.removeImage(nome);
    m.addImage(nome, bmp, { pixelRatio: ratio ?? 3 });
  } catch (e) {
    annota('immagine', nome, e);
  }
}

/** Le trame del suolo: puntini leggeri, che il prato non sembri carta. */
function motiviSuolo(m) {
  const P = S.notte ? NOTTE : GIORNO;
  const fai = (nome, base, macchie, n, seme) => {
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const g = c.getContext('2d');
    g.fillStyle = base;
    g.fillRect(0, 0, 128, 128);
    let s0 = seme;
    const r = () => {
      s0 = (s0 * 16807) % 2147483647;
      return s0 / 2147483647;
    };
    for (let i = 0; i < n; i++) {
      const [cc, a, sz] = macchie[Math.floor(r() * macchie.length)];
      g.globalAlpha = a * (0.4 + r() * 0.6);
      g.fillStyle = cc;
      const x = r() * 128;
      const y = r() * 128;
      const w = sz * (0.5 + r());
      g.beginPath();
      g.ellipse(x, y, w, w * (0.5 + r() * 0.5), r() * 3, 0, 6.3);
      g.fill();
    }
    g.globalAlpha = 1;
    if (m.hasImage(nome)) m.removeImage(nome);
    m.addImage(nome, g.getImageData(0, 0, 128, 128), { pixelRatio: 1 });
  };
  const notte = S.notte;
  const dk = notte ? '#10151f' : '#5f6a5a';
  const lt = notte ? '#3a4560' : '#ffffff';
  fai('p-sfondo', P.sfondo, [[dk, 0.05, 6], [lt, 0.12, 5], [dk, 0.04, 2]], 260, 7);
  fai('p-abitato', P.abitato, [[dk, 0.05, 6], [lt, 0.12, 5], [dk, 0.05, 2]], 260, 11);
  fai('p-industria', P.industria, [[dk, 0.06, 7], [lt, 0.1, 6], [notte ? '#0e121a' : '#7d7466', 0.06, 3]], 300, 13);
  fai('p-prato', P.prato, [[notte ? '#132a22' : '#7fa865', 0.18, 5], [notte ? '#2e4d40' : '#e2efc9', 0.22, 4], [notte ? '#132a22' : '#9cb874', 0.2, 2]], 420, 17);
  fai('p-bosco', P.bosco, [[notte ? '#0f241c' : '#6f9a57', 0.25, 6], [notte ? '#2a4a3a' : '#cfe3b7', 0.2, 4]], 420, 19);
  const usa = (strato, proprieta, img) => {
    if (m.getLayer(strato)) m.setPaintProperty(strato, proprieta, img);
  };
  usa('sfondo', 'background-pattern', 'p-sfondo');
  usa('abitato', 'fill-pattern', 'p-abitato');
  usa('industria', 'fill-pattern', 'p-industria');
  usa('prato', 'fill-pattern', 'p-prato');
  usa('parco', 'fill-pattern', 'p-prato');
  usa('bosco', 'fill-pattern', 'p-bosco');
}

/** I cartelli dei numeri delle strade: verde autostrada, blu le altre. */
function cartelli(m) {
  for (const [nome, fondo] of [
    ['scudo-verde', '#0B7A3E'],
    ['scudo-blu', '#1D4FA3'],
  ]) {
    const c = document.createElement('canvas');
    c.width = 48;
    c.height = 40;
    const g = c.getContext('2d');
    g.fillStyle = '#FFFFFF';
    g.beginPath();
    g.roundRect(1, 1, 46, 38, 9);
    g.fill();
    g.fillStyle = fondo;
    g.beginPath();
    g.roundRect(4, 4, 40, 32, 7);
    g.fill();
    if (m.hasImage(nome)) m.removeImage(nome);
    m.addImage(nome, g.getImageData(0, 0, 48, 40), {
      pixelRatio: 2,
      stretchX: [[14, 34]],
      stretchY: [[12, 28]],
      content: [8, 6, 40, 34],
    });
  }
}

// ─── Lo strato 3D ────────────────────────────────────────────────────────

/**
 * Lo strato dell'auto: la stessa scena, solo i livelli dell'auto (vedi
 * [Scena.creaAuto]) e i segni che stanno sopra (le persone in quota).
 */
const STRATO_AUTO = 'gdanav-3d-auto';
function stratoAuto() {
  const camera = new THREE.Camera();
  camera.matrixAutoUpdate = false;
  camera.matrixWorldAutoUpdate = false;
  camera.layers.set(1);
  return {
    id: STRATO_AUTO,
    type: 'custom',
    renderingMode: '3d',
    render(gl, args) {
      const renderer = S.renderer;
      if (!renderer || !S.origine || !(scena.auto?.visible || scena.segniSopra) || !scena.mondo.visible) return;
      matriciCamera(camera, args);
      renderer.resetState();
      renderer.render(scena.scena, camera);
    },
  };
}

/**
 * Pulisce solo il bit dello stencil delle ombre ([BIT_OMBRA]): prima della
 * scena, perché ogni punto si scurisca una volta; dopo, perché MapLibre
 * ritrovi lo stencil delle sue tessere com'era.
 */
function pulisciBitOmbra(gl) {
  gl.disable(gl.SCISSOR_TEST);
  gl.stencilMask(BIT_OMBRA);
  gl.clearStencil(0);
  gl.clear(gl.STENCIL_BUFFER_BIT);
  gl.stencilMask(0xff);
}

/** La telecamera di three.js dalle matrici di MapLibre (metri della scena → schermo). */
function matriciCamera(camera, args) {
  const m = S.mappa;
  const o = S.origine;
  const ws = m.transform.worldSize;
  const Pm = new THREE.Matrix4().fromArray(args.projectionMatrix);
  const VP = new THREE.Matrix4().fromArray(args.modelViewProjectionMatrix);
  const V = Pm.clone().invert().multiply(VP);
  const Mm = new THREE.Matrix4().set(o.s * ws, 0, 0, o.mx * ws, 0, -o.s * ws, 0, o.my * ws, 0, 0, 1, 0, 0, 0, 0, 1);
  const VM = V.multiply(Mm);
  camera.projectionMatrix.copy(Pm);
  camera.projectionMatrixInverse.copy(Pm).invert();
  camera.matrixWorldInverse.copy(VM);
  camera.matrixWorld.copy(VM).invert();
  camera.matrix.copy(camera.matrixWorld);
  return Pm;
}

function strato3d() {
  let renderer = null;
  const camera = new THREE.Camera();
  camera.matrixAutoUpdate = false;
  camera.matrixWorldAutoUpdate = false;
  let ultimo = null;
  return {
    id: STRATO_3D,
    type: 'custom',
    renderingMode: '3d',
    onAdd(m, gl) {
      renderer = new THREE.WebGLRenderer({ canvas: m.getCanvas(), context: gl, antialias: true });
      renderer.autoClear = false;
      renderer.outputColorSpace = THREE.SRGBColorSpace;
      S.renderer = renderer;
    },
    onRemove() {
      renderer?.dispose();
      renderer = null;
      S.renderer = null;
    },
    render(gl, args) {
      const m = S.mappa;
      const o = S.origine;
      if (!renderer || !o) return;
      const t0 = performance.now();
      const ws = m.transform.worldSize;
      const zoom = m.getZoom();
      scena.mondo.visible = zoom >= ZOOM_3D - 0.05;
      const Pm = new THREE.Matrix4().fromArray(args.projectionMatrix);
      const VP = new THREE.Matrix4().fromArray(args.modelViewProjectionMatrix);
      const V = Pm.clone().invert().multiply(VP);
      const Mm = new THREE.Matrix4().set(o.s * ws, 0, 0, o.mx * ws, 0, -o.s * ws, 0, o.my * ws, 0, 0, 1, 0, 0, 0, 0, 1);
      const VM = V.multiply(Mm);
      camera.projectionMatrix.copy(Pm);
      camera.projectionMatrixInverse.copy(Pm).invert();
      camera.matrixWorldInverse.copy(VM);
      camera.matrixWorld.copy(VM).invert();
      camera.matrix.copy(camera.matrixWorld);
      const ppm = o.s * ws;
      const P = scena.P;
      scena.scena.fog.near = P.nebbiaDa * ppm;
      scena.scena.fog.far = P.nebbiaA * ppm;
      scena.materialeFoschia.uniforms.uNear.value = P.nebbiaDa * 0.8 * ppm;
      scena.materialeFoschia.uniforms.uFar.value = P.nebbiaA * 1.1 * ppm;
      if (scena.mat.bagliore) scena.mat.bagliore.size = 9 * ppm;
      scena.scalaSegni(Pm.elements[5], m.getCanvas().clientHeight);
      // La camera di three.js con le matrici di questo fotogramma, per sfoltire i nomi.
      const occupati = [];
      // Dov'è l'auto sullo schermo: lì gli edifici davanti a lei si fanno trasparenti.
      const ue = scena.uniformiEdifici;
      ue.uSchermo.value.set(gl.drawingBufferWidth, gl.drawingBufferHeight);
      if (S.auto) {
        const vs = new THREE.Vector3(S.auto.x, S.auto.y, S.auto.z + 1.2).project(camera);
        ue.uAutoSchermo.value.set(vs.x, vs.y, vs.z);
      } else ue.uAutoSchermo.value.set(0, -2, -1);
      if (S.auto) {
        const va = new THREE.Vector3(S.auto.x, S.auto.y, S.auto.z + 1).project(camera);
        const ax = ((va.x + 1) / 2) * m.getCanvas().clientWidth;
        const ay = ((1 - va.y) / 2) * m.getCanvas().clientHeight;
        occupati.push([ax - 70, ay - 60, ax + 70, ay + 40]);
      }
      scena.sfoltisciSegni(camera, m.getCanvas().clientWidth, m.getCanvas().clientHeight, occupati);
      pulisciBitOmbra(gl);
      renderer.resetState();
      renderer.render(scena.scena, camera);
      renderer.resetState();
      pulisciBitOmbra(gl);
      S.camera3d = camera;
      const ora = performance.now();
      S.msDisegno = smorza(S.msDisegno ?? ora - t0, ora - t0, 1, 10);
      // La sonda: gli intervalli fra i fotogrammi mentre la mappa si muove.
      // Appena arrivata una tessera la GPU riceve le geometrie: quei
      // fotogrammi lenti non dicono quanto va il telefono.
      if (ultimo !== null && S.anima && !S.sondato && ora - (S.ultimaTessera ?? 0) > 1500) {
        S.intervalli.push(ora - ultimo);
        if (S.intervalli.length >= 240) sonda();
      }
      ultimo = S.anima ? ora : null;
    },
  };
}

function sonda() {
  const esito = valutaPrestazioni(S.intervalli.slice(30));
  S.sondato = true;
  if (esito) manda('prestazioni', { ...esito, triangoli: scena.triangoli, tessere: S.costruite.size });
}

// ─── Le tessere ──────────────────────────────────────────────────────────

const lavoratore = (() => {
  try {
    const w = new Worker(URL.createObjectURL(new Blob([codiceLavoratore], { type: 'text/javascript' })));
    w.onmessage = (e) => allaTessera(e.data);
    w.onerror = (e) => {
      annota('lavoratore', e.message);
      S.lavoro = null;
    };
    return w;
  } catch (e) {
    annota('lavoratore non partito', e);
    return null;
  }
})();

function cacheOpenmaptiles() {
  const st = S.mappa?.style;
  return st?.sourceCaches?.openmaptiles ?? st?.tileManagers?.openmaptiles ?? null;
}

/** I byte delle tessere z14 che MapLibre ha già scaricato: se ne tiene copia. */
function raccogliGrezze() {
  const sc = cacheOpenmaptiles();
  if (!sc) return;
  for (const t of Object.values(sc._tiles ?? {})) {
    const c = t.tileID?.canonical;
    if (!c || c.z !== 14 || !t.latestRawTileData) continue;
    const k = chiaveTessera(14, c.x, c.y);
    if (S.grezze.has(k)) {
      const v = S.grezze.get(k);
      S.grezze.delete(k);
      S.grezze.set(k, v);
      continue;
    }
    S.grezze.set(k, t.latestRawTileData.slice(0));
  }
  while (S.grezze.size > 48) S.grezze.delete(S.grezze.keys().next().value);
}

/** Il centro e il lato della tessera, nei metri della scena; e la scala. */
function postoTessera(k) {
  const { z, x, y } = daChiave(k);
  const n = 2 ** z;
  const mx = (x + 0.5) / n;
  const my = (y + 0.5) / n;
  const s = mercPerMetro(latDaMerc(my));
  const [cx, cy] = S.origine.daMerc(mx, my);
  const scala = s / S.origine.s;
  return { cx, cy, lato: (1 / n / s) * scala, scala };
}

/** Dove sta l'auto (o il centro della mappa), nei metri della scena. */
function doveGuardo() {
  if (S.auto) return [S.auto.x, S.auto.y];
  if (!S.mappa || !S.origine) return null;
  const c = S.mappa.getCenter();
  return S.origine.daLonLat(c.lng, c.lat);
}

let presto = null;
function pianificaPresto() {
  if (presto) return;
  presto = setTimeout(() => {
    presto = null;
    pianifica();
  }, 120);
}

function pianifica() {
  if (!S.mappa || !S.stileCaricato || S.pausa) return;
  raccogliGrezze();
  if (!S.origine) {
    const c = S.mappa.getCenter();
    S.origine = new Origine(c.lng, c.lat);
  }
  const qui = doveGuardo();
  if (!qui) return;
  const disponibili = [...S.grezze.keys()].map((k) => ({ chiave: k, ...postoTessera(k) }));
  const piano = pianoTessere(disponibili, S.costruite, qui[0], qui[1]);
  for (const k of piano.butta) {
    scena.togliTessera(k);
    indice.togli(k);
    S.costruite.delete(k);
    S.sporco.profilo = true;
  }
  const disegno = daDisegnare(S.costruite, qui[0], qui[1], BUDGET, S.disegnate);
  S.disegnate = disegno.si;
  for (const k of S.costruite.keys()) scena.mostraTessera(k, disegno.si.has(k));
  if (S.lavoro || !lavoratore) return;
  let prossima = piano.richieste[0];
  // Niente di nuovo: si rifà una tessera fatta senza una vicina che ora c'è.
  if (!prossima) {
    for (const c of S.costruite.values()) {
      const mancanti = vicineDi(c.chiave).filter((v) => S.grezze.has(v) && !c.vicine.has(v));
      if (mancanti.length) {
        prossima = { chiave: c.chiave, dettaglio: c.dettaglio };
        break;
      }
    }
  }
  if (prossima) chiedi(prossima.chiave, prossima.dettaglio);
}

function vicineDi(k) {
  const { z, x, y } = daChiave(k);
  const out = [];
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) if (dx || dy) out.push(chiaveTessera(z, x + dx, y + dy));
  return out;
}

function chiedi(k, dettaglio) {
  const { z, x, y } = daChiave(k);
  const tessere = {};
  const vicine = new Set();
  for (let dx = -1; dx <= 1; dx++) {
    for (let dy = -1; dy <= 1; dy++) {
      const kk = chiaveTessera(z, x + dx, y + dy);
      const dati = S.grezze.get(kk);
      if (!dati) continue;
      tessere[`${dx},${dy}`] = { chiave: kk, dati: dati.slice(0) };
      if (dx || dy) vicine.add(kk);
    }
  }
  const id = ++S.numeroLavoro;
  S.lavoro = { id, chiave: k, dettaglio, vicine, da: performance.now() };
  lavoratore.postMessage({ id, z, x, y, tessere, dettaglio }, Object.values(tessere).map((t) => t.dati));
}

function allaTessera({ id, tessera, errore }) {
  const lavoro = S.lavoro;
  S.lavoro = null;
  if (!lavoro || lavoro.id !== id) return pianificaPresto();
  if (errore) {
    annota('tessera', lavoro.chiave, errore);
    // Non si riprova subito: si segna come fatta, vuota, ridotta.
    S.costruite.set(lavoro.chiave, { chiave: lavoro.chiave, ...postoTessera(lavoro.chiave), dettaglio: 'pieno', triangoli: 0, vicine: new Set(vicineDi(lavoro.chiave)) });
    return pianificaPresto();
  }
  const posto = postoTessera(tessera.chiave);
  scena.aggiungiTessera(tessera, posto.cx, posto.cy, posto.scala);
  indice.aggiungi(tessera.chiave, tessera.segmenti, posto.cx, posto.cy, posto.scala);
  S.costruite.set(tessera.chiave, {
    chiave: tessera.chiave,
    ...posto,
    dettaglio: tessera.dettaglio,
    triangoli: tessera.conti.triangoli,
    vicine: lavoro.vicine,
    conti: tessera.conti,
  });
  annota('tessera', tessera.chiave, tessera.dettaglio, JSON.stringify(tessera.conti), Math.round(performance.now() - lavoro.da) + 'ms');
  S.sporco.profilo = true;
  S.sporco.traffico = true;
  S.sporco.segni = true;
  S.ultimaTessera = performance.now();
  S.mappa?.triggerRepaint();
  sveglia();
  pianificaPresto();
}

/** Lontani dall'origine i numeri perdono precisione: si riparte da qui. */
function riorigina(lon, lat) {
  if (!S.origine || !S.auto) return;
  if (Math.hypot(S.auto.x, S.auto.y) < 40000) return;
  S.origine = new Origine(lon, lat);
  for (const c of S.costruite.values()) {
    const p = postoTessera(c.chiave);
    Object.assign(c, p);
    scena.spostaTessera(c.chiave, p.cx, p.cy, p.scala);
    const v = scena.tessere.get(c.chiave);
    if (v) indice.aggiungi(c.chiave, v.dati.segmenti, p.cx, p.cy, p.scala);
  }
  if (S.percorso) S.percorso.linea = lineaDi(S.percorso.lonlat, S.percorso.metri);
  if (S.risparmio) S.risparmio.linea = lineaDi(S.risparmio.lonlat);
  if (S.fatto) S.fatto.linea = lineaDi(S.fatto.lonlat);
  moto.s = null;
  moto.x = null;
  S.auto = null;
  S.sporco.profilo = true;
  S.sporco.traffico = true;
}

function lineaDi(lonlat, metri = null) {
  const xy = new Float64Array(lonlat.length);
  for (let i = 0; i < lonlat.length; i += 2) {
    const [x, y] = S.origine.daLonLat(lonlat[i], lonlat[i + 1]);
    xy[i] = x;
    xy[i + 1] = y;
  }
  return new Linea(xy, metri);
}

// ─── Il percorso, la freccia, la strada a risparmio, il traffico ─────────

let ultimoProfilo = 0;

/** La sorgente della strada già fatta (`sorgenteFatto` in `stile.dart`). */
const SORGENTE_FATTO = 'gdanav-fatto';
/** Quanta strada già fatta disegna il 3D: dietro l'auto, oltre non si vede. */
const FATTO_M = 1500;
function aggiornaPercorso(adesso) {
  const p = S.percorso;
  const s = S.auto?.s ?? (p ? 0 : null);
  const fuori = p && p.da !== null && s !== null && (s > p.da + FINESTRA_AVANTI - 900 || s < p.da);
  if (!S.sporco.profilo && !fuori) return;
  if (adesso - ultimoProfilo < 1200 && !fuori && p?.profilo) return;
  ultimoProfilo = adesso;
  S.sporco.profilo = false;
  if (!p || p.linea.lunghezza < 2) {
    for (const n of ['percorso', 'alone', 'freccia']) scena.impostaNastro(n, null);
    scena.impostaPunta(null);
    scriviOltre(null, 0);
  } else {
    const da = Math.max(0, (s ?? 0) - FINESTRA_DIETRO);
    const a = Math.min(p.linea.lunghezza, da + FINESTRA_AVANTI);
    scriviOltre(p, a);
    p.da = da;
    p.profilo = profiloDi(p.linea, da, a, indice);
    S.sporco.segni = true;
    scena.impostaNastro('alone', nastro(p.linea, p.profilo, da, a, 15, 0.55), 'alone', 4);
    scena.impostaNastro('percorso', nastro(p.linea, p.profilo, da, a, 4.6, 0.62, { code: p.code }), 'percorso', 5);
    aggiornaFreccia();
  }
  // La strada già fatta: gli ultimi [FATTO_M] metri, all'altezza giusta.
  const f = S.fatto;
  if (f && f.linea.lunghezza > 2) {
    const a = f.linea.lunghezza;
    const da = Math.max(0, a - FATTO_M);
    scena.impostaNastro('fatto', nastro(f.linea, profiloDi(f.linea, da, a, indice), da, a, 3.6, 0.5), 'fatto', 3);
  } else scena.impostaNastro('fatto', null);
  const r = S.risparmio;
  if (r && r.linea.lunghezza > 2) {
    // La strada proposta: verde, all'altezza giusta, vicino all'auto.
    const qui = doveGuardo();
    const da = qui ? Math.max(0, r.linea.proietta(qui[0], qui[1]).s - 200) : 0;
    const a = Math.min(r.linea.lunghezza, da + FINESTRA_AVANTI);
    const prof = profiloDi(r.linea, da, a, indice);
    scena.impostaNastro('risparmio', nastro(r.linea, prof, da, a, 4, 0.5), 'risparmio', 3);
  } else scena.impostaNastro('risparmio', null);
}

/**
 * Il percorso oltre quello che fa il 3D ([FINESTRA_AVANTI] davanti all'auto),
 * piatto come sulla mappa di sempre (`SORGENTE_OLTRE` in `stile3d.js`).
 * «Ad un certo punto la linea si interrompe, non si vede più»: spostando la
 * mappa più avanti il percorso finiva nel vuoto, dove il 3D non arrivava.
 */
function scriviOltre(p, a) {
  const vuoto = { type: 'FeatureCollection', features: [] };
  if (!p || a >= p.linea.lunghezza - 1) return scriviSorgente(SORGENTE_OLTRE, vuoto);
  const linea = (props, da, fino = p.linea.lunghezza) => ({
    type: 'Feature',
    geometry: { type: 'LineString', coordinates: pezzoDi(p, da, fino) },
    properties: props,
  });
  // Le code oltre, dello stesso colore che hanno da vicino.
  const code = (p.code ?? []).filter(([, fino]) => fino > a).map(([da, fino, livello]) => linea({ livello }, Math.max(a, da), fino));
  scriviSorgente(SORGENTE_OLTRE, { type: 'FeatureCollection', features: [linea({}, a), ...code] });
}

/** I punti `[lon, lat]` del percorso [p] fra [da] e [fino] metri. */
function pezzoDi(p, da, fino) {
  const [x0, y0, i] = p.linea.a(da);
  const [x1, y1, j] = p.linea.a(fino);
  const punti = [S.origine.lonLat(x0, y0)];
  for (let k = i; k < j; k++) punti.push([p.lonlat[2 * k], p.lonlat[2 * k + 1]]);
  punti.push(S.origine.lonLat(x1, y1));
  return punti;
}

function aggiornaFreccia() {
  const p = S.percorso;
  if (!p?.profilo || !S.manovra) {
    scena.impostaNastro('freccia', null);
    scena.impostaPunta(null);
    return;
  }
  const s = S.auto?.s ?? 0;
  const [da, a] = S.manovra;
  const inizio = Math.max(da, s + 6);
  const fine = a - 7;
  if (fine - inizio < 3) {
    scena.impostaNastro('freccia', null);
    scena.impostaPunta(null);
    return;
  }
  scena.impostaNastro('freccia', nastro(p.linea, p.profilo, inizio, fine, 3.0, 0.7, { passo: 1.5 }), 'freccia', 6);
  const [x, y] = p.linea.a(fine);
  const [sx, sy] = p.profilo.sposta(fine);
  scena.impostaPunta([x + sx, y + sy, p.profilo.quota(fine) + 0.72, p.linea.direzione(fine, 3)]);
  S.frecciaDa = inizio;
}

let ultimoTraffico = 0;
function aggiornaTraffico(adesso) {
  if (!S.sporco.traffico || adesso - ultimoTraffico < 3000 || !S.mappa?.getSource('traffico')) return;
  ultimoTraffico = adesso;
  S.sporco.traffico = false;
  const qui = doveGuardo();
  if (!qui || indice.vuoto) return;
  let elementi = [];
  try {
    elementi = S.mappa.querySourceFeatures('traffico', { sourceLayer: 'Traffic flow' });
  } catch {
    return;
  }
  const parti = [];
  const viste = new Set();
  for (const f of elementi) {
    const p = f.properties ?? {};
    const lento = +(p.traffic_level ?? p.trafficLevel ?? 1);
    if (!(lento < 0.6)) continue;
    const g = f.geometry;
    const linee = g.type === 'LineString' ? [g.coordinates] : g.type === 'MultiLineString' ? g.coordinates : [];
    for (const l of linee) {
      if (l.length < 2) continue;
      const firma = l[0].join() + l[l.length - 1].join();
      if (viste.has(firma)) continue;
      viste.add(firma);
      const xy = [];
      let vicino = false;
      for (const [lon, lat] of l) {
        const [x, y] = S.origine.daLonLat(lon, lat);
        xy.push(x, y);
        if (Math.hypot(x - qui[0], y - qui[1]) < 2500) vicino = true;
      }
      if (!vicino) continue;
      const linea = new Linea(xy);
      const L = linea.lunghezza;
      if (L < 5) continue;
      const passo = 5;
      const punti = [];
      for (let s = 0; s <= L; s += passo) punti.push(linea.a(s).slice(0, 2));
      const prof = new Profilo(0, passo, riempiQuote(quote(punti, indice)));
      parti.push(nastro(linea, prof, 0, L, 2.4, 0.34, { passo, code: [[0, L + 1, lento < 0.3 ? 2 : 1]] }));
    }
  }
  scena.impostaNastro('traffico', unisciNastri(parti), 'traffico', 3);
}

function unisciNastri(parti) {
  if (!parti.length) return null;
  let nv = 0;
  let ni = 0;
  for (const p of parti) {
    nv += p.posizioni.length / 3;
    ni += p.indici.length;
  }
  const out = {
    posizioni: new Float32Array(nv * 3),
    uv: new Float32Array(nv * 2),
    livelli: new Float32Array(nv),
    indici: nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni),
  };
  let ov = 0;
  let oi = 0;
  for (const p of parti) {
    out.posizioni.set(p.posizioni, ov * 3);
    out.uv.set(p.uv, ov * 2);
    out.livelli.set(p.livelli, ov);
    for (let k = 0; k < p.indici.length; k++) out.indici[oi + k] = p.indici[k] + ov;
    ov += p.posizioni.length / 3;
    oi += p.indici.length;
  }
  return out;
}

// ─── I segni in quota: icone e nomi sui viadotti ─────────────────────────

/**
 * Le sorgenti con punti che possono stare su un viadotto, e come disegnarli:
 * l'immagine (dalla proprietà o fissa) e quanto è grande (come in stile.dart).
 */
const IN_QUOTA = {
  'gdanav-segnalazioni': { strato: () => 'segnalazioni', immagine: (p) => p.icona, grandezza: (p) => (p.tipo === 'autovelox' ? 1.15 : 0.85) },
  'gdanav-arrivo': { strato: () => 'arrivo', immagine: () => 'arrivo-bandiera', grandezza: () => 1.7 },
  // Le colonnine (le soste col numero, grandi) e le tappe: cerchi come quelli
  // di MapLibre, coi colori presi dallo stile.
  'gdanav-colonnine': {
    strato: (p) => (p.sosta ? 'gdanav-soste' : 'gdanav-colonnine'),
    tela: (p) =>
      p.sosta
        ? cerchio(14, colore('gdanav-soste', 'circle-color', p), colore('gdanav-soste', 'circle-stroke-color', p), 3, String(p.numero ?? ''), '#FFFFFF', 14)
        : cerchio(6.5, colore('gdanav-colonnine', 'circle-color', p), colore('gdanav-colonnine', 'circle-stroke-color', p), 2),
    grandezza: () => 1,
  },
  'gdanav-tappe': {
    strato: () => 'tappe',
    tela: (p) => cerchio(12, colore('tappe', 'circle-color', p), colore('tappe', 'circle-stroke-color', p), 3.5, String(p.numero ?? ''), colore('tappe-numeri', 'text-color', p), 13),
    grandezza: () => 1,
  },
  // Le persone di casa (da GdAHome): il tondo viola con le iniziali e il nome
  // sotto, come a terra; su un viadotto all'altezza dell'impalcato.
  'gdanav-persone': {
    strato: () => 'persone',
    tela: (p) => segnoPersona(p),
    grandezza: () => 1,
    // Sopra i nomi e i cartelli di MapLibre, come l'auto: un «A52» non la copre.
    sopra: true,
  },
};

/** Il colore del nome di una persona, dallo stile (`persone-nome`). */
function coloreNome(proprieta, altrimenti) {
  try {
    const c = S.mappa?.getPaintProperty('persone-nome', proprieta);
    return typeof c === 'string' ? c : altrimenti;
  } catch {
    return altrimenti;
  }
}

/**
 * Il segno di una persona in quota: il cerchio di `persone` (15 col bordo di
 * 3, le iniziali in bianco) e sotto il nome con l'alone, come gli strati
 * `persone-iniziali` e `persone-nome` a terra. Ancorato al centro del cerchio.
 */
function segnoPersona(p) {
  const nome = String(p.nome ?? '');
  const riempi = colore('persone', 'circle-color', p);
  const bordo = colore('persone', 'circle-stroke-color', p);
  const chiave = ['persona', S.notte, riempi, bordo, p.iniziali ?? '', nome].join('|');
  let c = teleCerchi.get(chiave);
  if (c) return c;
  const k = 2;
  const r = 15;
  const spessore = 3;
  const font = (corpo) => `700 ${corpo * k}px "Noto Sans", Roboto, "Helvetica Neue", Arial, sans-serif`;
  const misura = document.createElement('canvas').getContext('2d');
  misura.font = font(13);
  const largoNome = nome ? Math.ceil(misura.measureText(nome).width) + 8 * k : 0;
  const lato = Math.ceil((r + spessore) * 2 * k) + 4;
  const bmp = document.createElement('canvas');
  bmp.width = Math.max(lato, largoNome);
  bmp.height = lato + (nome ? 20 * k : 0);
  const g = bmp.getContext('2d');
  const cx = bmp.width / 2;
  const cy = lato / 2;
  g.beginPath();
  g.arc(cx, cy, (r + spessore / 2) * k, 0, Math.PI * 2);
  g.fillStyle = riempi;
  g.fill();
  g.lineWidth = spessore * k;
  g.strokeStyle = bordo;
  g.stroke();
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.font = font(13);
  g.fillStyle = '#FFFFFF';
  g.fillText(String(p.iniziali ?? ''), cx, cy + k);
  if (nome) {
    const y = lato + 9 * k;
    g.lineJoin = 'round';
    g.lineWidth = 4 * k;
    g.strokeStyle = coloreNome('text-halo-color', S.notte ? '#28324A' : '#FFFFFF');
    g.strokeText(nome, cx, y);
    g.fillStyle = coloreNome('text-color', S.notte ? '#E8ECF2' : '#3E434A');
    g.fillText(nome, cx, y);
  }
  // Il centro del cerchio, da sotto (come `center` degli sprite di three.js).
  c = { bmp, ratio: k, centro: 1 - cy / bmp.height, chiave };
  if (teleCerchi.size > 200) teleCerchi.clear();
  teleCerchi.set(chiave, c);
  return c;
}

/** Il colore di uno strato dello stile per un punto (i «match» sullo stato come in stile.dart). */
function colore(strato, proprieta, p) {
  let e;
  try {
    e = S.mappa?.getPaintProperty(strato, proprieta);
  } catch {
    e = null;
  }
  if (typeof e === 'string') return e;
  if (Array.isArray(e) && e[0] === 'match' && Array.isArray(e[1]) && e[1][0] === 'get') {
    const v = p[e[1][1]];
    for (let i = 2; i < e.length - 1; i += 2) if (e[i] === v) return e[i + 1];
    return e[e.length - 1];
  }
  return '#8A94A6';
}

/** Un cerchio col bordo e (se c'è) il numero, disegnato al doppio come le etichette. */
const teleCerchi = new Map();
function cerchio(r, riempi, bordo, spessore, testo = '', coloreTesto = '#FFFFFF', corpo = 13) {
  const chiave = [r, riempi, bordo, spessore, testo, coloreTesto, corpo].join('|');
  let c = teleCerchi.get(chiave);
  if (c) return c;
  const k = 2;
  const lato = Math.ceil((r + spessore) * 2 * k) + 4;
  const bmp = document.createElement('canvas');
  bmp.width = lato;
  bmp.height = lato;
  const g = bmp.getContext('2d');
  g.beginPath();
  g.arc(lato / 2, lato / 2, (r + spessore / 2) * k, 0, Math.PI * 2);
  g.fillStyle = riempi;
  g.fill();
  g.lineWidth = spessore * k;
  g.strokeStyle = bordo;
  g.stroke();
  if (testo) {
    g.font = `700 ${corpo * k}px "Noto Sans", Roboto, "Helvetica Neue", Arial, sans-serif`;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillStyle = coloreTesto;
    g.fillText(testo, lato / 2, lato / 2 + k);
  }
  c = { bmp, ratio: k, centro: 0.5, chiave };
  if (teleCerchi.size > 200) teleCerchi.clear();
  teleCerchi.set(chiave, c);
  return c;
}

/** I punti delle sorgenti che stanno in quota (chiave → quota), rifatti in [aggiornaSegni]. */
const inQuota = new Map();

/**
 * Le segnalazioni (autovelox, tutor, polizia…) troppo lontane dall'auto: non
 * si disegnano, né in quota né a terra. «Si vedono da lontano i punti per
 * autovelox, stanno piazzati in alto»: col 3D inclinato quelli a chilometri
 * finivano all'orizzonte, in cima allo schermo, grandi come quelli vicini.
 */
const lontani = new Set();
const VICINO_SEGNALAZIONI_M = 1200;

/** I dati per MapLibre senza i punti che disegna il 3D in quota. */
function sulSuolo(id, dati) {
  if (!IN_QUOTA[id] || !dati?.features) return dati;
  return { ...dati, features: dati.features.filter((f, i) => !inQuota.has(`${id}#${i}`) && !lontani.has(`${id}#${i}`)) };
}

/**
 * La quota di un punto: quella del percorso se ci sta sopra (entro 15 m),
 * altrimenti quella della strada sotto, se lì c'è una strada sola; `null`
 * se è a terra o non si sa (allora lo disegna MapLibre come sempre).
 */
function quotaDi(x, y) {
  const p = S.percorso;
  if (p?.profilo) {
    const q = p.linea.proietta(x, y, p.profilo.s0, p.profilo.s1);
    if (q.d < 15) return p.profilo.quota(q.s);
  }
  const c = indice.candidati(x, y, 0, 0, 10);
  if (!c.length) return null;
  const alte = c.filter((v) => v.h > 2.5);
  return alte.length === c.length ? Math.max(...alte.map((v) => v.h)) : null;
}

let ultimiSegni = 0;
let segniDa = null;
function aggiornaSegni(adesso) {
  const qui = doveGuardo();
  const lontano = qui && segniDa ? Math.hypot(qui[0] - segniDa[0], qui[1] - segniDa[1]) : Infinity;
  if (!S.origine || !qui || (!S.sporco.segni && lontano < 100) || adesso - ultimiSegni < 1500) return;
  ultimiSegni = adesso;
  segniDa = qui;
  S.sporco.segni = false;
  const segni = [];
  for (const [id, regola] of Object.entries(IN_QUOTA)) {
    const dati = S.sorgenti.get(id);
    if (!dati?.features) continue;
    let cambiato = false;
    dati.features.forEach((f, i) => {
      const k = `${id}#${i}`;
      const xy = f.geometry?.type === 'Point' ? f.geometry.coordinates : null;
      let z = null;
      let x = 0;
      let y = 0;
      let via = false;
      if (xy) {
        [x, y] = S.origine.daLonLat(xy[0], xy[1]);
        const d = Math.hypot(x - qui[0], y - qui[1]);
        via = id === 'gdanav-segnalazioni' && d > VICINO_SEGNALAZIONI_M;
        if (d < 3000 && !via) z = quotaDi(x, y);
      }
      if (via !== lontani.has(k)) {
        cambiato = true;
        if (via) lontani.add(k);
        else lontani.delete(k);
      }
      const pr = f.properties ?? {};
      const img = z !== null && z > 2.5 ? (regola.tela ? regola.tela(pr) : S.bitmap.get(regola.immagine(pr))) : null;
      if (img) {
        if (!inQuota.has(k)) cambiato = true;
        inQuota.set(k, z);
        const g = regola.grandezza(pr);
        // La chiave dice anche l'immagine: un punto che cambia (stato, numero) si ridisegna.
        const segno = { chiave: `${k}|${img.chiave ?? regola.immagine(pr)}`, x, y, z: z + 0.4, immagine: img.bmp, w: (img.bmp.width / img.ratio) * g, h: (img.bmp.height / img.ratio) * g };
        // Toccandolo in quota arriva all'app come lo strato di MapLibre a terra.
        segno.elemento = { type: 'Feature', geometry: f.geometry, properties: pr, layer: regola.strato(pr) };
        if (img.centro !== undefined) segno.centro = img.centro;
        if (regola.sopra) segno.sopra = true;
        segni.push(segno);
      } else if (inQuota.delete(k)) cambiato = true;
    });
    if (cambiato) scriviSorgente(id, sulSuolo(id, dati));
  }
  // I nomi che il 3D scrive al posto di MapLibre (rampe in quota, gallerie).
  const nascosti = new Set();
  for (const c of S.costruite.values()) for (const n of scena.tessere.get(c.chiave)?.dati.nascosti ?? []) nascosti.add(n);
  const elenco = [...nascosti].sort().slice(0, 300);
  const firma = elenco.join('|');
  if (firma !== S.nomiNascosti && S.mappa?.getLayer('nomi-strade')) {
    S.nomiNascosti = firma;
    S.mappa.setFilter('nomi-strade', filtroNomi(elenco));
  }
  // I nomi dei ponti e delle rampe vicine, scritti sull'impalcato; delle
  // strade con una galleria, fuori dalla galleria.
  const nomi = [];
  for (const c of S.costruite.values()) {
    const v = scena.tessere.get(c.chiave);
    for (const e of v?.dati.etichette ?? []) {
      const x = c.cx + e.x * c.scala;
      const y = c.cy + e.y * c.scala;
      const d = Math.hypot(x - qui[0], y - qui[1]);
      if (d < 1600) nomi.push({ ...e, x, y, d });
    }
  }
  nomi.sort((a, b) => a.d - b.d);
  const messi = [];
  for (const e of nomi) {
    // I nomi lunghi («A4 Svincolo Fiera Porta Est / Milano Fiorenza») si accorciano.
    const intero = e.nome || e.ref;
    const testo = intero.length > 30 ? intero.slice(0, 28).trimEnd() + '…' : intero;
    if (messi.length >= 8 || messi.some((m) => m.testo === testo && Math.hypot(m.x - e.x, m.y - e.y) < 250)) continue;
    messi.push({ ...e, testo });
    const tela = etichetta(testo, !e.nome);
    segni.push({ chiave: `nome:${testo}:${Math.round(e.x)}:${Math.round(e.y)}`, x: e.x, y: e.y, z: e.h + 1.2, immagine: tela, w: tela.width / 2, h: tela.height / 2, centro: 0.5 });
  }
  scena.impostaSegni(segni);
}

/**
 * Il segno in quota sotto il dito (in punti dello schermo), il più vicino se
 * ce n'è più d'uno; `null` se non ce n'è. Il riquadro è quello dell'immagine
 * (ancorata in basso o nel mezzo), con un margine per le dita.
 */
function segnoToccato(px, py, margine = 8) {
  const cam = S.camera3d;
  if (!cam || !scena.segni || !S.mappa) return null;
  const c = S.mappa.getCanvas();
  const W = c.clientWidth;
  const H = c.clientHeight;
  const v = new THREE.Vector3();
  let meglio = null;
  let dMeglio = Infinity;
  for (const sp of scena.segni.values()) {
    const el = sp.userData.elemento;
    if (!el || !sp.visible) continue;
    sp.getWorldPosition(v).project(cam);
    if (v.z > 1 || v.z < -1) continue;
    const sx = ((v.x + 1) / 2) * W;
    const sy = ((1 - v.y) / 2) * H;
    const w = sp.userData.w;
    const h = sp.userData.h;
    const cy = sp.center.y;
    const alto = sy - h * (1 - cy) - margine;
    const basso = sy + h * cy + margine;
    if (px < sx - w / 2 - margine || px > sx + w / 2 + margine || py < alto || py > basso) continue;
    const d = Math.hypot(px - sx, py - (alto + basso) / 2);
    if (d < dMeglio) {
      dMeglio = d;
      meglio = el;
    }
  }
  return meglio;
}

/** Il nome di un ponte, come quelli di MapLibre: scritta scura con l'alone chiaro (o un cartello per i numeri). */
const teleEtichette = new Map();
function etichetta(testo, cartello) {
  const chiave = `${S.notte}|${cartello}|${testo}`;
  let c = teleEtichette.get(chiave);
  if (c) return c;
  c = document.createElement('canvas');
  const g = c.getContext('2d');
  const font = '700 28px "Noto Sans", Roboto, "Helvetica Neue", Arial, sans-serif';
  g.font = font;
  const w = Math.ceil(g.measureText(testo).width);
  c.width = w + (cartello ? 34 : 18);
  c.height = cartello ? 46 : 40;
  g.font = font;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  if (cartello) {
    g.fillStyle = '#FFFFFF';
    g.beginPath();
    g.roundRect(1, 1, c.width - 2, c.height - 2, 10);
    g.fill();
    g.fillStyle = '#0B7A3E';
    g.beginPath();
    g.roundRect(4, 4, c.width - 8, c.height - 8, 8);
    g.fill();
    g.fillStyle = '#FFFFFF';
    g.fillText(testo, c.width / 2, c.height / 2 + 1);
  } else {
    g.lineJoin = 'round';
    g.lineWidth = 7;
    g.strokeStyle = S.notte ? '#28324A' : '#FFFFFF';
    g.strokeText(testo, c.width / 2, c.height / 2);
    g.fillStyle = S.notte ? '#E8ECF2' : '#3E434A';
    g.fillText(testo, c.width / 2, c.height / 2);
  }
  teleEtichette.set(chiave, c);
  return c;
}

// ─── L'auto e la telecamera, a ogni fotogramma ───────────────────────────

let richiesta = null;
let ultimoFotogramma = 0;

/** Riaccende i fotogrammi (se non è in pausa). */
function sveglia() {
  if (richiesta || S.pausa || !S.mappa) return;
  richiesta = requestAnimationFrame(fotogramma);
}

function fotogramma(adesso) {
  richiesta = null;
  // Col tempo delle prove (i video) i fotogrammi li chiede il collaudo.
  if (S.pausa || !S.mappa || !S.stileCaricato || S.orologioProva !== undefined) return;
  if (adesso - ultimoFotogramma < FOTOGRAMMA_MS - 2) {
    richiesta = requestAnimationFrame(fotogramma);
    return;
  }
  const dt = ultimoFotogramma ? adesso - ultimoFotogramma : 0;
  ultimoFotogramma = adesso;
  aggiornaPercorso(adesso);
  aggiornaTraffico(adesso);
  aggiornaSegni(adesso);
  const ancora = muovi(adesso, dt);
  S.anima = ancora;
  if (ancora) richiesta = requestAnimationFrame(fotogramma);
}

/** Muove auto e telecamera; dice se c'è ancora da muovere. */
function muovi(adesso, dt) {
  const m = S.mappa;
  const pos = moto.passo(S.orologioProva ?? Date.now());
  const p = S.percorso;
  if (!pos || !S.origine || (pos.s !== undefined && !p)) {
    aggiornaCielo();
    return false;
  }
  let x;
  let y;
  let z;
  let dir;
  let rottaCamera;
  if (pos.s !== undefined && p) {
    const s = Math.min(pos.s, p.linea.lunghezza);
    [x, y] = p.linea.a(s);
    const prof = p.profilo;
    // Sulla strada come la linea (vedi `spostamenti` in percorso.js).
    if (prof) {
      const [sx, sy] = prof.sposta(s);
      x += sx;
      y += sy;
    }
    const q = (v) => (prof && v >= prof.s0 && v <= prof.s1 ? prof.quota(v) : 0);
    z = q(s);
    dir = p.linea.direzione(s, 4);
    const pendenza = Math.atan2(q(s + 3) - q(s - 3), 6);
    scena.mettiAuto(x, y, z, dir, pendenza);
    // La mappa guarda un poco avanti: in curva la strada che arriva resta in vista.
    rottaCamera = 90 - (p.linea.direzione(s + 20, 26) * 180) / Math.PI;
    S.auto = { x, y, z, s };
    if (scena.mat.percorso) scena.uniformiPercorso.uInizio.value = s + 1.5;
    // Il fantasma comincia oltre il muso dell'auto (lunga nove metri, in scala).
    scena.uniformiFantasma.uInizio.value = s + 6;
    if (S.manovra && S.frecciaDa !== undefined && s + 6 > S.frecciaDa + 4) aggiornaFreccia();
  } else {
    x = pos.x;
    y = pos.y;
    dir = ((90 - pos.rotta) * Math.PI) / 180;
    // Senza percorso: la quota della strada sotto, la più vicina a quella di prima.
    const cand = indice.candidati(x, y, Math.cos(dir), Math.sin(dir), 7);
    const prima = S.auto?.z ?? 0;
    let voluta = 0;
    if (cand.length) voluta = cand.reduce((a, c) => (Math.abs(c.h - prima) < Math.abs(a - prima) ? c.h : a), cand[0].h);
    z = smorza(prima, voluta, dt, 300);
    scena.mettiAuto(x, y, z, dir, 0);
    rottaCamera = pos.rotta;
    S.auto = { x, y, z, s: null };
  }
  copertaDaUnPonte(x, y, z, dir);
  aggiornaIo();
  const [lon, lat] = S.origine.lonLat(x, y);
  const vista = VISTE[S.vista] ?? VISTE.inclinata;
  let assestata = true;
  if (S.camera.modo === 'segui') {
    const zoomVoluto = S.zoomVoluto ?? vista.zoom;
    // L'inclinazione: quella della vista, o quella chiesta (sull'auto più
    // dall'alto: «voglio vederla un po' più dall'alto»).
    const pitchVoluto = S.camera.pitch ?? vista.pitch;
    const c = (S.cam ??= { rotta: rottaCamera, zoom: zoomVoluto, quota: z, pitch: pitchVoluto });
    c.rotta = angoloVerso(c.rotta, rottaCamera, 1 - Math.exp(-dt / 400));
    c.zoom = smorza(c.zoom, zoomVoluto, dt, 1500);
    c.quota = smorza(c.quota, z, dt, 300);
    c.pitch = smorza(c.pitch, pitchVoluto, dt, 600);
    const H = m.getCanvas().clientHeight;
    const W = m.getCanvas().clientWidth;
    // Lo spazio delle schede, mai più di metà schermo: con misure sbagliate
    // (l'auto le dà in punti suoi) l'auto finiva in un angolo, lontana.
    const sopra = Math.min(H * 0.12 + S.camera.sopra * 0.8, H * 0.5);
    const sinistra = Math.min(S.camera.sinistra ?? 0, W * 0.45);
    let voluta = { center: [lon, lat], zoom: c.zoom, pitch: c.pitch, bearing: c.rotta, padding: { top: sopra, bottom: 0, left: sinistra, right: 0 } };
    const tr = S.transizione;
    if (tr) {
      tr.partenza ??= { center: m.getCenter().toArray(), zoom: m.getZoom(), pitch: m.getPitch(), bearing: m.getBearing() };
      const t = Math.min(1, (adesso - tr.da) / tr.dur);
      const e = t * t * (3 - 2 * t);
      const a = tr.partenza;
      voluta = {
        ...voluta,
        center: [a.center[0] + (lon - a.center[0]) * e, a.center[1] + (lat - a.center[1]) * e],
        zoom: a.zoom + (c.zoom - a.zoom) * e,
        pitch: a.pitch + (c.pitch - a.pitch) * e,
        bearing: angoloVerso(a.bearing, c.rotta, e),
      };
      if (t >= 1) S.transizione = null;
      assestata = false;
    }
    m.jumpTo(voluta);
    if (Math.abs(c.zoom - zoomVoluto) > 0.01 || Math.abs((((c.rotta - rottaCamera) % 360) + 540) % 360 - 180) > 0.3) assestata = false;
  } else {
    S.cam = null;
    m.triggerRepaint();
  }
  aggiornaCielo();
  return !(moto.fermo && assestata);
}

/**
 * L'auto sta in cima a tutto (anche ai cartelli di MapLibre), tranne quando
 * un ponte le passa sopra o subito dietro (fra lei e la telecamera): lì si
 * disegna con la scena, coperta davvero dal ponte, e se ne vede la sagoma.
 */
let ultimoCoperta = 0;
function copertaDaUnPonte(x, y, z, dir) {
  const ora = performance.now();
  if (ora - ultimoCoperta < 200) return;
  ultimoCoperta = ora;
  const dx = Math.cos(dir);
  const dy = Math.sin(dir);
  let coperta = false;
  for (let d = -40; d <= 6 && !coperta; d += 4) {
    for (const c of indice.candidati(x + dx * d, y + dy * d, 0, 0, 9)) {
      if (c.h > z + 3) {
        coperta = true;
        break;
      }
    }
  }
  if (coperta === S.autoCoperta || !scena.auto) return;
  S.autoCoperta = coperta;
  scena.autoCoperta = coperta;
  scena.auto.traverse((o) => o.layers.set(coperta ? 0 : 1));
}

/** Il segnaposto 2D: si vede solo da lontano (sotto lo zoom del 3D). */
let ultimoIo = 0;
function aggiornaIo(subito = false) {
  const m = S.mappa;
  if (!m || !S.stileCaricato || !S.auto || !S.origine) return;
  const ora = performance.now();
  if (!subito && (m.getZoom() >= ZOOM_3D || ora - ultimoIo < 250)) return;
  ultimoIo = ora;
  const [lon, lat] = S.origine.lonLat(S.auto.x, S.auto.y);
  const rotta = S.posizione?.rotta ?? 0;
  scriviSorgente('gdanav-io', { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [lon, lat] }, properties: { icona: S.icona, rotta } }] });
}

/** Il cielo: un gradiente dietro la mappa, con l'orizzonte dove lo vede la telecamera. */
let ultimoOrizzonte = null;
function aggiornaCielo(forza = false) {
  const m = S.mappa;
  if (!m) return;
  const H = m.getCanvas().clientHeight;
  const c = m.getCenter();
  const b = (m.getBearing() * Math.PI) / 180;
  // Un punto lontano davanti: la sua altezza sullo schermo è l'orizzonte.
  const lontano = [c.lng + (Math.sin(b) * 0.4) / Math.cos((c.lat * Math.PI) / 180), c.lat + Math.cos(b) * 0.4];
  let hy = m.getPitch() > 50 ? m.project(lontano).y : -1;
  if (!Number.isFinite(hy) || hy < 0) hy = H * 0.12;
  hy = Math.round(hy);
  if (!forza && ultimoOrizzonte !== null && Math.abs(hy - ultimoOrizzonte) < 3) return;
  ultimoOrizzonte = hy;
  const P = S.notte ? NOTTE : GIORNO;
  document.getElementById('mappa').style.background = S.notte
    ? `linear-gradient(180deg, #040915 0px, #0b1633 ${hy * 0.55}px, #283456 ${hy - 14}px, #4a4660 ${hy - 3}px, ${P.nebbia} ${hy + 4}px, ${P.nebbia} 100%)`
    : `radial-gradient(ellipse 60% 18% at 22% ${hy * 0.35}px, rgba(255,255,255,.55), rgba(255,255,255,0) 70%), radial-gradient(ellipse 45% 12% at 78% ${hy * 0.55}px, rgba(255,255,255,.45), rgba(255,255,255,0) 70%), linear-gradient(180deg, #3f86d6 0px, #79b0e6 ${hy * 0.5}px, #cfe2f2 ${hy - 8}px, ${P.nebbia} ${hy + 4}px, ${P.nebbia} 100%)`;
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) S.mappa?.stop();
  else sveglia();
});

// ─── Per le prove e per capire cosa succede ──────────────────────────────

function diagnosi() {
  const tessere = [...S.costruite.values()].map((c) => ({ chiave: c.chiave, dettaglio: c.dettaglio, triangoli: c.triangoli, visibile: scena.tessere.get(c.chiave)?.gruppo.visible ?? false, conti: c.conti }));
  return {
    pronta: window.gdanav3d.pronta(),
    stile: S.stileCaricato,
    tessere,
    triangoli: scena.triangoli,
    budget: BUDGET.triangoli,
    msDisegno: S.msDisegno,
    intervalli: S.intervalli.length,
    auto: S.auto,
    camera: S.camera.modo,
    profilo: S.percorso?.profilo ? { da: S.percorso.profilo.s0, a: S.percorso.profilo.s1, max: Math.max(...S.percorso.profilo.h) } : null,
    log: S.log.slice(-40),
  };
}

manda('caricata', { versione: 1 });
