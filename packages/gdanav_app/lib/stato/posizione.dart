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

/// Il GPS del telefono, uno per tutta l'app: vedi [FlussoGps].
final _gps = FlussoGps(
  apri: (soloIlGps) => Geolocator.getPositionStream(locationSettings: _comeLeggere(soloIlGps)),
  chiedi: (soloIlGps, limite) => Geolocator.getCurrentPosition(locationSettings: _comeChiedere(soloIlGps, limite)),
);

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
///
/// E non si fida del silenzio. Su Android il flusso può morire senza dirlo a
/// nessuno: quando l'attività si stacca dal motore Flutter — l'app tolta
/// dalle recenti, o Android che la chiude per fare posto — il plugin del GPS
/// smette di ascoltare e stacca il canale, e al Dart non arriva né un errore
/// né una fine. Dentro gdahome il motore resta acceso per Android Auto, e da
/// lì la guida restava ferma sulla prima manovra, col tachimetro inchiodato
/// all'ultima velocità e la mappa immobile. La posizione chiesta una volta
/// sola passa da un altro canale, e quella funziona ancora. Così una
/// sentinella guarda ogni [giro]: se da [sollecito] non arriva niente chiede
/// una posizione sola e la manda avanti come le altre (una alla volta, mai
/// due insieme), e finché il flusso non riparte continua a chiederle, una a
/// ogni giro; se il flusso tace da [morto], o finisce, lo chiude e lo
/// riapre. Quando nessuno ascolta, la sentinella dorme e il GPS si spegne.
class FlussoGps {
  FlussoGps({required this.apri, required this.chiedi, DateTime Function()? orologio})
    : _ora = orologio ?? DateTime.now {
    _uscita = StreamController<Position>.broadcast(onListen: _accendi, onCancel: _spegni);
  }

  /// Apre il flusso del GPS della piattaforma. [soloIlGps] è
  /// `forceLocationManager`: vedi sopra.
  final Stream<Position> Function(bool soloIlGps) apri;

  /// Una posizione sola, entro [limite].
  final Future<Position> Function(bool soloIlGps, Duration limite) chiedi;

  final DateTime Function() _ora;
  late final StreamController<Position> _uscita;

  /// Ogni quanto la sentinella guarda se il GPS parla.
  static const giro = Duration(seconds: 2);

  /// Dopo quanto silenzio si chiede una posizione sola. Non meno: da fermi
  /// certi telefoni lasciano passare tre o quattro secondi senza niente, e
  /// non è un guasto.
  static const sollecito = Duration(seconds: 5);

  /// Quanto si aspetta la posizione chiesta.
  static const attesa = Duration(seconds: 4);

  /// Dopo quanto silenzio il flusso si dà per morto e si riapre. Se riaprirlo
  /// non basta (il canale staccato non torna finché il motore non si rifà) lo
  /// si riprova sempre più di rado, fino a [mortoAlPiu]: intanto la posizione
  /// arriva lo stesso, chiesta una volta alla volta.
  static const morto = Duration(seconds: 12);
  static const mortoAlPiu = Duration(minutes: 2);

  /// Dopo un errore del flusso si riprova fra poco.
  static const dopoUnErrore = Duration(seconds: 15);

  StreamSubscription<Position>? _dalGps;
  Timer? _fraPoco;
  Timer? _sentinella;
  var _soloIlGps = false;
  var _chiesta = false;

  /// L'ultima posizione è arrivata perché la si è chiesta: il flusso tace, e
  /// la prossima si chiede al giro dopo, senza aspettare di nuovo [sollecito].
  /// Una posizione ogni sei secondi era troppo poco per guidare.
  var _sollecitando = false;

  /// L'ultima posizione mandata avanti, da dovunque venga.
  var _ultima = DateTime(0);

  /// L'ultima posizione arrivata dal flusso, o quando lo si è aperto.
  var _dalFlusso = DateTime(0);
  var _riapriDopo = morto;

