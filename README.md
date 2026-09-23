# gdanav

Il navigatore per auto elettriche: la community di Waze (traffico,
incidenti, autovelox, colonnine guaste) e la pianificazione dei consumi di
ABRP, **collegato a Home Assistant**. Costruito per costare zero finché non
arrivano gli abbonati.

## Cosa c'è qui

| Cartella | Cosa | Linguaggio |
| --- | --- | --- |
| [`packages/gdanav_core`](packages/gdanav_core) | Il motore: consumi, soste di ricarica, sorgenti dei dati dell'auto, protocollo con Home Assistant | Dart puro |
| [`app`](app) | L'app Android e iOS: mappa, switch «Fonte dati auto», abbinamento con Home Assistant | Flutter |
| [`custom_components/gdanav`](custom_components/gdanav) | L'integrazione Home Assistant, da installare con HACS | Python |
| [`relay`](relay) | Il punto d'incontro fra Home Assistant e l'app, cifrato end-to-end | Cloudflare Worker |
| [`docs`](docs) | [Protocollo](docs/protocollo.md), [architettura](docs/architettura.md), vettore di prova condiviso | |

`custom_components/` e `hacs.json` stanno nella radice perché HACS li cerca
lì: questa repository si aggiunge a HACS così com'è.

## Come si prova

    # Il motore
    cd packages/gdanav_core && dart pub get && dart test

    # L'app
    cd app && flutter pub get && flutter analyze && flutter test

    # L'integrazione (serve Python 3.13)
    pip install -r requirements_test.txt && pytest

    # Il relay
    cd relay && npm ci && npm test

E la prova che conta, con tutti i pezzi veri insieme:

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
Assistant, relay, schermata con mappa OpenFreeMap e abbinamento.

Da fare, in ordine: routing con Valhalla, navigazione passo-passo
(Ferrostar), colonnine (Open Charge Map + PUN), il `CarAppService` Kotlin per
Android Auto, OBD via Bluetooth, segnalazioni della community. Il piano è in
[`docs/architettura.md`](docs/architettura.md).
