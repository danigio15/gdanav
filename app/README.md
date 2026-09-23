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
- **Pastiglia della batteria**: «82% · Home Assistant · 12 min fa». Toccandola
  si apre lo switch **Fonte dati auto** (Automatica o una sorgente fissa) e
  si può scrivere la batteria a mano.
- **Home Assistant**: si inquadra il QR dell'integrazione; l'abbinamento sta
  nel portachiavi del telefono.

## Android Auto

Il lato Dart è pronto: `SorgenteAndroidAuto` ascolta l'`EventChannel`
`gdanav/auto` e si aspetta mappe `{batteria, autonomia_km, letto_ms,
automotive}`. Manca il lato Kotlin: un `CarAppService` di categoria
navigazione che registra `CarInfo.addEnergyLevelListener` e gira le letture
sul canale (permessi `com.google.android.gms.permission.CAR_FUEL` e
`CAR_MILEAGE`). Se l'auto non passa i dati il canale tace e l'arbitro usa
un'altra sorgente.