  /// Per quanto il GPS dell'auto conta come vivo dopo la sua ultima
  /// posizione: in questo tempo quelle del telefono non passano.
  static const autoViva = Duration(seconds: 3);

  /// Certe auto mandano la posizione dieci volte al secondo: alla guida e alla
  /// mappa ne basta una ogni tanto così.
  static const autoAlPiu = Duration(milliseconds: 400);

  var _dallAuto = DateTime(0);
  var _mandataDallAuto = DateTime(0);

  /// Le posizioni, finché qualcuno ascolta.
  Stream<Position> get posizioni => _uscita.stream;

  /// Una posizione dal GPS dell'auto, quando Android Auto la passa.
  ///
  /// L'antenna dell'auto sta sul tetto e il telefono in tasca, o in un vano:
  /// finché l'auto ne manda (l'ultima da meno di [autoViva]) vanno avanti
  /// quelle, e quelle del telefono si lasciano cadere, perché due GPS che si
  /// alternano farebbero ballare il segnaposto fra due strade. Quando l'auto
  /// tace si torna al telefono. Per la sentinella è una posizione come le
  /// altre: finché parla l'auto non chiede niente al telefono e non ne
  /// riapre il flusso. Le auto che la posizione non la danno (tante) non
  /// mandano niente, e non cambia niente.
  ///
  /// Su CarPlay non c'è niente del genere: iOS non dà il GPS dell'auto alle
  /// app, e lì resta quello del telefono.
  void dallAuto(Position p) {
    final ora = _ora();
    _dallAuto = ora;
    if (ora.difference(_mandataDallAuto) < autoAlPiu) return;
    _mandataDallAuto = ora;
    _sollecitando = false;
    _manda(p, ora);
  }

  bool _parlaLAuto(DateTime ora) => ora.difference(_dallAuto) < autoViva;

  void _accendi() {
    // Chi comincia ad ascoltare non ha ancora avuto niente: il silenzio si
    // conta da adesso, non dall'ultima posizione di chissà quando.
    final ora = _ora();
    _ultima = ora;
    _dalFlusso = ora;
    _riapriDopo = morto;
    _sollecitando = false;
    _apri();
    _sentinella ??= Timer.periodic(giro, (_) => _controlla());
  }

  void _spegni() {
    _sentinella?.cancel();
    _sentinella = null;
    _fraPoco?.cancel();
    _fraPoco = null;
    _chiudi();
  }

  void _apri() {
    _fraPoco?.cancel();
    _fraPoco = null;
    if (_dalGps != null) return;
    _dalFlusso = _ora();
    late final StreamSubscription<Position> s;
    try {
      s = apri(_soloIlGps).listen(
        _dalTelefono,
        onError: (Object e) => _riprova(e, s),
        // Finito: lo riapre la sentinella al prossimo giro.
        onDone: () {
          if (identical(_dalGps, s)) _dalGps = null;
        },
      );
    } catch (e) {
      _riprova(e, null);
      return;
    }
    _dalGps = s;
  }

  void _chiudi() {
    final s = _dalGps;
    _dalGps = null;
    // Si chiude subito, prima di riaprire: il canale del GPS è uno solo, e
    // chi lo lasciasse dopo che il nuovo l'ha preso lo lascerebbe muto.
    if (s != null) unawaited(s.cancel().catchError((Object _) {}));
  }

  void _dalTelefono(Position p) {
    final ora = _ora();
    _dalFlusso = ora;
    _riapriDopo = morto;
    if (_parlaLAuto(ora)) return;
    _sollecitando = false;
    _manda(p, ora);
  }

  void _manda(Position p, DateTime ora) {
    _ultima = ora;
    _uscita.add(p);
  }

