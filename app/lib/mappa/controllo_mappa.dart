import 'package:flutter/foundation.dart';

/// I comandi della mappa che stanno fuori dalla mappa: 2D o 3D, e «torna su
/// di me».
class ControlloMappa extends ChangeNotifier {
  bool inclinata = false;
  int _centra = 0;

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
}
