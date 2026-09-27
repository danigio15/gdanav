// Le versioni dell'app: la build più vecchia ancora buona. Sotto quella,
// l'app si ferma e chiede di aggiornarla (il giorno dei pagamenti, per
// spegnere le build di prova con Premium sbloccato). Il numero è la
// variabile VERSIONE_MINIMA_APP di wrangler.toml: 0 = nessun blocco.

/** Quanto la risposta può restare in cache: poco, per poterla cambiare. */
export const DURATA_CACHE_VERSIONI_S = 300;

/** Il numero di VERSIONE_MINIMA_APP; 0 se manca o non è un intero ≥ 0. */
export function versioneMinima(env) {
  const testo = String(env?.VERSIONE_MINIMA_APP ?? '0').trim();
  return /^\d{1,9}$/.test(testo) ? Number(testo) : 0;
}

/** GET /v1/versioni → { gdanav: { minima } }, aperto a tutti. */
export function versioni(richiesta, env) {
  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, OPTIONS',
  };
  if (richiesta.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (richiesta.method !== 'GET' && richiesta.method !== 'HEAD') {
    return new Response(JSON.stringify({ errore: 'metodo' }), {
      status: 405,
      headers: { 'content-type': 'application/json', allow: 'GET, OPTIONS', ...cors },
    });
  }
  return new Response(JSON.stringify({ gdanav: { minima: versioneMinima(env) } }), {
    headers: {
      'content-type': 'application/json',
      'cache-control': `public, max-age=${DURATA_CACHE_VERSIONI_S}`,
      ...cors,
    },
  });
}
