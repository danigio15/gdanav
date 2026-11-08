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

export class Moto {
  constructor({ tau = 320 } = {}) {
    this.tau = tau;
    this.lettura = null;
    this.s = null;
    this.x = null;
    this.y = null;
    this.rotta = 0;
    this.ultimo = null;
  }

  /** Una lettura nuova. [metri] lungo il percorso (o null), [x, y] in metri della scena. */
  posizione({ metri = null, v = 0, x = null, y = null, rotta = 0, quando }) {
    this.lettura = { metri, v: Math.max(0, v || 0), x, y, rotta, quando };
    if (metri === null) this.s = null;
  }

  /** Dove vuole essere l'auto adesso. */
  voluto(adesso) {
    const l = this.lettura;
    if (!l) return null;
    const dt = Math.min(AVANTI_MAX_S, Math.max(0, (adesso - l.quando) / 1000));
    if (l.metri !== null) return { s: l.metri + l.v * dt };
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
      if (this.s === null || v.s - this.s > 150 || v.s < this.s - 40) this.s = v.s;
      else if (v.s > this.s) this.s = smorza(this.s, v.s, dt, this.tau);
      // Più indietro di poco: si aspetta lì, non si torna.
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
