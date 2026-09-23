import { DurableObject } from 'cloudflare:workers';

import { MASSIMO_BYTE, destinatari, impronta, leggiRichiesta, presenza, puoEntrare } from './regole.js';

export default {
  async fetch(richiesta, env) {
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
