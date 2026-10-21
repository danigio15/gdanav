import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Com'è fatta l'auto che GdAHome ha nella sezione Auto della sua plancia.
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

/// La fonte «GdAHome»: i dati dell'auto dalla casa, quando GdANav gira dentro
/// l'app GdAHome.
///
/// Niente codice né QR: GdAHome è già collegata alla sua casa, sa quale auto
/// c'è nella sezione Auto della plancia e quali sensori la raccontano, e
/// manda qui ogni lettura appena Home Assistant la cambia ([manda]). Chi ospita
/// GdANav la crea e la passa a `preparaGdanav`; l'app GdANav da sola non ce
/// l'ha.
class SorgenteGdahome extends ChangeNotifier implements SorgenteDatiAuto {
  final _letture = StreamController<StatoAuto>.broadcast();

  /// L'ultima lettura: chi arriva dopo la riceve subito ([avvia]).
  StatoAuto? ultima;

  /// L'auto della plancia, se GdAHome ne ha una.
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
    final s = lettura.sorgente == tipo && _consumo.isEmpty ? lettura : _conSorgente(lettura, _consumo);
    ultima = s;
    _letture.add(s);
    notifyListeners();
  }

  /// I dati del consumo che GdAHome legge dai sensori dell'auto, coi nomi
  /// del messaggio `stato_auto` di Home Assistant (`energia_kwh`,
  /// `capacita_kwh`, `consumo_medio_kwh100`, `potenza_clima_w`,
  /// `clima_acceso`, `batteria_in_riscaldamento`, `temperatura_interna_c`:
  /// il contratto di GdAAuto, `docs/DATI-AUTO.md`). Vanno nelle letture
  /// che li hanno vuoti; uno che cambia rimanda subito l'ultima lettura.
  ///
  /// È una mappa e non campi di [StatoAuto] perché GdAHome la manda anche a
  /// un GdANav di prima, che semplicemente non ha questo metodo.
  set datiDelConsumo(Map<String, Object?> dati) {
    final nuovi = Map<String, Object?>.unmodifiable(dati);
    if (mapEquals(nuovi, _consumo)) return;
    _consumo = nuovi;
    if (ultima case final u?) manda(u);
  }

  Map<String, Object?> _consumo = const {};

  /// Come si chiede alla casa di rileggere l'auto adesso: lo mette chi
  /// ospita GdANav (GdAHome chiama `homeassistant.update_entity` sui sensori
  /// dell'auto). Senza, i dati arrivano solo quando l'integrazione dell'auto
  /// li aggiorna da sé, che per alcune vuol dire ogni mezz'ora o più.
  Future<void> Function()? aggiorna;

  /// Come si manda un comando alla casa e se ne aspetta la risposta: lo
  /// mette chi ospita GdANav (GdAHome, sul suo filo con la casa). Serve ai
  /// viaggi pianificati, che dentro GdAHome stanno nella casa
  /// (`ponte/viaggi/*`): la casa sa chi chiede, e ognuno vede solo i suoi.
  /// `null` in GdANav da sola, o finché GdAHome non ha una casa.
  Future<Object?> Function(Map<String, Object?> comando)? get chiedi => _chiedi;
  Future<Object?> Function(Map<String, Object?> comando)? _chiedi;
  set chiedi(Future<Object?> Function(Map<String, Object?> comando)? c) {
    if (identical(c, _chiedi)) return;
    _chiedi = c;
    notifyListeners();
  }

  /// L'ultima ricarica a casa dell'auto della plancia (`ponte/auto/
  /// ricariche-di-casa`): quanti kWh, quanti col sole, gli euro di rete,
  /// fino a che percentuale. Per il costo vero del viaggio. `null` fuori da
  /// GdAHome, senza casa, o se la casa non ne ha ancora vista una.
  Future<RicaricaDiCasa?> ricaricaDiCasa() async {
    final c = _chiedi;
    if (c == null) return null;
    try {
      final r = await c({'type': 'ponte/auto/ricariche-di-casa'}).timeout(const Duration(seconds: 8));
      final elenco = r is Map ? r['ricariche'] : null;
      if (elenco is! List || elenco.isEmpty) return null;
      final voci = elenco.whereType<Map>().toList();
      final nomi = {_auto?.nome, _auto?.etichetta}..removeWhere((n) => n == null || n.isEmpty);
      final sua = voci.where((v) => nomi.contains(v['nome'])).firstOrNull ?? (voci.length == 1 ? voci.single : null);
      return RicaricaDiCasa.daJson(sua);
    } catch (e) {
      debugPrint('GdAHome, la ricarica di casa: $e');
      return null;
    }
  }

  /// In viaggio, all'avvio e quando si torna nell'app: dati freschi, se chi
  /// ospita sa chiederli. Un errore non si propaga: i dati di prima restano.
  Future<void> chiediAggiornamento() async {
    try {
      await aggiorna?.call();
    } catch (e) {
      debugPrint('GdAHome, aggiornamento dell\'auto: $e');
    }
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

  static double? _numero(Map<String, Object?> d, String nome) => (d[nome] as num?)?.toDouble();

  static StatoAuto _conSorgente(StatoAuto l, Map<String, Object?> d) => StatoAuto(
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
    energiaKwh: l.energiaKwh ?? _numero(d, 'energia_kwh'),
    capacitaKwh: l.capacitaKwh ?? _numero(d, 'capacita_kwh'),
    consumoMedioKwh100: l.consumoMedioKwh100 ?? _numero(d, 'consumo_medio_kwh100'),
    potenzaClimaW: l.potenzaClimaW ?? _numero(d, 'potenza_clima_w'),
    climaAcceso: l.climaAcceso ?? d['clima_acceso'] as bool?,
    batteriaInRiscaldamento: l.batteriaInRiscaldamento ?? d['batteria_in_riscaldamento'] as bool?,
    temperaturaInternaC: l.temperaturaInternaC ?? _numero(d, 'temperatura_interna_c'),
  );
}
