// L'auto che scorre fra una posizione e l'altra.
//
// Sul percorso, quando l'app manda la lettura del GPS com'era (i metri, l'ora
// del fix, la precisione) la fa il filtro di Kalman (`filtro.js`), con la
// velocità dell'auto se il cruscotto la dice. Quello che segue qui sotto
// resta per le app che quella lettura non la mandano ancora, e fuori dal
// percorso.
//
// L'app manda la posizione quando la sa (una volta al secondo, di solito):
// i metri lungo il percorso, la velocità, e quando l'ha letta. Qui, a ogni
// fotogramma, l'auto va verso dove è adesso (la lettura portata avanti con
// la velocità) con un moto morbido, e non torna mai indietro lungo la
// strada: una lettura nuova è una correzione, non un salto. Come
// `MotoSullaStrada` dell'app, ma qui, vicino al disegno, senza un messaggio
// per fotogramma.

/** Quanto si va verso [voluto] in [dt] ms, con costante [tau] ms. */
export const smorza = (attuale, voluto, dt, tau) => attuale + (voluto - attuale) * (1 - Math.exp(-Math.max(0, dt) / tau));

/**
 * Il raccordo fra un profilo del percorso e il successivo, sotto la freccia.
 *
 * «La navigazione continua a non essere fluida: va a scatti.» La freccia sta
 * sulla strada col profilo del percorso: lo spostamento di lato verso il
 * mezzo della strada e la quota. Il profilo si rifà spesso (a ogni tessera
 * nuova, e quando la finestra scorre), e dove si è il nuovo poteva dire due o
 * tre metri diversi dal vecchio: freccia e telecamera saltavano di colpo.
 * Adesso la differenza diventa una correzione che si spegne in mezzo
 * secondo: si arriva al nuovo piano, e per il resto si segue la strada
 * esattamente come prima (anche su una rampa che sale).
 */
export class Raccordo {
  constructor(tau = 450, salto = 8) {
    this.tau = tau;
    this.salto = salto;
    this.profilo = null;
    this.x = 0;
    this.y = 0;
    this.z = 0;
  }

  /**
   * La correzione `[x, y, z]` da aggiungere a [profilo] in [s], dopo [dt] ms.
   * [valori] `(profilo, s)` dà `[dx, dy, quota]`, o `null` fuori dal profilo.
   */
  passo(profilo, s, valori, dt) {
    const k = Math.exp(-Math.max(0, dt) / this.tau);
    this.x *= k;
    this.y *= k;
    this.z *= k;
    if (profilo !== this.profilo) {
      const a = this.profilo && s !== null && s !== undefined ? valori(this.profilo, s) : null;
      const b = a && profilo ? valori(profilo, s) : null;
      // Oltre qualche metro non è lo stesso posto (un percorso nuovo): si va.
      if (a && b && Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]) < this.salto) {
        this.x += a[0] - b[0];
        this.y += a[1] - b[1];
        this.z += a[2] - b[2];
      }
      this.profilo = profilo;
    }
    return [this.x, this.y, this.z];
  }
}

/** L'angolo (gradi) da [a] verso [b] per la via più corta, di [f]. */
export function angoloVerso(a, b, f) {
  const d = ((((b - a) % 360) + 540) % 360) - 180;
  return (((a + d * f) % 360) + 360) % 360;
}

/** Oltre questo l'auto non si porta avanti da sola (il GPS tace). */
const AVANTI_MAX_S = 2.5;

/** In quanto si recupera la distanza dal punto voluto (secondi). */
const RECUPERO_S = 0.9;
/** Quanto più veloce della lettura può andare la freccia per recuperare (m/s). */
const VELOCITA_IN_PIU = 8;
/** Quanto può restare avanti la freccia ferma, senza tornare indietro (m). */
const AVANTI_TOLLERATO_M = 3;
/** Sotto questa velocità la freccia non passa una svolta prima del GPS (m/s). */
const PIANO_MS = 3;
/** Una svolta è passata quando il GPS è oltre l'angolo di tanto (m). */
const SVOLTA_PASSATA_M = 2;
/** Quanto morbidamente cambia la velocità della freccia (ms). */
const TAU_VELOCITA = 220;

import { FiltroSullaStrada } from './filtro.js';

export class Moto {
  constructor({ tau = 320 } = {}) {
    this.tau = tau;
    this.filtro = new FiltroSullaStrada();
    this.colFiltro = false;
    /** I metri delle svolte strette del percorso ([svolteDi]). */
    this.svolte = [];
    /** I metri dell'ultima lettura del GPS così com'era (o la stima, senza). */
    this.ultimoFix = null;
    this.lettura = null;
    this.s = null;
    this.x = null;
    this.y = null;
    this.rotta = 0;
    this.ultimo = null;
    this.vel = null;
  }

