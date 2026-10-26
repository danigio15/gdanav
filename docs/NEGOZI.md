# GdANav nei negozi

Come GdANav arriva sul Play Store e sull'App Store **da sola**, per chi la
vuole senza GdAHome: un navigatore con Premium in abbonamento e, per chi ce
l'ha, Home Assistant collegato con l'integrazione di questa repository.

Il codice sa già tutto quello che serve. Quello che manca sta **fuori dalla
repository**: due account sviluppatore, una chiave, qualche segreto, e le
schede dei negozi. Questa pagina dice cosa, dove, e in che ordine.

## Com'è fatta la pubblicazione

| Cosa | Dove |
| --- | --- |
| Il nome dell'app nei negozi | `it.gdanav.gdanav`: `applicationId` in `app/android/app/build.gradle.kts`, `PRODUCT_BUNDLE_IDENTIFIER` in Xcode, `COME_SI_CHIAMA` in `tools/porta-nel-negozio.mjs` |
| Il workflow che pubblica | `.github/workflows/negozi.yml`, «GdANav nei negozi»: a mano o a ogni etichetta `v*` |
| Il workflow di ogni push | `.github/workflows/prove.yml`, «Le prove»: compila firmato d'anteprima (`it.gdanav.gdanav.prova`), e su `main` manda l'iPhone su TestFlight |
| Lo strumento del Play Console | `tools/porta-nel-negozio.mjs`: carica l'`.aab`, lo mette sulla pista, consegna, e riguarda che ci sia davvero |
| Le novità di ogni versione | `app/negozio/it-IT.txt` e `en-US.txt`, al massimo 500 caratteri: vanno nel negozio con il pacchetto |
| Le schede dei negozi | `docs/negozio/it-IT.md` e `en-US.md`: titolo, descrizioni, parole chiave, da incollare una volta |
| Le grafiche | `docs/logo/play_icona_512.png`, `docs/logo/play_evidenza_1024x500.png`, `docs/logo/logo_1024.png` (App Store) |
| Il numero di build | `tools/numero-di-build.sh`: i minuti dal 1970, uguale per tutti i workflow, cresce sempre |
| La versione | L'etichetta: `v1.0.0` → `1.0.0` nei negozi. A mano, quella di `app/pubspec.yaml` |
| Premium | Si vende solo con la variabile `GDANAV_PAGAMENTI = si`; senza, ogni pacchetto esce con Premium per tutti e «production» si ferma |
| Le versioni vecchie | `VERSIONE_MINIMA_APP` in `relay/wrangler.toml`: le build sotto quel numero chiedono di aggiornarsi |

Due chiavi per Android, e la differenza conta. Quella **d'anteprima**
(`app/android/app/anteprima.jks`) sta nella repository con la sua parola, e
non è un segreto: firma solo i pacchetti `.prova`, che sono un'app a parte e
non si installano sopra quella dei negozi. Quella **vera** la si fa una volta,
sta nei segreti di GitHub, e un pacchetto `release` col nome vero si firma
solo con lei: se manca, Gradle si ferma subito e lo dice.

## Play Store

### 1. L'account e l'app

1. Un account sviluppatore Google Play (25 $ una volta sola). Un account
   personale nuovo deve fare una **prova chiusa con almeno 12 collaudatori
   per 14 giorni** prima di poter chiedere la produzione: va messa in conto.
2. Play Console → **Crea app**: nome «GdANav», lingua italiano, app, gratis.
   Il nome del pacchetto lo prende dal primo `.aab` caricato:
   `it.gdanav.gdanav`.
3. **Firma dell'app da Google Play** (Play App Signing): accettarla. Google
   tiene la chiave di firma; noi diamo solo una **chiave di caricamento**,
   che è quella qui sotto. Se un giorno si perde si può chiedere di
   cambiarla.

### 2. La chiave di caricamento

Una volta sola, su un computer, e **non** nella repository:

