// Dove sta l'auto lungo la strada, adesso: un filtro di Kalman.
//
// «Ci sono ancora problemi di reale posizione: trova un metodo serio per
// mantenere la posizione reale e fluida.» Prima c'erano due stime una sopra
// l'altra: l'app portava avanti la lettura di un anticipo fisso (900 ms) e la
// mandava con l'ora dell'invio; qui la freccia la inseguiva con un moto suo,
// portandola avanti ancora. Due inseguitori in fila si sbagliano in due modi:
// in accelerazione la freccia restava dietro, in frenata andava oltre e poi
// si fermava ad aspettare. «A volte prima, a volte dopo.»
//
// Adesso uno solo, quello dei navigatori: un filtro di Kalman lungo il
// percorso, con tre numeri — dove si è (metri), quanto si va (m/s), quanto
// si accelera (m/s²) — e quanto ci si fida di ognuno.
//
//  - A ogni fotogramma si PREDICE: l'auto va avanti con la sua velocità e la
//    sua accelerazione. Niente da aspettare: la freccia scorre.
//  - A ogni lettura del GPS si CORREGGE, con la lettura com'era QUANDO è
//    stata fatta (l'ora del fix, non dell'arrivo) e dove era l'auto allora,
//    meno [RITARDO_S]: il GPS del telefono liscia le posizioni, e liscio
//    vuol dire indietro. Il ritardo si toglie una volta sola, qui.
//  - La freccia non copia lo stato: lo insegue come una molla smorzata,
//    con una velocità sua che non cambia di colpo. Andando non torna mai
//    indietro.
//  - Da fermi (velocità del GPS sotto 0,3 m/s) si dice al filtro che la
//    velocità è zero: il GPS che balla di qualche metro al semaforo non
//    muove la freccia.
//  - Quanto pesa una lettura lo dice la sua precisione: un fix da 25 m sposta
//    poco, uno da 3 m molto.

/** Il ritardo delle posizioni del telefono rispetto alla strada (s): il
 * filtro del fornitore della posizione più il tempo del disegno. Dal campo:
 * a 50 all'ora la freccia stava una decina di metri dietro con 0,3 s. */
export const RITARDO_S = 0.8;

/** Una velocità del cruscotto più vecchia di così non si usa (ms). */
const VELOCITA_VECCHIA_MS = 1500;
/** Il ritardo della velocità dell'auto (s): poco, viene dal cruscotto. */
const RITARDO_AUTO_S = 0.1;

/** Quanto è svelta la freccia a raggiungere lo stato (rad/s): circa un secondo. */
const OMEGA = 4.5;
/** L'accelerazione della freccia, al più (m/s²). */
const ACC_MAX = 12;
/** Da ferma la freccia non si muove per meno di così (m). */
const FERMO_TOLLERATO_M = 2.5;

/** Quanto può cambiare l'accelerazione (m/s³): un'auto, non un razzo. */
const STRAPPO = 6;
/** In quanto l'accelerazione torna a zero se nessuno la conferma (s). */
const TAU_ACC = 2.0;
/** Sotto questa velocità del GPS l'auto è ferma (m/s). */
const FERMO_MS = 0.3;
/** Oltre questo silenzio del GPS la velocità si spegne (s). */
const SILENZIO_S = 2.5;
/** Una lettura così lontana dalla stima è un altro percorso: si riparte. */
const SALTO_AVANTI_M = 150;
const SALTO_INDIETRO_M = 40;

const mul = (A, B) => A.map((r) => B[0].map((_, j) => r.reduce((s, x, k) => s + x * B[k][j], 0)));
const tr = (A) => A[0].map((_, j) => A.map((r) => r[j]));
const somma = (A, B) => A.map((r, i) => r.map((x, j) => x + B[i][j]));

export class FiltroSullaStrada {
  constructor({ ritardo = RITARDO_S } = {}) {
    this.ritardo = ritardo;
    this.reset();
  }

  reset() {
    /** Lo stato [metri, m/s, m/s²] all'istante [t] (ms). */
    this.x = null;
    this.P = null;
    this.t = null;
    this.ultimaLettura = null;
    this.fermo = false;
    /** La freccia: dove sta e quanto va. */
    this.mostrato = null;
    this.velMostrata = 0;
    this.ultimaVelocitaAuto = null;
    this.ultimoPasso = null;
  }