  /** Un percorso nuovo: i metri ripartono da capo. */
  nuovoPercorso() {
    this.filtro.reset();
    this.s = null;
  }

  /** La velocità dell'auto stessa, dal cruscotto: [v] m/s letta [alle], arrivata [adesso]. */
  velocitaAuto(v, alle, adesso) {
    if (this.colFiltro) this.filtro.velocitaAuto(v, alle, adesso);
  }

  /**
   * Una lettura nuova. [metri] lungo il percorso (o null), [x, y] in metri
   * della scena. [lettura]: il GPS com'era (`{metri, alle, v, precisione}`),
   * se l'app la manda; [adesso]: quando è arrivata.
   */
  posizione({ metri = null, v = 0, x = null, y = null, rotta = 0, quando, lettura = null, adesso = quando }) {
    this.colFiltro = metri !== null && lettura !== null && Number.isFinite(lettura?.metri);
    if (this.colFiltro) this.filtro.misura(lettura, adesso);
    else this.filtro.reset();
    this.ultimoFix = this.colFiltro ? lettura.metri : metri;
    this.vFix = this.colFiltro && Number.isFinite(lettura.v) ? lettura.v : v || 0;
    const prima = this.lettura;
    const vel = Math.max(0, v || 0);
    // Frenando, il punto portato avanti con la velocità di adesso va oltre
    // dove l'auto si ferma: l'accelerazione dalle ultime due letture.
    const tra = prima ? (quando - prima.quando) / 1000 : 0;
    const acc = tra > 0.2 && tra < 3 ? Math.min(3, Math.max(-6, (vel - prima.v) / tra)) : 0;
    this.lettura = { metri, v: vel, acc, x, y, rotta, quando };
    if (metri === null) this.s = null;
  }

  /** Dove vuole essere l'auto adesso. */
  voluto(adesso) {
    const l = this.lettura;
    if (!l) return null;
    const dt = Math.min(AVANTI_MAX_S, Math.max(0, (adesso - l.quando) / 1000));
    if (l.metri !== null) {
      // Con la frenata stimata: ci si ferma dove l'auto si fermerebbe.
      const a = l.acc < 0 ? l.acc : 0;
      const t = a < 0 ? Math.min(dt, l.v / -a) : dt;
      return { s: l.metri + l.v * t + 0.5 * a * t * t };
    }
    const a = ((90 - l.rotta) * Math.PI) / 180;
    return { x: l.x + Math.cos(a) * l.v * dt, y: l.y + Math.sin(a) * l.v * dt, rotta: l.rotta };
  }

  /** Un fotogramma: dove sta l'auto. */
  passo(adesso) {
    const v = this.voluto(adesso);
    const dt = this.ultimo === null ? 0 : adesso - this.ultimo;
    this.ultimo = adesso;
    if (!v) return null;
    if (v.s !== undefined && this.colFiltro) {
      let s = this.filtro.passo(adesso);
      if (s !== null) {
        const fino = this.primaDellaSvolta(s);
        if (s > fino) {
          s = fino;
          this.filtro.mostrato = s;
          this.filtro.velMostrata = Math.min(this.filtro.velMostrata, 0);
        }
        this.s = s;
        return { s };
      }
    }
    if (v.s !== undefined) {
      const lv = this.lettura.v;
      if (this.s === null || v.s - this.s > 150 || v.s < this.s - 40) {
        this.s = v.s;
        this.vel = lv;
        return { s: this.s };
      }
      /* «Alcune volte è prima e altre dopo la posizione reale.» Prima la
       * freccia inseguiva il punto voluto con un ritardo fisso: in marcia
       * restava sempre indietro (a 50 all'ora quasi cinque metri), e
       * rallentando il punto portato avanti con la velocità di prima la
       * faceva andare oltre, dove poi si fermava di colpo ad aspettare. Ora
       * ha una velocità sua: quella della lettura più la correzione
       * dell'errore, che si recupera in [RECUPERO_S]. A velocità costante
       * sta sul punto; davanti rallenta, dietro accelera; indietro torna
       * solo da ferma, piano. */
      const errore = v.s - this.s;
      const voluta = Math.min(Math.max(0, lv + errore / RECUPERO_S), lv + VELOCITA_IN_PIU);
      this.vel = smorza(this.vel ?? lv, voluta, dt, TAU_VELOCITA);
      this.s += Math.max(0, this.vel) * (dt / 1000);
      // Ferma o quasi, e davanti alla posizione (una frenata che il GPS ha
      // detto tardi): torna piano dov'è, invece di restare avanti per sempre.
      // Solo oltre [AVANTI_TOLLERATO_M]: da fermi il GPS balla di qualche
      // metro, e una freccia che va avanti e indietro al semaforo è peggio.
      if (lv < 1.5 && v.s < this.s - AVANTI_TOLLERATO_M) this.s = smorza(this.s, v.s + AVANTI_TOLLERATO_M, dt, 1200);
      this.s = Math.min(this.s, this.primaDellaSvolta(this.s));
      return { s: this.s };
    }
    if (this.x === null || Math.hypot(v.x - this.x, v.y - this.y) > 150) {
      this.x = v.x;
      this.y = v.y;
      this.rotta = v.rotta;
    } else {
      this.x = smorza(this.x, v.x, dt, this.tau);
      this.y = smorza(this.y, v.y, dt, this.tau);
      this.rotta = angoloVerso(this.rotta, v.rotta, 1 - Math.exp(-dt / 250));
    }
    return { x: this.x, y: this.y, rotta: this.rotta };
  }

