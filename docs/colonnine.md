# Da dove vengono le colonnine

Questo documento esiste perché la domanda «perché al Centro Direzionale di
Napoli l'app mostra sette colonnine e le altre app ne mostrano dodici» ha
richiesto una giornata di misure, e la risposta non si deve riscoprire.

Tutto quello che c'è qui è **misurato**, non supposto: le sonde in `tools/`
lo rifanno quando serve, e scrivono i risultati nella release «lavoro».

## Cosa usa gdanav, oggi

| fonte | cosa dà | dove |
|---|---|---|
| archivio nell'APK | anagrafica, offline | `packages/gdanav_app/assets/colonnine.json` |
| relay di gdanav | anagrafica, fuori archivio | `ClienteColonnineRelay` |
| Open Charge Map | anagrafica, con la chiave | `ClienteOpenChargeMap` |
| Overpass | anagrafica, riserva lenta | `ClienteOverpass` |
| TomTom Search | stato in tempo reale | `DisponibilitaTomTom` |

Le prime quattro **si sommano** (`FonteColonnineUnite`): prima era una
catena che si fermava alla prima che rispondeva, e bastava che Open Charge
Map rispondesse per perdere tutto il resto.

L'archivio e il relay nascono tutti e due da **OpenStreetMap**, quindi
sanno le stesse cose.

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

**La PUN non espone niente di pubblico.** `tools/sonda_pun.py`:

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

## Cosa resta da fare, e non è codice

1. **MASE / GSE** — chiedere un accesso in lettura ai dati della PUN (oltre
   32.000 punti, raccolti per obbligo di legge). Gratis se lo concedono,
   e risolve l'Italia intera.
2. **Un operatore alla volta** — chiedere credenziali OCPI come eMSP, solo
   `Locations` e `Tariffs`. Gratis, e il codice per leggerle c'è già.
3. **Eco-Movement** — a contratto, copertura come ABRP.

Qualunque credenziale arrivi va nel **relay**, non nell'APK: una sola per
tutti gli utenti, e niente segreti dentro l'applicazione.

## Lo stato in tempo reale

TomTom Search dà 2.500 chiamate al mese e ne bruciavamo due per colonnina:
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
