import 'dart:async';

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
///
/// E non si arrende. Aperta da Android Auto la schermata del telefono non
/// c'è, e senza schermata Android non può chiedere di accendere la
/// precisione di Google: il controllo delle impostazioni fallisce, il GPS
/// risponde con un errore e non parte. Prima quell'errore finiva nel vuoto e
/// il flusso restava muto fino a riaprire l'app — «se non si apre l'app non
/// lega il GPS». Adesso si riprova da solo, e dopo un errore così la
/// posizione la si chiede direttamente al GPS (`forceLocationManager`), che
/// quel controllo non lo fa e non apre finestre: a posizione spenta risponde
/// di no in silenzio, e appena la si riaccende parte.
final _gps = StreamController<Position>.broadcast(onListen: _accendiIlGps);
StreamSubscription<Position>? _dalGps;
Timer? _fraPoco;
var _soloIlGps = false;

Stream<Position> _flusso() => _gps.stream;

void _accendiIlGps() {
  _fraPoco?.cancel();
  _fraPoco = null;
  _dalGps ??= Geolocator.getPositionStream(locationSettings: _comeLeggere()).listen(_gps.add, onError: _riprova);
}

Future<void> _riprova(Object errore) async {
  final prima = _dalGps;
  _dalGps = null;
  await prima?.cancel();
  if (errore is LocationServiceDisabledException) _soloIlGps = true;
  _fraPoco?.cancel();
  _fraPoco = Timer(const Duration(seconds: 15), () {
    if (_gps.hasListener) _accendiIlGps();
  });
}

LocationSettings _comeLeggere() => switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    intervalDuration: const Duration(seconds: 1),
    forceLocationManager: _soloIlGps,
  ),
  // Su iPhone, con CarPlay acceso, l'app sul telefono sta dietro: la
  // posizione deve continuare ad arrivare, e iOS non deve metterla in pausa
  // a un semaforo lungo.
  TargetPlatform.iOS => AppleSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    activityType: ActivityType.automotiveNavigation,
    pauseLocationUpdatesAutomatically: false,
    allowBackgroundLocationUpdates: true,
    showBackgroundLocationIndicator: true,
  ),
  _ => const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
};

/// Le posizioni mentre si guida.
Stream<Punto> posizioniGuida() => _flusso().map((p) => Punto(p.latitude, p.longitude));

/// Le letture per il segnaposto: posizione, direzione, velocità, e quanto il
/// telefono dice di potersi sbagliare.
///
/// La direzione passa da [rottaDaFidarsi]: Android quella casella la riempie
/// sempre, e quando non ce l'ha ci mette zero — che vuol dire nord.
Stream<Lettura> lettureGps() => _flusso().map(
  (p) => Lettura(
    Punto(p.latitude, p.longitude),
    rotta: rottaDaFidarsi(p.heading, p.headingAccuracy),
    velocitaMs: p.speed,
    precisioneM: p.accuracy > 0 ? p.accuracy : null,
  ),
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