  /**
   * Fin dove può arrivare la freccia, adesso.
   *
   * «Alle svolte, se sto fermo, lui ha già girato.» Fermi o quasi davanti a
   * un incrocio, una stima un po' avanti — o il GPS che balla e si aggancia
   * alla strada dopo l'angolo — faceva girare la freccia prima dell'auto. Da
   * piano (sotto [PIANO_MS]) la freccia non passa una svolta stretta finché
   * una lettura del GPS non dice che l'auto l'ha passata davvero: si ferma
   * un metro prima dell'angolo e aspetta. Andando non si tiene: a quella
   * velocità la svolta la si fa, e fermare la freccia la farebbe restare
   * indietro.
   */
  primaDellaSvolta(s) {
    if (this.ultimoFix === null || !this.svolte.length) return Infinity;
    const vel = Math.max(this.vFix ?? 0, this.colFiltro ? this.filtro.velocita : 0);
    if (vel >= PIANO_MS) return Infinity;
    for (const svolta of this.svolte) {
      if (svolta <= this.ultimoFix + SVOLTA_PASSATA_M) continue;
      return s > svolta - 1 ? svolta - 1 : Infinity;
    }
    return Infinity;
  }

  /** Quanto si va, secondo quello che si disegna (m/s). */
  get velocita() {
    if (this.colFiltro) return Math.max(0, this.filtro.velMostrata ?? 0);
    return Math.max(0, this.vel ?? this.lettura?.v ?? 0);
  }

  /** Ferma e arrivata: niente fotogrammi fino alla lettura dopo. */
  get fermo() {
    const l = this.lettura;
    if (this.colFiltro && l) return this.filtro.velocita < 0.05 && Math.abs(this.filtro.velMostrata) < 0.05;
    if (!l || l.v > 0.3) return !l;
    if (l.metri !== null) return this.s !== null && Math.abs(l.metri - this.s) < 0.05;
    return this.x !== null && Math.hypot(l.x - this.x, l.y - this.y) < 0.05;
  }
}

/**
 * I metri delle svolte strette di [linea] (`Linea` di percorso.js): dove la
 * strada gira di più di [gradi] fra gli otto metri prima e gli otto dopo.
 * Una curva lunga non è una svolta: lì la strada gira piano.
 */
export function svolteDi(linea, gradi = 40) {
  const out = [];
  if (!linea || linea.lunghezza < 20) return out;
  const soglia = (gradi * Math.PI) / 180;
  const angolo = (u, w) => Math.abs(Math.atan2(Math.sin(w - u), Math.cos(w - u)));
  for (let i = 1; i < linea.s.length - 1; i++) {
    const m = linea.s[i];
    if (m < 8 || m > linea.lunghezza - 8) continue;
    const [ax, ay] = linea.a(m - 8);
    const [bx, by] = linea.a(m);
    const [cx, cy] = linea.a(m + 8);
    const g = angolo(Math.atan2(by - ay, bx - ax), Math.atan2(cy - by, cx - bx));
    if (g < soglia) continue;
    const ultima = out[out.length - 1];
    if (ultima && m - ultima.m < 15) {
      if (g > ultima.g) out[out.length - 1] = { m, g };
    } else {
      out.push({ m, g });
    }
  }
  return out.map((x) => x.m);
}
