// La mappa 3D di GdANav in guida: MapLibre GL JS per il suolo, i nomi e le
// icone (lo stile dell'app), three.js per le strade in quota, gli edifici,
// gli alberi, il percorso e l'auto. La guida la comanda l'app (Flutter) coi
// messaggi di `messaggi.js`; sopra resta il cruscotto di Flutter.

import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import * as THREE from 'three';
import codiceLavoratore from 'gdanav:lavoratore';
import { BUDGET, daDisegnare, pianoTessere } from './budget.js';
import { intervalloPerLaSonda, livelloDiCarico, rapportoPixel, Ritmo, valutaPrestazioni, valutaWebgl } from './capacita.js';
import { chiave as chiaveTessera, codaDi, daChiave, mercPerMetro, latDaMerc, lonDaMerc, marginiAiLati, zoomPerLoSpazio } from './geo.js';
import { codeOrdinate, decodifica } from './messaggi.js';
import { AggancioStrada, SOGLIA_M } from './aggancio.js';
import { angoloVerso, Moto, Raccordo, smorza, svolteDi } from './moto.js';
import { alzataDeiNastri, direzioneDisegnata, fasciaDelPercorso, IndiceSegmenti, Linea, lungoLaLinea, nastro, Origine, Profilo, profiloDi, quote, quoteSullaFascia, riempiQuote, sensiDiMarcia, spostamenti } from './percorso.js';
import { BIT_OMBRA, BIT_OMBRA_PONTE, Scena } from './scena.js';
import { dallaScorta, nellaScorta } from './scorte.js';
import { SORGENTE_OLTRE, STRATO_3D, ZOOM_3D, adattaStile, filtroNomi } from './stile3d.js';
import { tavolozza } from './tavolozza.js';
import { asfaltoDelleCorsie, corsiaDellAuto, corsieLungoIlPercorso, zoomCorsie, IndiceCorsie, preparaCorsie, riquadroCorsie, riquadroLonLat, tessereConCorsieVere } from './corsie.js';
import './gdanav3d.css';

/** Gli strati da toccare (come `stratiToccabili` in stile.dart). */
const TOCCABILI = ['persone', 'alternative-etichetta', 'alternative', 'gdanav-soste', 'gdanav-colonnine', 'gdanav-distributori', 'gdanav-vicine', 'gdanav-tutte-gruppi', 'gdanav-tutte', 'nomi-poi', 'segnalazioni', 'tappe', 'arrivo'];

/** Le viste: inclinazione e zoom di partenza (il prototipo approvato). */
const VISTE = { inclinata: { pitch: 70, zoom: 17.9 }, immersiva: { pitch: 74, zoom: 18.3 } };

/*
 * La vista «Corsie» (`opzioni.corsie`): una vista in più, sopra le altre.
 * La telecamera più bassa e più vicina dietro l'auto, con l'obiettivo più
 * largo (le corsie che corrono verso l'orizzonte, come chi guida le vede), e
 * l'auto nel terzo basso dello schermo: davanti c'è la strada da fare.
 */
const VISTA_CORSIE = { pitch: 62, zoom: 18.6 };
/** Quanti gradi più dall'alto la vista «Corsie» per ogni livello che si allontana nel pannello piccolo. */
const PITCH_PER_LO_SPAZIO = 8;
const OBIETTIVO_CORSIE_GRADI = 44;
/** La fascia della corsia: quanto è larga (m) e quanto sta sopra l'asfalto. */
// Larga meno di una corsia, che ci stia dentro con un margine: in città la
// corsia è di tre metri, e fra la riga di bordo e quella di mezzo ne restano
// 2,65; a 2,7 m (e anche a 2,3) la fascia stava sulle righe.
const FASCIA_CORSIA = { largo: 2.0, sopra: 0.3 };
/** Ogni quanti metri un punto della fascia (il profilo del «3D aumentato» ne ha uno ogni quattro). */
const PASSO_CORSIE = 2;
/** La freccia della manovra: nel «3D aumentato», e sulla fascia della vista «Corsie». */
const FRECCIA = { largo: 3.0, sopra: 0.7, punta: 1 };
const FRECCIA_CORSIA = { largo: 2.1, sopra: FASCIA_CORSIA.sopra + 0.12, punta: 0.75 };
/** Fin dove attorno a una tessera si mandano le vie con le corsie (gradi, ~200 m). */
const MARGINE_CORSIE = 0.002;

/** Al più un fotogramma ogni tanto: trenta al secondo da fermi, o col
 * telefono che fatica; sessanta andando, se il telefono ci sta dietro (lo
 * dice [Ritmo], dall'intervallo vero fra i fotogrammi). «Va a scatti»: a
 * trenta, con la telecamera che segue l'auto e i fotogrammi che non arrivano
 * sempre allo stesso passo, si vedeva. Sull'auto (`opzioni.inAuto`) sempre
 * trenta, fissi. */
const ritmo = new Ritmo();

function intervalloDeiFotogrammi() {
  // La telecamera che si muove da sé (un tasto dello zoom, l'arrivo sull'auto): fluida.
  const svelta = !!S.transizione || performance.now() < (S.zoomSubitoFino ?? 0);
  return ritmo.intervallo(moto.velocita, svelta);
}

/*
 * Fin dove davanti all'auto si fa il percorso in 3D, e da quanto dietro.
 *
 * «A un certo punto scompare quella grande, si vede una sottile, ma non è
 * nemmeno coerente con il percorso e con il traffico.» Il nastro in 3D
 * arrivava a 2600 metri dall'auto quando si rifaceva, e prima di rifarsi
 * scendeva a 900; ma la scena in 3D (strade, viadotti, case) attorno all'auto
 * può arrivare più in là. Spostando la mappa lungo la strada da fare, dentro
 * la scena, il nastro finiva e restava la linea piatta della mappa: a terra
 * sotto i viadotti, e non appoggiata sulle strade. Adesso il nastro arriva
 * fin dove c'è la scena ([finDoveCELaScena]), e la linea piatta comincia
 * dove la mappa torna piatta.
 */
const FINESTRA_AVANTI = 6500;
const FINESTRA_DIETRO = 80;
/** Davanti all'auto il nastro c'è sempre almeno per tanto, anche se la scena deve ancora arrivare. */
const AVANTI_SEMPRE = 1200;
/** Quando davanti all'auto ne resta meno di così, il tratto si rifà. */
const AVANTI_ALMENO = 700;
/*
 * Con la mappa spostata a mano, lontano dall'auto.
 *
 * «Poi all'improvviso scompare»: la scena in 3D si costruiva solo attorno
 * all'auto. Guardando più avanti lungo il percorso si usciva dalla scena:
 * niente strade (in 3D le fa la scena, e lì non c'era), e del percorso la
 * sola linea piatta e sottile. Adesso la scena si costruisce dove si guarda
 * ([doveGuardo]), e il nastro arriva fin lì ([finDoveCELaScena]).
 */
/** Più lontano di così dall'auto, col dito sulla mappa, si guarda altrove. */
const GUARDO_ALTROVE_M = 600;
/** Il nastro arriva tanto oltre il punto che si guarda. */
const AVANTI_GUARDANDO = 2500;
/** E mai più lungo di così, dall'auto. */
const NASTRO_MASSIMO = 40000;

/** In quanto tempo lo zoom arriva dove deve: scelto coi tasti, avvicinandosi da sé, allontanandosi da sé. */
const ZOOM_DEL_TASTO_MS = 220;
const ZOOM_SI_AVVICINA_MS = 2200;
const ZOOM_SI_ALLONTANA_MS = 5000;
/** Per quanto, dopo un tasto, lo zoom va svelto. */
const ZOOM_SUBITO_MS = 1500;

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
  camera: { modo: 'segui', sopra: 0, sinistra: 0, destra: 0, riquadro: null },
  pausa: false,
  /** Sull'auto c'è un'altra app (messaggio `nascosta`): non si disegna. */
  nascosta: false,
  /** La pagina è quella dello schermo dell'auto (`opzioni.inAuto`). */
  inAuto: false,
  /** Quanto può pesare la scena, dal telefono (messaggio `carico`). */
  carico: null,
  /** Sul telefono, con un'altra scena sull'auto (messaggio `leggera`): le regole dell'auto. */
  leggera: false,
  grezze: new Map(),
  /** Gli edifici di Overture dall'app, per tessera: `{dati, quando}` (dati null: non ci sono). */
  edifici: new Map(),
  edificiDallApp: false,
  attesaEdifici: null,
  costruite: new Map(),
  lavoro: null,
  numeroLavoro: 0,
  /* Cosa rifare: il profilo del percorso (e con lui tutti i nastri), solo la
   * strada fatta, solo la freccia, il traffico, i segni in quota. */
  sporco: { profilo: true, fatto: true, freccia: true, traffico: true, segni: true },
  /** Quante volte si è rifatto cosa (per [diagnosi]). */
  rifatti: { profilo: 0, fatto: 0, freccia: 0 },
  bitmap: new Map(),
  intervalli: [],
  sondato: false,
  log: [],
  /** La vista «Corsie» accesa (`opzioni.corsie`). */
  corsie: false,
  /** I messaggi `corsie` arrivati, per tessera (si sommano: un messaggio per tessera; vedi [prendiCorsie]). */
  corsieDati: new Map(),
  /** Quelli arrivati e non ancora presi (vedi [CORSIE_INSIEME_MS]). */
  corsieInArrivo: [],
  corsieAttesa: null,
  /** Le stesse, pronte (vedi `preparaCorsie`), e nei metri della scena. */
  corsiePronte: null,
  indiceCorsie: null,
  /** Le tessere che hanno le corsie vere (un messaggio `corsie` con delle vie): le altre le stimano. */
  corsieTessere: new Set(),
  /** Le corsie stimate dal lavoratore, per tessera (vedi `stima.js`): per il percorso sulla corsia. */
  stimeCorsie: new Map(),
  /** Le stesse, pronte (vedi `preparaCorsie`); `null` da rifare. */
  stimePronte: null,
  /** Le corsie giuste della manovra secondo chi fa il percorso (TomTom): `[{s, giuste}]`. */
  suggerimenti: [],
};

