import 'package:geolocator/geolocator.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_posizione.dart';

/// Chiede il permesso della posizione, se non c'è ancora. `true` se c'è.
Future<bool> chiediPosizione() async {
  try {
    var permesso = await Geolocator.checkPermission();
    if (permesso == LocationPermission.denied) permesso = await Geolocator.requestPermission();
    return permesso == LocationPermission.always || permesso == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}

/// Se il permesso c'è già, senza chiederlo: all'avvio da Android Auto non
/// c'è una schermata a cui chiederlo.
Future<bool> haPosizione() async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}

/// Le posizioni mentre si guida: alta precisione, una ogni 5 metri.
Stream<Punto> posizioniGuida() => Geolocator.getPositionStream(
  locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 5),
).map((p) => Punto(p.latitude, p.longitude));

/// Le letture per il segnaposto: posizione, direzione e velocità.
Stream<Lettura> lettureGps() => Geolocator.getPositionStream(
  locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
).map((p) => Lettura(Punto(p.latitude, p.longitude), rotta: p.heading >= 0 ? p.heading : null, velocitaMs: p.speed));

/// Dove si è adesso, chiedendo il permesso la prima volta. `null` se la
/// posizione è spenta o negata: chi chiama lo dice all'utente.
Future<Punto?> posizioneAttuale() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permesso = await Geolocator.checkPermission();
  if (permesso == LocationPermission.denied) permesso = await Geolocator.requestPermission();
  if (permesso == LocationPermission.denied || permesso == LocationPermission.deniedForever) return null;
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    return Punto(p.latitude, p.longitude);
  } catch (_) {
    final ultima = await Geolocator.getLastKnownPosition();
    return ultima == null ? null : Punto(ultima.latitude, ultima.longitude);
  }
}
