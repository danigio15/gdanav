import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Quello che l'app ricorda: l'abbinamento con Home Assistant (contiene la
/// chiave, quindi sta nel portachiavi del telefono) e come è messo lo switch.
class Archivio {
  Archivio([FlutterSecureStorage? portachiavi]) : _p = portachiavi ?? const FlutterSecureStorage();

  final FlutterSecureStorage _p;

  static const _abbinamento = 'abbinamento_home_assistant';
  static const _fonte = 'fonte_dati_auto';

  Future<Abbinamento?> abbinamento() async {
    final uri = await _p.read(key: _abbinamento);
    if (uri == null) return null;
    try {
      return Abbinamento.daUri(uri);
    } on FormatException {
      return null;
    }
  }

  Future<void> salvaAbbinamento(Abbinamento? a) =>
      a == null ? _p.delete(key: _abbinamento) : _p.write(key: _abbinamento, value: a.uri);

  /// `automatica` oppure il nome di una [TipoSorgente].
  Future<ModalitaFonte> fonte() async {
    final nome = await _p.read(key: _fonte);
    final tipo = TipoSorgente.values.where((t) => t.name == nome).firstOrNull;
    return tipo == null ? const Automatica() : Fissa(tipo);
  }

  Future<void> salvaFonte(ModalitaFonte m) => _p.write(
    key: _fonte,
    value: switch (m) {
      Automatica() => 'automatica',
      Fissa(:final sorgente) => sorgente.name,
    },
  );
}
