# gdanav su iPhone

Quello che su Android c'è, su iPhone c'è uguale: la mappa, la guida con la
voce, le soste, il dongle OBD, Home Assistant, Premium e lo schermo dell'auto,
che qui è **CarPlay**. Questa pagina dice cosa è già nel codice, cosa si fa una
volta sola dalla parte di Apple, e come esce una versione.

## Cosa c'è nel codice

| Su Android | Su iPhone | Dove |
| --- | --- | --- |
| Android Auto (`auto/*.kt`) | CarPlay, stessi schermi e stesso canale `gdanav/schermo_auto` | `packages/gdanav_app/ios/gdanav_app/Sources/gdanav_app` |
| Un motore Flutter per telefono e auto (`MotoreFlutter.kt`) | Lo stesso: acceso all'avvio in `AppDelegate`, e la schermata del telefono lo prende da lì | `app/ios/Runner` |
| Premium dal Play Store | Premium dall'App Store (StoreKit 2) | `stato/gestore_premium.dart` |
| Permesso Bluetooth per il dongle OBD | Lo chiede iOS da sé alla prima ricerca | `sorgenti/canale_ble.dart`, `GdanavAppPlugin.swift` |
| La posizione in guida (`AndroidSettings`) | `AppleSettings` per l'auto, anche con CarPlay acceso e il telefono in tasca | `stato/posizione.dart` |
| La voce | La voce abbassa la musica e si sente anche a schermo spento | `stato/voce.dart` |
| Diagnosi di Android Auto | Cosa controllare se gdanav non compare in CarPlay | `schermate/diagnosi_auto.dart` |

Il progetto iOS è **solo iPhone** (niente iPad: meno schermate da preparare e
una revisione in meno), dall'iOS 15, con il privacy manifest
(`PrivacyInfo.xcprivacy`) e la cifratura già dichiarata
(`ITSAppUsesNonExemptEncryption = NO`: è quella standard, X25519/AES-GCM e
HTTPS).

### CarPlay, e cosa è diverso da Android Auto

Gli schermi sono gli stessi: la mappa di gdanav, Cerca, il Menu (Casa, Lavoro,
preferiti e recenti, colonnine o distributori, Segnala, Impostazioni), le
opzioni del percorso, la batteria all'arrivo, «C'è ancora?» dopo una
segnalazione. Tre differenze vengono da Apple, non da noi:

- **Sopra la mappa niente pannelli.** Su Android Auto la scheda della manovra,
  la velocità col limite e la barra con batteria e meteo le disegna gdanav.
  Apple vuole la mappa pulita e la guida nelle sue schede: la manovra, la vista
  dello svincolo o le corsie, la distanza e l'arrivo le mostra CarPlay; gli
  autovelox e le segnalazioni arrivano come avvisi di navigazione; la batteria
  all'arrivo sta nel riepilogo del viaggio. La velocità e il limite in CarPlay
  non si possono mostrare.
- **CarPlay non dà i dati dell'auto** (batteria, velocità, chilometri): restano
  Home Assistant, il dongle OBD e l'inserimento a mano.
- **Niente tocco sulla mappa**: le colonnine e i distributori si scelgono dagli
  elenchi del Menu.

## Una volta sola, dalla parte di Apple

