# Per chi sviluppa

[![Le prove](https://github.com/danigio15/gdanav/actions/workflows/prove.yml/badge.svg)](https://github.com/danigio15/gdanav/actions/workflows/prove.yml)

Quello che il [README](../README.md) non dice: com'è fatta la repository,
come si prova, come esce una versione e dove sono i pagamenti.

## Cosa c'è qui

| Cartella | Cosa | Linguaggio |
| --- | --- | --- |
| [`packages/gdanav_core`](../packages/gdanav_core) | Il motore: consumi, soste di ricarica, percorso, colonnine, distributori, traffico, meteo, segnalazioni, sorgenti dei dati dell'auto, protocollo con Home Assistant | Dart puro |
| [`packages/gdanav_app`](../packages/gdanav_app) | Lo schermo: mappa, guida, Premium, abbinamento con Home Assistant, Android Auto e CarPlay. Lo usano l'app e gdahome | Flutter, Kotlin, Swift |
| [`app`](../app) | L'app Android e iPhone: l'involucro del pacchetto qui sopra ([iPhone e CarPlay](ios.md)) | Flutter |
| [`custom_components/gdanav`](../custom_components/gdanav) | L'integrazione Home Assistant, da installare con HACS | Python |
| [`relay`](../relay) | Il punto d'incontro fra Home Assistant e l'app, cifrato end-to-end; le segnalazioni, i codici di abbinamento, la versione minima, la [privacy](https://gdanav.gdahome.org/privacy) | Cloudflare Worker |
| [`valhalla`](../valhalla) | Il nostro server dei percorsi, per Oracle Cloud Always Free | Docker + Caddy |
| [`docs`](.) | [Architettura](architettura.md), [protocollo](protocollo.md), [iPhone](ios.md), vettore di prova condiviso, [logo](logo), le [immagini del README](immagini) | |

`custom_components/` e `hacs.json` stanno nella radice perché HACS li cerca
lì: questa repository si aggiunge a HACS così com'è.

Il calcolo sta sul telefono; il server fa solo percorsi e community, il resto
viene da servizi gratuiti. Il perché e i pezzi sono in
[`architettura.md`](architettura.md).

### Home Assistant e il relay

Fra l'app e Home Assistant i dati passano dal relay di gdanav cifrati da un
capo all'altro (AES-256-GCM): la chiave la conoscono solo il telefono e la
Home Assistant dell'utente, il relay sposta buste che non può aprire e non
conserva niente. Home Assistant chiama fuori, non si apre nessuna porta di
casa. I dettagli sono in [`protocollo.md`](protocollo.md).

## Come si prova

    # Il motore
    cd packages/gdanav_core && dart pub get && dart test

    # Lo schermo
    cd packages/gdanav_app && flutter pub get && flutter analyze && flutter test

    # L'app
    cd app && flutter pub get && flutter analyze

    # L'integrazione (serve Python 3.13)
    pip install -r requirements_test.txt && pytest

    # Il relay
    cd relay && npm ci && npm test

E la prova che conta, con tutti i pezzi veri insieme:

    pip install pyvalhalla && valhalla/prova_locale.sh    # Valhalla vero, mappa di Utrecht
    cd packages/gdanav_core && GDANAV_VALHALLA=http://127.0.0.1:8002/ dart test
    cd relay && npx wrangler dev --port 8799 &
    GDANAV_RELAY=ws://127.0.0.1:8799 pytest tests/test_relay_vero.py
    cd packages/gdanav_core && GDANAV_RELAY=ws://127.0.0.1:8799 dart test test/relay_vero_test.dart

Le immagini delle schermate di Premium si rifanno con
`flutter test test_render/render_test.dart` in `packages/gdanav_app` (la
cartella si sceglie con `GDANAV_RENDER`). Quelle in
[`immagini`](immagini) vengono da lì e da scatti fatti allo stesso modo, con
la mappa tolta (la mappa vera vuole il nativo).

## Pubblicare e pagamenti

Le build escono dalla CI (`.github/workflows/prove.yml`): Android per il Play
Store, iPhone per TestFlight e l'App Store ([`ios.md`](ios.md)).

- **I pagamenti** si accendono con la variabile del repository
  `GDANAV_PAGAMENTI` = `si`: finché non c'è, le build escono con Premium
  sbloccato.
- **Le versioni vecchie** si fermano dal relay, con `VERSIONE_MINIMA_APP` in
  `relay/wrangler.toml`.

Come si fa, passo per passo, è in
[`architettura.md`](architettura.md#fermare-le-versioni-vecchie).

I prezzi (2,99 €/mese, 29,99 €/anno, 14 giorni di prova) stanno nei negozi,
non nel codice. Le licenze e i codici regalo passano dal quadro delle licenze
di gdahome (`docs/LICENZE.md` in gdahomeapp): lì anche gli installatori danno
licenze e codici gdanav, e gdahome Premium comprende gdanav Premium.

## A che punto è

Fatto: tutto quello che c'è nel README, su Android, iPhone, Android Auto e
CarPlay, da soli e dentro gdahome. I percorsi li calcola per ora il Valhalla
pubblico di FOSSGIS; le colonnine vengono da Open Charge Map e OpenStreetMap,
il loro stato da TomTom.

Da fare: accendere il nostro Valhalla su Oracle ([`valhalla/`](../valhalla),
scritto ma non ancora provato su una macchina vera); collegare la PUN (il
client OCPI c'è, manca l'indirizzo vero); il permesso di CarPlay da Apple
([`ios.md`](ios.md#carplay-il-permesso-di-apple)).

## Da citare

«© OpenStreetMap contributors», «© Open Charge Map contributors», OpenFreeMap
per la mappa, TomTom per traffico e colonnine in tempo reale, MET Norway per
il meteo, MIMIT per i prezzi dei carburanti.
