import { DurableObject } from 'cloudflare:workers';

import {
  DURATA_CACHE_S,
  SERVER_OVERPASS,
  fresca,
  leggiRiquadro,
  occupato,
  richiestaOverpass,
  rispostaBuona,
} from './colonnine.js';
import { DURATA_CODICE_MS, bustaValida, codiceVivo, leggiIndirizzoCodice } from './codici.js';
import { MASSIMO_BYTE, destinatari, impronta, leggiRichiesta, presenza, puoEntrare } from './regole.js';
import {
  FINESTRA_MS,
  MASSIMO_PER_FINESTRA,
  crea,
  leggiIndirizzo,
  leggiNuova,
  pubblica,
  viva,
  vota,
  zona,
  zoneVicine,
} from './segnalazioni.js';

const json = (dati, stato = 200) =>
  new Response(JSON.stringify(dati), { status: stato, headers: { 'content-type': 'application/json' } });

export default {
  async fetch(richiesta, env, ctx) {
    const percorso = new URL(richiesta.url).pathname;
    if (percorso.startsWith('/v1/segnalazioni')) return segnalazioni(richiesta, env);
    if (percorso.startsWith('/v1/codici/')) return codici(richiesta, env);
    if (percorso.startsWith('/v1/colonnine/')) return colonnine(richiesta, ctx);
    if (richiesta.headers.get('Upgrade') !== 'websocket') {
      return new Response('gdanav relay\n', { status: 426 });
    }
    const r = leggiRichiesta(richiesta.url);
    if (r.errore) return new Response(r.errore, { status: r.stato });
    const stanza = env.STANZE.get(env.STANZE.idFromName(r.canale));
    return stanza.fetch(richiesta);
  },
};

/** Una stanza per auto. Tiene solo l'impronta del gettone, mai i messaggi. */
export class Stanza extends DurableObject {
  async fetch(richiesta) {
    const { ruolo, accesso } = leggiRichiesta(richiesta.url);
    const improntaNuova = await impronta(accesso);
    const improntaSalvata = (await this.ctx.storage.get('impronta')) ?? null;
    const esito = puoEntrare({
      improntaSalvata,
      improntaNuova,
      ruolo,
      appCollegate: this.ctx.getWebSockets('app').length,
    });
    if (!esito.ok) return new Response(esito.errore, { status: esito.stato });
    if (esito.salva) await this.ctx.storage.put('impronta', improntaNuova);

    // Una casa sola per stanza: se si ricollega, la vecchia connessione cade.
    if (ruolo === 'casa') {
      for (const ws of this.ctx.getWebSockets('casa')) ws.close(4000, 'sostituita');
    }

    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, [ruolo]);

    // Chi entra sa subito se dall'altra parte c'è qualcuno; l'altra parte sa
    // che è arrivato.
    const altri = destinatari(ruolo);
    server.send(presenza(altri, this.ctx.getWebSockets(altri).length > 0));
    this.#manda(altri, presenza(ruolo, true));

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, messaggio) {
    const dimensione = typeof messaggio === 'string' ? messaggio.length : messaggio.byteLength;
    if (dimensione > MASSIMO_BYTE) {
      ws.close(1009, 'messaggio troppo grande');
      return;
    }
    const [ruolo] = this.ctx.getTags(ws);
    this.#manda(destinatari(ruolo), messaggio);
  }

  async webSocketClose(ws) {
    const [ruolo] = this.ctx.getTags(ws);
    const restano = this.ctx.getWebSockets(ruolo).filter((altro) => altro !== ws).length;
    if (restano === 0) this.#manda(destinatari(ruolo), presenza(ruolo, false));
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }

  #manda(ruolo, messaggio) {
    for (const ws of this.ctx.getWebSockets(ruolo)) {
      try {
        ws.send(messaggio);
      } catch {
        // Un filo che sta cadendo: ci pensa webSocketClose.
      }
    }
  }
}

