// Il telefono ce la fa? Prima di partire, cosa offre WebGL; poi, nei primi
// secondi di guida, a quanti fotogrammi va davvero. Sotto la soglia la
// mappa 3D si spegne da sola e torna quella di sempre.

/** Fotogrammi al secondo sotto i quali il 3D non vale la pena. */
export const FPS_MINIMI = 20;

/**
 * Cosa dice WebGL del telefono ([info]: dal contesto): se va bene, e
 * perché no. Un rendering software (SwiftShader, llvmpipe) è troppo lento
 * per un telefono vero; serve almeno WebGL 2 e trame da 4096.
 */
export function valutaWebgl(info) {
  if (!info || !info.webgl2) return { ok: false, motivo: 'webgl2' };
  if ((info.maxTrama ?? 0) < 4096) return { ok: false, motivo: 'trame' };
  const r = `${info.renderer ?? ''}`.toLowerCase();
  if (!info.software && /(swiftshader|llvmpipe|softpipe|software)/.test(r)) return { ok: false, motivo: 'software' };
  if (info.memoria !== undefined && info.memoria < 2) return { ok: false, motivo: 'memoria' };
  return { ok: true, motivo: null };
}

/**
 * Le prestazioni dai tempi fra un fotogramma e l'altro (ms), presi mentre
 * la mappa si muove: la mediana e il 90° percentile. Lento se la mediana
 * sta sotto [FPS_MINIMI], o se un fotogramma su dieci ci mette più di 120 ms.
 */
export function valutaPrestazioni(intervalli) {
  const v = intervalli.filter((x) => x > 0 && x < 2000).sort((a, b) => a - b);
  if (v.length < 30) return null;
  const mediana = v[Math.floor(v.length / 2)];
  const p90 = v[Math.floor(v.length * 0.9)];
  const fps = 1000 / mediana;
  return { fps: Math.round(fps * 10) / 10, p90: Math.round(p90), lento: fps < FPS_MINIMI || p90 > 120 };
}

/** I due passi dei fotogrammi (ms): trenta e sessanta al secondo. */
export const PASSO_30 = 1000 / 30;
export const PASSO_60 = 1000 / 60;
/** A trenta, sotto questo intervallo medio vero (ms) il telefono sta al passo: si prova a sessanta. */
const TIENE_30_MS = 36;
/** A sessanta, sopra questo (meno di 48 al secondo) non ce la fa: si torna a trenta. */
const NON_TIENE_60_MS = 21;
/** Dopo una prova andata male si riprova dopo tanto, ogni volta il doppio, fino a [RIPROVA_MAX_MS]. */
const RIPROVA_MS = 20000;
const RIPROVA_MAX_MS = 300000;
/** Più distanti di così due fotogrammi non sono di seguito (una pausa, la mappa ferma). */
const STACCO_MS = 250;

/**
 * Trenta o sessanta fotogrammi al secondo, dall'intervallo vero fra un
 * fotogramma disegnato e il successivo (una media mobile).
 *
 * Prima si guardava quanto ci metteva three.js a dare i comandi (il tempo
 * del processore): pochi millisecondi anche su un telefono la cui scheda
 * grafica non stava dietro a sessanta, che allora andava a scatti più che a
 * trenta. Adesso si prova: a trenta e al passo, si va a sessanta; se a
 * sessanta i fotogrammi arrivano più radi, si torna a trenta e si riprova
 * più tardi. Con [fisso30] (sull'auto) sempre trenta.
 */
export class Ritmo {
  constructor({ fisso30 = false } = {}) {
    this.fisso30 = fisso30;
    this.svelto = false;
    /** La media dell'intervallo (ms) al passo [passo], su [campioni] fotogrammi. */
    this.media = null;
    this.campioni = 0;
    this.passo = PASSO_30;
    this.ultimo = null;
    this.riprovaDa = 0;
    this.attesa = RIPROVA_MS;
  }

  /** Il passo voluto (ms), andando a [velocita] m/s: da fermi trenta. */
  intervallo(velocita) {
    return !this.fisso30 && this.svelto && velocita > 2 ? PASSO_60 : PASSO_30;
  }

  /**
   * Un fotogramma disegnato alle [ora] (ms), col passo voluto [passo];
   * [conta]: la mappa si muove da sé (non un fotogramma isolato, né quelli
   * lenti di una tessera appena arrivata).
   */
  disegnato(ora, passo, conta = true) {
    const dt = this.ultimo === null ? null : ora - this.ultimo;
    this.ultimo = conta ? ora : null;
    if (dt === null || dt <= 0 || dt > STACCO_MS) return;
    if (passo !== this.passo) {
      this.passo = passo;
      this.media = null;
      this.campioni = 0;
    }
    this.media = this.media === null ? dt : this.media + (dt - this.media) * 0.08;
    this.campioni++;
    if (this.fisso30) return;
    if (passo === PASSO_60) {
      if (!this.svelto) return;
      if (this.campioni >= 30 && this.media > NON_TIENE_60_MS) {
        this.svelto = false;
        this.riprovaDa = ora + this.attesa;
        this.attesa = Math.min(this.attesa * 2, RIPROVA_MAX_MS);
      } else if (this.campioni >= 600) this.attesa = RIPROVA_MS;
    } else if (!this.svelto && this.campioni >= 60 && this.media < TIENE_30_MS && ora >= this.riprovaDa) {
      this.svelto = true;
    }
  }
}
