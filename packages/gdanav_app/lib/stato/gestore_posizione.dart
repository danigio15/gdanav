import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/segnaposto.dart';
import 'archivio.dart';

/// Una lettura del GPS: dove, e verso dove si va se il telefono lo sa.
class Lettura {
  const Lettura(this.punto, {this.rotta, this.velocitaMs = 0, this.precisioneM});
  final Punto punto;
  final double? rotta;
  final double velocitaMs;

  /// Il raggio entro cui il telefono dice di trovarsi, in metri. `null`
  /// quando non lo dice.
  ///
  /// Non e' un di piu': e' il telefono stesso che ammette di non saperlo. Fra
  /// i palazzi dichiara cinquanta, ottanta metri, ed e' proprio li' che il
  /// puntino «esce dalla carreggiata e rientra».
  final double? precisioneM;
}

/// La direzione che ha mandato il telefono, se c'e' da fidarsi.
///
/// Android la casella la riempie **sempre**: quando la direzione non ce l'ha
/// ci mette zero, non «niente» — e zero vuol dire nord. Un telefono senza
/// bussola avrebbe fatto puntare il segnaposto a nord per tutto il viaggio,
/// e con l'aria di un dato vero.
///
/// Si guarda la precisione della direzione, che c'e' da Android 8 e su
/// iPhone: quando dice qualcosa, la direzione e' una direzione. Quando tace,
/// uno zero tondo non e' nord — e' una casella non riempita; qualunque altro
/// valore invece nessuno lo scrive per sbaglio.
double? rottaDaFidarsi(double gradi, [double precisione = 0]) {
  if (!gradi.isFinite || gradi < 0 || gradi >= 360) return null;
  if (precisione > 0) return gradi;
  return gradi == 0 ? null : gradi;
}