/** Le segnalazioni: si leggono dalle nove zone intorno, si scrivono nella propria. */
async function segnalazioni(richiesta, env) {
  const r = leggiIndirizzo(richiesta.method, richiesta.url);
  if (r.errore) return json({ errore: r.errore }, r.stato);
  const zonaDo = (z) => env.ZONE.get(env.ZONE.idFromName(z));
  // Solo per contare le segnalazioni di ciascuno: l'indirizzo non si salva.
  const chi = await impronta(richiesta.headers.get('cf-connecting-ip') ?? 'anonimo');

  if (r.azione === 'elenco') {
    const liste = await Promise.all(zoneVicine(r.lat, r.lon).map((z) => zonaDo(z).elenco()));
    return json({ segnalazioni: liste.flat() }, 200);
  }
  if (r.azione === 'nuova') {
    let corpo;
    try {
      corpo = await richiesta.json();
    } catch {
      return json({ errore: 'JSON non valido' }, 400);
    }
    const n = leggiNuova(corpo);
    if (n.errore) return json({ errore: n.errore }, 400);
    const esito = await zonaDo(zona(n.lat, n.lon)).aggiungi(n, chi);
    return json(esito, esito.errore ? 429 : 201);
  }
  let corpo;
  try {
    corpo = await richiesta.json();
  } catch {
    return json({ errore: 'JSON non valido' }, 400);
  }
  if (typeof corpo?.ancora !== 'boolean') return json({ errore: 'ancora: vero o falso' }, 400);
  return json(await zonaDo(r.zona).vota(r.id, corpo.ancora), 200);
}

/** Una zona di 0,2°: le sue segnalazioni, e chi ne ha fatte troppe di fila. */
export class Zona extends DurableObject {
  #recenti = new Map();

  async elenco() {
    const ora = Date.now();
    const vive = [];
    const scadute = [];
    for (const [chiave, s] of await this.ctx.storage.list({ prefix: 's:' })) {
      if (viva(s, ora)) vive.push(pubblica(s));
      else scadute.push(chiave);
    }
    if (scadute.length) await this.ctx.storage.delete(scadute);
    return vive;
  }

  async aggiungi(nuova, chi) {
    const ora = Date.now();
    const sue = (this.#recenti.get(chi) ?? []).filter((t) => ora - t < FINESTRA_MS);
    if (sue.length >= MASSIMO_PER_FINESTRA) return { errore: 'troppe segnalazioni, riprova tra poco' };
    this.#recenti.set(chi, [...sue, ora]);
    const id = `${zona(nuova.lat, nuova.lon)}~${crypto.randomUUID().replaceAll('-', '').slice(0, 16)}`;
    const s = crea(nuova, ora, id);
    await this.ctx.storage.put(`s:${id}`, s);
    return pubblica(s);
  }

  async vota(id, ancora) {
    const s = await this.ctx.storage.get(`s:${id}`);
    if (!s) return { tolta: true };
    const n = vota(s, ancora, Date.now());
    if (n === null) {
      await this.ctx.storage.delete(`s:${id}`);
      return { tolta: true };
    }
    await this.ctx.storage.put(`s:${id}`, n);
    return pubblica(n);
  }
}

/** I codici di abbinamento: uno per oggetto, dieci minuti, una lettura. */
async function codici(richiesta, env) {
  const r = leggiIndirizzoCodice(richiesta.method, richiesta.url);
  if (r.errore) return json({ errore: r.errore }, r.stato);
  const codice = env.CODICI.get(env.CODICI.idFromName(r.id));
  if (r.azione === 'prendi') {
    const busta = await codice.prendi();
    return busta
      ? new Response(busta, { status: 200, headers: { 'content-type': 'application/json' } })
      : json({ errore: 'codice sbagliato o scaduto' }, 404);
  }
  const busta = await richiesta.text();
  if (!bustaValida(busta)) return json({ errore: 'busta non valida' }, 400);
  await codice.lascia(busta);
  return json({ scade_tra_s: DURATA_CODICE_MS / 1000 }, 201);
}

export class Codice extends DurableObject {
  async lascia(busta) {
    const scade = Date.now() + DURATA_CODICE_MS;
    await this.ctx.storage.put('codice', { busta, scade });
    await this.ctx.storage.setAlarm(scade);
  }

