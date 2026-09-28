# Da dove vengono le colonnine

Questo documento esiste perché la domanda «perché al Centro Direzionale di
Napoli l'app mostra sette colonnine e le altre app ne mostrano dodici» ha
richiesto una giornata di misure, e la risposta non si deve riscoprire.

Tutto quello che c'è qui è **misurato**, non supposto: le sonde in `tools/`
lo rifanno quando serve, e scrivono i risultati nella release «lavoro».

## Cosa usa gdanav, oggi

| fonte | cosa dà | dove |
|---|---|---|
| archivio nell'APK | anagrafica, offline: OpenStreetMap + PUN | `packages/gdanav_app/assets/colonnine.json` |
| relay di gdanav | anagrafica, fuori archivio | `ClienteColonnineRelay` |
| Open Charge Map | anagrafica, con la chiave | `ClienteOpenChargeMap` |
| Overpass | anagrafica, riserva lenta | `ClienteOverpass` |
| TomTom Search | stato in tempo reale | `DisponibilitaTomTom` |

Le prime quattro **si sommano** (`FonteColonnineUnite`): prima era una
catena che si fermava alla prima che rispondeva, e bastava che Open Charge
Map rispondesse per perdere tutto il resto.

Il relay nasce da **OpenStreetMap**. L'archivio anche, e in più ha i posti
della **Piattaforma Unica Nazionale** (vedi «La PUN, dentro l'archivio»):
è lì che ci sono le colonnine che OpenStreetMap non ha.

## Il difetto del filtro, e quanto valeva

Fino a oggi archivio e Overpass tenevano solo le colonnine «rapide»: prese
CCS/CHAdeMO/Tesla scritte nei tag, **oppure** un operatore fra sedici nomi
in elenco. Una Type 2 da 22 kW in città non entrava proprio nei dati.

Tolto il filtro, l'archivio passa da **6.812 a 20.832** colonnine (da 558
a 1.607 kB). A togliere le troppo lente ci pensa la potenza minima, dove
la sceglie chi guida: il percorso filtra a 40 kW, il pianificatore a 50
(dalle preferenze), «colonnine vicine» non filtra.

**Ma non era il difetto del Centro Direzionale**, e questo è il punto che
costa più tempo capire:

```
Centro Direzionale, entro 1200 m
  OpenStreetMap        4 stazioni   (con la vecchia regola ne passavano 4 lo stesso)
                       0 spine mappate a parte (man_made=charge_point)
                       8 prese dai soli socket:*
                       9 prese contando anche capacity
  Open Charge Map      2 stazioni, 4 prese
  archivio gdanav      6 → 7 stazioni, 12 prese
  EVDC / ABRP         ~12 stazioni, 442 prese
```

Lì il filtro non toglieva niente. **Le fonti gratuite quelle colonnine non
ce le hanno.** La Plenitude di Via Domenico Aulisio, con le sue 202 prese,
su OpenStreetMap non esiste.

### Contare le spine invece delle stazioni

Domanda giusta, e misurata: nell'archivio le 20.832 stazioni fanno **39.120
prese**, di cui 16.898 da 40 kW in su. Contare le spine raddoppia il numero
in generale — ma al Centro Direzionale porta da 8 a 9, contro 442. Lì non è
un problema di conteggio.

Cercando lì però sono usciti **due difetti veri**, che altrove contano:

* `_prese` tagliava a **venti** qualunque numero (`clamp(1, 20)`): una
  stazione grande veniva mutilata. Il tetto adesso è 400;
* **`capacity` era ignorato**. Quando le prese non sono scritte una per una
  si creava un connettore solo, e per una colonnina da otto stalli era una
  bugia. Al Centro Direzionale **2 stazioni su 4** hanno `capacity` scritto.

E una strada chiusa con la misura: **`man_made=charge_point`**, il tag con
cui in OpenStreetMap si mappano le singole spine dentro un impianto, lì non
lo usa nessuno — **zero**. Non lo stavamo buttando via: non c'è.

## La PUN, dentro l'archivio

