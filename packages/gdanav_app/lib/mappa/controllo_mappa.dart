import 'dart:async';

import 'package:flutter/foundation.dart';

/// I comandi della mappa che stanno fuori dalla mappa: 2D o 3D, «torna su
/// di me» e la mappa libera.
class ControlloMappa extends ChangeNotifier {
  ControlloMappa({this.ritornoAutomatico = const Duration(seconds: 20), this.inclinata = true, this.salvaInclinazione});

  /// 3D: inclinata, girata come si va, e (fuori dalla guida come in guida)
  /// la mappa segue chi guida. 2D: dall'alto. Di partenza 3D, come sullo
  /// schermo dell'auto; la scelta si ricorda ([salvaInclinazione], [carica]).
  bool inclinata;

  /// Dove si ricorda la scelta 2D/3D; `null` nelle prove che non la guardano.
  final Future<void> Function(bool inclinata)? salvaInclinazione;

  var _sceltaQui = false;
  int _centra = 0;

  /// La mappa non segue più chi guida: l'ha spostata un dito (e dopo
  /// [ritornoAutomatico] senza tocchi torna a seguirlo da sola), o si sta
  /// guardando una persona di casa (finché non si chiede «Dove sono»).
  bool libera = false;
  final Duration ritornoAutomatico;
  Timer? _ritorno;

  /// Cresce a ogni «centra»: la mappa se ne accorge e si muove.
  int get richiesteCentra => _centra;

  /// La scelta ricordata, appena letta. Se nel frattempo se n'è già fatta
  /// una qui, vale quella.
  Future<void> carica(Future<bool> ricordata) async {
    final v = await ricordata;
    if (_sceltaQui || v == inclinata) return;
    inclinata = v;
    notifyListeners();
  }

  /// Il tasto 2D/3D: cambia, si ricorda, e si torna a seguire.
  void alternaInclinazione() {
    inclinata = !inclinata;
    _sceltaQui = true;
    unawaited(salvaInclinazione?.call(inclinata));
    _ritorno?.cancel();
    libera = false;
    notifyListeners();
  }

  /// «Dove sono»: la mappa torna su di te, e (in 3D) ti segue di nuovo.
  void centra() {
    _ritorno?.cancel();
    libera = false;
    _centra++;
    notifyListeners();
  }

  /// Un dito sulla mappa: la si lascia dov'è. [torna]: da sola, dopo
  /// [ritornoAutomatico]; altrimenti fino a «Dove sono» (una persona di casa
  /// mostrata, che si vuole guardare quanto serve).
  void toccata({bool torna = true}) {
    _ritorno?.cancel();
    _ritorno = torna ? Timer(ritornoAutomatico, segui) : null;
    if (libera) return;
    libera = true;
    notifyListeners();
  }

  /// Quanto spazio in alto copre un popup (in punti): la mappa sposta giù
  /// l'auto, così quello che arriva resta in vista sotto il popup.
  double coperto = 0;

  void copriAlto(double punti) {
    if ((punti - coperto).abs() < 1) return;
    coperto = punti;
    notifyListeners();
  }

  /// Si torna a seguire l'auto.
  void segui() {
    _ritorno?.cancel();
    if (!libera) return;
    libera = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _ritorno?.cancel();
    super.dispose();
  }
}
