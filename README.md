# gdanav

[![Le prove](https://github.com/danigio15/gdanav/actions/workflows/prove.yml/badge.svg)](https://github.com/danigio15/gdanav/actions/workflows/prove.yml)
[![Licenza proprietaria](https://img.shields.io/badge/licenza-proprietaria-64748b)](LICENSE)

Il navigatore per auto elettriche: la community di Waze (traffico,
incidenti, autovelox, colonnine guaste) e la pianificazione dei consumi di
ABRP, **collegato a Home Assistant**. Costruito per costare zero finché non
arrivano gli abbonati.

## Cosa c'è qui

| Cartella | Cosa | Linguaggio |
| --- | --- | --- |
| [`packages/gdanav_core`](packages/gdanav_core) | Il motore: consumi, soste di ricarica, sorgenti dei dati dell'auto, protocollo con Home Assistant | Dart puro |
| [`packages/gdanav_app`](packages/gdanav_app) | Lo schermo: mappa, guida, switch «Fonte dati auto», abbinamento con Home Assistant. Lo usano l'app e gdahome | Flutter |
| [`app`](app) | L'app Android e iOS: l'involucro del pacchetto qui sopra, con Android Auto e CarPlay ([iPhone](docs/ios.md)) | Flutter |
| [`custom_components/gdanav`](custom_components/gdanav) | L'integrazione Home Assistant, da installare con HACS | Python |
| [`relay`](relay) | Il punto d'incontro fra Home Assistant e l'app, cifrato end-to-end | Cloudflare Worker |
| [`valhalla`](valhalla) | Il server dei percorsi, per Oracle Cloud Always Free | Docker + Caddy |
| [`docs`](docs) | [Protocollo](docs/protocollo.md), [architettura](docs/architettura.md), vettore di prova condiviso | |

`custom_components/` e `hacs.json` stanno nella radice perché HACS li cerca
lì: questa repository si aggiunge a HACS così com'è.

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

## Home Assistant

1. HACS → Integrazioni → i tre puntini → **Repository personalizzati** →
   questo indirizzo, categoria *Integrazione*.
2. Installa **gdanav** e riavvia Home Assistant.
3. Impostazioni → Dispositivi e servizi → **Aggiungi integrazione** → gdanav.
   Scegli le entità della tua auto (serve solo la batteria).
4. Apri il dispositivo *gdanav <la tua auto>* e inquadra il **QR di
   abbinamento** con l'app.

Da lì Home Assistant ha `sensor.gdanav_eta`, `sensor.gdanav_soc_arrivo`,
`sensor.gdanav_prossima_sosta`, `sensor.gdanav_soc_necessario`,
`binary_sensor.gdanav_in_viaggio`, l'evento `gdanav_evento` per le
automazioni e il servizio `gdanav.pianifica_viaggio`. Nelle opzioni si
scelgono gli script che l'app può avviare (pre-condizionamento, limite di
carica): solo quelli, mai altro.

> Il QR contiene la chiave: chi lo inquadra legge la tua auto. Mostralo solo
> a chi deve usare l'app.

## A che punto è

Fatto e provato: motore consumi e soste, switch delle sorgenti con modalità
automatica, protocollo cifrato identico fra Dart e Python, integrazione Home
Assistant, relay, schermata con mappa OpenFreeMap e abbinamento. Il client di
**Valhalla** (provato contro Valhalla 3.9 vero), le **colonnine** da Open
Charge Map e da OCPI (il formato dei punti di accesso AFIR, come la PUN), la
loro unione e il **pianificatore del viaggio** che mette tutto insieme. Nell'app
la **schermata del viaggio**: ricerca della destinazione (Photon), percorso e
soste sulla mappa, la scheda con batteria all'arrivo e ricariche.

Da fare, in ordine: accendere Valhalla su Oracle ([`valhalla/`](valhalla),
scritto ma non ancora provato su una macchina vera), l'indirizzo vero della
PUN, la scelta del modello d'auto, navigazione passo-passo (Ferrostar),
segnalazioni della community.

Su iPhone c'è tutto quello che c'è su Android, CarPlay compreso: cosa manca
dalla parte di Apple (account, chiavi, il permesso di CarPlay) e come esce una
versione su TestFlight è in [`docs/ios.md`](docs/ios.md).

Le colonnine vanno citate: «© Open Charge Map contributors», e la PUN per i
dati in tempo reale.

## Licenza

Il codice è pubblico perché si possa leggere e controllare cosa fa con
l'auto, la posizione e i dati di chi lo usa. Non è open source:
[licenza proprietaria](LICENSE), tutti i diritti riservati. Si può
installare e usare per sé; non si può ripubblicare, distribuire modificato o
usare commercialmente senza permesso scritto.
