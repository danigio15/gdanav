import { DurableObject } from 'cloudflare:workers';

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
  async fetch(richiesta, env) {
    if (new URL(richiesta.url).pathname.startsWith('/v1/segnalazioni')) return segnalazioni(richiesta, env);
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
