import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/dati_viaggio.dart';
import 'distributori.dart';
import 'gestore_auto.dart';
import 'gestore_posizione.dart';
import 'gestore_viaggio.dart';

/// Quello che c'è intorno a te, sulla mappa: i distributori coi prezzi se
/// l'auto è termica, le colonnine rapide adatte se è elettrica. Si ricerca
/// quando ci si sposta di un paio di chilometri o si cambia auto.
class GestoreVicini extends ChangeNotifier {
  GestoreVicini({
    required this.auto,
    required this.posizione,
    Future<List<Distributore>> Function(Punto qui)? distributori,
    Future<List<Colonnina>> Function(Punto qui, ProfiloVeicolo v)? colonnine,
  }) : _cercaDistributori = distributori ?? distributoriVicini,
       _cercaColonnine = colonnine ?? ((q, v) => colonnineVicine(q, v, km: 12, quante: 25)) {
    auto.addListener(_forse);
    posizione.addListener(_forse);
    _forse();
  }

  final GestoreAuto auto;
  final GestorePosizione posizione;
  final Future<List<Distributore>> Function(Punto qui) _cercaDistributori;
  final Future<List<Colonnina>> Function(Punto qui, ProfiloVeicolo v) _cercaColonnine;

  List<Distributore> distributori = const [];
  List<Colonnina> colonnine = const [];

  /// Dove e per che auto si è cercato l'ultima volta.
  Punto? _cercatoDa;
  (bool, String, Carburante)? _perAuto;
  var _cercando = false;

  void _forse() {
    final qui = posizione.qui;
    if (qui == null || _cercando) return;
    final perAuto = (auto.elettrica, auto.veicolo.id, auto.carburante);
    final lontano = _cercatoDa == null || distanzaM(_cercatoDa!, qui) > 2000;
    if (!lontano && perAuto == _perAuto) return;
    unawaited(_cerca(qui, perAuto));
  }

  Future<void> _cerca(Punto qui, (bool, String, Carburante) perAuto) async {
    _cercando = true;
    _cercatoDa = qui;
    _perAuto = perAuto;
    try {
      if (auto.elettrica) {
        colonnine = await _cercaColonnine(qui, auto.veicolo);
        distributori = const [];
      } else {
        distributori = await _cercaDistributori(qui);
        colonnine = const [];
      }
      notifyListeners();
    } catch (e) {
      // Senza rete si riprova al prossimo spostamento.
      _cercatoDa = null;
      debugPrint('vicini: $e');
    } finally {
      _cercando = false;
    }
  }

  Distributore? distributore(String id) => distributori.where((d) => d.id == id).firstOrNull;
  Colonnina? colonnina(String id) => colonnine.where((c) => c.id == id).firstOrNull;

  /// Le due sorgenti della mappa, in GeoJSON.
  Map<String, Map<String, Object?>> dati() => {
    'gdanav-distributori': datiDistributori(distributori, auto.carburante),
    'gdanav-vicine': datiColonnineVicine(colonnine, auto.veicolo.connettori),
  };

  @override
  void dispose() {
    auto.removeListener(_forse);
    posizione.removeListener(_forse);
    super.dispose();
  }
}
