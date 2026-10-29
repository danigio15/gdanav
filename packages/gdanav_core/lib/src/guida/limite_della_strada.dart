import 'dart:async';

import '../geo/geo.dart';

/* Il limite di velocità senza navigazione.
 *
 * Dal campo: «il limite si vede solo navigando, senza c'è solo il
 * tachimetro». In guida i limiti arrivano col percorso, strada per strada;
 * senza percorso non c'è niente da cui leggerli. Qui si chiede al server
 * delle strade (Valhalla, lo stesso dei percorsi) dove si sta andando: le
 * ultime posizioni si appoggiano alle strade, e il limite è quello
 * dell'ultima.
 *
 * Senza esagerare: una domanda ogni [ogniM] metri, mai più di una ogni
 * [almenoOgni], e solo andando. Da fermi (un semaforo) il limite resta.
 * Una risposta vecchia non resta per sempre: dopo [validoPerM] metri senza
 * una nuova (niente rete, un tunnel) il cartello sparisce, invece di
 * mostrare il limite di una strada lasciata da un pezzo. */
class LimiteDellaStrada {
  LimiteDellaStrada(
    this.chiedi, {
    this.cambiato,
    this.attivo,
    this.ogniM = 250,
    this.almenoOgni = const Duration(seconds: 10),
    this.dopoUnErrore = const Duration(seconds: 30),
    this.validoPerM = 1500,
  });

  /// La domanda al server: le ultime posizioni, la più recente per ultima.
  final Future<int?> Function(List<Punto> tracciato) chiedi;

  /// Chiamata quando [limiteKmh] cambia.
  final void Function()? cambiato;

  /// Se serve chiedere adesso (in guida no: i limiti li ha il percorso).
  final bool Function()? attivo;

  final double ogniM;
  final Duration almenoOgni;
  final Duration dopoUnErrore;
  final double validoPerM;

  /// Sotto questa velocità si è fermi: niente domande, il limite resta.
  static const fermoSottoMs = 3.0;

  /// Le posizioni tenute per la domanda: abbastanza per capire la strada.
  static const quantePosizioni = 8;

  /// Più vicine di così non aggiungono niente.
  static const passoMinimoM = 15.0;

  /// Più lontana di così dalla precedente: un salto del GPS, si riparte.
  static const saltoM = 800.0;

  int? _limite;
  final _traccia = <Punto>[];
  Punto? _chiestoDove;
  DateTime? _chiestoAlle;
  DateTime? _erroreAlle;
  Punto? _rispostaDove;
  var _inVolo = false;
  var _giro = 0;

  /// Il limite della strada di adesso, in km/h; `null` se non si sa.
  int? get limiteKmh => _limite;

  /// Una posizione nuova, con la sua velocità e l'ora.
  void posizione(Punto p, {required double velocitaMs, required DateTime alle}) {
    final ultima = _traccia.isEmpty ? null : _traccia.last;
    if (ultima != null && distanzaM(ultima, p) > saltoM) _traccia.clear();
    if (_traccia.isEmpty || distanzaM(_traccia.last, p) >= passoMinimoM) {
      _traccia.add(p);
      if (_traccia.length > quantePosizioni) _traccia.removeAt(0);
    }
    // Troppo lontani da dove valeva la risposta: non vale più.
    final dove = _rispostaDove;
    if (_limite != null && dove != null && distanzaM(dove, p) > validoPerM) _metti(null, null);

    if (_inVolo || velocitaMs < fermoSottoMs || _traccia.length < 3) return;
    if (attivo != null && !attivo!()) return;
    final quando = _chiestoAlle;
    if (quando != null && alle.difference(quando) < almenoOgni) return;
    final errore = _erroreAlle;
    if (errore != null && alle.difference(errore) < dopoUnErrore) return;
    final chiesto = _chiestoDove;
    if (chiesto != null && distanzaM(chiesto, p) < ogniM) return;
    unawaited(_chiedi(p, alle));
  }

  Future<void> _chiedi(Punto qui, DateTime alle) async {
    _inVolo = true;
    _chiestoDove = qui;
    _chiestoAlle = alle;
    final giro = _giro;
    try {
      final l = await chiedi(List.of(_traccia));
      if (giro != _giro) return;
      _erroreAlle = null;
      _metti(l, qui);
    } catch (_) {
      if (giro != _giro) return;
      // Si riprova più tardi; intanto resta quello che c'era, finché vale.
      _erroreAlle = alle;
      _chiestoDove = null;
    } finally {
      if (giro == _giro) _inVolo = false;
    }
  }

  void _metti(int? l, Punto? dove) {
    _rispostaDove = dove;
    if (l == _limite) return;
    _limite = l;
    cambiato?.call();
  }

  /// Si ricomincia da capo (una guida finita, un GPS che torna dopo tanto).
  void dimentica() {
    _giro++;
    _inVolo = false;
    _traccia.clear();
    _chiestoDove = null;
    _chiestoAlle = null;
    _erroreAlle = null;
    _metti(null, null);
  }
}