1. **Apple Developer Program** (99 $ l'anno), su
   [developer.apple.com/programs](https://developer.apple.com/programs/).
   L'account è lo stesso per gdanav e gdahome.
2. **L'identificativo dell'app**: Certificates, Identifiers & Profiles →
   Identifiers → `+` → App IDs → `it.gdanav.gdanav`. Capacità: In-App Purchase
   (c'è già di serie).
3. **L'app in App Store Connect**
   ([appstoreconnect.apple.com](https://appstoreconnect.apple.com)) → Le mie
   app → `+` → Nuova app: piattaforma iOS, nome «gdanav», lingua italiano,
   bundle ID `it.gdanav.gdanav`, SKU a piacere (`gdanav`).
4. **La chiave per GitHub**: App Store Connect → Utenti e accesso →
   Integrazioni → App Store Connect API → Chiavi del team → `+`, ruolo
   **App Manager**. Si scarica il file `.p8` (una volta sola: poi Apple non lo
   ridà), e si segnano l'**ID chiave** e l'**ID emittente** scritti in alto.
   L'**ID del team** è in developer.apple.com → Account → Membership.
5. **I quattro segreti** su GitHub, Settings → Secrets and variables →
   Actions (gli stessi valori vanno anche in gdahome):

   | Segreto | Cosa |
   | --- | --- |
   | `APPLE_CHIAVE_P8` | il contenuto del file `.p8`, tutto, righe `BEGIN`/`END` comprese |
   | `APPLE_CHIAVE_ID` | l'ID chiave (10 caratteri) |
   | `APPLE_EMITTENTE` | l'ID emittente (un UUID) |
   | `APPLE_SQUADRA` | l'ID del team (10 caratteri) |

   Certificato e profilo non servono: con la chiave, Xcode se li fa dare da
   Apple a ogni build.

### Premium sull'App Store

In App Store Connect, prima gli **accordi**: Business → Accordo per le app a
pagamento, con banca e dati fiscali. Senza, gli abbonamenti non si vedono
nemmeno in TestFlight.

Poi l'app → Monetizzazione → Abbonamenti → gruppo **«gdanav Premium»**, con
dentro due abbonamenti:

| ID prodotto | Durata | Offerta introduttiva |
| --- | --- | --- |
| `gdanav_premium_mensile` | 1 mese | gratuita, 2 settimane |
| `gdanav_premium_annuale` | 1 anno | gratuita, 2 settimane |

Gli ID devono essere esattamente questi (`idAppStore` in
`gestore_premium.dart`). I prezzi: gli stessi del Play Store. Se la prova non
è di 14 giorni, va cambiato anche `giorniProvaAppStore`: StoreKit dice se la
prova spetta, non quanto dura. La prova spetta una volta per gruppo, e chi
l'ha già usata vede subito il prezzo.

La schermata Premium ha già i due link che Apple vuole accanto a un
abbonamento: la privacy (`https://gdanav.gdahome.org/privacy`) e le condizioni
d'uso (quelle standard di Apple). In App Store Connect, nella scheda
dell'app, va scritto lo stesso indirizzo della privacy.

### CarPlay: il permesso di Apple

CarPlay non si accende da soli: Apple lo concede app per app, e ci mette da
qualche giorno a qualche settimana. Si chiede su
[developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay/),
categoria **Navigation**, per `it.gdanav.gdanav`. Conviene chiederlo subito:
l'attesa è la parte lunga.

Finché non arriva, l'app esce e va su TestFlight lo stesso, **senza CarPlay**:
il permesso è fuori dalla firma (`Runner.entitlements` è vuoto). Quando Apple
risponde di sì:

1. developer.apple.com → Identifiers → `it.gdanav.gdanav`: la capacità
   **CarPlay Navigation** compare fra quelle dell'app. Si spunta.
2. Su GitHub, Settings → Secrets and variables → Actions → **Variables** →
   `GDANAV_CARPLAY` = `si`. Da lì in poi la build usa
   `RunnerCarPlay.entitlements`.

Per provarlo prima, su un Mac: Xcode → Open Developer Tool → Simulator, poi
nel simulatore I/O → External Displays → CarPlay. Nel simulatore il permesso
non serve.

## Come esce una versione

Il lavoro **iphone** delle Prove (`.github/workflows/prove.yml`) gira su un Mac
di GitHub, su main, sulle richieste di unione e a mano:

1. **Compila sempre**, senza firma: se è verde, lo Swift di CarPlay e i plugin
   stanno in piedi. È la prima cosa da guardare: questo codice non si può
   costruire senza un Mac, e la prima volta è lì che si vede.
2. **Con i quattro segreti** firma, e da main (o a mano) manda su
   **TestFlight**. Il numero sale a ogni corsa. Dopo qualche minuto arriva la
   mail di Apple, e dall'app TestFlight sull'iPhone si installa.
3. **Sull'App Store** si va da App Store Connect: si sceglie la build arrivata
   da TestFlight e si manda in revisione. Serve, la prima volta:
   - le **schermate** dell'iPhone da 6,9" (1290 × 2796 o 1320 × 2868): le altre
     misure Apple le ricava da queste;
   - descrizione, parole chiave, sottotitolo, URL di supporto e della privacy;
   - **Privacy dell'app**: posizione precisa (funzionalità dell'app, non
     collegata all'utente, niente tracciamento). Le foto dell'auto restano sul
     telefono e non si dichiarano;
   - la **classificazione per età** (il questionario: tutte «no»);
   - per la revisione, una nota su Home Assistant (facoltativo) e su CarPlay.

I Mac di GitHub contano dieci minuti per ogni minuto, se la repository è
privata: per questo il lavoro non gira a ogni push sui rami.
