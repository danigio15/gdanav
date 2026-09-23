import 'dart:async';

import 'package:gdanav_core/gdanav_core.dart';

/// La batteria scritta a mano, alla partenza.
class SorgenteManuale implements SorgenteDatiAuto {
  final _letture = StreamController<StatoAuto>.broadcast();

  @override
  TipoSorgente get tipo => TipoSorgente.manuale;

  @override
  Stream<StatoAuto> get letture => _letture.stream;

  void imposta(double batteria) => _letture.add(StatoAuto(sorgente: tipo, letto: DateTime.now(), batteria: batteria));

  @override
  Future<void> avvia() async {}

  @override
  Future<void> ferma() async {}
}
