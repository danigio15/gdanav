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
  OpenStreetMap        4   (con la vecchia regola ne passavano 4 lo stesso)
  Open Charge Map      2
  archivio gdanav      6 → 7
  EVDC / ABRP         ~12 stazioni, 442 prese
```

Lì il filtro non toglieva niente. **Le fonti gratuite quelle colonnine non
ce le hanno.** La Plenitude di Via Domenico Aulisio, con le sue 202 prese,
su OpenStreetMap non esiste.

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