```sh
keytool -genkeypair -v -keystore gdanav.jks -alias gdanav \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=GdANav, O=CRV Immobiliare S.r.l., L=Napoli, C=IT"
```

Alla domanda della parola della chiave, **INVIO**: così portachiavi e chiave
hanno la stessa parola e basta un segreto. Il file `gdanav.jks` si conserva
in un posto sicuro (gestore di password): senza, la prossima versione non si
carica finché Google non accetta una chiave nuova.

I segreti su GitHub, nell'ambiente **`negozio`** (Settings → Environments →
New environment, nome `negozio`; lì dentro i segreti, e si può chiedere che
ogni corsa la approvi il proprietario):

| Segreto | Cosa |
| --- | --- |
| `CHIAVE_ANDROID` | Il portachiavi in base64: `base64 -w0 gdanav.jks` (su Mac `base64 -i gdanav.jks`) |
| `CHIAVE_ANDROID_PASSWORD` | La parola del portachiavi |
| `CHIAVE_ANDROID_ALIAS` | Solo se la chiave non si chiama `gdanav` |
| `CHIAVE_ANDROID_KEY_PASSWORD` | Solo se la parola della chiave è diversa da quella del portachiavi |

Il workflow controlla tutte e quattro le cose con `keytool` **prima** di
costruire, e se una non va lo dice con parole sue.

### 3. Il credenziale del Play Console

Lo strumento parla col negozio con un **account di servizio** di Google
Cloud:

1. [console.cloud.google.com](https://console.cloud.google.com) → un
   progetto (anche quello di GdAHome) → **API e servizi → Libreria** →
   abilitare **Google Play Android Developer API**.
2. **IAM → Account di servizio → Crea**: nome `negozio-gdanav`. Nella sua
   scheda, **Chiavi → Aggiungi chiave → JSON**: scarica il file.
3. Play Console → **Utenti e autorizzazioni → Invita nuovi utenti**: la
   posta dell'account di servizio (`…@….iam.gserviceaccount.com`), con i
   permessi **Rilascia app nelle tracce di test** e, quando sarà, **Rilascia
   in produzione** sull'app GdANav. L'invito ci mette fino a un giorno a
   valere: un `invalid_grant` o un 403 nelle prime ore è normale.
4. Il JSON, così com'è o in base64, nel segreto **`NEGOZIO_GOOGLE`**
   dell'ambiente `negozio`.

Per vedere che funzioni senza pubblicare niente: Actions → «GdANav nei
negozi» → Run workflow con **elenca_le_piste** spuntato. Poi con la pista
`internal` e **prova_del_negozio** spuntato: fa tutto il giro e butta la
modifica.

### 4. La scheda, prima della prima versione

Il Play Console non accetta la prima versione finché la scheda non è
completa. Tutto quello che chiede:

- **Scheda dello Store**: titolo, descrizione breve e completa da
  `docs/negozio/it-IT.md` (e la traduzione da `en-US.md`); icona
  `docs/logo/play_icona_512.png`; grafica in evidenza
  `docs/logo/play_evidenza_1024x500.png`; **almeno 2 schermate del
  telefono** fra 320 e 3840 px per lato, con proporzione fra 16:9 e 9:16
  (le immagini in `docs/immagini/` sono 420×909, troppo strette: vanno
  rifatte sul telefono o sull'emulatore, in verticale, per esempio
  1080×2340). Per Android Auto il negozio vuole anche le schermate dello
  schermo dell'auto (si fanno con la Desktop Head Unit dell'SDK).
- **Contenuti dell'app → Norme sulla privacy**:
  `https://gdanav.gdahome.org/privacy`.
