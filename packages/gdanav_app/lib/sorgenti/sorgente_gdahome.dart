import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Com'è fatta l'auto che gdahome ha nella sezione Auto della sua plancia.
@immutable
class AutoDiGdahome {
  const AutoDiGdahome({this.nome = '', this.marca = '', this.modello = '', this.kwh});

  /// Come l'ha chiamata chi l'ha configurata («La Zoe»).
  final String nome;
  final String marca;
  final String modello;

  /// La capacità della batteria scritta nella plancia, se c'è.
  final double? kwh;

  /// Il nome da far vedere: quello dato, se no marca e modello.
  String get etichetta => nome.isNotEmpty ? nome : '$marca $modello'.trim();

  @override
  bool operator ==(Object other) =>
      other is AutoDiGdahome &&
      other.nome == nome &&
      other.marca == marca &&
      other.modello == modello &&
      other.kwh == kwh;

  @override
  int get hashCode => Object.hash(nome, marca, modello, kwh);
}

/// La fonte «gdahome»: i dati dell'auto dalla casa, quando gdanav gira dentro
/// l'app gdahome.
///
/// Niente codice né QR: gdahome è già collegata alla sua casa, sa quale auto
/// c'è nella sezione Auto della plancia e quali sensori la raccontano, e
/// manda qui ogni lettura appena Home Assistant la cambia ([manda]). Chi ospita
/// gdanav la crea e la passa a `preparaGdanav`; l'app gdanav da sola non ce
/// l'ha.
class SorgenteGdahome extends ChangeNotifier implements SorgenteDatiAuto {
  final _letture = StreamController<StatoAuto>.broadcast();

  /// L'ultima lettura: chi arriva dopo la riceve subito ([avvia]).
  StatoAuto? ultima;

  /// L'auto della plancia, se gdahome ne ha una.
  AutoDiGdahome? get auto => _auto;
  AutoDiGdahome? _auto;

  /// Se la casa è collegata adesso: senza, i dati invecchiano e basta.
  bool get collegata => _collegata;
  bool _collegata = false;

  @override
  TipoSorgente get tipo => TipoSorgente.gdahome;

  @override
  Stream<StatoAuto> get letture => _letture.stream;

  /// Una lettura nuova dalla casa.
  void manda(StatoAuto lettura) {
    final s = lettura.sorgente == tipo ? lettura : _conSorgente(lettura);
    ultima = s;
    _letture.add(s);
    notifyListeners();
  }

  /// Quale auto c'è nella plancia; `null` se non ce n'è nessuna.
  void descrivi(AutoDiGdahome? auto) {
    if (auto == _auto) return;
    _auto = auto;
    notifyListeners();
  }

  void collegamento(bool si) {
    if (si == _collegata) return;
    _collegata = si;
    notifyListeners();
  }

  @override
  Future<void> avvia() async {
    if (ultima case final u?) _letture.add(u);
  }

  @override
  Future<void> ferma() async {}

  static StatoAuto _conSorgente(StatoAuto l) => StatoAuto(
    sorgente: TipoSorgente.gdahome,
    letto: l.letto,
    batteria: l.batteria,
    autonomiaKm: l.autonomiaKm,
    inCarica: l.inCarica,
    potenzaCaricaKw: l.potenzaCaricaKw,
    temperaturaBatteriaC: l.temperaturaBatteriaC,
    latitudine: l.latitudine,
    longitudine: l.longitudine,
    temperaturaEsternaC: l.temperaturaEsternaC,
    velocitaKmh: l.velocitaKmh,
    potenzaKw: l.potenzaKw,
    odometroKm: l.odometroKm,
  );
}
