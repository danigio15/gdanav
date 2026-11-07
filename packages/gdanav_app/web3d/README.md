# La mappa 3D di GdANav in guida

La mappa sotto il cruscotto della guida, in 3D: i viadotti alla loro altezza
con le rampe che salgono, i piloni e le ombre, le righe delle corsie, gli
alberi nei parchi veri e lungo le strade, gli edifici con le facciate e (di
notte) le finestre accese, il percorso luminoso all'altezza della strada e
l'auto rossa. È il prototipo approvato, fatto sul serio: niente server e
niente dati preparati, tutto nasce sul telefono dalle tessere vettoriali che
la mappa scarica già (OpenFreeMap, schema OpenMapTiles).

## Come è fatta

- **MapLibre GL JS** disegna il suolo, i nomi, le icone e lo stile di sempre
  (`stileMappa` di `lib/mappa/stile.dart`, mandato dall'app così com'è e
  adattato in `src/stile3d.js`): colonnine, autovelox, segnalazioni, meta,
  tappe, ZTL, traffico di TomTom.
- **three.js**, in uno strato `custom` di MapLibre, disegna il 3D
  (`src/scena.js`).
- Un **lavoratore** (`src/lavoratore.js`, un Web Worker) fa le tessere 3D: per
  ogni tessera z14 (con le otto vicine, per le rampe che passano il bordo)
  il grafo delle strade, le quote (`src/elevazione.js`: ponti a 7 m per
  livello di `layer`, rampe in salita col 5,5%), e le geometrie
  (`src/tessera.js`). Il seme degli alberi è la tessera: tornandoci sono gli
  stessi.
- Il **percorso** sta all'altezza della strada su cui passa
  (`src/percorso.js`): ogni pochi metri le quote delle strade sotto, e la
  sequenza più continua (chi è sul viadotto ci resta).
- L'**auto** scorre fra una posizione e l'altra (`src/moto.js`): l'app manda
  la posizione quando la sa, la pagina la porta avanti a ogni fotogramma.
- Il **budget** (`src/budget.js`): vicino all'auto tutto, più in là niente
  alberi né lampioni, oltre la nebbia niente; al più 900 000 triangoli. Si
  disegna solo quando qualcosa si muove, al più 30 fotogrammi al secondo, e
  niente con l'app in secondo piano.
- Senza rete resta la scena già fatta (le tessere costruite si tengono).

L'app parla con la pagina coi messaggi di `src/messaggi.js` (lo stesso
formato di `lib/mappa/ponte_3d.dart`); la WebView è in
`lib/mappa/mappa_3d.dart`. Se WebGL manca, o nei primi secondi di guida va
sotto i 20 fotogrammi al secondo, la pagina lo dice e l'app torna alla mappa
di sempre (e se lo ricorda: «Mappa 3D» nel menu).

## Impacchettare

Dentro l'app non si carica codice da internet (App Store, regola 2.5.2): il
JavaScript e il CSS sono in `assets/web3d/`, fatti da qui.

```sh
npm ci
npm test              # le prove delle parti pure (node --test)
npm run build         # rifà assets/web3d/
npm run controlla     # i file committati sono quelli della sorgente?
```

Dopo ogni modifica in `src/` si rifà il pacchetto e si committano tutti e
due: la prova di CI (`npm run controlla`) fallisce se non sono uguali.

## Il collaudo nel browser

`collaudo/collaudo.mjs` apre la pagina impacchettata in Chromium (WebGL in
software), con un'app finta che manda lo stile vero (`collaudo/stile.dart`),
un percorso vero (trovato sulle tessere da `collaudo/strada.mjs`), un
autovelox, una coda e l'auto che avanza; fa le foto di giorno e di notte e
controlla che la tela non sia vuota e i triangoli stiano nel budget. I casi:
Rho/Pero (A4 → viadotto A52 → A8, il prototipo), Roma (GRA, svincolo A24),
Bologna (Casalecchio).

```sh
NODE_USE_ENV_PROXY=1 node collaudo/collaudo.mjs collaudo/uscita
```

## Sull'auto (Android Auto e CarPlay)

Sull'auto la mappa resta quella nativa di MapLibre, con l'**aspetto** della
mappa 3D (`stileMappa(aspetto3d: true)`, acceso con la «Mappa 3D»): i
colori del suolo, l'asfalto grigio coi bordi chiari, le corsie tratteggiate
delle autostrade da vicino, i ponti sollevati (ombra spostata, parapetto di
cemento, sopra le strade a terra), gli edifici coi colori delle facciate
(scuri di notte), e l'auto rossa al posto della freccia di partenza. Niente
animazioni in più. Le immagini le fa `collaudo/auto.mjs`.

Perché non la pagina 3D anche lì:

- **Copiare i fotogrammi** da una WebView fuori schermo alla superficie
  dell'auto vuol dire leggere ogni fotogramma dalla GPU (`readPixels` o una
  cattura della vista) e ridisegnarlo: a 1280×720 sono 3,7 MB per
  fotogramma, e su un telefono di fascia media si sta sotto i 10–15
  fotogrammi al secondo, col telefono che scalda. Da scartare.
- **La WebView direttamente sulla superficie** su Android Auto si può: la
  mappa dell'auto è già una `Presentation` su un `VirtualDisplay` della
  superficie (`RendererMappa.kt`), e una WebView ci starebbe come la
  `MapView` di adesso, senza copie. Servirebbe portare i messaggi di
  `messaggi.js` anche da Kotlin (i dati ci sono già: `PonteAuto.kt`), e su
  CarPlay una `WKWebView` nella finestra di CarPlay (`MappaCarPlay.swift`).
  È la strada buona per un passo dopo, ma va provata su un'auto vera: due
  scene WebGL (telefono e auto) nella memoria del telefono, il contesto
  WebGL che Android può togliere a una vista non in primo piano, e per
  CarPlay una vista web come mappa, che Apple non vieta ma che va fatta
  vedere alla revisione.
- **Il 3D nativo** di MapLibre Native (Android 13.5.0, iOS 6.28.0) ha solo
  `fill-extrusion` da poligoni: i ponti nelle tessere sono linee, e non c'è
  uno strato di modelli 3D. I viadotti in quota nativi vorrebbero un
  motore di disegno nostro (strato personalizzato in OpenGL/Metal): troppo
  per l'auto, dove la mappa deve soprattutto restare leggibile.