  async prendi() {
    const salvato = await this.ctx.storage.get('codice');
    await this.ctx.storage.deleteAll();
    return codiceVivo(salvato, Date.now()) ? salvato.busta : null;
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

/** Un riquadro di colonnine: dalla cache, o da Overpass e poi in cache. */
async function colonnine(richiesta, ctx) {
  const r = leggiRiquadro(richiesta.method, richiesta.url);
  if (r.errore) return json({ errore: r.errore }, r.stato);
  const chiave = new Request(`https://cache.gdanav/colonnine/v1/${r.riga}/${r.colonna}`);
  const inCache = await caches.default.match(chiave);
  if (inCache && fresca(Number(inCache.headers.get('x-gdanav-salvata')), Date.now())) return inCache;

  const corpo = new URLSearchParams({ data: richiestaOverpass(r.riga, r.colonna) });
  let ultimo = 'nessun server';
  for (const server of SERVER_OVERPASS) {
    for (let tentativo = 0; tentativo < 2; tentativo++) {
      try {
        const risposta = await fetch(server, {
          method: 'POST',
          body: corpo,
          headers: { 'user-agent': 'gdanav relay (github.com/danigio15/gdanav)' },
          signal: AbortSignal.timeout(25000),
        });
        const testo = await risposta.text();
        if (risposta.ok && rispostaBuona(testo)) {
          const buona = new Response(testo, {
            headers: {
              'content-type': 'application/json',
              'cache-control': `public, max-age=${DURATA_CACHE_S}`,
              'x-gdanav-salvata': String(Date.now()),
            },
          });
          ctx.waitUntil(caches.default.put(chiave, buona.clone()));
          return buona;
        }
        ultimo = `${new URL(server).host}: ${risposta.status}`;
        if (!occupato(risposta.status)) break;
        await new Promise((fatto) => setTimeout(fatto, 2000));
      } catch (e) {
        ultimo = `${new URL(server).host}: ${e}`;
        break;
      }
    }
  }
  // Overpass non risponde: meglio la copia di qualche settimana fa che niente.
  if (inCache) return inCache;
  return json({ errore: `colonnine: ${ultimo}` }, 502);
}

export class Codice extends DurableObject {
  async lascia(busta) {
    const scade = Date.now() + DURATA_CODICE_MS;
    await this.ctx.storage.put('codice', { busta, scade });
    await this.ctx.storage.setAlarm(scade);
  }

  async prendi() {
    const salvato = await this.ctx.storage.get('codice');
    await this.ctx.storage.deleteAll();
    return codiceVivo(salvato, Date.now()) ? salvato.busta : null;
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

/** Un riquadro di colonnine: dalla cache, o da Overpass e poi in cache. */
async function colonnine(richiesta, ctx) {
  const r = leggiRiquadro(richiesta.method, richiesta.url);
  if (r.errore) return json({ errore: r.errore }, r.stato);
  const chiave = new Request(`https://cache.gdanav/colonnine/v1/${r.riga}/${r.colonna}`);
  const inCache = await caches.default.match(chiave);
  if (inCache) return inCache;
  const corpo = new URLSearchParams({ data: richiestaOverpass(r.riga, r.colonna) });
  let ultimo = 'nessun server';
  for (const server of SERVER_OVERPASS) {
    try {
      const risposta = await fetch(server, {
        method: 'POST',
        body: corpo,
        headers: { 'user-agent': 'gdanav relay (github.com/danigio15/gdanav)' },
        signal: AbortSignal.timeout(30000),
      });
      const testo = await risposta.text();
      if (!risposta.ok || !rispostaBuona(testo)) {
        ultimo = `${new URL(server).host}: ${risposta.status}`;
        continue;
      }
      const buona = new Response(testo, {
        headers: { 'content-type': 'application/json', 'cache-control': `public, max-age=${DURATA_CACHE_S}` },
      });
      ctx.waitUntil(caches.default.put(chiave, buona.clone()));
      return buona;
    } catch (e) {
      ultimo = `${new URL(server).host}: ${e}`;
    }
  }
  return json({ errore: `colonnine: ${ultimo}` }, 502);
}
