// L'auto che scorre fra una posizione e l'altra.
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
/** Quanto morbidamente cambia la velocità della freccia (ms). */
const TAU_VELOCITA = 220;

export class Moto {
  constructor({ tau = 320 } = {}) {
    this.tau = tau;
    this.lettura = null;
    this.s = null;
    this.x = null;
    this.y = null;
    this.rotta = 0;
    this.ultimo = null;
    this.vel = null;
  }

  /** Una lettura nuova. [metri] lungo il percorso (o null), [x, y] in metri della scena. */
  posizione({ metri = null, v = 0, x = null, y = null, rotta = 0, quando }) {
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

  /** Ferma e arrivata: niente fotogrammi fino alla lettura dopo. */
  get fermo() {
    const l = this.lettura;
    if (!l || l.v > 0.3) return !l;
    if (l.metri !== null) return this.s !== null && Math.abs(l.metri - this.s) < 0.05;
    return this.x !== null && Math.hypot(l.x - this.x, l.y - this.y) < 0.05;
  }
}
