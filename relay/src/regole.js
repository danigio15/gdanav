// Le regole del relay, senza Cloudflare intorno: così si provano con node.
//
// Il relay non sa niente dei messaggi. Sa solo:
// - in quale stanza (canale) va un filo;
// - se chi entra ha il gettone giusto;
// - a chi girare quello che arriva.

export const RUOLI = ['casa', 'app'];

/** Oltre questo, un messaggio è sicuramente sbagliato. */
export const MASSIMO_BYTE = 64 * 1024;

/** Quanti telefoni per auto: chi guida, e chi sta a casa a guardare. */
export const MASSIMO_APP = 4;

const CANALE = /^[A-Za-z0-9_-]{22}$/;
const ACCESSO = /^[A-Za-z0-9_-]{43}$/;

/**
 * Legge l'indirizzo `/v1/canale/<canale>?ruolo=casa|app&accesso=<gettone>`.
 * Restituisce `{canale, ruolo, accesso}` oppure `{errore, stato}`.
 */
export function leggiRichiesta(url) {
  const u = new URL(url);
  const m = u.pathname.match(/^\/v1\/canale\/([^/]+)$/);
  if (!m) return { errore: 'indirizzo sconosciuto', stato: 404 };
  const canale = m[1];
  const ruolo = u.searchParams.get('ruolo');
  const accesso = u.searchParams.get('accesso');
  if (!CANALE.test(canale)) return { errore: 'canale non valido', stato: 400 };
  if (!RUOLI.includes(ruolo)) return { errore: 'ruolo non valido', stato: 400 };
  if (!accesso || !ACCESSO.test(accesso)) return { errore: 'accesso non valido', stato: 400 };
  return { canale, ruolo, accesso };
}

export async function impronta(testo) {
  const byte = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(testo));
  return [...new Uint8Array(byte)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Chi può entrare. La prima casa che arriva fissa l'impronta del gettone
 * (la stanza nasce con lei); da lì in poi entra solo chi ha lo stesso
 * gettone. Un'app non crea stanze: se la casa non è mai passata, aspetta.
 */
export function puoEntrare({ improntaSalvata, improntaNuova, ruolo, appCollegate }) {
  if (improntaSalvata == null) {
    return ruolo === 'casa' ? { ok: true, salva: true } : { ok: false, stato: 404, errore: 'auto mai collegata' };
  }
  if (improntaSalvata !== improntaNuova) return { ok: false, stato: 403, errore: 'accesso negato' };
  if (ruolo === 'app' && appCollegate >= MASSIMO_APP) return { ok: false, stato: 429, errore: 'troppi telefoni' };
  return { ok: true, salva: false };
}

/** A chi va un messaggio: dalla casa a tutte le app, da un'app alla casa. */
export function destinatari(mittente) {
  return mittente === 'casa' ? 'app' : 'casa';
}

/** Il messaggio che il relay manda per dire chi c'è. In chiaro, senza segreti. */
export function presenza(ruolo, presente) {
  return JSON.stringify({ relay: presente ? 'presente' : 'assente', ruolo });
}
