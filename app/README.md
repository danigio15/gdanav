# L'app

Flutter, Android e iOS. Il motore sta in
[`../packages/gdanav_core`](../packages/gdanav_core): qui c'è solo quello che
tocca lo schermo e il telefono.

    flutter pub get
    flutter analyze
    flutter test
    flutter run

## Cosa c'è

- **Mappa**: MapLibre con lo stile di OpenFreeMap, gratis e senza chiave.
- **Dove vuoi andare?**: si cerca un posto (Photon, su OpenStreetMap), oppure
  si tiene premuto sulla mappa. L'app calcola percorso, colonnine e soste e
  li disegna: la linea blu, le soste in verde, l'arrivo in rosso. Sotto, la
  scheda con durata, chilometri, batteria all'arrivo e ogni sosta
  («42 km · 150 kW · 18% → 70% in 21 min»).
- **Pastiglia della batteria**: «82% · Home Assistant · 12 min fa». Toccandola
  si apre lo switch **Fonte dati auto** (Automatica o una sorgente fissa) e
  si può scrivere la batteria a mano.
- **Home Assistant**: si inquadra il QR dell'integrazione; l'abbinamento sta
  nel portachiavi del telefono.
- **Impostazioni**: l'indirizzo e la chiave del server dei percorsi
  ([`../valhalla`](../valhalla)) e la chiave di Open Charge Map. Si possono
  anche dare alla compilazione:

      flutter run --dart-define=GDANAV_VALHALLA=https://1-2-3-4.sslip.io/ \
                  --dart-define=GDANAV_VALHALLA_CHIAVE=... \
                  --dart-define=GDANAV_OCM_CHIAVE=...

Se manca qualcosa (server, batteria, posizione) la scheda lo dice con le
parole di cosa fare, e porta dove si sistema.

Per ora l'auto è un profilo d'esempio (segmento C, 60 kWh): la scelta del
modello è da fare.

## Android Auto

Il lato Dart è pronto: `SorgenteAndroidAuto` ascolta l'`EventChannel`
`gdanav/auto` e si aspetta mappe `{batteria, autonomia_km, letto_ms,
automotive}`. Manca il lato Kotlin: un `CarAppService` di categoria
navigazione che registra `CarInfo.addEnergyLevelListener` e gira le letture
sul canale (permessi `com.google.android.gms.permission.CAR_FUEL` e
`CAR_MILEAGE`). Se l'auto non passa i dati il canale tace e l'arbitro usa
un'altra sorgente.