  /** Porta lo stato all'istante [t] (ms). */
  predici(t) {
    if (this.x === null) return;
    const dt = (t - this.t) / 1000;
    if (dt <= 0) return;
    const [s, v, a] = this.x;
    const silenzio = this.ultimaLettura === null ? 0 : (t - this.ultimaLettura) / 1000;
    const e = Math.exp(-dt / TAU_ACC);
    let s1;
    let v1 = v + a * dt;
    let a1 = a * e;
    if (v1 < 0) {
      // Frenando ci si ferma dentro il passo: dove la frenata porta, e lì.
      const t0 = a < 0 ? v / -a : 0;
      s1 = s + v * t0 + 0.5 * a * t0 * t0;
      v1 = 0;
      a1 = 0;
    } else {
      s1 = s + v * dt + 0.5 * a * dt * dt;
    }
    // Il GPS tace (una galleria): l'auto rallenta piano, non corre da sola.
    if (silenzio > SILENZIO_S) v1 *= Math.exp(-dt / 1.5);
    this.x = [Math.max(s, s1), v1, a1];
    const F = [
      [1, dt, 0.5 * dt * dt],
      [0, 1, dt],
      [0, 0, e],
    ];
    const q = STRAPPO * STRAPPO;
    const Q = [
      [(q * dt ** 5) / 20, (q * dt ** 4) / 8, (q * dt ** 3) / 6],
      [(q * dt ** 4) / 8, (q * dt ** 3) / 3, (q * dt ** 2) / 2],
      [(q * dt ** 3) / 6, (q * dt ** 2) / 2, q * dt],
    ];
    this.P = somma(mul(mul(F, this.P), tr(F)), Q);
    this.t = t;
  }

  /** Una correzione: la misura [z] = H·stato, con varianza [R]. */
  correggi(H, z, R) {
    const Ht = H.map((h) => [h]);
    const PHt = mul(this.P, Ht);
    const S = H.reduce((s, h, i) => s + h * PHt[i][0], 0) + R;
    const y = z - H.reduce((s, h, i) => s + h * this.x[i], 0);
    const K = PHt.map((r) => r[0] / S);
    this.x = this.x.map((x, i) => x + K[i] * y);
    const KH = K.map((k) => H.map((h) => k * h));
    const I_KH = KH.map((r, i) => r.map((x, j) => (i === j ? 1 : 0) - x));
    this.P = mul(I_KH, this.P);
    return y;
  }

  /**
   * Una lettura: [metri] lungo il percorso dov'era l'auto, letta [alle] (ms
   * dall'epoca, l'ora del fix), a [v] m/s (o null), con [precisione] metri
   * (o null); arrivata [adesso].
   */
  misura({ metri, alle, v = null, precisione = null }, adesso) {
    if (!Number.isFinite(metri)) return;
    const quando = Number.isFinite(alle) && alle <= adesso && adesso - alle < 5000 ? alle : adesso;
    const indietro = this.ritardo + (adesso - quando) / 1000;
    const vm = Number.isFinite(v) ? Math.max(0, v) : null;
    if (this.x !== null) {
      this.predici(adesso);
      const stima = this.x[0] - this.x[1] * indietro;
      if (metri - stima > SALTO_AVANTI_M || metri < stima - SALTO_INDIETRO_M) this.reset();
    }
    if (this.x === null) {
      const v0 = vm ?? 0;
      this.x = [metri + v0 * indietro, v0, 0];
      this.P = [
        [25, 0, 0],
        [0, 4, 0],
        [0, 0, 1],
      ];
      this.t = adesso;
      this.ultimaLettura = adesso;
      this.fermo = vm !== null && vm < FERMO_MS;
      return;
    }
    this.ultimaLettura = adesso;
    const eraFermo = this.fermo;
    // Se l'auto dice la sua velocità, è lei a dire se si è fermi.
    if (!(this.ultimaVelocitaAuto != null && adesso - this.ultimaVelocitaAuto < 1500)) this.fermo = vm !== null && vm < FERMO_MS;
    if (eraFermo && !this.fermo) {
      // Si riparte: da fermi il filtro era sicuro che velocità e
      // accelerazione fossero zero, e ci avrebbe messo secondi a crederci.
      // Anche dove si è: fermo a lungo, il filtro era così sicuro del
      // semaforo che, per far tornare i conti, si inventava una frenata.
      this.P = [
        [Math.max(this.P[0][0], 4), 0, 0],
        [0, Math.max(this.P[1][1], 9), 0],
        [0, 0, Math.max(this.P[2][2], 4)],
      ];
    }
    const autoFresca = this.ultimaVelocitaAuto != null && adesso - this.ultimaVelocitaAuto < 1500;
    if (this.fermo && !autoFresca) {
      // Fermi: la velocità e l'accelerazione sono quasi zero. Quasi: un
      // filtro certo dello zero ci mette secondi a credere alla ripartenza,
      // e la freccia ferma è già tenuta dalla sua zona morta.
      this.correggi([0, 1, -indietro], 0, 0.04);
      this.correggi([0, 0, 1], 0, 0.25);
    } else if (vm !== null) {
      // Con la velocità dell'auto fresca, quella del GPS conta poco: è la
      // stessa, ma vecchia di un secondo.
      const auto = this.ultimaVelocitaAuto != null && adesso - this.ultimaVelocitaAuto < 1500;
      this.correggi([0, 1, -indietro], vm, auto ? 4 : 0.25);
    }
    // La posizione: quella di allora, cioè lo stato portato indietro.
    const sigma = Math.min(25, Math.max(3, precisione ?? 6));
    const R = sigma * sigma;
    this.correggi([1, -indietro, 0.5 * indietro * indietro], metri, R);
    if (this.x[1] < 0) this.x[1] = 0;
  }

