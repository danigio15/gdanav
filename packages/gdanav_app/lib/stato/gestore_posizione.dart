import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/segnaposto.dart';
import 'archivio.dart';

/// Una lettura del GPS: dove, e verso dove si va se il telefono lo sa.
class Lettura {
  const Lettura(this.punto, {this.rotta, this.velocitaMs = 0});
  final Punto punto;
  final double? rotta;
  final double velocitaMs;
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

  void _nuova(Lettura l) {
    final prima = qui;
    final ora = _ora();
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