- **Contenuti dell'app → Sicurezza dei dati**, da dichiarare come fa
  l'app (`app/ios/Runner/PrivacyInfo.xcprivacy` dice le stesse cose per
  Apple):
  - *Posizione precisa*: raccolta, non condivisa con terzi a fini
    pubblicitari, usata per le funzioni dell'app (percorsi, traffico,
    segnalazioni). Esce dal telefono verso i servizi dei percorsi e del
    traffico (Valhalla, TomTom, HERE) e verso il relay per le segnalazioni
    della comunità: va detto che è **condivisa** con fornitori di servizi.
  - Niente account, niente identificatori, niente dati raccolti a fini
    pubblicitari o di analisi.
  - I dati viaggiano cifrati (TLS; con Home Assistant anche la busta).
  - Si possono chiedere la cancellazione? Non c'è niente da cancellare:
    l'app non ha account. Lo si dice.
- **Contenuti dell'app → Annunci**: no.
- **Contenuti dell'app → Classificazione dei contenuti**: il questionario,
  categoria «Utilità, produttività, comunicazione o altro».
- **Contenuti dell'app → Pubblico di destinazione**: 18 e più (c'è un
  abbonamento e si usa in auto).
- **Contenuti dell'app → Android Auto**: va dichiarata. Categoria
  **Navigazione**; serve la **schermata dell'app in auto** e la conferma che
  segue le regole (niente video, niente testo lungo mentre si guida). Google
  la rivede a parte, e può metterci qualche settimana: finché non è
  approvata, in auto l'app compare solo dalla pista di test interna con la
  **modalità sviluppatore** di Android Auto («Origini sconosciute»).
- **Contenuti dell'app → App per il governo / finanziarie / sanitarie**: no.
- **Autorizzazioni sensibili**: la posizione **in primo piano** soltanto
  (l'app non chiede `ACCESS_BACKGROUND_LOCATION`); il Bluetooth per il
  dongle OBD, dichiarato `neverForLocation`. Se un giorno si aggiunge un
  servizio in primo piano per guidare a schermo spento, va dichiarato qui.

### 5. Premium nel Play Console

L'app cerca l'abbonamento `gdanav_premium` con due **piani base** e, per
ciascuno, un'offerta di prova (`packages/gdanav_app/lib/stato/gestore_premium.dart`):

| Cosa | Nome | Prezzo |
| --- | --- | --- |
| Abbonamento | `gdanav_premium` («GdANav Premium») | |
| Piano base | `mensile`, rinnovo ogni mese | 2,99 € |
| Piano base | `annuale`, rinnovo ogni anno | 29,99 € |
| Offerta su ogni piano | prova gratuita 14 giorni, una volta per utente | |

Monetizza → Prodotti → Abbonamenti. I prezzi negli altri paesi li converte
Google. Serve un **profilo pagamenti** del venditore (CRV Immobiliare
S.r.l.) e, per l'Italia, la partita IVA. Finché `GDANAV_PAGAMENTI` non è
«si», l'app non apre il negozio e Premium è di tutti: il giorno che si
accende, in `relay/wrangler.toml` si mette in `VERSIONE_MINIMA_APP` il numero
della prima build a pagamento, così le build di prova con Premium per tutti
chiedono di aggiornarsi.

Per provare gli acquisti senza pagare: Play Console → Impostazioni →
**Test delle licenze**, le poste dei collaudatori.

### 6. Pubblicare

1. `git tag v1.0.0 && git push origin v1.0.0` (dalla `main` verde).
2. «GdANav nei negozi» parte da sola: firma con la chiave vera, costruisce
   l'`.aab` e, se c'è la variabile **`PISTA_DEL_NEGOZIO`** (Settings →
   Variables, per esempio `internal`), lo carica e lo mette su quella pista
   con le novità di `app/negozio/`. Senza variabile costruisce e basta.
3. Per portare **la stessa** build su un'altra pista (da `internal` a
   `production`) non si ricarica: si promuove dal Play Console, oppure si
   rilancia a mano lo strumento con `--pista=production --davvero`.
4. A mano, Run workflow: la casella **negozio** dice la pista;
   **production** vuole anche la spunta **davvero_in_produzione**.

