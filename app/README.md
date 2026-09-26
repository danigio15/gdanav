# L'app

Flutter, Android e iOS. Il motore sta in
[`../packages/gdanav_core`](../packages/gdanav_core); lo schermo — mappa,
guida, schermate — in [`../packages/gdanav_app`](../packages/gdanav_app), che
porta gdanav anche dentro gdahome come sezione. Qui resta l'app: l'icona,
Android Auto, iOS. Per l'iPhone e CarPlay: [`../docs/ios.md`](../docs/ios.md).

    flutter pub get
    flutter analyze
    flutter run

    # Le prove dello schermo
    cd ../packages/gdanav_app && flutter test

## Cosa c'è

- **Mappa**: MapLibre con lo stile di gdanav (`../packages/gdanav_app/lib/mappa/stile.dart`), chiaro o
  scuro come il telefono, sui dati gratuiti di OpenFreeMap. Il bottone **3D**
  inclina la mappa e gli edifici si alzano; **Dove sono** la riporta su di te.
  Il rilievo del terreno in 3D MapLibre per telefoni ancora non lo fa.
- **Dove vuoi andare?**: si cerca un posto (Photon) o si tiene premuto sulla
  mappa. Percorso, colonnine e soste si disegnano sulla mappa: linea blu,
  colonnine colorate per stato (verde libera, ambra piena, rosso guasta,
  grigio sconosciuto), soste numerate, arrivo in rosso.
- **La scheda del viaggio**, da tirare su: ora d'arrivo, durata, chilometri,
  batteria all'arrivo, soste e consumo; il grafico della batteria lungo la
  strada; ogni sosta con potenza, prese libere e quanto si ricarica; le altre
  colonnine lungo la strada.
- **Colonnina**: toccandola (sulla mappa o nella scheda) si vedono prese e
  stato, e **Fermati qui** la aggiunge come sosta. Il piano si ricalcola.
- **Menu**: la tua auto (trenta modelli), le preferenze di ricarica (soglie,
  massimo di ricarica, potenza minima, evitare le colonnine piene), la fonte
  dei dati dell'auto, Home Assistant, i servizi.
- **Batteria in alto**: anello con la percentuale, i chilometri che restano,
  l'auto e da dove arriva il dato.

Server dei percorsi e chiave di Open Charge Map si scrivono in **Servizi**, o
alla compilazione:

    flutter run --dart-define=GDANAV_VALHALLA=https://1-2-3-4.sslip.io/ \
                --dart-define=GDANAV_VALHALLA_CHIAVE=... \
                --dart-define=GDANAV_OCM_CHIAVE=...

## Android Auto e CarPlay

Lo schermo dell'auto parla col Dart sul canale `gdanav/schermo_auto`
(`../packages/gdanav_app/lib/auto/ponte_auto.dart`). Dall'altra parte c'è
Android Auto (`../packages/gdanav_app/android/.../auto`, con la sessione in
`android/app/src/main/kotlin/it/gdanav/gdanav/auto`) o CarPlay
(`../packages/gdanav_app/ios/gdanav_app/Sources/gdanav_app`, con la scena
dichiarata in `ios/Runner/Info.plist`). Batteria, velocità e chilometri
dall'auto (`EventChannel` `gdanav/auto`) li dà solo Android Auto: CarPlay non
li passa, e l'arbitro usa un'altra sorgente.
