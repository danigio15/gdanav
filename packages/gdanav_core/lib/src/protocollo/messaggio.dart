import 'dart:math';

/// Chi manda: serve anche a cifrare, perché un messaggio dell'app
/// rispedito all'app non si apra.
enum Mittente { casa, app }

/// I tipi di messaggio. L'elenco completo, con i campi, è in
/// `docs/protocollo.md`.
abstract final class TipoMessaggio {
  // casa → app
  static const statoAuto = 'stato_auto';
  static const pianificaViaggio = 'pianifica_viaggio';
  static const comandiDisponibili = 'comandi_disponibili';
  static const esitoComando = 'esito_comando';

  // app → casa
  static const viaggio = 'viaggio';
  static const evento = 'evento';
  static const socNecessario = 'soc_necessario';
  static const comando = 'comando';
  static const richiediStato = 'richiedi_stato';
}

class Messaggio {
  Messaggio({required this.tipo, Map<String, Object?>? dati, String? id, DateTime? ts})
    : dati = dati ?? const {},
      id = id ?? _nuovoId(),
      ts = (ts ?? DateTime.now()).toUtc();

  factory Messaggio.daJson(Map<String, Object?> json) => Messaggio(
    tipo: json['tipo'] as String,
    id: json['id'] as String,
    ts: DateTime.parse(json['ts'] as String),
    dati: (json['dati'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  final String tipo;
  final String id;
  final DateTime ts;
  final Map<String, Object?> dati;

  Map<String, Object?> toJson() => {'tipo': tipo, 'id': id, 'ts': ts.toIso8601String(), 'dati': dati};

  static String _nuovoId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
