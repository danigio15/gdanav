import 'dart:async';

import 'package:flutter/foundation.dart';

/// I comandi della mappa che stanno fuori dalla mappa: 2D o 3D, «torna su
/// di me» e, in guida, la mappa libera.
class ControlloMappa extends ChangeNotifier {
  ControlloMappa({this.ritornoAutomatico = const Duration(seconds: 20)});

  bool inclinata = false;
  int _centra = 0;

  /// In guida: toccata la mappa, smette di seguire l'auto; dopo
  /// [ritornoAutomatico] senza tocchi torna a seguirla da sola.
  bool libera = false;
  final Duration ritornoAutomatico;
  Timer? _ritorno;

  /// Cresce a ogni «centra»: la mappa se ne accorge e si muove.
  int get richiesteCentra => _centra;

  void alternaInclinazione() {
    inclinata = !inclinata;
    notifyListeners();
  }

  void centra() {
    _centra++;
    notifyListeners();
  }

  /// Un dito sulla mappa: la si lascia dov'è.
  void toccata() {
    _ritorno?.cancel();
    _ritorno = Timer(ritornoAutomatico, segui);
    if (libera) return;
    libera = true;
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
