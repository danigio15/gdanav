import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';

/// Il consumo imparato della tua auto: parte dalla scheda tecnica e si
/// corregge viaggio dopo viaggio con la batteria vera (Home Assistant,
/// Android Auto, OBD). Uno per modello scelto.
class GestoreConsumo extends ChangeNotifier {
  GestoreConsumo(this.archivio);

  final Archivio archivio;
  ConsumoImparato imparato = const ConsumoImparato();
  String? _veicolo;

  Future<void> carica(String veicoloId) async {
    if (veicoloId == _veicolo) return;
    _veicolo = veicoloId;
    imparato = await archivio.consumo(veicoloId);
    notifyListeners();
  }

  Future<void> registra(MisuraConsumo m) async {
    imparato = imparato.con(previstoWh: m.previstoWh, realeWh: m.realeWh, km: m.km, tipo: m.tipo);
    notifyListeners();
    if (_veicolo case final v?) await archivio.salvaConsumo(v, imparato);
  }

  Future<void> azzera() async {
    imparato = const ConsumoImparato();
    notifyListeners();
    if (_veicolo case final v?) await archivio.salvaConsumo(v, imparato);
  }

  /// Le condizioni per il pianificatore: il correttivo imparato e, se l'auto
  /// la dice, la temperatura esterna (col clima che ne segue).
  Condizioni condizioni(StatoAuto? s, {bool conFattore = true}) {
    final f = conFattore ? imparato.fattore : 1.0;
    // Dove si è misurato abbastanza, il correttivo di quel tipo di strada.
    final strade = conFattore
        ? {
            for (final MapEntry(:key, :value) in imparato.strade.entries)
              if (value.affidabile) key: value.fattore,
          }
        : const <TipoStrada, double>{};
    final t = s?.temperaturaEsternaC;
    return t == null
        ? Condizioni(fattoreConsumo: f, fattoriStrada: strade)
        : Condizioni.daMeteo(temperaturaC: t, fattoreConsumo: f, fattoriStrada: strade);
  }
}