const scena = new Scena();
const indice = new IndiceSegmenti();
/** L'auto sulla strada fuori dal percorso (`aggancio.js`). */
const aggancio = new AggancioStrada();
const moto = new Moto();
const raccordo = new Raccordo();
/** Lo spostamento e la quota di un profilo in [s], se ci arriva (vedi [Raccordo]). */
const valoriDelProfilo = (pr, s) => (pr && s >= pr.s0 && s <= pr.s1 ? [...pr.sposta(s), pr.quota(s)] : null);

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
  if (!S.mappa && !['stile', 'opzioni', 'pausa', 'carico', 'nascosta', 'leggera', 'corsie'].includes(m.tipo)) {
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
    S.edificiDallApp = m.edifici === true;
    S.inAuto = m.inAuto === true;
    aggiornaLeggerezza();
    // La vista «Corsie»: si accende e si spegne senza rifare la pagina.
    const corsie = m.corsie === true;
    const cambiaCorsie = corsie !== S.corsie;
    S.corsie = corsie;
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
    if (cambiaCorsie) {
      // Le corsie stimate le rifanno le tessere, se la vista si riaccende.
      S.stimeCorsie.clear();
      S.stimePronte = null;
      S.indiceCorsie = null;
      scena.impostaCorsie(corsie);
      S.mappa?.setVerticalFieldOfView(corsie ? OBIETTIVO_CORSIE_GRADI : OBIETTIVO_GRADI);
      // Lo stile di sotto (i colori chiari), e le tessere con o senza corsie.
      if (S.mappa && S.stileGrezzo && !cambiaNotte) caricaStile(S.stileGrezzo);
      rifaiTessere(null, { scarta: true });
      S.sporco.profilo = true;
    }
    sveglia();
  },
  /**
   * Le vie con le corsie e i nodi da disegnare (il formato è in `corsie.js`).
   * Si sommano a quelli arrivati prima (una tessera alla volta, dal relay):
   * i raccordi fra le vie si rifanno su tutti (vedi [prendiCorsie]).
   */
  corsie(m) {
    if (!m.dati || typeof m.dati !== 'object') return;
    // Arrivano a mazzi (l'app ne chiede fino a dodici insieme): si prendono
    // tutti insieme, una volta sola (vedi [prendiCorsie]).
    S.corsieInArrivo.push(m.dati);
    if (!S.corsieAttesa) S.corsieAttesa = setTimeout(prendiCorsie, CORSIE_INSIEME_MS);
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
      // Arriva ogni tre secondi, ed è tutta la traccia del viaggio (fino a
      // seimila punti, per la mappa piatta da lontano): il 3D ne disegna solo
      // gli ultimi [FATTO_M] metri, e si rifà solo il suo nastro, non il
      // profilo del percorso coi suoi.
      const c = (m.dati?.features ?? []).find((f) => f.geometry?.type === 'LineString')?.geometry.coordinates ?? [];
      const lonlat = codaDi(c.flat(), FATTO_M + 300);
      S.fatto = lonlat.length >= 4 && S.origine ? { lonlat, linea: lineaDi(lonlat) } : null;
      S.sporco.fatto = true;
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
      // Senza ancora una posizione, la scena si conta dall'inizio del percorso.
      if (!S.posizione) riorigina(m.punti[0], m.punti[1]);
      // Un percorso nuovo (un ricalcolo, non le code aggiornate): i metri
      // ripartono da capo, e il filtro della posizione con loro.
      const quale = `${m.punti.length}:${m.punti[0]}:${m.punti[1]}:${m.punti[m.punti.length - 2]}`;
      if (quale !== S.qualePercorso) moto.nuovoPercorso();
      S.qualePercorso = quale;
      S.percorso = { lonlat: m.punti, metri: m.metri ?? null, linea: lineaDi(m.punti, m.metri), code: codeOrdinate(m.code), suStrada: m.suStrada ?? [], profilo: null, da: null, a: 0 };
      moto.svolte = svolteDi(S.percorso.linea);
    }
    S.sporco.profilo = true;
    sveglia();
  },
  manovra(m) {
    S.manovra = m.da === null ? null : [m.da, m.a];
    // Le corsie giuste per la manovra, se chi fa il percorso le sa (da
    // sinistra, come le corsie di TomTom): nella vista «Corsie» vincono
    // sulle frecce dipinte. [dove]: i metri della manovra (se no, la fine del
    // tratto della freccia, meno i suoi 45 metri dopo).
    const prima = JSON.stringify(S.suggerimenti);
    S.suggerimenti = m.da !== null && Array.isArray(m.corsie) && m.corsie.length ? [{ s: m.dove ?? m.a - 45, giuste: m.corsie.map((c) => c === true || c?.giusta === true) }] : [];
    if (S.corsie && JSON.stringify(S.suggerimenti) !== prima) S.sporco.profilo = true;
    // Solo la freccia: il profilo del percorso è quello di prima.
    S.sporco.freccia = true;
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
    let [x, y] = S.origine.daLonLat(m.lon, m.lat);
    let rotta = m.rotta;
    // Fuori dal percorso (o senza): sulla strada più vicina, se è vicina e va
    // come l'auto (`aggancio.js`), non accanto dove dice il GPS.
    if (!(S.percorso && m.metri !== null && m.metri !== undefined)) {
      // La rotta che l'app non sa ancora (`rottaIncerta`: il nord di
      // partenza, prima di essersi mossi) non sceglie il verso della strada.
      // Col percorso sotto (il viaggio pronto, non ancora partito) quel verso
      // lo dice il percorso: si parte come va lui, non all'indietro.
      let rottaNota = m.rottaIncerta === true ? null : m.rotta;
      if (rottaNota === null && S.percorso?.linea) {
        const q = S.percorso.linea.proietta(x, y);
        if (q.d < SOGLIA_M) rottaNota = (((90 - (S.percorso.linea.direzione(q.s, 8) * 180) / Math.PI) % 360) + 360) % 360;
      }
      const su = aggancio.aggancia(x, y, rottaNota, m.velocita ?? 0, indice.vicini(x, y, SOGLIA_M));
      if (su) {
        x = su.x;
        y = su.y;
        rotta = su.rotta;
      }
    } else aggancio.dimentica();
    S.posizione = rotta === m.rotta ? m : { ...m, rotta };
    if (m.zoom !== undefined) S.zoomVoluto = m.zoom;
    S.zoomScelto = m.zoomScelto ?? 0;
    // Lo zoom scelto coi tasti: subito, non piano come quello che cambia da sé.
    if (m.zoomSubito) S.zoomSubitoFino = performance.now() + ZOOM_SUBITO_MS;
    moto.posizione({
      metri: S.percorso ? m.metri : null,
      v: m.velocita,
      x,
      y,
      rotta,
      quando: m.quando,
      lettura: S.percorso && m.lettura ? m.lettura : null,
      adesso: S.orologioProva ?? Date.now(),
    });
    sveglia();
  },
  /** Gli edifici di Overture di una tessera, dall'app (risposta a «edifici?»). */
  edifici(m) {
    const k = chiaveTessera(m.z, m.x, m.y);
    let dati = null;
    if (typeof m.dati === 'string') {
      const b = atob(m.dati);
      const u = new Uint8Array(b.length);
      for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
      dati = u.buffer;
    }
    if (S.attesaEdifici?.chiave === k) return S.attesaEdifici.fatto(dati);
    // Arrivati tardi (l'app li ha letti in rete): la tessera s'era fatta con
    // quelli di sempre, o si sta facendo. Si rifà con questi.
    const prima = edificiDa(k);
    ricordaEdifici(k, dati);
    if (dati && !prima && (S.costruite.has(k) || S.lavoro?.chiave === k)) rifaiTessere([k]);
  },
  /** La velocità dell'auto dal cruscotto (Android Auto, il dongle): più volte al secondo. */
  velocita(m) {
    moto.velocitaAuto(m.ms, m.alle, S.orologioProva ?? Date.now());
    sveglia();
  },
  /** L'accelerazione di marcia dall'accelerometro del telefono: le frenate
   * e le ripartenze quando succedono, non un secondo dopo col GPS. */
  accelerazione(m) {
    moto.accelerazione(m.a, m.alle, S.orologioProva ?? Date.now(), m.ritardo ?? null);
    sveglia();
  },
  /** Un dito sullo schermo dell'auto: la mappa si sposta e smette di seguire. */
  sposta(m) {
    if (!S.mappa) return;
    const r = window.devicePixelRatio || 1;
    S.mappa.panBy([m.dx / r, m.dy / r], { duration: 0 });
    if (S.camera.modo === 'segui') S.camera.modo = 'libera';
    sveglia();
  },
  /** «Centra» sull'auto (o il tempo scaduto): si torna a seguire. */
  riprendi() {
    if (S.camera.modo !== 'libera') return;
    S.camera.modo = 'segui';
    S.transizione = { da: performance.now(), dur: 900, partenza: null };
    sveglia();
  },
  camera(m) {
    const prima = S.camera.modo;
    S.camera = { modo: m.modo, sopra: m.sopra ?? S.camera.sopra, sinistra: m.sinistra ?? 0, destra: m.destra ?? 0, pitch: m.pitch ?? null, riquadro: m.riquadro ?? null };
    if (m.modo === 'segui' && prima !== 'segui') S.transizione = { da: performance.now(), dur: 900, partenza: null };
    if (m.modo === 'panoramica' && m.riquadro && S.mappa) {
      const [s, o, n, e] = m.riquadro;
      const H = S.mappa.getCanvas().clientHeight;
      // Dall'alto il centro sta a terra (seguendo l'auto era alla sua quota).
      if (S.mappa.getCenterElevation()) S.mappa.setCenterElevation(0);
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
  /** Dal telefono, sull'auto: il calore e il telefono in uso (vedi `fpsInAuto` e `rapportoPixel`). */
  carico(m) {
    S.carico = { livello: m.livello, telefono: m.telefono === true };
    ritmo.livello = livelloDiCarico(S.carico);
    annota('carico', JSON.stringify(S.carico), ritmo.livello);
    aggiornaPixel();
    sveglia();
  },
  /**
   * Sul telefono, mentre sull'auto gira un'altra scena: due scene 3D intere
   * sulla stessa scheda grafica («va lento il telefono e il navigatore»).
   * Quella del telefono allora segue le regole dell'auto: mai sessanta
   * fotogrammi, il passo secondo la velocità, il tetto dei pixel.
   */
  leggera(m) {
    S.leggera = m.si;
    aggiornaLeggerezza();
    sveglia();
  },
  /** Sull'auto c'è un'altra app: niente fotogrammi finché GdANav non torna. */
  nascosta(m) {
    S.nascosta = m.si;
    if (m.si) {
      S.mappa?.stop();
      return;
    }
    S.mappa?.triggerRepaint();
    sveglia();
  },
};

/** Le regole dell'auto: sull'auto, e sul telefono mentre sull'auto c'è un'altra scena. */
const comeInAuto = () => S.inAuto || S.leggera;

function aggiornaLeggerezza() {
  ritmo.fisso30 = comeInAuto();
  if (ritmo.fisso30) ritmo.svelto = false;
  aggiornaPixel();
}

/**
 * La risoluzione della tela (vedi `rapportoPixel`): sul telefono quella
 * dello schermo, sull'auto con un tetto di pixel che scende col carico.
 */
function aggiornaPixel() {
  const m = S.mappa;
  if (!m) return;
  const c = m.getCanvas();
  const r = rapportoPixel({
    dpr: window.devicePixelRatio || 1,
    larghezza: c.clientWidth || window.innerWidth,
    altezza: c.clientHeight || window.innerHeight,
    inAuto: comeInAuto(),
    livello: ritmo.livello,
  });
  if (Math.abs(m.getPixelRatio() - r) < 0.001) return;
  annota('pixel', r, c.clientWidth, c.clientHeight);
  m.setPixelRatio(r);
  // Subito, non al prossimo giro: la tela rifatta è vuota, e per un
  // fotogramma si vedrebbe il cielo al posto della mappa.
  if (S.stileCaricato) m.redraw();
  else m.triggerRepaint();
}

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
    /**
     * La linea del percorso disegnata (nella vista «Corsie» il mezzo della
     * fascia), un punto `[s, lon, lat]` ogni [passo] metri: per misurare se
     * sta sull'asfalto.
     */
    lineaDisegnata(passo = 1) {
      const p = S.percorso;
      const pr = p?.profilo;
      if (!pr || p.da === null || p.da === undefined || !S.origine) return null;
      const out = [];
      for (let s = p.da; s <= p.a; s += passo) {
        const [x, y] = p.linea.a(s);
        const [sx, sy] = pr.sposta(s);
        out.push([s, ...S.origine.lonLat(x + sx, y + sy)]);
      }
      return out;
    },
    /**
     * Le quote del percorso fra [da] e [a] metri, una ogni [passo]: quella
     * scelta e quelle delle strade lì sotto (per capire un salto).
     */
    quoteDelPercorso(da, a, passo = 5) {
      const p = S.percorso;
      const pr = p?.profilo;
      if (!pr) return null;
      const out = [];
      for (let s = Math.max(da, pr.s0); s <= Math.min(a, pr.s1); s += passo) {
        const [x, y] = p.linea.a(s);
        const v = p.linea.direzione(s, 3);
        const strade = indice.candidati(x, y, Math.cos(v), Math.sin(v), 12, 12).map((c) => [Math.round(c.h * 10) / 10, Math.round(c.d * 10) / 10]);
        out.push([s, Math.round(pr.quota(s) * 10) / 10, strade]);
      }
      return out;
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
      style: adattaStile(stile, { notte: S.notte, corsie: S.corsie }),
      center: [12.5, 41.9],
      zoom: vista.zoom,
      pitch: vista.pitch,
      maxPitch: 80,
      attributionControl: false,
      pixelRatio: rapportoPixel({ dpr: window.devicePixelRatio || 1, larghezza: window.innerWidth, altezza: window.innerHeight, inAuto: comeInAuto(), livello: ritmo.livello }),
      canvasContextAttributes: { antialias: true, preserveDrawingBuffer: new URLSearchParams(location.search).has('prova') },
      fadeDuration: 150,
      // Senza terreno MapLibre rimetterebbe a zero la quota del centro a ogni
      // fotogramma: la decide la telecamera (vedi [muovi]).
      centerClampedToGround: false,
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
  mappa.setVerticalFieldOfView(S.corsie ? OBIETTIVO_CORSIE_GRADI : OBIETTIVO_GRADI);
  S.mappa = mappa;
  alPassoDellaScena(mappa);
  window.__mappa = mappa;
  window.__scena = scena;
  // Con gli edifici di Overture (dati ODbL) si dice anche da dove vengono.
  mappa.addControl(
    new maplibregl.AttributionControl({ compact: true, customAttribution: S.edificiDallApp ? '© Overture Maps Foundation, Microsoft' : undefined }),
    'top-left',
  );
  mappa.on('style.load', alloStile);
  // Cambiata la grandezza (lo schermo diviso sull'auto), cambia il tetto dei pixel.
  mappa.on('resize', aggiornaPixel);
  // L'attribuzione chiusa: si apre toccando la «i».
  mappa.once('load', () => mappa.getContainer().querySelector('.maplibregl-ctrl-attrib')?.classList.remove('maplibregl-compact-show'));
  mappa.on('webglcontextlost', () => manda('errore', { motivo: 'contesto' }));
  // Senza rete le tessere non arrivano: resta la scena che c'è, senza rumore.
  mappa.on('error', (e) => annota('mappa', e?.error?.message ?? e));
  mappa.on('sourcedata', (e) => {
    if (e.sourceId === 'openmaptiles' && e.tile) pianificaPresto();
    if ((e.sourceId === 'traffico' || e.sourceId === 'eventi') && e.tile) S.sporco.traffico = true;
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

/*
 * Sull'auto anche i disegni che MapLibre si chiede da sé vanno al passo
 * della scena.
 *
 * Il passo dei fotogrammi ([intervalloDeiFotogrammi]) vale per quelli della
 * pagina (l'auto e la telecamera che si spostano), ma MapLibre dopo ogni
 * spostamento si ridisegna anche da solo, a ogni giro dello schermo, finché
 * le tessere nuove e i nomi non hanno finito di comparire. Misurato su uno
 * schermo a sessanta giri: con la scena a trenta passi al secondo, MapLibre
 * disegnava 57 volte al secondo (e ogni disegno è un fotogramma intero,
 * mappa e scena 3D) — il «fisso a trenta» dell'auto non lo era. Qui quei
 * disegni aspettano il passo; le sfumature vanno a tempo, finiscono quando
 * devono, con meno fotogrammi.
 */
function alPassoDellaScena(mappa) {
  const chiedi = mappa.triggerRepaint.bind(mappa);
  // Quando si è chiesto l'ultimo disegno (non quando è arrivato: i passi
  // della pagina non devono slittare di un giro dello schermo ciascuno).
  let chiesto = 0;
  let attesa = null;
  const ridisegna = () => {
    chiesto = performance.now();
    chiedi();
  };
  mappa.triggerRepaint = () => {
    // Solo mentre la telecamera segue l'auto: un dito sulla mappa (sul
    // telefono) e la panoramica che vola restano fluidi.
    if (!comeInAuto() || S.camera.modo !== 'segui' || S.orologioProva !== undefined) return chiedi();
    // Il passo della pagina stessa: già al suo ritmo.
    if (nelFotogramma) return ridisegna();
    const resta = chiesto + intervalloDeiFotogrammi() - 4 - performance.now();
    if (resta <= 0) return ridisegna();
    attesa ??= setTimeout(() => {
      attesa = null;
      ridisegna();
    }, resta);
  };
}

function caricaStile(stile) {
  S.stileCaricato = false;
  // Lo stile nuovo ha il filtro dei nomi di partenza: si rimette.
  S.nomiNascosti = null;
  S.sporco.segni = true;
  S.mappa.setStyle(adattaStile(stile, { notte: S.notte, corsie: S.corsie }), { diff: false });
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
    // A ogni stile nuovo (giorno ↔ notte) le immagini si rimettono tutte: la
    // stessa si riusa, invece di farne un'altra (e un'altra trama per i segni
    // in quota) ogni volta.
    const prima = S.bitmap.get(nome);
    let bmp = prima?.png === png ? prima.bmp : null;
    if (!bmp) {
      const byte = Uint8Array.from(atob(png), (c) => c.charCodeAt(0));
      bmp = await createImageBitmap(new Blob([byte], { type: 'image/png' }));
    }
    const m = S.mappa;
    if (!m || !S.stileCaricato) return;
    if (S.bitmap.get(nome)?.bmp !== bmp) {
      S.bitmap.set(nome, { bmp, png, ratio: ratio ?? 3 });
      S.sporco.segni = true;
    }
    if (m.hasImage(nome)) m.removeImage(nome);
    m.addImage(nome, bmp, { pixelRatio: ratio ?? 3 });
  } catch (e) {
    annota('immagine', nome, e);
  }
}

/** Le trame del suolo: puntini leggeri, che il prato non sembri carta. */
function motiviSuolo(m) {
  const P = tavolozza(S.notte, S.corsie);
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
  // Nella vista «Corsie» il suolo è liscio: i suoi colori, senza puntini.
  if (S.corsie) return;
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
 * Pulisce solo i bit dello stencil delle ombre ([BIT_OMBRA], [BIT_OMBRA_PONTE]):
 * prima della scena, perché ogni punto si scurisca una volta; dopo, perché
 * MapLibre ritrovi lo stencil delle sue tessere com'era.
 */
function pulisciBitOmbra(gl) {
  gl.disable(gl.SCISSOR_TEST);
  gl.stencilMask(BIT_OMBRA | BIT_OMBRA_PONTE);
  gl.clearStencil(0);
  gl.clear(gl.STENCIL_BUFFER_BIT);
  gl.stencilMask(0xff);
  // I numeri delle tessere di MapLibre più alti usano anche quei bit: gli
  // strati dopo la scena rifanno le loro maschere invece di fidarsi.
  const pittore = S.mappa?.painter;
  if (pittore) pittore.currentStencilSource = undefined;
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

/*
 * Un renderer di three.js solo, per tutta la vita della mappa.
 *
 * A ogni stile nuovo (giorno ↔ notte) MapLibre rifà lo strato 3D e chiama il
 * suo `onAdd`, ma non `onRemove` di quello di prima: ogni volta nasceva un
 * renderer nuovo, e quello vecchio restava vivo con le sue copie nella
 * scheda grafica. E il nuovo non sapeva niente delle geometrie e dei
 * programmi già caricati dal vecchio: ricaricava tutta la scena, una seconda
 * copia. Il contesto WebGL è sempre lo stesso (quello della mappa): il
 * renderer si fa al primo `onAdd` e si riusa.
 */
function rendererDellaMappa(m, gl) {
  if (!S.renderer) {
    const r = new THREE.WebGLRenderer({ canvas: m.getCanvas(), context: gl, antialias: true });
    r.autoClear = false;
    r.outputColorSpace = THREE.SRGBColorSpace;
    S.renderer = r;
    // three.js si ricorda l'altezza della tela di adesso (per i punti luminosi).
    S.pixelDelRenderer = m.getPixelRatio();
  }
  return S.renderer;
}

function strato3d() {
  const camera = new THREE.Camera();
  camera.matrixAutoUpdate = false;
  camera.matrixWorldAutoUpdate = false;
  let ultimo = null;
  return {
    id: STRATO_3D,
    type: 'custom',
    renderingMode: '3d',
    onAdd(m, gl) {
      rendererDellaMappa(m, gl);
    },
    render(gl, args) {
      const m = S.mappa;
      const o = S.origine;
      const renderer = S.renderer;
      if (!renderer || !o) return;
      const t0 = performance.now();
      const ws = m.transform.worldSize;
      const zoom = m.getZoom();
      scena.mondo.visible = zoom >= ZOOM_3D - 0.05;
      scena.uAlza.value = alzataDeiNastri(zoom);
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
      // I bagliori dei lampioni sono punti, grandi in pixel secondo l'altezza
      // della tela che three.js ha visto nascendo: se poi la risoluzione
      // cambia (il carico sull'auto), restano grandi uguali sullo schermo.
      if (scena.mat.bagliore) scena.mat.bagliore.size = (9 * ppm * m.getPixelRatio()) / (S.pixelDelRenderer || m.getPixelRatio());
      scena.scalaSegni(Pm.elements[5], m.getCanvas().clientHeight);
      // La camera di three.js con le matrici di questo fotogramma, per sfoltire i nomi.
      const occupati = [];
      // Dov'è l'auto sullo schermo: lì gli edifici davanti a lei si fanno trasparenti.
      const ue = scena.uniformiEdifici;
      ue.uSchermo.value.set(gl.drawingBufferWidth, gl.drawingBufferHeight);
      if (S.auto) {
        const vs = new THREE.Vector3(S.auto.x, S.auto.y, S.auto.z + 1.2).project(camera);
        ue.uAutoSchermo.value.set(vs.x, vs.y, vs.z);
        // Quanto è grande l'auto sullo schermo: tre metri e mezzo di lato (la
        // freccia della vista «Corsie» è larga quasi cinque), nella misura di
        // `uAutoSchermo` (l'altezza dello schermo vale due).
        const destra = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 0).normalize().multiplyScalar(3.5);
        const vd = new THREE.Vector3(S.auto.x + destra.x, S.auto.y + destra.y, S.auto.z + 1.2 + destra.z).project(camera);
        const aspetto = gl.drawingBufferWidth / Math.max(1, gl.drawingBufferHeight);
        scena.uniformiTaglio.uRaggioAuto.value = Math.min(0.5, Math.max(0.03, Math.hypot((vd.x - vs.x) * aspetto, vd.y - vs.y)));
      } else ue.uAutoSchermo.value.set(0, -2, -1);
      // Le strade e i ponti sopra l'auto, fra lei e la telecamera: in trasparenza (vedi `tagliaSopra`).
      if (S.auto) scena.uniformiTaglio.uAutoTaglio.value.set(S.auto.x, S.auto.y, S.auto.z);
      else scena.uniformiTaglio.uAutoTaglio.value.set(0, 0, 1e9);
      scena.uniformiTaglio.uOcchioTaglio.value.setFromMatrixPosition(camera.matrixWorld);
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
      // Trenta o sessanta: dall'intervallo vero fra questo fotogramma e il
      // precedente, mentre la guida muove la mappa e non appena arrivata una tessera.
      ritmo.disegnato(ora, intervalloDeiFotogrammi(), !!S.anima && ora - (S.ultimaTessera ?? 0) > 1500);
      // La sonda: gli intervalli fra i fotogrammi mentre la mappa si muove.
      // Appena arrivata una tessera la GPU riceve le geometrie: quei
      // fotogrammi lenti non dicono quanto va il telefono.
      if (ultimo !== null && S.anima && !S.sondato && ora - (S.ultimaTessera ?? 0) > 1500) {
        S.intervalli.push(intervalloPerLaSonda(ora - ultimo, intervalloDeiFotogrammi()));
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

/**
 * Il punto attorno a cui si costruisce la scena, nei metri della scena: dove
 * sta l'auto, finché la si segue (o la si guarda da vicino); il centro della
 * mappa quando la si è spostata a mano più in là, o senza auto.
 */
function doveGuardo() {
  const auto = S.auto ? [S.auto.x, S.auto.y] : null;
  if (!S.mappa || !S.origine) return auto;
  if (auto && S.camera.modo === 'segui') return auto;
  const c = S.mappa.getCenter();
  const centro = S.origine.daLonLat(c.lng, c.lat);
  if (auto && Math.hypot(centro[0] - auto[0], centro[1] - auto[1]) < GUARDO_ALTROVE_M) return auto;
  return centro;
}

/**
 * Dove si guarda lungo il percorso [p], in metri, con la mappa spostata a
 * mano lontano dall'auto; `null` se si segue l'auto o si guarda altrove.
 */
function fuocoSulPercorso(p) {
  if (!p?.linea) return null;
  // Senza l'auto («GPS assente») si guarda sempre dove sta la mappa: prima il
  // nastro sulle strade arrivava solo ai primi chilometri, e più in là il
  // percorso era la linea piatta della mappa, fuori dalle strade e sotto i
  // viadotti.
  if (S.auto && S.camera.modo === 'segui') return null;
  const qui = doveGuardo();
  if (!qui || (S.auto && qui[0] === S.auto.x && qui[1] === S.auto.y)) return null;
  const q = p.linea.proietta(qui[0], qui[1]);
  return q.d < 1500 ? q.s : null;
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
  if (!S.mappa || !S.stileCaricato || S.pausa || S.nascosta) return;
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
    if (S.stimeCorsie.delete(k)) S.stimePronte = null;
    S.sporco.profilo = true;
  }
  const disegno = daDisegnare(S.costruite, qui[0], qui[1], BUDGET, S.disegnate);
  // Cambiate le tessere che si disegnano, cambia fin dove arriva il nastro
  // del percorso (vedi `finDoveCELaScena`).
  const prima = S.disegnate ?? new Set();
  if (disegno.si.size !== prima.size || [...disegno.si].some((k) => !prima.has(k))) S.sporco.profilo = true;
  // E cambia se, con la mappa spostata a mano, si guarda un altro tratto.
  const fuoco = fuocoSulPercorso(S.percorso);
  const fuocoDiPrima = S.percorso?.fuoco ?? null;
  if ((fuoco === null) !== (fuocoDiPrima === null) || (fuoco !== null && Math.abs(fuoco - fuocoDiPrima) > 300)) {
    S.sporco.profilo = true;
    S.mappa.triggerRepaint();
  }
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

/** Più lontano di così dall'origine della scena, la si sposta (vedi [riorigina]). */
const RIORIGINA_OLTRE_M = 40000;

function vicineDi(k) {
  const { z, x, y } = daChiave(k);
  const out = [];
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) if (dx || dy) out.push(chiaveTessera(z, x + dx, y + dy));
  return out;
}

/* Gli edifici veri, da Overture.
 *
 * «Lungo il percorso voglio vedere le cose reali.» Gli edifici delle tessere
 * di OpenFreeMap sono quelli di OpenStreetMap, e in tanti paesi non ci sono.
 * L'app ha, per la zona, quelli di Overture (OpenStreetMap più quelli che
 * Microsoft ha ricavato dalle foto dal satellite, con l'altezza), in un
 * pacchetto sul telefono o, finché non c'è, letti in rete una tessera alla
 * volta: prima di costruire una tessera li si chiede, e se arrivano prendono
 * il posto di quelli di sempre. Si aspetta poco: se non arrivano in tempo la
 * tessera si fa con quelli di sempre, e quando arrivano (dalla rete, in auto,
 * ci vuole anche qualche secondo) la si rifà con loro. La risposta «niente»
 * si richiede dopo un minuto (il pacchetto intanto può essere arrivato). */
const ATTESA_EDIFICI_MS = 1500;
const RIPROVA_EDIFICI_MS = 60000;
const EDIFICI_TENUTI = 48;

function ricordaEdifici(k, dati) {
  S.edifici.delete(k);
  S.edifici.set(k, { dati, quando: performance.now() });
  while (S.edifici.size > EDIFICI_TENUTI) S.edifici.delete(S.edifici.keys().next().value);
}

function edificiDa(k) {
  const e = S.edifici.get(k);
  if (!e) return undefined;
  if (e.dati === null && performance.now() - e.quando > RIPROVA_EDIFICI_MS) return undefined;
  return e.dati;
}

function chiedi(k, dettaglio) {
  if (S.edificiDallApp && edificiDa(k) === undefined) {
    const { z, x, y } = daChiave(k);
    // Fermi come un lavoro in corso: la pianificazione aspetta questa tessera.
    S.lavoro = { id: 0, chiave: k, dettaglio, vicine: new Set(), da: performance.now() };
    const fatto = (dati) => {
      if (S.attesaEdifici?.chiave !== k) return;
      clearTimeout(S.attesaEdifici.timer);
      S.attesaEdifici = null;
      ricordaEdifici(k, dati);
      S.lavoro = null;
      chiedi(k, dettaglio);
    };
    S.attesaEdifici = { chiave: k, fatto, timer: setTimeout(() => fatto(null), ATTESA_EDIFICI_MS) };
    manda('edifici?', { z, x, y });
    return;
  }
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
  const e = S.edificiDallApp ? edificiDa(k) : null;
  const edifici = e ? e.slice(0) : null;
  const trasferiti = Object.values(tessere).map((t) => t.dati);
  if (edifici) trasferiti.push(edifici);
  // Nella vista «Corsie», senza le corsie vere della tessera le stima il lavoratore (vedi `stima.js`).
  const stima = S.corsie && !S.corsieTessere.has(k);
  lavoratore.postMessage({ id, z, x, y, tessere, dettaglio, edifici, corsie: S.corsie && !stima ? corsiePerTessera(z, x, y) : null, vistaCorsie: S.corsie, stimaCorsie: stima }, trasferiti);
}

/*
 * Le corsie vere, dal relay: un messaggio per tessera, che l'app manda
 * appena arriva (fino a dodici insieme, e una nuova ogni tanto, andando).
 *
 * «Va a scatti, non è fluido.» A ogni messaggio la pagina rifaceva tutto:
 * le vie pronte di tutte le tessere arrivate dall'inizio del viaggio (mai
 * buttate), e tutte le tessere costruite, togliendo al lavoratore quella che
 * stava facendo. Peggio: la risposta del lavoro tolto, arrivando, toglieva a
 * sua volta quello nuovo e ne chiedeva un altro, e così via per sempre — il
 * lavoratore sempre al lavoro sulla stessa tessera, che non arrivava mai
 * (né le corsie vere). Adesso i messaggi arrivati insieme si prendono una
 * volta, si tengono solo le tessere vicine ([CORSIE_TENUTE]), si rifanno solo
 * le tessere costruite che le nuove vie toccano, e il lavoro in corso finisce.
 */
const CORSIE_INSIEME_MS = 150;
const CORSIE_TENUTE = 36;

function prendiCorsie() {
  S.corsieAttesa = null;
  const nuovi = S.corsieInArrivo.splice(0);
  if (!nuovi.length) return;
  let senzaTessera = 0;
  for (const d of nuovi) {
    const k = Number.isInteger(d.x) && Number.isInteger(d.y) ? chiaveTessera(d.z ?? 14, d.x, d.y) : `altro/${S.corsieDati.size}/${senzaTessera++}`;
    S.corsieDati.delete(k);
    S.corsieDati.set(k, d);
    // La tessera ha le corsie vere: non le stima più (una arrivata vuota sì).
    for (const t of tessereConCorsieVere(d)) {
      S.corsieTessere.add(t);
      if (S.stimeCorsie.delete(t)) S.stimePronte = null;
    }
  }
  // Le più lontane dall'auto si lasciano (le tessere arrivate prima, se non si sa dove si è).
  if (S.corsieDati.size > CORSIE_TENUTE) {
    const qui = S.posizione ? [S.posizione.lon, S.posizione.lat] : null;
    const lontane = [...S.corsieDati.keys()]
      .map((k, i) => ({ k, d: qui && /^\d+\/\d+\/\d+$/.test(k) ? distanzaDaTessera(qui, k) : -i }))
      .sort((a, b) => b.d - a.d);
    // Le loro tessere, se ci si torna, le stimano (l'app non le rimanda).
    for (const { k } of lontane.slice(0, S.corsieDati.size - CORSIE_TENUTE)) {
      for (const t of tessereConCorsieVere(S.corsieDati.get(k))) S.corsieTessere.delete(t);
      S.corsieDati.delete(k);
    }
  }
  const strade = new Map();
  const nodi = new Map();
  const alberi = new Map();
  const filari = new Map();
  for (const d of S.corsieDati.values()) {
    for (const st of d.strade ?? []) strade.set(st.id, st);
    for (const n of d.nodi ?? []) nodi.set(n.id, n);
    for (const a of d.alberi ?? []) alberi.set(`${a[0]},${a[1]}`, a);
    for (const f of d.filari ?? []) filari.set(f.id ?? f.g.join(), f);
  }
  S.corsiePronte = preparaCorsie({ strade: [...strade.values()], nodi: [...nodi.values()], alberi: [...alberi.values()], filari: [...filari.values()] });
  for (const v of [...S.corsiePronte.strade, ...S.corsiePronte.altre]) v.riquadro = riquadroLonLat(v.ll);
  indicizzaCorsie();
  if (S.corsie) {
    // Le tessere costruite che le vie nuove toccano (coi raccordi delle
    // vicine), e quella che il lavoratore sta facendo, se le tocca.
    const r = nuovi.map(riquadroCorsie).filter(Boolean);
    const chiavi = new Set(S.costruite.keys());
    if (S.lavoro?.chiave) chiavi.add(S.lavoro.chiave);
    rifaiTessere([...chiavi].filter((k) => r.some((q) => toccaTessera(q, k, MARGINE_CORSIE))));
  }
  S.sporco.profilo = true;
  sveglia();
}

/** Quanto è lontano [lonlat] dal mezzo della tessera [k] (gradi, alla buona: per ordinare). */
function distanzaDaTessera([lon, lat], k) {
  const { z, x, y } = daChiave(k);
  const n = 2 ** z;
  const c = [lonDaMerc((x + 0.5) / n), latDaMerc((y + 0.5) / n)];
  return Math.hypot((c[0] - lon) * Math.cos((lat * Math.PI) / 180), c[1] - lat);
}

/** Se la tessera [k] (coi [margine] gradi attorno) tocca il riquadro [q] `[o, s, e, n]`. */
function toccaTessera(q, k, margine) {
  const { z, x, y } = daChiave(k);
  const n = 2 ** z;
  const o = lonDaMerc(x / n) - margine;
  const e = lonDaMerc((x + 1) / n) + margine;
  const nord = latDaMerc(y / n) + margine;
  const sud = latDaMerc((y + 1) / n) - margine;
  return q[2] >= o && q[0] <= e && q[3] >= sud && q[1] <= nord;
}

/** Le vie con le corsie (e i nodi) attorno alla tessera z/x/y, per il lavoratore. */
function corsiePerTessera(z, x, y) {
  const c = S.corsiePronte;
  if (!c?.strade.length) return null;
  const n = 2 ** z;
  const o = lonDaMerc(x / n) - MARGINE_CORSIE;
  const e = lonDaMerc((x + 1) / n) + MARGINE_CORSIE;
  const nord = latDaMerc(y / n) + MARGINE_CORSIE;
  const sud = latDaMerc((y + 1) / n) - MARGINE_CORSIE;
  const tocca = (v) => v.riquadro[2] >= o && v.riquadro[0] <= e && v.riquadro[3] >= sud && v.riquadro[1] <= nord;
  const strade = c.strade.filter(tocca).map(({ xy, sxy, riquadro, ...v }) => v);
  const altre = (c.altre ?? []).filter(tocca).map(({ riquadro, ...v }) => v);
  if (!strade.length && !c.alberi.length) return null;
  const dentro = (lon, lat) => lon >= o && lon <= e && lat >= sud && lat <= nord;
  const nodi = c.nodi.filter((q) => dentro(q.g[0], q.g[1]));
  const alberi = c.alberi.filter((a) => dentro(a[0], a[1]));
  const filari = c.filari.filter((f) => {
    for (let i = 0; i < f.g.length; i += 2) if (dentro(f.g[i], f.g[i + 1])) return true;
    return false;
  });
  return { strade, nodi, alberi, filari, altre };
}

/**
 * Le vie con le corsie nei metri della scena, per il percorso (vedi
 * `corsieLungoIlPercorso`): le vere, e nella vista «Corsie» quelle stimate
 * delle tessere che non le hanno vere.
 */
function indicizzaCorsie() {
  const c = S.corsiePronte;
  const stimate = S.corsie ? corsieStimatePronte() : null;
  if ((!c && !stimate) || !S.origine) {
    S.indiceCorsie = null;
    return;
  }
  const strade = [...(c?.strade ?? []), ...(stimate?.strade ?? [])];
  for (const v of strade) {
    v.xy = [];
    for (let i = 0; i < v.llVia.length; i += 2) v.xy.push(S.origine.daLonLat(v.llVia[i], v.llVia[i + 1]));
  }
  S.indiceCorsie = new IndiceCorsie(strade);
}

/** Le corsie stimate delle tessere senza quelle vere, pronte; `null` se non ce ne sono. */
function corsieStimatePronte() {
  if (!S.stimePronte) {
    const strade = [];
    for (const [k, ss] of S.stimeCorsie) if (!S.corsieTessere.has(k)) strade.push(...ss);
    if (!strade.length) return null;
    S.stimePronte = preparaCorsie({ v: 1, strade });
  }
  return S.stimePronte;
}

/**
 * Le tessere [chiavi] da rifare (tutte, senza: la vista «Corsie» accesa o
 * spenta; quelle che toccano le corsie arrivate): si tengono finché le nuove
 * non arrivano, e rifatte prendono il loro posto. Quella che il lavoratore
 * sta facendo finisce lo stesso (vedi [prendiCorsie]): arrivata si rifà
 * ancora, o con [scarta] (la vista cambiata: è fatta per l'altra) si butta.
 */
function rifaiTessere(chiavi = null, { scarta = false } = {}) {
  const quali = chiavi ?? [...S.costruite.keys()];
  for (const k of quali) {
    const c = S.costruite.get(k);
    if (c) c.rifare = true;
  }
  const l = S.lavoro;
  if (l && (chiavi === null || quali.includes(l.chiave))) l.stantio = scarta ? 'scarta' : 'rifai';
  pianificaPresto();
}

function allaTessera({ id, tessera, errore, stimate }) {
  const lavoro = S.lavoro;
  // La risposta di un lavoro che non è quello in corso (non dovrebbe più
  // capitare): quello in corso resta, e la sua risposta arriverà.
  if (lavoro && lavoro.id !== id) return;
  S.lavoro = null;
  if (!lavoro || lavoro.stantio === 'scarta') return pianificaPresto();
  if (errore) {
    annota('tessera', lavoro.chiave, errore);
    // Non si riprova subito: si segna come fatta, vuota, ridotta.
    S.costruite.set(lavoro.chiave, { chiave: lavoro.chiave, ...postoTessera(lavoro.chiave), dettaglio: 'pieno', triangoli: 0, vicine: new Set(vicineDi(lavoro.chiave)) });
    return pianificaPresto();
  }
  const posto = postoTessera(tessera.chiave);
  // Le corsie stimate della tessera (o niente, con quelle vere): il percorso le usa.
  const cambiate = S.stimeCorsie.delete(tessera.chiave) || stimate?.length > 0;
  if (stimate?.length) S.stimeCorsie.set(tessera.chiave, stimate);
  if (cambiate) {
    S.stimePronte = null;
    S.indiceCorsie = null;
  }
  scena.aggiungiTessera(tessera, posto.cx, posto.cy, posto.scala);
  indice.aggiungi(tessera.chiave, tessera.segmenti, posto.cx, posto.cy, posto.scala);
  S.costruite.set(tessera.chiave, {
    chiave: tessera.chiave,
    ...posto,
    dettaglio: tessera.dettaglio,
    triangoli: tessera.conti.triangoli,
    vicine: lavoro.vicine,
    conti: tessera.conti,
    // Arrivata mentre cambiava quello che le serve (le corsie): si rifà.
    rifare: lavoro.stantio === 'rifai',
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

/**
 * Lontani dall'origine i numeri perdono precisione: si riparte da qui.
 *
 * Conta quanto è lontano il punto [lon, lat], non dove sta l'auto disegnata:
 * l'origine nasce al centro della mappa appena aperta (che può essere a
 * centinaia di chilometri), e aspettando l'auto — che si disegna dopo la
 * prima posizione — fino alla seconda posizione tutta la scena restava
 * contata da là.
 */
function riorigina(lon, lat) {
  if (!S.origine) return;
  const [dx, dy] = S.origine.daLonLat(lon, lat);
  if (Math.hypot(dx, dy) < RIORIGINA_OLTRE_M) return;
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
  S.indiceCorsie = null;
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
  const lungo = p?.linea.lunghezza ?? 0;
  const finoA = p?.a ?? 0;
  // Fuori dal tratto fatto: dietro il suo inizio, o con troppo poco davanti
  // (se il percorso continua oltre).
  const fuori = p && p.da !== null && s !== null && (s < p.da || (finoA < lungo - 1 && finoA - s < AVANTI_ALMENO));
  if ((!S.sporco.profilo && !fuori) || (adesso - ultimoProfilo < 1200 && !fuori && p?.profilo)) {
    // Il profilo resta quello di prima: si rifà solo quello che è cambiato.
    // La strada fatta arriva ogni tre secondi, e rifare per lei il profilo e
    // i nastri di sei chilometri e mezzo di percorso costava ogni volta.
    if (S.sporco.fatto) aggiornaFatto();
    if (S.sporco.freccia) aggiornaFreccia();
    return;
  }
  ultimoProfilo = adesso;
  S.sporco.profilo = false;
  S.rifatti.profilo++;
  if (!p || p.linea.lunghezza < 2) {
    for (const n of ['percorso', 'alone', 'freccia']) scena.impostaNastro(n, null);
    scena.impostaPunta(null);
    scriviOltre(null, 0);
  } else {
    const da = Math.max(0, (s ?? 0) - FINESTRA_DIETRO);
    p.fuoco = fuocoSulPercorso(p);
    const a = finDoveCELaScena(p, da, p.fuoco);
    scriviOltre(p, a);
    p.da = da;
    p.a = a;
    // Dove sta l'auto la quota si sa già (dal profilo di prima): chi è sul
    // viadotto ci resta, anche con una strada più vicina sotto.
    const qui = s !== null && p.profilo ? p.profilo.quotaVera(s) : null;
    p.profilo = profiloDi(p.linea, da, a, indice, 4, qui === null ? null : { s, h: qui }, p.suStrada);
    S.sporco.segni = true;
    if (S.corsie && (S.corsiePronte || S.stimeCorsie.size)) {
      // La vista «Corsie»: il percorso (e l'auto con lui) sulla corsia da
      // tenere, una fascia verde trasparente invece della linea blu.
      sullaCorsia(p);
      scena.impostaNastro('alone', null);
      scena.impostaNastro('percorso', nastro(p.linea, p.profilo, da, a, FASCIA_CORSIA.largo, FASCIA_CORSIA.sopra, { code: p.code }), 'percorsoCorsia', 5);
    } else {
      scena.impostaNastro('alone', nastro(p.linea, p.profilo, da, a, 15, 0.55), 'alone', 4);
      scena.impostaNastro('percorso', nastro(p.linea, p.profilo, da, a, 4.6, 0.62, { code: p.code }), 'percorso', 5);
    }
    aggiornaFreccia();
  }
  // Con le tessere cambiate cambiano le quote anche della strada fatta.
  aggiornaFatto();
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
 * Il percorso [p] sulla corsia giusta: allo spostamento che lo mette sulla
 * strada (il profilo) si aggiunge quello di lato fino al mezzo della corsia
 * (vedi `corsieLungoIlPercorso`), e alle svolte la curva da una corsia
 * all'altra (vedi `fasciaSullaCorsia`). Lo seguono la fascia e l'auto. Il
 * profilo si fa più fitto ([PASSO_CORSIE]): le curve sono di pochi metri.
 */
function sullaCorsia(p) {
  if (!S.indiceCorsie) indicizzaCorsie();
  if (!S.indiceCorsie || !p.profilo?.dx) return;
  const pr = (p.profilo = p.profilo.piuFitto(PASSO_CORSIE));
  const n = pr.dx.length;
  const linea = [];
  const punti = [];
  for (let k = 0; k < n; k++) {
    const [x, y] = p.linea.a(pr.s0 + k * pr.passo);
    linea.push([x, y]);
    punti.push([x + pr.dx[k], y + pr.dy[k]]);
  }
  const r = corsieLungoIlPercorso(punti, S.indiceCorsie, { passo: pr.passo, s0: pr.s0, suggerimenti: S.suggerimenti });
  const fascia = fasciaDelPercorso(linea, punti, r, pr.h, (x, y, h) => [...indice.asfaltoVicino(x, y, h), ...asfaltoDelleCorsie(S.indiceCorsie, x, y)], pr.passo);
  for (let k = 0; k < n; k++) {
    pr.dx[k] = fascia[k][0] - linea[k][0];
    pr.dy[k] = fascia[k][1] - linea[k][1];
  }
  quoteSullaFascia(pr, punti, fascia, indice, r.vie, S.indiceCorsie.strade);
  pr.ancora(p.linea);
  p.manovreCorsie = r.manovre.map((m) => ({ s: m.s, dir: m.dir }));
}

/** La strada già fatta: gli ultimi [FATTO_M] metri, all'altezza giusta. */
function aggiornaFatto() {
  S.sporco.fatto = false;
  S.rifatti.fatto++;
  const f = S.fatto;
  // Nella vista «Corsie» la strada fatta non si disegna: conta quella da fare.
  if (f && f.linea.lunghezza > 2 && !S.corsie) {
    const a = f.linea.lunghezza;
    const da = Math.max(0, a - FATTO_M);
    scena.impostaNastro('fatto', nastro(f.linea, profiloDi(f.linea, da, a, indice), da, a, 3.6, 0.5), 'fatto', 3);
  } else scena.impostaNastro('fatto', null);
}

/**
 * Fin dove, lungo il percorso [p] da [da] metri, c'è la scena in 3D: l'ultimo
 * punto dentro una tessera che si sta disegnando, al più [FINESTRA_AVANTI]
 * più avanti. Un buco corto (una tessera che deve ancora arrivare) non ferma;
 * e davanti all'auto il nastro c'è comunque per [AVANTI_SEMPRE].
 *
 * [fuoco]: i metri del punto che si guarda con la mappa spostata a mano
 * ([fuocoSulPercorso]). La scena lì è un'isola, staccata da quella attorno
 * all'auto: il nastro arriva fino a lei e [AVANTI_GUARDANDO] oltre, anche
 * attraverso il tratto in mezzo dove la scena non c'è.
 */
function finDoveCELaScena(p, da, fuoco = null) {
  const lungo = p.linea.lunghezza;
  const guardando = fuoco !== null && fuoco > da;
  const massimo = Math.min(lungo, guardando ? Math.min(da + NASTRO_MASSIMO, Math.max(da + FINESTRA_AVANTI, fuoco + AVANTI_GUARDANDO)) : da + FINESTRA_AVANTI);
  const minimo = Math.min(lungo, da + AVANTI_SEMPRE);
  const quadri = [...(S.disegnate ?? [])].map((k) => S.costruite.get(k)).filter(Boolean);
  if (!quadri.length) return minimo;
  const dentro = (x, y) => quadri.some((c) => Math.abs(x - c.cx) <= c.lato / 2 + 30 && Math.abs(y - c.cy) <= c.lato / 2 + 30);
  let fine = minimo;
  let fuoriDa = null;
  for (let v = da; v <= massimo; v += 40) {
    const [x, y] = p.linea.a(v);
    if (dentro(x, y)) {
      fine = Math.max(fine, v + 40);
      fuoriDa = null;
    } else {
      fuoriDa ??= v;
      // Prima del punto che si guarda un buco non ferma: oltre c'è la sua scena.
      if (v - fuoriDa > 400 && v > minimo && !(guardando && v < fuoco)) break;
    }
  }
  return Math.min(massimo, fine);
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
  S.sporco.freccia = false;
  S.rifatti.freccia++;
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
  /* Nella vista «Corsie» la freccia sta sopra la fascia verde, sulla sua
   * corsia (il profilo è già spostato lì, vedi [sullaCorsia]), più stretta.
   * Prima lì non c'era: «oltre agli incroci e svincoli mancano le frecce sul
   * percorso». */
  const f = S.corsie ? FRECCIA_CORSIA : FRECCIA;
  scena.impostaNastro('freccia', nastro(p.linea, p.profilo, inizio, fine, f.largo, f.sopra, { passo: 1.5 }), 'freccia', 6);
  const [x, y] = p.linea.a(fine);
  const [sx, sy] = p.profilo.sposta(fine);
  // La punta guarda come il nastro che chiude, non come la linea di TomTom
  // sotto: dove la linea si sposta di più (alla rotonda) erano due versi.
  scena.impostaPunta([x + sx, y + sy, p.profilo.quota(fine) + f.sopra + 0.02, direzioneDisegnata(p.linea, p.profilo, fine)], f.punta);
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
  // I tratti chiusi e coi lavori (gli eventi di TomTom): la mappa piatta li
  // disegna sotto la strada 3D, dove non si vedono. Qui, come le code, con
  // un colore loro, a tratti col bianco: bordeaux la chiusura (4), arancio i
  // lavori (5) — vedi FRAMMENTO_CODA in scena.js.
  if (S.mappa.getSource('eventi')) {
    try {
      for (const f of S.mappa.querySourceFeatures('eventi', { sourceLayer: 'Traffic incidents flow' })) {
        const tipo = +(f.properties?.icon_category ?? 0);
        if (tipo === 8 || tipo === 9) elementi.push({ ...f, geometry: f.geometry, properties: { ...f.properties, evento: tipo } });
      }
    } catch {}
  }
  const passo = 5;
  const parti = [];
  const viste = new Set();
  for (const f of elementi) {
    const p = f.properties ?? {};
    const evento = p.evento ?? 0;
    const lento = evento ? 0 : +(p.traffic_level ?? p.trafficLevel ?? 1);
    if (!evento && !(lento < 0.6)) continue;
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
      const punti = [];
      for (let s = 0; s <= L; s += passo) punti.push(linea.a(s).slice(0, 2));
      // Lungo il percorso il traffico lo dice già lui, coi suoi colori: in
      // 3D, e oltre con la linea piatta (che porta gli stessi colori). Un
      // nastro del traffico lì sopra, in quota e appoggiato alle strade,
      // stava accanto alla linea piatta: «non è coerente col traffico».
      const pr = S.percorso;
      if (pr?.linea && lungoLaLinea(pr.linea, punti, pr.profilo?.s0 ?? 0, (pr.profilo?.s1 ?? Infinity) + 8000)) continue;
      // La geometria del traffico è di chi lo fornisce, non della mappa: ci si
      // appoggia sulle strade come il percorso.
      const grezze = quote(punti, indice);
      const [sx, sy] = spostamenti(grezze.dx, grezze.dy, punti, passo);
      parti.push({ linea, L, punti, grezze, sx, sy, lento, evento });
    }
  }
  // I due sensi di una strada, ognuno nella sua metà (vedi [sensiDiMarcia]):
  // a destra del verso di marcia, dove sono le auto di quel senso.
  const code = parti.filter((p) => !p.evento);
  const lati = sensiDiMarcia(code.map(({ punti, sx, sy }) => punti.map(([x, y], k) => [x + sx[k], y + sy[k]])));
  const destra = parti.map((p) => (p.evento ? 0 : lati[code.indexOf(p)]));
  const nastri = parti.map(({ linea, L, punti, grezze, sx, sy, lento, evento }, i) => {
    const d = destra[i];
    if (d) {
      for (let k = 0; k < punti.length; k++) {
        const a = punti[Math.max(0, k - 1)];
        const b = punti[Math.min(punti.length - 1, k + 1)];
        const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
        sx[k] += ((b[1] - a[1]) / l) * d;
        sy[k] -= ((b[0] - a[0]) / l) * d;
      }
    }
    const prof = new Profilo(0, passo, riempiQuote(grezze), null, sx, sy);
    // Coi due sensi la strada si divide: ogni nastro sta nella sua metà.
    const livello = evento === 8 ? 4 : evento === 9 ? 5 : lento < 0.3 ? 2 : 1;
    return nastro(linea, prof, 0, L, d ? 1.7 : evento ? 2.8 : 2.4, 0.34, { passo, code: [[0, L + 1, livello]] });
  });
  scena.impostaNastro('traffico', unisciNastri(nastri), 'traffico', 3);
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
  let c = dallaScorta(teleCerchi, chiave);
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
  nellaScorta(teleCerchi, chiave, c, TETTO_CERCHI);
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
/** Quante tele di cerchi e di nomi si tengono pronte (le meno usate di recente se ne vanno). */
const TETTO_CERCHI = 200;
const TETTO_ETICHETTE = 120;
function cerchio(r, riempi, bordo, spessore, testo = '', coloreTesto = '#FFFFFF', corpo = 13) {
  const chiave = [r, riempi, bordo, spessore, testo, coloreTesto, corpo].join('|');
  let c = dallaScorta(teleCerchi, chiave);
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
  nellaScorta(teleCerchi, chiave, c, TETTO_CERCHI);
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
    S.mappa.setFilter('nomi-strade', filtroNomi(elenco, S.corsie));
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
    // La notte nella chiave: passando al buio il nome si riscrive coi suoi
    // colori (lo stesso segno, riusato, restava scuro sull'alone bianco).
    segni.push({ chiave: `nome:${testo}:${Math.round(e.x)}:${Math.round(e.y)}:${S.notte ? 'notte' : 'giorno'}`, x: e.x, y: e.y, z: e.h + 1.2, immagine: tela, w: tela.width / 2, h: tela.height / 2, centro: 0.5 });
  }
  // Nella vista «Corsie», sopra i semafori vicini un fumetto col semaforo
  // (spento: di che colore è non lo sa nessuno), che si veda anche da lontano.
  if (S.corsie) {
    const semafori = [];
    for (const c of S.costruite.values()) {
      const t = scena.tessere.get(c.chiave)?.dati.semafori;
      for (let i = 0; t && i < t.length; i += 3) {
        const x = c.cx + t[i] * c.scala;
        const y = c.cy + t[i + 1] * c.scala;
        const d = Math.hypot(x - qui[0], y - qui[1]);
        if (d < SEMAFORI_VICINI_M) semafori.push({ x, y, z: t[i + 2], d });
      }
    }
    semafori.sort((a, b) => a.d - b.d);
    const tela = iconaSemaforo();
    for (const q of semafori.slice(0, 6)) {
      segni.push({ chiave: `semaforo:${Math.round(q.x)}:${Math.round(q.y)}:${S.notte ? 'notte' : 'giorno'}`, x: q.x, y: q.y, z: q.z, immagine: tela, w: tela.width / 2, h: tela.height / 2 });
    }
  }
  scena.impostaSegni(segni);
}

/** Fin dove si mette il fumetto sopra i semafori (vista «Corsie»). */
const SEMAFORI_VICINI_M = 350;

/** Il fumetto del semaforo: bianco, la lanterna scura con le tre lenti grigie, la punta in basso. */
let telaSemaforo = null;
function iconaSemaforo() {
  const notte = S.notte;
  if (telaSemaforo?.notte === notte) return telaSemaforo.tela;
  const c = document.createElement('canvas');
  c.width = 60;
  c.height = 80;
  const g = c.getContext('2d');
  g.fillStyle = 'rgba(15,23,42,0.25)';
  g.beginPath();
  g.roundRect(4, 5, 52, 60, 14);
  g.fill();
  g.fillStyle = notte ? '#E5E9F0' : '#FFFFFF';
  g.beginPath();
  g.roundRect(4, 2, 52, 60, 14);
  g.fill();
  g.beginPath();
  g.moveTo(22, 60);
  g.lineTo(30, 76);
  g.lineTo(38, 60);
  g.fill();
  g.fillStyle = '#1F2430';
  g.beginPath();
  g.roundRect(20, 9, 20, 46, 6);
  g.fill();
  g.fillStyle = '#8A93A3';
  for (const y of [18, 32, 46]) {
    g.beginPath();
    g.arc(30, y, 5, 0, Math.PI * 2);
    g.fill();
  }
  telaSemaforo = { notte, tela: c };
  return c;
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
  let c = dallaScorta(teleEtichette, chiave);
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
  nellaScorta(teleEtichette, chiave, c, TETTO_ETICHETTE);
  return c;
}

// ─── L'auto e la telecamera, a ogni fotogramma ───────────────────────────

let richiesta = null;
let ultimoFotogramma = 0;
/** Dentro [fotogramma]: i disegni chiesti lì sono già al passo. */
let nelFotogramma = false;

/** Riaccende i fotogrammi (se non è in pausa). */
function sveglia() {
  if (richiesta || S.pausa || S.nascosta || !S.mappa) return;
  richiesta = requestAnimationFrame(fotogramma);
}

function fotogramma(adesso) {
  richiesta = null;
  // Col tempo delle prove (i video) i fotogrammi li chiede il collaudo.
  if (S.pausa || S.nascosta || !S.mappa || !S.stileCaricato || S.orologioProva !== undefined) return;
  if (adesso - ultimoFotogramma < intervalloDeiFotogrammi() - 2) {
    richiesta = requestAnimationFrame(fotogramma);
    return;
  }
  const dt = ultimoFotogramma ? adesso - ultimoFotogramma : 0;
  ultimoFotogramma = adesso;
  nelFotogramma = true;
  let ancora;
  try {
    aggiornaPercorso(adesso);
    aggiornaTraffico(adesso);
    aggiornaSegni(adesso);
    ancora = muovi(adesso, dt);
  } finally {
    nelFotogramma = false;
  }
  S.anima = ancora;
  if (ancora) richiesta = requestAnimationFrame(fotogramma);
}

/**
 * A quanti metri del percorso [p] finisce la strada già fatta (la traccia
 * dell'app, che arriva ogni tre secondi): da lì all'auto, a [s] metri, la
 * strada fatta la disegna il nastro del percorso (`uniformiFattoVicino`).
 * Senza traccia, o con la traccia che finisce lontano dal percorso (appena
 * ricalcolato), gli ultimi centocinquanta metri.
 */
function doveFinisceIlFatto(p, s) {
  const f = S.fatto;
  if (!f) return s - 150;
  if (p.fattoDi !== f) {
    p.fattoDi = f;
    const n = f.linea.x.length;
    const q = p.linea.proietta(f.linea.x[n - 1], f.linea.y[n - 1], Math.max(0, s - 600), s + 60);
    p.fattoFinoA = q.d < 25 ? q.s : null;
  }
  return p.fattoFinoA === null ? s - 150 : Math.min(s, p.fattoFinoA);
}

/** Muove auto e telecamera; dice se c'è ancora da muovere. */
function muovi(adesso, dt) {
  const m = S.mappa;
  const pos = moto.passo(S.orologioProva ?? Date.now());
  const p = S.percorso;
  let latoInMoto = false;
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
    S.latoCorsia = 0;
    const s = Math.min(pos.s, p.linea.lunghezza);
    [x, y] = p.linea.a(s);
    const prof = p.profilo;
    // Sulla strada come la linea (vedi `spostamenti` in percorso.js); quando
    // il profilo si rifà, ci si arriva piano (vedi [Raccordo]).
    const [cx, cy, cz] = raccordo.passo(prof, s, valoriDelProfilo, dt);
    if (prof) {
      const [sx, sy] = prof.sposta(s);
      x += sx;
      y += sy;
    }
    x += cx;
    y += cy;
    // Fuori dal tratto del profilo (si sta rifacendo, l'auto è scattata
    // avanti) la quota del capo più vicino: a zero l'auto cadeva a terra da
    // un viadotto per un fotogramma, e la telecamera con lei.
    const q = (v) => (prof ? prof.quota(v) : (S.auto?.z ?? 0));
    z = q(s) + cz;
    // La strada su cui si sta, non quella dove si andrà: da cinque metri
    // dietro a uno avanti. Centrata, la freccia girava prima dell'angolo.
    const [dx0, dy0] = p.linea.a(s - 5);
    const [dx1, dy1] = p.linea.a(s + 1);
    // All'inizio e in fondo al percorso i due punti si toccano: lì la direzione di sempre.
    dir = Math.hypot(dx1 - dx0, dy1 - dy0) > 0.5 ? Math.atan2(dy1 - dy0, dx1 - dx0) : p.linea.direzione(s, 4);
    const pendenza = Math.atan2(q(s + 3) - q(s - 3), 6);
    scena.mettiAuto(x, y, z, dir, pendenza);
    // La mappa guarda un poco avanti: in curva la strada che arriva resta in
    // vista. Quanto avanti lo dice la velocità — un secondo e mezzo di
    // strada, al più venti metri — e da fermi niente: fermi davanti a una
    // svolta la mappa girava già sulla strada dopo, venti metri più in là.
    const avanti = Math.min(20, Math.max(0, moto.velocita * 1.5));
    const [cx0, cy0] = p.linea.a(s - 6);
    const [cx1, cy1] = p.linea.a(s + 1 + 2 * avanti);
    const versoCamera = Math.hypot(cx1 - cx0, cy1 - cy0) > 0.5 ? Math.atan2(cy1 - cy0, cx1 - cx0) : dir;
    rottaCamera = 90 - (versoCamera * 180) / Math.PI;
    S.auto = { x, y, z, s };
    if (scena.mat.percorso) scena.uniformiPercorso.uInizio.value = s + 1.5;
    // La strada fatta arriva fino all'auto, da dove finisce la traccia.
    scena.uniformiFattoVicino.uInizio.value = doveFinisceIlFatto(p, s) - 6;
    scena.uniformiFattoVicino.uFine.value = s + 1;
    // Il fantasma comincia oltre il muso dell'auto (lunga nove metri, in scala).
    scena.uniformiFantasma.uInizio.value = s + 6;
    if (S.manovra && S.frecciaDa !== undefined && s + 6 > S.frecciaDa + 4) aggiornaFreccia();
  } else {
    x = pos.x;
    y = pos.y;
    dir = ((90 - pos.rotta) * Math.PI) / 180;
    // Nella vista «Corsie» l'auto sta nella sua corsia (vedi `corsiaDellAuto`),
    // e non a cavallo della riga di mezzo; ci va piano, cambiando strada.
    if (S.corsie && !S.indiceCorsie) indicizzaCorsie();
    const lato = S.corsie ? corsiaDellAuto(S.indiceCorsie, x, y, pos.rotta) : null;
    S.latoCorsia = smorza(S.latoCorsia ?? 0, lato ?? 0, dt, 500);
    if (Math.abs(S.latoCorsia - (lato ?? 0)) > 0.03) latoInMoto = true;
    x += -Math.sin(dir) * S.latoCorsia;
    y += Math.cos(dir) * S.latoCorsia;
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
  const vista = S.corsie ? VISTA_CORSIE : (VISTE[S.vista] ?? VISTE.inclinata);
  let assestata = true;
  if (S.camera.modo === 'segui') {
    // Nella vista «Corsie» più vicini di quanto chiede l'app, sempre con la
    // sua inclinazione (anche sull'auto).
    const H0 = m.getCanvas().clientHeight;
    const W0 = m.getCanvas().clientWidth;
    /* Il pannello piccolo (lo schermo diviso dell'auto, con la scheda della
     * musica sopra): la vista si allontana fin che si vede il pezzo di mondo
     * di un telefono (`zoomPerLoSpazio`), e nella vista «Corsie» guarda un
     * po' più dall'alto, che i palazzi accanto non chiudano la strada. */
    const [ls, ld] = marginiAiLati(S.camera.sinistra ?? 0, S.camera.destra ?? 0, W0);
    const lontano = zoomPerLoSpazio(W0 - ls - ld, H0 - Math.min(S.camera.sopra ?? 0, H0 * 0.5));
    const zoomVoluto = (S.corsie ? zoomCorsie(S.zoomVoluto ?? 17.9, S.zoomScelto ?? 0) : (S.zoomVoluto ?? vista.zoom)) + lontano;
    // L'inclinazione: quella della vista, o quella chiesta (sull'auto più
    // dall'alto: «voglio vederla un po' più dall'alto»).
    const pitchVoluto = S.corsie ? vista.pitch + PITCH_PER_LO_SPAZIO * lontano : (S.camera.pitch ?? vista.pitch);
    const c = (S.cam ??= { rotta: rottaCamera, zoom: zoomVoluto, quota: z, pitch: pitchVoluto });
    c.rotta = angoloVerso(c.rotta, rottaCamera, 1 - Math.exp(-dt / 400));
    /* Lo zoom cambia da sé (in autostrada si allontana, vicino a una manovra
     * torna) e a mano, coi tasti dell'auto. Prima andavano tutti e due con lo
     * stesso passo, un secondo e mezzo: troppo svelto per quello che cambia da
     * sé («ero in autostrada, e all'improvviso a uno svincolo ha fatto zoom
     * out»: passata l'uscita la mappa si riallontanava di colpo), troppo lento
     * per i tasti («zoom in e zoom out non va»: si preme e per un secondo non
     * si muove niente). Allontanarsi da sé è la cosa più lenta; il tasto è
     * subito. */
    const passoZoom = adesso < (S.zoomSubitoFino ?? 0) ? ZOOM_DEL_TASTO_MS : zoomVoluto < c.zoom ? ZOOM_SI_ALLONTANA_MS : ZOOM_SI_AVVICINA_MS;
    c.zoom = smorza(c.zoom, zoomVoluto, dt, passoZoom);
    c.quota = smorza(c.quota, z, dt, 300);
    c.pitch = smorza(c.pitch, pitchVoluto, dt, 600);
    const H = m.getCanvas().clientHeight;
    const W = m.getCanvas().clientWidth;
    // Lo spazio delle schede, mai più di metà schermo: con misure sbagliate
    // (l'auto le dà in punti suoi) l'auto finiva in un angolo, lontana.
    // Nella vista «Corsie» l'auto sta più in basso, poco sotto i sei decimi
    // dello schermo: davanti c'è la strada da fare, e sotto restano il
    // contachilometri e il limite del cruscotto, che più giù la coprivano.
    const sopra = S.corsie ? Math.min(H * 0.24 + S.camera.sopra * 0.5, H * 0.5) : Math.min(H * 0.12 + S.camera.sopra * 0.8, H * 0.5);
    // In larghezza l'auto sta in mezzo alla parte libera: a sinistra il
    // cruscotto di traverso sul telefono, a destra l'altra app dello schermo
    // diviso sull'auto («la navigazione si nasconde sotto l'altro pezzo di
    // schermo»).
    const [sinistra, destra] = marginiAiLati(S.camera.sinistra ?? 0, S.camera.destra ?? 0, W);
    /* La quota del centro: l'auto sul viadotto. Nella vista di sempre, da
     * lontano, sette, quattordici metri non si notano; in quella «Corsie» la
     * telecamera sta una ventina di metri sopra il centro, e sulla rampa di
     * uno svincolo a 24 m l'auto usciva dallo schermo in alto e la telecamera
     * finiva dentro il viadotto di sopra (lo schermo tutto grigio). */
    let voluta = { center: [lon, lat], zoom: c.zoom, pitch: c.pitch, bearing: c.rotta, elevation: S.corsie ? c.quota : 0, padding: { top: sopra, bottom: 0, left: sinistra, right: destra } };
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
  return !(moto.fermo && assestata && !latoInMoto);
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
  // Nella vista «Corsie» quello che sta sopra fra la telecamera e l'auto è un
  // fantasma a puntini, con una finestra libera davanti all'auto (vedi
  // `tagliaSopra` in scena.js): niente la copre, e la sagoma rossa piatta
  // sembrava un'auto rotta.
  for (let d = -40; d <= 6 && !coperta && !S.corsie; d += 4) {
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
  const P = tavolozza(S.notte, S.corsie);
  // Nella vista «Corsie» un cielo chiaro e pulito, senza nuvole.
  if (S.corsie && !S.notte) {
    document.getElementById('mappa').style.background = `linear-gradient(180deg, #a9c8ea 0px, #d6e5f3 ${hy * 0.6}px, ${P.nebbia} ${hy + 4}px, ${P.nebbia} 100%)`;
    return;
  }
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
    ritmo: { media: ritmo.media, passo: ritmo.passo, svelto: ritmo.svelto, auto: ritmo.fisso30, livello: ritmo.livello, leggera: S.leggera },
    pixel: S.mappa?.getPixelRatio() ?? null,
    nascosta: S.nascosta,
    rifatti: S.rifatti,
    intervalli: S.intervalli.length,
    auto: S.auto,
    camera: S.camera.modo,
    profilo: S.percorso?.profilo ? { da: S.percorso.profilo.s0, a: S.percorso.profilo.s1, max: Math.max(...S.percorso.profilo.h) } : null,
    log: S.log.slice(-40),
  };
}

manda('caricata', { versione: 1 });
