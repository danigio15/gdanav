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
  GestorePosizione({required this.archivio, required this.letture, DateTime Function()? orologio})
    : _ora = orologio ?? DateTime.now;

  final DateTime Function() _ora;

  final Archivio archivio;
  final Stream<Lettura> Function() letture;

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
    // Da fermi la bussola del GPS impazzisce: si tiene l'ultima direzione.
    if (l.rotta != null && l.velocitaMs > 1.5) {
      rotta = l.rotta!;
    } else if (prima != null && distanzaM(prima, l.punto) > 8) {
      rotta = rottaGradi(prima, l.punto);
    }
    final ora = _ora();
    final lettaPrima = lettoAlle;
    // Molti telefoni non danno la velocità: la si ricava dallo spostamento.
    var v = l.velocitaMs;
    if (v <= 0.3 && prima != null && lettaPrima != null) {
      final secondi = ora.difference(lettaPrima).inMilliseconds / 1000;
      if (secondi >= 0.5 && secondi <= 10) v = distanzaM(prima, l.punto) / secondi;
    }
    qui = l.punto;
    lettoAlle = ora;
    // Sotto i 2 km/h è rumore del GPS: si è fermi.
    velocitaKmh = v * 3.6 < 2 ? 0 : v * 3.6;
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
