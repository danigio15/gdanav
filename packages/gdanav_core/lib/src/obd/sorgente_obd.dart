import 'dart:async';

import '../veicolo/sorgente_dati_auto.dart';
import '../veicolo/stato_auto.dart';
import 'elm327.dart';
import 'profili_obd.dart';

/// I dati dell'auto dal dongle OBD, come fa ABRP: a giri, una richiesta per
/// volta, con il profilo del modello.
class SorgenteObd implements SorgenteDatiAuto {
  SorgenteObd({
    required this.apri,
    this.profilo = profiloStandard,
    this.intervallo = const Duration(seconds: 5),
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now;

  /// Apre il filo col dongle (Bluetooth nell'app).
  final Future<CanaleObd> Function() apri;
  final ProfiloObd profilo;
  final Duration intervallo;
  final DateTime Function() _ora;

  final _letture = StreamController<StatoAuto>.broadcast();
  Elm327? _elm;
  Timer? _giro;
  var _n = 0;
  var _occupato = false;
  final _ultimi = <CampoObd, double>{};

  /// Cosa è successo l'ultima volta: per dirlo all'utente.
  String? ultimoErrore;

  @override
  TipoSorgente get tipo => TipoSorgente.obd;

  @override
  Stream<StatoAuto> get letture => _letture.stream;

  /// Si collega e parte a giri. Se il dongle è spento o lontano non è un
  /// errore: si riprova ogni tanto, finché l'auto non si accende.
  @override
  Future<void> avvia() async {
    _giro ??= Timer.periodic(intervallo, (_) => giro());
    await giro();
  }

  /// Ogni quanti giri riprovare a collegarsi (6 × 5 s = 30 s).
  static const _riprovaOgni = 6;
  var _attesaCollegamento = 0;

  Future<bool> _collega() async {
    if (_attesaCollegamento > 0) {
      _attesaCollegamento--;
      return false;
    }
    try {
      final elm = Elm327(await apri());
      try {
        await elm.inizializza();
      } catch (_) {
        await elm.chiudi();
        rethrow;
      }
      _elm = elm;
      ultimoErrore = null;
      return true;
    } catch (e) {
      ultimoErrore = '$e';
      _attesaCollegamento = _riprovaOgni - 1;
      return false;
    }
  }

  /// Un giro di richieste. Chi non risponde si salta; se il dongle tace del
  /// tutto si riprova al giro dopo.
  Future<void> giro() async {
    if (_occupato) return;
    _occupato = true;
    try {
      if (_elm == null && !await _collega()) return;
      final elm = _elm!;
      var risposte = 0;
      for (final l in profilo.letture) {
        if (_n % l.ogni != 0 && _ultimi.containsKey(l.campo)) continue;
        try {
          final b = await elm.richiesta(l.pid, intestazione: l.intestazione);
          risposte++;
          final v = b == null ? null : l.formula(b);
          if (v != null) _ultimi[l.campo] = v;
        } on ErroreObd catch (e) {
          ultimoErrore = e.messaggio;
        }
      }
      // Il dongle non risponde più (auto spenta, fuori portata): si richiude
      // e si riproverà.
      if (risposte == 0) {
        await elm.chiudi().catchError((Object _) {});
        _elm = null;
        return;
      }
      _n++;
      final stato = statoDaObd(_ultimi, _ora());
      if (stato != null) _letture.add(stato);
    } finally {
      _occupato = false;
    }
  }

  @override
  Future<void> ferma() async {
    _giro?.cancel();
    _giro = null;
    await _elm?.chiudi();
    _elm = null;
  }
}
