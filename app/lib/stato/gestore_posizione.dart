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
  GestorePosizione({required this.archivio, required this.letture});

  final Archivio archivio;
  final Stream<Lettura> Function() letture;

  Punto? qui;
  double rotta = 0;
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
    // Da fermi la bussola del GPS impazzisce: si tiene l'ultima direzione.
    if (l.rotta != null && l.velocitaMs > 1.5) {
      rotta = l.rotta!;
    } else if (prima != null && distanzaM(prima, l.punto) > 8) {
      rotta = rottaGradi(prima, l.punto);
    }
    qui = l.punto;
    notifyListeners();
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