La Piattaforma Unica Nazionale dei punti di ricarica (MASE) raccoglie per
legge i punti di ricarica pubblici. **onData** ne ha pubblicato
un'estrazione in CSV, con licenza **CC BY 4.0**, nel repository
[`ondata/rete_ricarica_veicoli_elettrici`](https://github.com/ondata/rete_ricarica_veicoli_elettrici)
(`data/pdr_latest_ready.csv`). È ferma all'ottobre 2024: poi la PUN ha
cambiato il modo di pubblicare e la loro estrazione si è rotta.

`Pun.leggiCsv` (nel nucleo) la legge; `tool/colonnine_pun.dart` la fonde
con l'archivio di OpenStreetMap usando `fondiColonnine`, e il lavoro
`[colonnine]` in CI lo fa da solo dopo gli estratti di Geofabrik.

```
OpenStreetMap     20.832 stazioni   39.120 prese
PUN (onData)      20.158 posti      44.874 punti di ricarica
  nella stessa posizione in tutte e due   4.541
  solo nella PUN                         15.617
archivio          36.449 stazioni   78.393 prese   1,6 → 3,6 MB

Centro Direzionale, entro 1200 m
  prima            4 stazioni     9 prese
  dopo            14 stazioni   841 prese
    Isola A3 202 · P5 Via Domenico Aulisio 194 · L1 144 · L2 135 · L3 112
    · Volta-Brin 41 (Plenitude/Be Charge, tutte a 22 kW) · le Enel X
```

Sono gli stessi numeri di ABRP ed EVDC: il «189/202» di ABRP ha il totale
dell'Isola A3, i 194 di EVDC sono il P5.

**Poi la PUN di oggi.** Il 28 settembre 2026 il lavoro `[colonnine]` l'ha
letta dall'API del portale (`tools/pun/estrai.py`, vedi più sotto), in 765
richieste, e da allora l'archivio è questo:

```
PUN (API, oggi)   75.761 punti sulla mappa
                  29.975 posti      71.432 punti di ricarica (tolti i
                                    pianificati, i rimossi e le prese da scooter)
OpenStreetMap     20.832 stazioni   59.055 prese
  nella stessa posizione in tutte e due   5.403
  solo nella PUN                         24.572
archivio          45.404 stazioni  120.758 prese   6,4 MB (con gli EVSE ID)

Centro Direzionale, entro 1200 m: 855 punti in 14 posti
  Isola A3 202 · Via Domenico Aulisio 20 194 · Viale della Costituzione 12
  144 · Isola G8 135 · Via Giovanni Porzio 4 112 · Volta-Brin 40 · …
```

Gli operatori hanno il nome dell'azienda (Enel X, Plenitude, Repower, A2A
E.Mobility, Hera Comm, Acea Energia…), e ogni posto ha gli EVSE ID dei suoi
punti: servono a chiedere alla PUN lo stato di adesso. La citazione è
«PUN (GSE), CC BY 4.0».

Le regole, tutte con una prova in `test/pun_test.dart`:

* **Una riga è un punto di ricarica**, cioè un'auto alla volta: se ha più
  spine (CCS e CHAdeMO) se ne tiene la migliore, perché contarle tutte
  direbbe due auto dove se ne carica una.
* **PLANNED e REMOVED si saltano**; le prese da scooter (Tipo 3A), Schuko e
  Tipo 1 non sono per queste auto.
* **Lo stato non si usa**: è una fotografia del 2024, e una presa guasta
  allora oggi può andare.
* **Il nome è spesso una matricola** (`18XM32T77B3W000013`, `LOC69618`):
  lì si mostra l'indirizzo.
* **L'operatore** è il codice in mezzo all'EVSE ID (`IT*BEC*EW003907*1` →
  BEC, Be Charge), ma solo se è di tre caratteri come vuole lo standard.
* **La licenza chiede di citarla**: «PUN (GSE), CC BY 4.0» compare nella
  scheda della colonnina, nel dettaglio e nella scheda del viaggio
  (`creditoColonnina`). Con la fotografia di onData era «PUN (MASE),
  elaborazione onData, CC BY 4.0»: se il lavoro torna a onData perché
  l'API non risponde, va rimessa quella.

Con i 22 kW del Centro Direzionale è venuto fuori anche un difetto della
scelta della potenza: **«Tutte» valeva 22 kW**, e 5.758 posti dell'archivio
(le 11, 15, 20 kW, le Enel X da 21) non si vedevano mai. Adesso «Tutte»
intorno a te vuol dire tutte; per le soste del viaggio il minimo resta 22.

## Perché le altre app le hanno

Dalla scheda di EVDC esce l'identificativo `IT*PLN*EW002913*1`: paese,
operatore (PLN, Plenitude), stazione, presa. È un **EVSE ID eMI3/OCPI**.
Quei dati circolano via OCPI fra operatori e fornitori di servizi, e
`Ocpi.leggiLocations` li sa già leggere — manca solo l'indirizzo.

ABRP compra da **Eco-Movement** (aggregatore commerciale), e ci aggiunge
Open Charge Map, GoingElectric e Uppladdning.

## Le strade che abbiamo escluso, con la prova

**Le porte OCPI non si indovinano.** `tools/sonda_ocpi.py` prova i sette
percorsi di scoperta standard sui domini di dodici operatori italiani:
**zero porte**. Un 403 di Be Charge sembrava una porta, ma il sito
risponde 403 anche a un indirizzo inventato: è il suo firewall. Gli
endpoint OCPI stanno su host separati e si ricevono in accreditamento.

