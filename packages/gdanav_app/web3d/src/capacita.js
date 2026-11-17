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

/*
 * Sull'auto.
 *
 * «Quando è attiva la modalità 3D aumentata si rallenta anche lo smartphone:
 * se lo utilizzo va lento il telefono e il navigatore.» Sull'auto la scena
 * doveva andare a trenta fotogrammi al secondo, e ne faceva quasi sessanta
 * (MapLibre si ridisegna da sé fra un passo e l'altro: vedi
 * `alPassoDellaScena` in principale.js), alla risoluzione piena dello
 * schermo dell'auto (2000×1100: 2,2 milioni di pixel, una volta e mezza la
 * scena del telefono); e ogni fotogramma Android Auto lo codifica anche in
 * video. La scheda grafica è la stessa dell'app che si sta usando sul
 * telefono.
 *
 * Adesso i fotogrammi seguono la velocità (piano, l'auto sullo schermo si
 * sposta di poco: bastano meno fotogrammi; ferma e assestata, nessuno), e il
 * telefono dice quanto può pesare la scena ([carico]: il calore, il telefono
 * in uso). La risoluzione interna ha un tetto di pixel, e il browser la
 * porta alla grandezza dello schermo.
 */

/** I fotogrammi al secondo al più, sull'auto, per livello di carico (0–3). */
export const FPS_IN_AUTO = [30, 20, 15, 10];

/** I pixel della tela al più, sull'auto, per livello di carico (0–3). */
export const PIXEL_IN_AUTO = [1.5e6, 1.1e6, 0.8e6, 0.55e6];

const livelloDi = (l) => Math.min(3, Math.max(0, Math.round(Number.isFinite(l) ? l : 0)));

/**
 * Il livello di carico, da quello che dice il telefono ([carico]:
 * `{livello, telefono}`): il telefono in uso vale almeno uno.
 */
export function livelloDiCarico(carico) {
  if (!carico) return 0;
  return livelloDi(Math.max(livelloDi(carico.livello), carico.telefono ? 1 : 0));
}

/**
 * I fotogrammi al secondo sull'auto, andando a [velocita] m/s col carico
 * [livello]: piano (in coda, a passo d'uomo) quindici, sotto i trenta
 * all'ora venti, più svelti trenta. Tutti divisori di sessanta: su uno
 * schermo a sessanta giri i fotogrammi cadono sempre allo stesso passo.
 * [svelto]: la telecamera si sta muovendo da sé (un tasto dello zoom,
 * l'arrivo sull'auto): fino al tetto del livello.
 */
export function fpsInAuto(velocita, livello = 0, svelto = false) {
  const tetto = FPS_IN_AUTO[livelloDi(livello)];
  if (svelto) return tetto;
  const v = Number.isFinite(velocita) ? velocita : 0;
  const voluti = v < 1.5 ? 15 : v < 8 ? 20 : 30;
  return Math.min(voluti, tetto);
}

/**
 * Un intervallo fra due fotogrammi ([dt] ms) come lo vuole la sonda
 * ([valutaPrestazioni]), col passo voluto [passo] (ms).
 *
 * La sonda dice «lento» sotto i venti fotogrammi al secondo, pensando che
 * se ne vogliano trenta. Ma sull'auto, piano, se ne vogliono apposta
 * quindici: senza questo conto la scena si sarebbe spenta da sola («3D
 * aumentato non è disponibile») proprio quando fa quello che deve. Con un
 * passo voluto più lungo di un trentesimo l'intervallo si riporta a quel
 * passo: chi tiene i quindici voluti vale come chi tiene i trenta.
 */
export function intervalloPerLaSonda(dt, passo) {
  return passo > PASSO_30 ? (dt * PASSO_30) / passo : dt;
}

/**
 * Quanti pixel della tela per un punto della pagina: sul telefono quelli
 * dello schermo (al più due); sull'auto anche al più [PIXEL_IN_AUTO] in
 * tutto, per una tela di [larghezza]×[altezza] punti. A passi di 0,05, per
 * non rifare la tela per niente.
 */
export function rapportoPixel({ dpr = 1, larghezza = 0, altezza = 0, inAuto = false, livello = 0 } = {}) {
  const pieno = Math.min(dpr > 0 ? dpr : 1, 2);
  if (!inAuto || !(larghezza > 0 && altezza > 0)) return pieno;
  const tetto = Math.sqrt(PIXEL_IN_AUTO[livelloDi(livello)] / (larghezza * altezza));
  return Math.max(0.35, Math.min(pieno, Math.floor(tetto * 20) / 20));
}

/**
 * Trenta o sessanta fotogrammi al secondo, dall'intervallo vero fra un
 * fotogramma disegnato e il successivo (una media mobile).
 *
 * Prima si guardava quanto ci metteva three.js a dare i comandi (il tempo
 * del processore): pochi millisecondi anche su un telefono la cui scheda
 * grafica non stava dietro a sessanta, che allora andava a scatti più che a
 * trenta. Adesso si prova: a trenta e al passo, si va a sessanta; se a
 * sessanta i fotogrammi arrivano più radi, si torna a trenta e si riprova
 * più tardi. Con [fisso30] (sull'auto) mai sessanta: quanti, lo dice
 * [fpsInAuto] col [livello] di carico.
 */
export class Ritmo {
  constructor({ fisso30 = false } = {}) {
    this.fisso30 = fisso30;
    /** Il livello di carico sull'auto (vedi [livelloDiCarico]). */
    this.livello = 0;
    this.svelto = false;
    /** La media dell'intervallo (ms) al passo [passo], su [campioni] fotogrammi. */
    this.media = null;
    this.campioni = 0;
    this.passo = PASSO_30;
    this.ultimo = null;
    this.riprovaDa = 0;
    this.attesa = RIPROVA_MS;
  }

  /**
   * Il passo voluto (ms), andando a [velocita] m/s: sul telefono da fermi
   * trenta; sull'auto [fpsInAuto] ([svelto]: la telecamera che si muove da sé).
   */
  intervallo(velocita, svelto = false) {
    if (this.fisso30) return 1000 / fpsInAuto(velocita, this.livello, svelto);
    return this.svelto && velocita > 2 ? PASSO_60 : PASSO_30;
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