  /**
   * Dove disegnare l'auto all'istante [adesso] (ms): i metri lungo il
   * percorso.
   *
   * La freccia non è lo stato del filtro: a ogni lettura lo stato si sposta
   * di colpo, e una freccia che lo copia scatta. Ha una posizione e una
   * velocità sue, e va verso lo stato come una molla smorzata: tirata dalla
   * distanza, frenata dalla differenza di velocità, con l'accelerazione al
   * più [ACC_MAX]. A velocità costante sta sullo stato; una correzione la
   * raggiunge in un secondo circa, senza strappi. Andando non torna indietro;
   * da ferma non si muove per meno di [FERMO_TOLLERATO_M].
   */
  passo(adesso) {
    if (this.x === null) return null;
    this.predici(adesso);
    const [sf, vf, af] = this.x;
    if (this.mostrato === null || Math.abs(sf - this.mostrato) > SALTO_INDIETRO_M) {
      this.mostrato = sf;
      this.velMostrata = vf;
      this.ultimoPasso = adesso;
      return sf;
    }
    let dt = this.ultimoPasso === null ? 0 : Math.max(0, adesso - this.ultimoPasso) / 1000;
    this.ultimoPasso = adesso;
    dt = Math.min(dt, 0.5);
    const w = OMEGA;
    // A passi corti: una scheda rimasta indietro non fa esplodere la molla.
    for (let resto = dt; resto > 1e-6; ) {
      const h = Math.min(resto, 1 / 60);
      resto -= h;
      const errore = sf + vf * (dt - resto - h) - this.mostrato;
      let acc;
      if (vf <= FERMO_MS && Math.abs(errore) < FERMO_TOLLERATO_M) acc = -2 * w * this.velMostrata;
      else acc = w * w * errore + 2 * w * (vf - this.velMostrata) + af;
      acc = Math.max(-ACC_MAX, Math.min(ACC_MAX, acc));
      this.velMostrata += acc * h;
      if (this.velMostrata < 0 && vf > FERMO_MS) this.velMostrata = 0;
      this.mostrato += this.velMostrata * h;
    }
    return this.mostrato;
  }

  /**
   * La velocità dell'auto stessa ([v] m/s, letta [alle] ms), arrivata
   * [adesso]: il cruscotto la sa subito e la dice più volte al secondo, senza
   * il ritardo del GPS. È lei a muovere la freccia in partenza e in frenata;
   * il GPS corregge dove si è.
   */
  velocitaAuto(v, alle, adesso) {
    if (this.x === null || !Number.isFinite(v)) return;
    // Solo fresca: una velocità di qualche secondo fa, presa per adesso,
    // farebbe correre la freccia oltre un semaforo.
    if (!Number.isFinite(alle) || adesso - alle > VELOCITA_VECCHIA_MS) return;
    const quando = Math.min(alle, adesso);
    this.predici(adesso);
    const indietro = RITARDO_AUTO_S + (adesso - quando) / 1000;
    const vm = Math.max(0, v);
    const eraFermo = this.fermo;
    this.fermo = vm < FERMO_MS;
    if (eraFermo && !this.fermo) {
      this.P = [
        [Math.max(this.P[0][0], 4), 0, 0],
        [0, Math.max(this.P[1][1], 9), 0],
        [0, 0, Math.max(this.P[2][2], 4)],
      ];
    }
    this.ultimaVelocitaAuto = adesso;
    this.correggi([0, 1, -indietro], vm, 0.02);
    if (this.x[1] < 0) this.x[1] = 0;
  }

  /** Quanto si va secondo il filtro (m/s). */
  get velocita() {
    return this.x === null ? 0 : this.x[1];
  }
}
