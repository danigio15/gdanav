# Il «3D aumentato» di GdANav in guida

Una vista della mappa, accanto a 2D, 3D e immersiva: si sceglie dal tasto
della vista (il segno «3D» con la scintilla; `VistaMappa.aumentata` in
`lib/mappa/controllo_mappa.dart`) e si ricorda come le altre. Le altre tre
restano la mappa di sempre (MapLibre Native); fuori dalla guida anche il 3D
aumentato la usa, come il 3D.

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
  il grafo delle strade, le quote (`src/elevazione.js`: ponti a 8 m per
  livello di `layer`, rampe in salita col 5,5%), e le geometrie
  (`src/tessera.js`). Il seme degli alberi è la tessera: tornandoci sono gli
  stessi.
- **Ponti, cavalcavia, svincoli, gallerie** (`src/tessera.js`): l'asfalto
  dei ponti è più chiaro di quello a terra; l'impalcato è spesso 1,9 m
  (cordolo chiaro che sporge, trave scura, ventre scurissimo, parapetto col
  corrimano scuro) e ha un poco di luce propria, perché anche il fianco in
  ombra si legga; sotto il ventre restano quasi 6 m di luce. Sotto ogni
  ponte la strada è più scura, a piombo, con un alone morbido, oltre
  all'ombra del sole; i piloni stanno ai due lati delle strade che passano
  sotto (e nello spartitraffico fra due carreggiate) e mai sopra, e dove un ponte
  finisce ancora in alto c'è la spalla. Le gallerie sono un nastro scuro e
  trasparente con gli imbocchi, e il percorso lì dentro è tenue e
  tratteggiato. Un ponte senza `layer` sta al primo livello (al più al
  quinto), le rampe salgono da sole verso il ponte a cui si attaccano.
- **I viadotti sulle valli** (`segnaViadotti` in `src/tessera.js`): le
  tessere danno solo il livello, ma in Italia i ponti sulle valli si
  chiamano «Viadotto …» (e quello di Genova «(Ponte San Giorgio) A10 …»):
  lungo quei nomi i pezzi di ponte stanno a 4,5 m ogni cento metri di
  lunghezza, fra 10 e 60 (Genova a 47,5). Le salite oltre i 6,5 m sono
  viadotti anche loro (impalcato e piloni, non un muro); i piloni alti sono
  più grossi e le campate più lunghe. Un modello del terreno non c'è: il
  suolo resta piano, e un'altezza vera sulla valle chiederebbe anche il
  terreno sotto (i dati di AWS Terrain Tiles si raggiungono, ma con un
  suolo piano darebbero solo un numero più preciso, non un paesaggio).
- **L'auto e il percorso non si perdono mai**: dove un ponte o un edificio
  ci passa davanti si vedono in trasparenza (la sagoma rossa, il percorso
  tenue). L'auto sta sopra i cartelli e i nomi di MapLibre, tranne sotto un
  ponte, dove il ponte la copre davvero.
- **Icone e nomi sui viadotti**: autovelox, segnalazioni, meta, soste di
  ricarica, tappe e nomi dei ponti stanno all'altezza dell'impalcato
  (`aggiornaSegni` in `src/principale.js`), e si toccano lì: la pagina li
  cerca sotto il dito proiettandoli sullo schermo e manda all'app
  l'elemento come lo strato a terra (la scheda è la stessa). I nomi delle
  strade con un pezzo in quota (anche le rampe non segnate come ponte) li
  scrive il 3D sul pezzo in quota; quelli con un pezzo in galleria, fuori
  dalla galleria (o per niente, se è tutta in galleria); MapLibre li tace
  (`filtroNomi` in `src/stile3d.js`).
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
sotto i 20 fotogrammi al secondo, o lo disegna solo in software, la pagina lo
dice e l'app torna alla vista di prima, con un avviso («3D aumentato non è
disponibile su questo telefono: torno alla vista 3D»), e se lo ricorda: nel
tasto della vista la voce resta spenta col perché, e toccandola «Riprova».
Un intoppo di una volta (la pagina che non risponde) fa tornare indietro
senza ricordarlo.

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
NODE_USE_ENV_PROXY=1 node collaudo/collaudo.mjs collaudo/uscita [caso…]
NODE_USE_ENV_PROXY=1 node collaudo/video.mjs collaudo/uscita rho 1700 2150 70
NODE_USE_ENV_PROXY=1 node collaudo/auto.mjs collaudo/uscita
```

I casi: Rho/Pero (rampa sul viadotto A52 e cavalcavia di secondo livello),
Roma (GRA/A24), Bologna (Casalecchio), un cavalcavia sopra l'auto in
autostrada (Borgo Panigale), tre livelli (Napoli, Capodichino), il
quadrifoglio (Torino, corso Francia), il viadotto San Giorgio (Genova), un
sottopasso (Milano). Per ognuno: il telefono di giorno e di notte, la
panoramica, la foto da vicino; i controlli dicono anche se l'auto si vede
(sotto il cavalcavia compreso), quanta luce c'è sotto il ponte (almeno 5,5
m), e a Rho toccano la tappa, la sosta e l'autovelox sul viadotto e
controllano che arrivi lo strato giusto. Di traverso la telecamera lascia
a sinistra il posto del cruscotto (`sinistra` nel messaggio `camera`). `video.mjs` fa un video MP4 della guida un fotogramma alla volta;
`auto.mjs` le immagini di Android Auto e CarPlay (prima e dopo) e del
telefono com'è oggi; con `TRAVERSO=1` il telefono di traverso con la mappa
di sempre nelle viste 2D, 3D e immersiva. Le immagini col cruscotto vero di
Flutter sopra le foto le fa `test_render/mappa_3d_render_test.dart` (con
`GDANAV_TRAVERSO=1` anche di traverso).

Una correzione a MapLibre 5.6.0 si fa impacchettando (`build.mjs`): con la
mappa molto inclinata `_updateRetainedTiles` leggeva quattro tessere figlie
dove ce n'era una e perdeva il fotogramma. Se un giorno il pezzo da
correggere non c'è più (MapLibre aggiornato), `build.mjs` si ferma e lo
dice, invece di impacchettare la versione con l'errore.

## Nell'app

Il ritorno automatico è provato in `test/aumentato_fallback_test.dart` con
una WebView finta (`test/webview_finta.dart`): la pagina che dice «lento»,
«software» o «webgl2», quella che non risponde, e il telefono che se lo
ricorda. Il cruscotto della guida di traverso (un pannello a sinistra) è
provato in `test/guida_di_traverso_test.dart` su telefoni e tablet.

## Sull'auto (Android Auto e CarPlay)

Sull'auto la mappa resta quella nativa di MapLibre, con l'**aspetto** della
mappa 3D (`stileMappa(aspetto3d: true)`, solo quando sul telefono la vista è
il 3D aumentato; altrimenti com'era): i
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