  void _riprova(Object errore, StreamSubscription<Position>? da) {
    if (da != null && !identical(_dalGps, da)) return;
    _chiudi();
    if (errore is LocationServiceDisabledException) _soloIlGps = true;
    _fraPoco?.cancel();
    _fraPoco = Timer(dopoUnErrore, () {
      _fraPoco = null;
      if (_uscita.hasListener) _apri();
    });
  }

  void _controlla() {
    final ora = _ora();
    // Finché parla l'auto il telefono non serve: lo si riguarda quando tace.
    if (_parlaLAuto(ora)) return;
    if (_dalGps == null) {
      // Finito da solo: lo si riapre. Dopo un errore invece c'è già chi
      // aspetta di riprovare.
      if (_fraPoco == null) _apri();
    } else if (ora.difference(_dalFlusso) >= _riapriDopo) {
      _chiudi();
      _riapriDopo = _riapriDopo * 2 > mortoAlPiu ? mortoAlPiu : _riapriDopo * 2;
      _apri();
    }
    final silenzio = _sollecitando ? Duration.zero : sollecito;
    if (!_chiesta && ora.difference(_ultima) >= silenzio) unawaited(_chiediUna());
  }

  Future<void> _chiediUna() async {
    _chiesta = true;
    final chiesta = _ora();
    try {
      // Il limite lo mette già il plugin; questo è per un telefono che non
      // risponde proprio, che non deve tenere ferma la sentinella.
      final p = await chiedi(_soloIlGps, attesa).timeout(attesa + const Duration(seconds: 1));
      // Nel frattempo è arrivata una posizione più fresca: questa è vecchia.
      if (!_ultima.isBefore(chiesta) || !_uscita.hasListener) return;
      _sollecitando = true;
      _manda(p, _ora());
    } catch (e) {
      if (e is LocationServiceDisabledException) _soloIlGps = true;
    } finally {
      _chiesta = false;
    }
  }
}

LocationSettings _comeLeggere(bool soloIlGps) => switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    intervalDuration: const Duration(seconds: 1),
    forceLocationManager: soloIlGps,
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

/// La posizione chiesta una volta sola dalla sentinella: come quelle del
/// flusso, con un limite di tempo.
LocationSettings _comeChiedere(bool soloIlGps, Duration limite) => switch (defaultTargetPlatform) {
  TargetPlatform.android => AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    forceLocationManager: soloIlGps,
    timeLimit: limite,
  ),
  TargetPlatform.iOS => AppleSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    activityType: ActivityType.automotiveNavigation,
    timeLimit: limite,
  ),
  _ => LocationSettings(accuracy: LocationAccuracy.bestForNavigation, timeLimit: limite),
};

/// Una posizione dal GPS dell'auto: la passa lo schermo di Android Auto
/// (`PonteAuto`), e finché arrivano vanno davanti a quelle del telefono.
/// Vedi [FlussoGps.dallAuto].
void gpsDellAuto(Position p) => _gps.dallAuto(p);

/// Le posizioni mentre si guida, con la direzione, la velocità e l'ora della
/// lettura ([PuntoInMoto]). Prima passavano solo latitudine e longitudine, e
/// il resto si perdeva qui: il ricalcolo non sapeva da che parte si andava, e
/// il segnaposto in guida non si poteva portare avanti del ritardo del GPS.
Stream<Punto> posizioniGuida() => _gps.posizioni.map(
  (p) => PuntoInMoto(
    p.latitude,
    p.longitude,
    rotta: rottaDaFidarsi(p.heading, p.headingAccuracy),
    velocitaMs: p.speed.isFinite && p.speed >= 0 ? p.speed : null,
    alle: p.timestamp,
  ),
);

/// Le letture per il segnaposto: posizione, direzione, velocità, e quanto il
/// telefono dice di potersi sbagliare.
///
/// La direzione passa da [rottaDaFidarsi]: Android quella casella la riempie
/// sempre, e quando non ce l'ha ci mette zero — che vuol dire nord.
Stream<Lettura> lettureGps() => _gps.posizioni.map(
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
