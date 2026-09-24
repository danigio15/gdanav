// I codici di abbinamento da scrivere a mano: Home Assistant lascia qui
// l'abbinamento cifrato, sotto un nome ricavato dal codice; l'app lo prende
// una volta sola. Il relay non vede né il codice né la chiave.

export const DURATA_CODICE_MS = 10 * 60 * 1000;
export const MASSIMO_BUSTA = 2048;

/** GET o PUT su /v1/codici/<id di 22 caratteri>. */
export function leggiIndirizzoCodice(metodo, url) {
  const m = new URL(url).pathname.match(/^\/v1\/codici\/([A-Za-z0-9_-]{22})$/);
  if (!m) return { errore: 'indirizzo sconosciuto', stato: 404 };
  if (metodo === 'GET') return { azione: 'prendi', id: m[1] };
  if (metodo === 'PUT') return { azione: 'lascia', id: m[1] };
  return { errore: 'metodo', stato: 405 };
}

/** La busta com'è fatta: JSON { v: 1, n, c }, piccola. */
export function bustaValida(testo) {
  if (typeof testo !== 'string' || testo.length > MASSIMO_BUSTA) return false;
  try {
    const b = JSON.parse(testo);
    return b?.v === 1 && typeof b.n === 'string' && typeof b.c === 'string';
  } catch {
    return false;
  }
}

export const codiceVivo = (salvato, ora) => salvato != null && ora < salvato.scade;
