# gdanav

[![Le prove](https://github.com/danigio15/gdanav/actions/workflows/prove.yml/badge.svg)](https://github.com/danigio15/gdanav/actions/workflows/prove.yml)
[![Licenza proprietaria](https://img.shields.io/badge/licenza-proprietaria-64748b)](LICENSE)

Il navigatore per chi guida un'auto elettrica, e va bene anche per la termica.
Le segnalazioni della community come Waze (code, incidenti, polizia, lavori,
autovelox), il calcolo dei consumi e delle soste di ricarica come ABRP, e il
collegamento con **Home Assistant**.

Gira su **Android** e **iPhone**, e sullo schermo dell'auto con **Android
Auto** e **CarPlay**. C'è anche dentro l'app **gdahome**, con lo stesso
schermo.

## Cosa fa

- **Percorso e guida**: ricerca della destinazione, tappe, strade alternative
  con la differenza in minuti, opzioni (più veloce, equilibrato, risparmio;
  evita pedaggi, autostrade, traghetti). Guida con la voce, le corsie, lo
  svincolo in 3D col cartello dell'uscita, il limite di velocità.
- **Traffico** sul percorso e sulla mappa, con il ricalcolo quando conviene.
- **Community**: si segnala con un tocco, e chi passa dopo conferma o dice che
  non c'è più. Gli autovelox fissi di Italia e dintorni sono già dentro l'app.
- **Meteo** lungo il viaggio: entra anche nel calcolo dei consumi.
- **Auto elettrica**: il consumo tratto per tratto (velocità, salite e
  discese, vento, temperatura, clima), la batteria all'arrivo, dove fermarsi e
  quanto caricare.
- **Auto termica**: i distributori vicini con i prezzi del giorno
  dall'Osservaprezzi carburanti del Ministero (MIMIT).
- **Home Assistant**: l'app legge la batteria dalla casa, la casa sa del
  viaggio (arrivo, batteria all'arrivo, prossima sosta) e può preparare l'auto.
- **Siri** su iPhone («Ehi Siri, portami a casa con gdanav»), «Ok Google» su
  Android. Mappe offline, preferiti importati da Google.

Niente account, niente pubblicità, niente statistiche d'uso: l'informativa è su
[gdanav.gdahome.org/privacy](https://gdanav.gdahome.org/privacy).

## Gratis e Premium

| Gratis, per tutti | Premium |
| --- | --- |
| Auto termica completa: percorso, guida, distributori con i prezzi MIMIT | Home Assistant, e la batteria letta dall'auto: dongle OBD, Android Auto, gdahome o Home Assistant, senza scrivere niente a mano |
| Auto elettrica con la batteria scritta a mano, percorso senza soste di ricarica | Percorso con le soste alle colonnine, e le colonnine libere o occupate in tempo reale |
| Traffico, autovelox, segnalazioni e meteo | Android Auto e CarPlay |

Premium costa **2,99 € al mese** o **29,99 € all'anno**. I primi **14 giorni
sono gratis**, una volta sola: chi disdice durante la prova non paga niente.
Si compra e si disdice dal Play Store o dall'App Store.

Con un **codice regalo** (`GDA-XXXX-XXXX-XXXX`) Premium si attiva dal menu
Premium → «Ho un codice regalo», per qualche mese o per sempre, a seconda del
codice.

**Dentro gdahome** gdanav Premium è compreso in gdahome Premium: lì lo decide
gdahome, e gdanav non chiede niente.

## Home Assistant

1. HACS → Integrazioni → i tre puntini → **Repository personalizzati** →
   questo indirizzo, categoria *Integrazione*.
2. Installa **gdanav** e riavvia Home Assistant.
3. Impostazioni → Dispositivi e servizi → **Aggiungi integrazione** → gdanav.
   Scegli le entità della tua auto (serve solo la batteria).
4. Apri il dispositivo *gdanav &lt;la tua auto&gt;* e inquadra il **QR di
   abbinamento** con l'app. Se il QR non si può inquadrare, il pulsante
   **Nuovo codice di abbinamento** dà un codice da scrivere nell'app, valido
   dieci minuti.

Da lì Home Assistant ha:

| Entità | Cosa |
| --- | --- |
| `sensor.gdanav_destinazione` | dove sta andando l'auto |
| `sensor.gdanav_eta` | l'arrivo previsto |
| `sensor.gdanav_soc_arrivo` | la batteria all'arrivo |
| `sensor.gdanav_prossima_sosta` | la prossima sosta di ricarica |
| `sensor.gdanav_soc_necessario` | la batteria che serve per il prossimo viaggio: la wallbox carica fin lì |
| `binary_sensor.gdanav_in_viaggio` | acceso durante il viaggio |
| `binary_sensor.gdanav_app_collegata` | l'app è collegata adesso |

Poi l'evento `gdanav_evento` per le automazioni (`partenza`, `arrivo`,
`arrivo_vicino`, `inizio_ricarica`, `fine_ricarica`) e il servizio
`gdanav.pianifica_viaggio`, che manda una destinazione all'app. Nelle opzioni
si scelgono gli script, i pulsanti e le scene che l'app può avviare
(pre-condizionamento, limite di carica): solo quelli, mai altro. Con due auto
la seconda prende `_2`.

> Il QR contiene la chiave: chi lo inquadra legge la tua auto. Mostralo solo
> a chi deve usare l'app.

Fra l'app e Home Assistant i dati passano dal relay di gdanav cifrati da un
capo all'altro (AES-256-GCM): la chiave la conoscono solo il telefono e la tua
Home Assistant, il relay sposta buste che non può aprire e non conserva
niente. Home Assistant chiama fuori, non si apre nessuna porta di casa. I
dettagli sono in [`docs/protocollo.md`](docs/protocollo.md).

## Per chi sviluppa

### Cosa c'è qui

| Cartella | Cosa | Linguaggio |
| --- | --- | --- |
| [`packages/gdanav_core`](packages/gdanav_core) | Il motore: consumi, soste di ricarica, percorso, colonnine, distributori, traffico, meteo, segnalazioni, sorgenti dei dati dell'auto, protocollo con Home Assistant | Dart puro |
| [`packages/gdanav_app`](packages/gdanav_app) | Lo schermo: mappa, guida, Premium, abbinamento con Home Assistant, Android Auto e CarPlay. Lo usano l'app e gdahome | Flutter, Kotlin, Swift |
| [`app`](app) | L'app Android e iPhone: l'involucro del pacchetto qui sopra ([iPhone e CarPlay](docs/ios.md)) | Flutter |
| [`custom_components/gdanav`](custom_components/gdanav) | L'integrazione Home Assistant, da installare con HACS | Python |
| [`relay`](relay) | Il punto d'incontro fra Home Assistant e l'app, cifrato end-to-end; le segnalazioni, i codici di abbinamento, la versione minima, la [privacy](https://gdanav.gdahome.org/privacy) | Cloudflare Worker |
| [`valhalla`](valhalla) | Il nostro server dei percorsi, per Oracle Cloud Always Free | Docker + Caddy |
| [`docs`](docs) | [Architettura](docs/architettura.md), [protocollo](docs/protocollo.md), [iPhone](docs/ios.md), vettore di prova condiviso | |

`custom_components/` e `hacs.json` stanno nella radice perché HACS li cerca
lì: questa repository si aggiunge a HACS così com'è.

Il calcolo sta sul telefono; il server fa solo percorsi e community, il resto
viene da servizi gratuiti. Il perché e i pezzi sono in
[`docs/architettura.md`](docs/architettura.md).

### Come si prova

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

### Pubblicare e pagamenti

Le build escono dalla CI (`.github/workflows/prove.yml`): Android per il Play
Store, iPhone per TestFlight e l'App Store ([`docs/ios.md`](docs/ios.md)).
Come si accendono i pagamenti (`GDANAV_PAGAMENTI`) e come si fermano le
versioni vecchie (`VERSIONE_MINIMA_APP` nel relay) è in
[`docs/architettura.md`](docs/architettura.md#fermare-le-versioni-vecchie).
I prezzi stanno nei negozi, non nel codice; le licenze e i codici regalo passano dal
quadro delle licenze di gdahome (`docs/LICENZE.md` in gdahomeapp).

### A che punto è

Fatto: tutto quello che c'è sopra, su Android, iPhone, Android Auto e CarPlay,
da soli e dentro gdahome. I percorsi li calcola per ora il Valhalla pubblico di
FOSSGIS; le colonnine vengono da Open Charge Map e OpenStreetMap, il loro stato
da TomTom.

Da fare: accendere il nostro Valhalla su Oracle ([`valhalla/`](valhalla),
scritto ma non ancora provato su una macchina vera); collegare la PUN (il
client OCPI c'è, manca l'indirizzo vero); il permesso di CarPlay da Apple
([`docs/ios.md`](docs/ios.md#carplay-il-permesso-di-apple)).

### Da citare

«© OpenStreetMap contributors», «© Open Charge Map contributors», OpenFreeMap
per la mappa, TomTom per traffico e colonnine in tempo reale, MET Norway per
il meteo, MIMIT per i prezzi dei carburanti.

## Licenza

Il codice è pubblico perché si possa leggere e controllare cosa fa con
l'auto, la posizione e i dati di chi lo usa. Non è open source:
[licenza proprietaria](LICENSE), tutti i diritti riservati. Si può
installare e usare per sé; non si può ripubblicare, distribuire modificato o
usare commercialmente senza permesso scritto.
