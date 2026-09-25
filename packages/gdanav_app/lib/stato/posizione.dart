import 'package:flutter/foundation.dart';
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

/// Un solo flusso del GPS per tutta l'app: una posizione al secondo, anche
/// da fermi, così il tachimetro scende a zero.
Stream<Position>? _gps;

Stream<Position> _flusso() => _gps ??= Geolocator.getPositionStream(
  locationSettings: defaultTargetPlatform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
        )
      : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
).asBroadcastStream();

/// Le posizioni mentre si guida.
Stream<Punto> posizioniGuida() => _flusso().map((p) => Punto(p.latitude, p.longitude));

/// Le letture per il segnaposto: posizione, direzione e velocità.
Stream<Lettura> lettureGps() => _flusso().map(
  (p) => Lettura(Punto(p.latitude, p.longitude), rotta: p.heading >= 0 ? p.heading : null, velocitaMs: p.speed),
);

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
