import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/vista_svincolo.dart' show haSvincolo;
import '../servizi.dart';
import 'gestore_guida.dart';

/// Le foto vere degli svincoli: avvicinandosi (a due chilometri) a
/// un'uscita o a un bivio si cerca su Mapillary la foto scattata poco prima,
/// nella nostra direzione, e la si scarica. Una sola per guida, condivisa
/// fra il telefono e lo schermo dell'auto. Dove non ce n'è, si resta allo
/// svincolo disegnato.
class FotoSvincoli extends ChangeNotifier {
  FotoSvincoli._(this.guida, this.cliente) {
    guida.addListener(_forse);
  }

  static final _perGuida = Expando<FotoSvincoli>();

  static FotoSvincoli di(GestoreGuida guida, {ClienteMapillary? cliente}) => _perGuida[guida] ??= FotoSvincoli._(
    guida,
    cliente ?? (Servizi.chiaveMapillary.isEmpty ? null : ClienteMapillary(Servizi.chiaveMapillary)),
  );

  final GestoreGuida guida;

  /// `null` senza chiave: niente foto.
  final ClienteMapillary? cliente;

  static const daMetri = 2000.0;

  final _foto = <int, (FotoStrada, Uint8List)?>{};
  final _chieste = <int>{};
  List<Punto>? _percorso;

  /// La foto dello svincolo della manovra [m], se è arrivata.
  (FotoStrada, Uint8List)? perManovra(Manovra m) => _foto[m.inizio];

  void _forse() {
    final c = cliente, a = guida.attiva ? guida.avanzamento : null, m = a?.prossima;
    final punti = guida.pronto?.viaggio.percorso.punti;
    if (c == null || a == null || m == null || punti == null || !haSvincolo(m)) return;
    // Percorso nuovo (ricalcolo): gli indici delle manovre cambiano.
    if (!identical(punti, _percorso)) {
      _percorso = punti;
      _foto.clear();
      _chieste.clear();
    }
    if (a.allaProssimaM > daMetri || !_chieste.add(m.inizio)) return;
    unawaited(_cerca(c, punti, m));
  }

  Future<void> _cerca(ClienteMapillary c, List<Punto> punti, Manovra m) async {
    try {
      final linea = Linea(punti);
      final r = await c.fotoSvincolo(linea, linea.cumulate[m.inizio.clamp(0, punti.length - 1)]);
      if (!identical(punti, _percorso)) return;
      _foto[m.inizio] = r;
      if (r != null) notifyListeners();
    } catch (e) {
      debugPrint('foto svincolo: $e');
    }
  }
}