**La PUN, cercandola a mano, sembrava non esporre niente.** `tools/sonda_pun.py`:

* `/ocpi/versions` e fratelli → HTTP 200 di 1371 byte, la pagina del sito
  (il server risponde così a **qualunque** percorso sconosciuto: attenzione,
  fa sembrare che qualcosa esista);
* il portale è React su AWS, la mappa è Esri **ArcGIS 4.31** caricata dal
  CDN — ma nel bundle **non c'è nessun FeatureServer**;
* nei 3 MB di codice non compare nessun dominio di backend: l'API è sullo
  stesso dominio e i suoi percorsi sono composti a runtime, non scritti in
  chiaro. Tutti i percorsi che si trovano (`/api/v1/documents`, `/maps/v0/…`,
  `/restapis/…`, `getClip`, `BatchDescribeEntities`) sono modelli interni
  dell'**SDK di AWS** impacchettato dentro, non chiamate dell'applicazione.

L'ArcGIS `services9.arcgis.com/Iko2iF79CuZQnhht` incontrato per strada non
c'entra: i suoi 51 servizi sono la Route 66, le Crociate e la Valle dei
Templi. È un inquilino del turismo.

**Poi l'ha trovata un browser.** L'API non è sullo stesso dominio del sito,
e per questo cercarla lì non dava niente: è su
`api.pun.piattaformaunicanazionale.it`. `tools/pun/cattura.mjs` apre la
mappa pubblica con un browser automatico, come la apre chiunque, e scrive le
chiamate che la pagina fa (`pun_api.txt` nella release «lavoro»):

```
GET  /v1/chargepoints/public/count          → {"Idrs":75765}
POST /v1/chargepoints/public/map/search     {"page":0,"size":12000} … fino a page 6
     → content: [{status, coordinates:{latitude,longitude}, evse_id}, …]
       status: AVAILABLE, CHARGING, UNKNOWN, …  ← lo stato di adesso
POST /v1/chargepoints/group                 ["IT*ENX*E24…*2", …]
     → [{location:{address, city, coordinates, party_id, parking_type,
                    opening_times, …}, …}]
GET  /v1/companies/list?status=APPROVED     → {"BEC": "…", "ENX": "…", …}
GET  /v1/tariffs/price-range                → {"min":0.0,"max":0.85}
```

Ogni richiesta è **firmata AWS** (`authorization`, `x-amz-date`,
`x-amz-security-token`, cioè credenziali provvisorie che la pagina si
procura da sola). Oggi i punti sono **75.765**, contro i 48.916 della
fotografia di onData: ne manca più di un terzo, e ogni punto ha lo stato di
adesso.

**Nel lavoro di CI sì, nell'app no.** AgID — l'Agenzia per l'Italia
Digitale — nel suo Cruscotto Italia
([`AgID/cruscotto-italia`](https://github.com/AgID/cruscotto-italia),
`etl/sources/pun.py`) legge l'intera PUN ogni giorno da questa API, con le
credenziali ospite che il sito pubblica in `/config.json`, e la pubblica
come **CC BY 4.0** per l'art. 52 c. 2 del CAD («open data by default») e
le Linee Guida Open Data AgID, citando «GSE — Piattaforma Unica Nazionale».
Da giugno 2026 il bottone «Esporta dati» non c'è più: l'API è l'unica
strada. Giovanni ha scelto di fare lo stesso per l'archivio.

`tools/pun/estrai.py` lo fa quando si rifà l'archivio (commit con
«[colonnine]»): le pagine della mappa come le chiede il sito, i dettagli a
blocchi di cento con una pausa, un CSV nel formato di `Pun.leggiCsv` con in
più il nome dell'azienda. Se l'API non risponde si torna alla fotografia di
onData, con un avviso: in quel caso la citazione nell'app va cambiata.

Nell'app invece no: ogni telefono che chiede a un'API interna del sito è un
carico che il GSE non ha previsto, e una cosa che si può rompere da un
giorno all'altro (è quello che ha fermato onData). Per lo stato in tempo
reale la strada giusta è una sola chiamata dal relay per tutti, o l'accesso
ufficiale: vedi sotto.

La cattura del 28 settembre 2026, contando le risposte della mappa:

```
75.759 punti di ricarica
  liberi 56.742 · fuori servizio 9.097 · in carica 4.630 · senza stato 2.045
  rimossi 1.317 · bloccati 1.214 · non operativi 670 · prenotati 27 · pianificati 17
Centro Direzionale, entro 1200 m: 855
  liberi 724 · fuori servizio 75 · bloccati 51 · in carica 5
```

## Cosa resta da fare, e non è codice

