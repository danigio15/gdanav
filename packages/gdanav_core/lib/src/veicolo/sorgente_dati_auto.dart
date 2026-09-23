import 'stato_auto.dart';

/// Una cosa che sa dire com'è messa l'auto.
///
/// Ogni implementazione vive dove ha senso: Home Assistant qui nel motore
/// (è Dart puro), Android Auto e OBD nell'app, perché passano dal codice
/// nativo.
abstract interface class SorgenteDatiAuto {
  TipoSorgente get tipo;

  /// Le letture, man mano che arrivano. Una sorgente che non ha dati
  /// (l'auto non li passa, il dongle non è collegato) semplicemente tace.
  Stream<StatoAuto> get letture;

  Future<void> avvia();
  Future<void> ferma();
}