/// Dove sei e verso dove guardi, per il segnaposto sulla mappa, e quale
/// segnaposto hai scelto.
class GestorePosizione extends ChangeNotifier {
  GestorePosizione({
    required this.archivio,
    required this.letture,
    this.velocitaDellAuto,
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now;

  final DateTime Function() _ora;

  final Archivio archivio;
  final Stream<Lettura> Function() letture;

  /// Quanto va l'auto secondo il suo cruscotto, `null` se non lo dice o se
  /// tace da qualche secondo. È [GestoreAuto.velocitaAuto].
  ///
  /// Serve per una domanda sola, ma è quella che conta: **siamo fermi?** Il
  /// tachimetro dell'auto non ha il ballonzolamento del GPS, e da fermo dice
  /// zero invece di dire «forse ti sei spostato di dieci metri».
  final double? Function()? velocitaDellAuto;

  Punto? qui;
  double rotta = 0;

  /// Dal GPS, per il tachimetro. Vedi [velocitaAdesso].
  double velocitaKmh = 0;

  /// Quando è arrivata l'ultima lettura.
  DateTime? lettoAlle;

  /// La velocità da mostrare: zero se il GPS tace da qualche secondo (da
  /// fermi certi telefoni non mandano più niente).
  double velocitaAdesso() {
    final t = lettoAlle;
    if (t == null || _ora().difference(t) > const Duration(seconds: 4)) return 0;
    return velocitaKmh;
  }

  Segnaposto segnaposto = Segnaposto.autoBlu;
  StreamSubscription<Lettura>? _iscrizione;

  Future<void> carica() async {
    segnaposto = await archivio.segnaposto();
    notifyListeners();
  }

  void avvia() {
    _iscrizione ??= letture().listen(_nuova, onError: (Object _) {});
  }

  /// Oltre questo raggio la lettura non dice piu' dove si e': dice in quale
  /// isolato. Cinquanta metri sono mezza strada.
  static const double _troppoImprecisa = 50;

  /// Quanto si puo' restare senza una lettura buona prima di prendere quella
  /// che c'e'. Meglio un puntino impreciso che nessun puntino: chi ha appena
  /// acceso l'app, o e' uscito da un tunnel, deve vedersi sulla mappa.
  static const Duration _senzaNienteDaTroppo = Duration(seconds: 10);

  /* Il telefono dichiara lui stesso quanto puo' sbagliare, e in citta' lo
   * dichiara grosso: cinquanta, ottanta metri fra i palazzi. Un punto cosi'
   * sposta il segnaposto di mezza carreggiata, e da fuori si vede il puntino
   * uscire dalla strada e rientrare — che e' esattamente la segnalazione.
   *
   * Si scarta, ma non a occhi chiusi: se non ne arriva una buona per dieci
   * secondi si prende quella che c'e'. Una mappa senza puntino e' peggio di
   * un puntino largo. */
  bool _daButtare(Lettura l, DateTime ora) {
    final quanto = l.precisioneM;
    if (quanto == null || quanto <= _troppoImprecisa) return false;
    final ultima = lettoAlle;
    if (qui == null || ultima == null) return false;
    return ora.difference(ultima) < _senzaNienteDaTroppo;
  }

  void _nuova(Lettura l) {
    final prima = qui;
    final ora = _ora();
    if (_daButtare(l, ora)) return;
    final lettaPrima = lettoAlle;
    // Molti telefoni non danno la velocità: la si ricava dallo spostamento.
    var v = l.velocitaMs;
    if (v <= 0.3 && prima != null && lettaPrima != null) {
      final secondi = ora.difference(lettaPrima).inMilliseconds / 1000;
      if (secondi >= 0.5 && secondi <= 10) v = distanzaM(prima, l.punto) / secondi;
    }
    // Sotto i 2 km/h è rumore del GPS: si è fermi.
    final dalGps = v * 3.6 < 2 ? 0.0 : v * 3.6;
    /* Fermi o no lo dice l'auto, quando parla. Il suo tachimetro da fermo
     * segna zero; il GPS invece continua a spostarsi di qualche metro, e da
     * quei metri si ricavava una direzione che non esisteva. */
    final vaKmh = velocitaDellAuto?.call() ?? dalGps;

    _dovePunta(prima, l, vaKmh);

    qui = l.punto;
    lettoAlle = ora;
    velocitaKmh = dalGps;
    notifyListeners();
  }

  /* ─── Verso dove guarda il segnaposto ──────────────────────────────────────
   *
   * Tre regole, e tutte e tre sono state pagate in strada.
   *
   * La prima: **da fermi non si gira**. Lo decide chi chiama, col tachimetro
   * dell'auto quando c'è. Prima il ramo dei due punti qui sotto scattava
   * comunque, e di notte fra i palazzi bastavano otto metri di scarto fra due
   * letture — che sono la normalità — per far girare la macchinina a destra,
   * poi a sinistra, ferma al semaforo.
   *
   * La seconda: la bussola del GPS si ascolta solo sopra i 5,4 km/h. Sotto è
   * rumore anche quando il telefono la dichiara.
   *
   * La terza: la direzione nuova non si prende com'è, si va verso. Una lettura
   * storta da sola non basta più a spostare il segnaposto, e una curva vera si
   * vede lo stesso perché le letture storte non sono tutte dalla stessa parte.
   */

  /// Sotto questa, si è fermi: è passo d'uomo, non andatura d'auto.
  static const double _fermoSotto = 3;

  /// Quanto ci si deve spostare perché sia un movimento e non il GPS che
  /// balla, **quando nessuno dice che si va**.
  ///
  /// Fermi in città il GPS salta di cinque, dieci, a volte venti metri: fra i
  /// palazzi è la norma. Oltre i venticinque non è più rumore, è strada fatta,
  /// e la direzione si può prendere anche senza che nessuno abbia detto una
  /// velocità — che è il caso dei telefoni che la bussola non la danno.
  static const double _troppoPerEsserRumore = 25;

  /// Quanto ci si sposta verso la direzione nuova a ogni lettura. Più basso è
  /// più fermo sta il segnaposto e più tardi segue le curve: a una lettura al
  /// secondo, con 0,6 una curva di 90° è finita in tre secondi.
  static const double _quantoSiGira = 0.6;

  bool _rottaConosciuta = false;

  void _dovePunta(Punto? prima, Lettura l, double vaKmh) {
    // La bussola del telefono, quando c'è e si sta andando abbastanza.
    if (l.rotta != null && l.velocitaMs > 1.5) {
      _verso(l.rotta!);
      return;
    }
    if (prima == null) return;
    /* Niente bussola: la direzione la danno i due punti. Ma ci si e' spostati
     * davvero? Due modi di saperlo, e basta uno: o qualcuno dice che si va —
     * il tachimetro dell'auto, o il GPS — e allora anche otto metri contano;
     * o nessuno lo dice, e allora ci vuole un salto troppo grande per essere
     * il GPS che balla. La seconda strada serve ai telefoni che la velocita'
     * non la danno mai: senza, da quelli la direzione non arriverebbe piu'. */
    final quanto = distanzaM(prima, l.punto);
    final soglia = vaKmh >= _fermoSotto ? 8.0 : _troppoPerEsserRumore;
    if (quanto > soglia) _verso(rottaGradi(prima, l.punto));
  }

  void _verso(double gradi) {
    // La prima volta non si smorza: si guarderebbe a nord fino alla curva.
    if (!_rottaConosciuta) {
      _rottaConosciuta = true;
      rotta = gradi % 360;
      return;
    }
    rotta = versoDiLa(rotta, gradi, _quantoSiGira);
  }

  Future<void> scegli(Segnaposto s) async {
    segnaposto = s;
    await archivio.salvaSegnaposto(s);
    notifyListeners();
  }

  @override
  void dispose() {
    _iscrizione?.cancel();
    super.dispose();
  }
}