1. **MASE / GSE** — chiedere un accesso in lettura ai dati della PUN
   (75.765 punti oggi, con lo stato di ognuno). L'argomento c'è: dal 14
   aprile 2025 il regolamento AFIR (UE 2023/1804, art. 20) vuole che i dati
   statici e dinamici dei punti di ricarica siano **aperti e gratuiti**
   attraverso il punto di accesso nazionale, e dal 14 aprile 2026 in
   DATEX II. Basta un accesso per il relay: risolve l'Italia intera, stato
   compreso.
2. **Un operatore alla volta** — chiedere credenziali OCPI come eMSP, solo
   `Locations` e `Tariffs`. Gratis, e il codice per leggerle c'è già.
3. **Eco-Movement** — a contratto, copertura come ABRP.

Qualunque credenziale arrivi va nel **relay**, non nell'APK: una sola per
tutti gli utenti, e niente segreti dentro l'applicazione.

## Lo stato in tempo reale

**Dalla PUN, per le colonnine che ne hanno gli EVSE ID** (`DisponibilitaPun`,
nel nucleo). La PUN dà lo stato punto per punto, quindi l'archivio tiene gli
EVSE ID di ogni posto (l'ottavo campo), e l'app li chiede alla PUN come la
sua mappa pubblica: credenziali ospite di Cognito (nessun login) e una
richiesta firmata SigV4 a `/v1/chargepoints/group`, al massimo cento punti
per volta. Lo chiede il telefono, solo per le colonnine che si guardano;
uno stato letto vale un minuto. Giovanni ha scelto l'app e non il relay:
costo zero, e il relay si pubblica solo da `main`.

* La firma è fatta in casa (`firmaSigV4`) e provata sull'esempio ufficiale
  della documentazione di AWS: il primo giro dava un'altra firma, perché
  con il percorso «/» usava un percorso vuoto.
* **`realTime: false` non è «libera»**: per i gestori che non aggiornano
  lo stato, la PUN ripete uno stato fisso. Lì si dice «non si sa».
* `BLOCKED` è occupata: un'auto ferma davanti.
* Se la PUN non risponde, o non conosce più nessuno dei punti, si prova
  TomTom (`DisponibilitaConPun`).

Il 28 settembre 2026 al Centro Direzionale la mappa della PUN diceva 724
libere, 5 in carica, 75 fuori servizio e 51 bloccate su 855.

**TomTom, per le altre.** TomTom Search dà 2.500 chiamate al giorno e ne bruciavamo due per colonnina:
il contatore era a zero e rispondeva 403, che in app diventava «Stato non
comunicato» su ogni colonnina. Adesso dopo un rifiuto si smette di chiedere
per sei ore, e la pastiglia dice quante prese ci sono invece di dire che
non si sa.

Open Charge Map, con la chiave, **non dà lo stato di adesso in Italia**:
degli stati che manda, 165 sono «50 = funziona» e 15 «150 = pianificata».
Quelli che direbbero libera o occupata (10 e 20) sono **zero**.

## Trappole, per chi ci torna

Quattro giri di sonda persi per queste, che sono tutte nostre:

* **Overpass e `around:`** — un raggio gli costa molto più di un rettangolo,
  e due tag in una richiesta raddoppiano. Chiedere `around:` con due tag ha
  prodotto 504 e timeout; un rettangolo per tag risponde subito.
* **Le sonde saltate** — il passo delle sonde girava solo se le prove di
  rete passavano, cioè si spegneva proprio quando serviva. Adesso ha
  `if: always()`.
* **`yaml.safe_load` tollera le chiavi doppie**, GitHub Actions no: un
  `if: always()` scritto due volte ha fatto fallire tutta la corsa con zero
  lavori e il nome sbagliato. Per controllare un workflow serve un lettore
  severo, non quello tollerante.
* **L'attesa dell'unione** era venti secondi: il relay di solito risponde in
  un decimo di secondo, ma in una giornata storta ci mette un minuto, e
  l'unione tornava vuota. Adesso aspetta sessanta, quanto il relay si dà da
  solo.

E tre dai dati veri della PUN, che un CSV di prova inventato non avrebbe
avuto:

* **La potenza può essere una lista** — `150000,62500` per una colonnina
  con CCS e CHAdeMO. Letta come un numero solo diventava zero, e si
  perdevano proprio le rapide doppie.
* **Il codice operatore non è sempre di tre caratteri** — c'è anche
  `IT*REVEPGS564*1*2`. Prenderlo com'è vorrebbe dire inventare un operatore.
* **Il sito della PUN risponde 200 a qualunque indirizzo** — con la sua
  pagina: fa sembrare che esista quello che non esiste. E la sua API sta
  su un altro dominio, `api.pun.…`: cercarla sul dominio del sito non
  poteva trovarla.