Il riepilogo della corsa dice con quale chiave ha firmato, quale versione
e numero, se Premium è in vendita, e cosa ha risposto il negozio.

## App Store

### 1. L'account e l'app

1. Apple Developer Program (99 €/anno), come persona giuridica (serve il
   D-U-N-S di CRV Immobiliare S.r.l.) per vendere abbonamenti a nome
   dell'azienda.
2. [developer.apple.com](https://developer.apple.com) → Certificates,
   Identifiers & Profiles → **Identifiers → App IDs → `it.gdanav.gdanav`**
   con le capacità **In-App Purchase** e, quando concessa, **CarPlay**.
3. App Store Connect → **Le mie app → +**: nome «GdANav», bundle
   `it.gdanav.gdanav`, SKU `gdanav`.
4. **Contratti**: quello degli **Accordi a pagamento** (Paid Applications) va
   firmato e completato con banca e dati fiscali, altrimenti gli abbonamenti
   non si vedono nemmeno in sandbox.

### 2. I segreti

App Store Connect → Utenti e accesso → **Integrazioni → Chiavi API App
Store Connect** → una chiave con ruolo **App Manager**. Nell'ambiente
`negozio` di GitHub:

| Segreto | Cosa |
| --- | --- |
| `APPLE_CHIAVE_P8` | Il contenuto del file `AuthKey_XXXXXXXXXX.p8` |
| `APPLE_CHIAVE_ID` | L'ID della chiave (le dieci lettere nel nome del file) |
| `APPLE_EMITTENTE` | L'Issuer ID, scritto in cima alla pagina delle chiavi |
| `APPLE_SQUADRA` | Il Team ID (Membership, dieci caratteri) |

Sono gli stessi che «Le prove» usa già per mandare l'iPhone su TestFlight
da `main`: se sono nei segreti del repository, nell'ambiente `negozio` si
possono anche ripetere uguali. Certificato e profilo di distribuzione li
tiene Apple: il workflow archivia senza firma e firma esportando con la
chiave, non serve niente sul computer.

### 3. CarPlay

CarPlay per le app di navigazione si chiede ad Apple:
[developer.apple.com/contact/carplay](https://developer.apple.com/contact/carplay),
categoria **Navigation (Maps)**. Rispondono in qualche settimana. Quando
l'entitlement compare sull'App ID, la variabile **`GDANAV_CARPLAY = si`** lo
mette nella firma (`app/ios/Runner/RunnerCarPlay.entitlements`). Prima no:
la firma non passerebbe.

### 4. Premium su App Store Connect

Sull'App Store ogni piano è un prodotto a sé, nello stesso **gruppo di
abbonamenti**:

| Cosa | Nome | Prezzo |
| --- | --- | --- |
| Gruppo | «GdANav Premium» | |
| Abbonamento con rinnovo automatico | `gdanav_premium_mensile`, 1 mese | 2,99 € |
| Abbonamento con rinnovo automatico | `gdanav_premium_annuale`, 1 anno | 29,99 € |
| Offerta introduttiva su entrambi | gratis per 2 settimane | |

Per ogni prodotto servono il nome visibile, una descrizione e una schermata
della scheda Premium dell'app (anche una qualsiasi, serve alla revisione).
I prodotti si mandano in revisione **insieme alla prima versione**
dell'app, dalla pagina della versione. Per provare: Utenti e accesso →
**Sandbox → Tester**, un Apple ID apposta.

### 5. La scheda e la revisione

- **Informazioni sull'app**: nome, sottotitolo (30 caratteri), categoria
  principale **Navigazione**, secondaria Viaggi; classificazione per età
  4+ (nessun contenuto); URL privacy `https://gdanav.gdahome.org/privacy`.
- **Privacy dell'app** (le etichette): coerenti con
  `app/ios/Runner/PrivacyInfo.xcprivacy` — *Posizione precisa* per
  funzionalità dell'app, non collegata all'utente, non usata per
  tracciare; nient'altro. «Dati non raccolti» non si può dire: la posizione
  esce verso i servizi dei percorsi.
- **Versione**: testo promozionale (170), descrizione, parole chiave (100),
  URL di supporto (`https://github.com/danigio15/gdanav/issues` o il sito),
  novità (le stesse di `app/negozio/`). Tutto in `docs/negozio/`.
- **Schermate**: obbligatorie per iPhone 6,9" (**1290×2796** o 1320×2868)
  e, se l'app gira su iPad (lo fa), per iPad 13" (2064×2752). Le immagini in
  `docs/immagini/` non bastano: si fanno sul simulatore (Xcode → Simulator →
  iPhone 17 Pro Max → ⌘S) con l'app in release.
- **Informazioni per la revisione**: non serve un accesso (niente account).
  Conviene scrivere che Home Assistant è facoltativo e richiede un server
  dell'utente, e allegare un **video** di un viaggio con la voce e, se
  concesso, di CarPlay: Apple prova la navigazione sul serio, e un
  revisore seduto in ufficio non può guidare.
- **Esportazione**: `ITSAppUsesNonExemptEncryption` è già `false` in
  `Info.plist` (si usa solo la crittografia del sistema): nessun modulo da
  compilare a ogni build.

### 6. Pubblicare

Con l'etichetta `v1.0.0` parte anche il lavoro **iPhone (TestFlight)** di
«GdANav nei negozi»: archivia, firma, carica. Su un'etichetta senza i
quattro segreti di Apple si ferma in rosso: un rilascio a metà non si fa.
La build compare in TestFlight dopo qualche minuto; da App Store Connect →
versione → **Build**, la si sceglie e si manda in revisione. A mano, Run
workflow con **testflight** spuntato.

## Per chi ha solo GdANav

Nel README è già scritto tutto quello che serve a chi non ha GdAHome:
l'app dal negozio, Premium in abbonamento o con un codice regalo,
l'integrazione di Home Assistant da HACS. Due cose da ricordare quando si
pubblica:

- Il sito di GdAHome (`sito/` in danigio15/gdahomeapp) dice oggi che GdANav
  sta solo dentro GdAHome: quando l'app è nei negozi, lì vanno i due link.
- L'integrazione Home Assistant resta un repository personalizzato di HACS.
  Per entrare nell'elenco di serie di HACS serve la richiesta nel repository
  `hacs/default`: si fa dopo, con l'app nei negozi.

### Il logo dell'integrazione in Home Assistant

Home Assistant non legge il logo dal codice dell'integrazione: lo prende
da [home-assistant/brands](https://github.com/home-assistant/brands), e
finché non c'è scrive «icon not available» nella pagina dell'integrazione
e in HACS. Le immagini sono pronte in `docs/logo/brands/`: `icon.png`
(256×256), `icon@2x.png` (512×512), `logo.png` e `logo@2x.png`. Si apre una
pull request su quel repository che le mette in
`custom_integrations/gdanav/` (la cartella delle integrazioni
personalizzate, non `core_integrations`), con il nome della cartella uguale
al dominio, `gdanav`. Dopo l'unione il logo compare da solo, senza toccare
niente qui: Home Assistant lo scarica da `brands.home-assistant.io`.

## Il numero di build

I negozi vogliono un numero che **cresca sempre** (`versionCode` su Android,
`CFBundleVersion` su iPhone). Prima era il numero della corsa di «Le
prove»; un workflow nuovo riparte da 1, e TestFlight avrebbe rifiutato la
prima build di «GdANav nei negozi». Adesso è lo stesso per tutti i
workflow: i minuti passati dal 1° gennaio 1970 (`tools/numero-di-build.sh`,
circa 29.900.000 nel 2026), che stanno sotto il tetto del Play Store. Lo
stesso numero entra nell'app come `GDANAV_COSTRUZIONE`, ed è quello con cui
`VERSIONE_MINIMA_APP` del relay decide chi deve aggiornarsi.
