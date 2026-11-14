// L'auto sulla strada, anche senza percorso (o fuori dal percorso).
//
// «Capita che il simbolino dell'auto non sia sulla strada ma a fianco,
// vicino. Gli altri navigatori mettono sempre la macchina sulla strada anche
// quando il GPS la darebbe fuori, se è molto vicina.» Sul percorso l'auto
// scorre sulla linea; fuori (senza destinazione, o uscendo dal percorso) si
// disegnava dove diceva il GPS. Qui il punto della strada più vicina fra
// quelle delle tessere già costruite (`IndiceSegmenti`), come
// `AggancioStrada` dell'app (gdanav_core, con le stesse regole): mai oltre
// [SOGLIA_M], mai di traverso né contromano su un senso unico, e fra due
// strade parallele si resta su quella di prima finché l'altra non è più
// vicina di [MARGINE_CAMBIO_M] per [LETTURE_CAMBIO] letture di fila.

/** Oltre questo (metri) non ci si aggancia: si disegna il GPS. */
export const SOGLIA_M = 25;
/** Andando, quanto può girare la strada rispetto a dove si va (gradi). */
const DIREZIONE_GRADI = 50;
/** Di quanto deve essere più vicina un'altra strada per passarci (m). */
const MARGINE_CAMBIO_M = 4;
/** E per quante letture di fila. */
const LETTURE_CAMBIO = 2;
/** Sopra questa velocità (m/s) la direzione dell'auto vuol dire qualcosa. */
const ANDANDO_DA_MS = 2;

/** Quanto si gira da [a] a [b] (gradi, fra -180 e 180). */
const giro = (a, b) => ((((b - a) % 360) + 540) % 360) - 180;

export class AggancioStrada {
  constructor({ soglia = SOGLIA_M } = {}) {
    this.soglia = soglia;
    this.ultimo = null;
    this.altrove = 0;
  }

  dimentica() {
    this.ultimo = null;
    this.altrove = 0;
  }

  /**
   * La lettura [x, y] (metri della scena), che va verso [rotta] (gradi da
   * nord) a [v] m/s, sui [segmenti] `{x0, y0, x1, y1, senso}` (senso 1 come
   * i punti, -1 al contrario, 0 tutti e due): `{x, y, rotta, lontano}`, o
   * `null` se nessuna strada è abbastanza vicina e va nel verso giusto.
   */
  aggancia(x, y, rotta, v, segmenti) {
    const andando = Number.isFinite(rotta) && v >= ANDANDO_DA_MS;
    const prima = this.ultimo;
    let meglio = null;
    let stessa = null;
    for (const s of segmenti) {
      const sx = s.x1 - s.x0;
      const sy = s.y1 - s.y0;
      const l2 = sx * sx + sy * sy;
      if (l2 < 0.01) continue;
      const u = Math.max(0, Math.min(1, ((x - s.x0) * sx + (y - s.y0) * sy) / l2));
      const px = s.x0 + sx * u;
      const py = s.y0 + sy * u;
      const d = Math.hypot(x - px, y - py);
      if (d > this.soglia) continue;
      const suo = ((Math.atan2(sx, sy) * 180) / Math.PI + 360) % 360;
      let verso = suo;
      let scarto = 0;
      if (andando) {
        const avanti = Math.abs(giro(suo, rotta));
        const indietro = 180 - avanti;
        const puoAvanti = s.senso >= 0;
        const puoIndietro = s.senso <= 0;
        if (puoAvanti && (avanti <= indietro || !puoIndietro)) scarto = avanti;
        else if (puoIndietro) {
          scarto = indietro;
          verso = (suo + 180) % 360;
        } else continue;
        if (scarto > DIREZIONE_GRADI) continue;
      } else if (prima) {
        if (Math.abs(giro(suo, prima.rotta)) > 90) verso = (suo + 180) % 360;
      } else if (s.senso < 0) verso = (suo + 180) % 360;
      const c = { x: px, y: py, rotta: verso, lontano: d, costo: d + scarto * 0.08 };
      if (!meglio || c.costo < meglio.costo) meglio = c;
      if (prima && proseguimento(prima, s, suo)) {
        if (!stessa || c.costo < stessa.costo) stessa = c;
      }
    }
    if (!meglio) {
      this.dimentica();
      return null;
    }
    let scelto = meglio;
    if (stessa && stessa !== meglio) {
      if (meglio.costo < stessa.costo - MARGINE_CAMBIO_M) {
        this.altrove++;
        if (this.altrove < LETTURE_CAMBIO) scelto = stessa;
        else this.altrove = 0;
      } else {
        this.altrove = 0;
        scelto = stessa;
      }
    } else this.altrove = 0;
    this.ultimo = { x: scelto.x, y: scelto.y, rotta: scelto.rotta, lontano: scelto.lontano };
    return this.ultimo;
  }
}

/** Se il segmento [s] (verso [suo]) continua la strada dell'aggancio [prima]. */
function proseguimento(prima, s, suo) {
  const g = Math.abs(giro(suo, prima.rotta));
  if (Math.min(g, 180 - g) > 30) return false;
  const sx = s.x1 - s.x0;
  const sy = s.y1 - s.y0;
  const l = Math.hypot(sx, sy);
  return Math.abs((prima.x - s.x0) * sy - (prima.y - s.y0) * sx) / l < 3.5;
}
