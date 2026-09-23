# Il relay

Dove Home Assistant e l'app si incontrano, senza che la casa apra niente:
è Home Assistant a chiamare fuori. Il relay sposta buste che non può aprire
(le regole sono in [`../docs/protocollo.md`](../docs/protocollo.md#relay)).

Una stanza per auto, ognuna un Durable Object con SQLite. I WebSocket sono
in ibernazione: mentre nessuno parla non consumano niente. Tutto dentro il
piano gratuito di Cloudflare.

    npm ci
    npm test                         # le regole, con node
    npx wrangler dev --port 8799     # in locale
    npx wrangler login && npx wrangler deploy

L'indirizzo che stampa `deploy` va in `RELAY_PREDEFINITO`
(`custom_components/gdanav/const.py`).
