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

  /// Il consumo di riferimento scritto a mano, per esempio quello calibrato
  /// di ABRP («Consumo di riferimento calibrato 188 Wh/km», alla velocità di
  /// riferimento, di solito 110 km/h): si parte da lì invece che dalla
  /// scheda tecnica, e guidando lo si corregge. Le misure per tipo di strada
  /// restano, per la precisione.
  Future<void> impostaRiferimento({required double whKm, required double kmh, required ProfiloVeicolo veicolo}) async {
    final r = RiferimentoConsumo(
      whKm: whKm,
      kmh: kmh,
      fattore: fattoreDaRiferimento(whKm: whKm, kmh: kmh, profilo: veicolo),
    );
    imparato = ConsumoImparato(fattore: r.fattore, strade: imparato.strade, riferimento: r);
    notifyListeners();
    if (_veicolo case final v?) await archivio.salvaConsumo(v, imparato);
  }

  Future<void> azzera() async {
    imparato = const ConsumoImparato();
    notifyListeners();
    if (_veicolo case final v?) await archivio.salvaConsumo(v, imparato);
  }

  /// Le condizioni per il pianificatore: il correttivo imparato (col
  /// consumo medio dell'auto di [veicolo], se lo dice) e, se l'auto li dice,
  /// la temperatura esterna e il clima. Il conto è in
  /// [ConsumoImparato.condizioni].
  Condizioni condizioni(StatoAuto? s, {bool conFattore = true, ProfiloVeicolo? veicolo}) =>
      imparato.condizioni(s, profilo: veicolo, conFattore: conFattore);
}
