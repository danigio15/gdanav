// Le scorte della pagina: le tele già disegnate (i nomi dei ponti, i cerchi
// delle soste) e le trame che più segni usano insieme. Guidando per ore i
// nomi cambiano di continuo: senza un tetto le tele crescevano sempre, e le
// trame dei segni tolti restavano nella scheda grafica.

/**
 * Quello che c'è per [chiave] nella [scorta] (una Map), o `undefined`; chi
 * si usa torna in fondo, fra i più recenti.
 */
export function dallaScorta(scorta, chiave) {
  const v = scorta.get(chiave);
  if (v !== undefined) {
    scorta.delete(chiave);
    scorta.set(chiave, v);
  }
  return v;
}

/**
 * Mette [valore] per [chiave] nella [scorta]; oltre [tetto] se ne va il meno
 * usato di recente (una tela tolta da qui resta a chi la sta già usando).
 */
export function nellaScorta(scorta, chiave, valore, tetto) {
  scorta.delete(chiave);
  scorta.set(chiave, valore);
  while (scorta.size > tetto) scorta.delete(scorta.keys().next().value);
}

/**
 * Cose da fare una volta e usare in tanti (una trama per immagine, anche se
 * la stessa icona sta su due segni): si contano quelli che la usano, e
 * quando l'ultimo la lascia si butta ([butta], es. `texture.dispose()`).
 */
export class Condivise {
  constructor(crea, butta) {
    this.crea = crea;
    this.butta = butta;
    this.voci = new Map();
  }

  /** La cosa per [chiave], fatta se non c'è: un utente in più. */
  prendi(chiave) {
    let v = this.voci.get(chiave);
    if (!v) {
      v = { cosa: this.crea(chiave), utenti: 0 };
      this.voci.set(chiave, v);
    }
    v.utenti++;
    return v.cosa;
  }

  /** Un utente in meno; l'ultimo la butta. */
  lascia(chiave) {
    const v = this.voci.get(chiave);
    if (!v) return;
    if (--v.utenti > 0) return;
    this.voci.delete(chiave);
    this.butta(v.cosa);
  }

  get size() {
    return this.voci.size;
  }
}
