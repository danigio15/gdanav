import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_auto.dart';
import 'gestore_viaggio.dart';
import 'voce.dart';

/// La guida passo-passo: segue la posizione, dice le manovre, ricalcola se
/// si esce di strada e racconta il viaggio a Home Assistant.
class GestoreGuida extends ChangeNotifier {
  GestoreGuida({
    required this.viaggio,
    required this.auto,
    required this.posizioni,
    required this.voce,
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now;

  final GestoreViaggio viaggio;
  final GestoreAuto auto;

  /// Le posizioni GPS mentre si guida.
  final Stream<Punto> Function() posizioni;
  final Voce voce;
  final DateTime Function() _ora;

  Guida? _guida;
  StreamSubscription<Punto>? _iscrizione;
  Avanzamento? avanzamento;
  var attiva = false;
  var ricalcolando = false;
  var muto = false;
  DateTime? _ultimoRacconto;
  var _vicinoDetto = false;

  ViaggioPronto? get pronto => switch (viaggio.stato) {
    final ViaggioPronto p => p,
    _ => null,
  };

  /// L'ora d'arrivo con quello che resta, più le ricariche ancora da fare.
  DateTime? get arrivoAlle {
    final a = avanzamento, p = pronto;
    if (a == null || p == null) return p?.arrivoAlle;
    final ricariche = (p.viaggio.piano?.soste ?? const <Sosta>[])
        .where((s) => s.colonnina.distanzaM > a.percorsiM)
        .fold(Duration.zero, (t, s) => t + s.ricarica);
    return _ora().add(a.restante + ricariche);
  }

  /// La prossima sosta ancora davanti, e quanto manca.
  (Sosta, double)? get prossimaSosta {
    final a = avanzamento, p = pronto;
    if (p == null) return null;
    final fatti = a?.percorsiM ?? 0;
    for (final s in p.viaggio.piano?.soste ?? const <Sosta>[]) {
      if (s.colonnina.distanzaM > fatti) return (s, s.colonnina.distanzaM - fatti);
    }
    return null;
  }

  void avvia() {
    final p = pronto;
    if (p == null || attiva) return;
    attiva = true;
    _vicinoDetto = false;
    _guida = Guida(p.viaggio.percorso);
    _iscrizione = posizioni().listen(_posizione);
    _evento('partenza');
    _racconta();
    notifyListeners();
  }

  Future<void> ferma() async {
    attiva = false;
    await _iscrizione?.cancel();
    _iscrizione = null;
    await voce.zitta();
    _racconta(inViaggio: false);
    notifyListeners();
  }

  /// Una frase fuori dalle manovre (una segnalazione più avanti).
  void annuncia(String frase) {
    if (!muto) unawaited(voce.parla(frase));
  }

  void alternaVoce() {
    muto = !muto;
    if (muto) voce.zitta();
    notifyListeners();
  }

  Future<void> _posizione(Punto qui) async {
    final g = _guida;
    if (g == null || !attiva) return;
    final a = g.aggiorna(qui);
    avanzamento = a;
    if (a.daDire case final frase? when !muto) unawaited(voce.parla(frase));
    if (a.arrivato) {
      _evento('arrivo');
      notifyListeners();
      await ferma();
      return;
    }
    if (!_vicinoDetto && a.restante.inMinutes < 10) {
      _vicinoDetto = true;
      _evento('arrivo_vicino', {'minuti': a.restante.inMinutes});
    }
    if (a.fuoriPercorso && !ricalcolando) unawaited(_ricalcola());
    if (_ultimoRacconto == null || _ora().difference(_ultimoRacconto!) > const Duration(minutes: 1)) _racconta();
    notifyListeners();
  }

  Future<void> _ricalcola() async {
    final d = viaggio.destinazione;
    if (d == null) return;
    ricalcolando = true;
    notifyListeners();
    if (!muto) unawaited(voce.parla('Ricalcolo il percorso.'));
    await viaggio.pianifica(d);
    ricalcolando = false;
    if (pronto case final p?) _guida = Guida(p.viaggio.percorso);
    notifyListeners();
  }

  /// A Home Assistant, se abbinato: dove si va, quando si arriva, con quanta
  /// batteria. Se il relay non c'è, niente.
  void _racconta({bool inViaggio = true}) {
    final r = auto.relay, p = pronto;
    if (r == null || p == null) return;
    _ultimoRacconto = _ora();
    final sosta = prossimaSosta;
    unawaited(
      r
          .manda(
            Messaggio(
              tipo: TipoMessaggio.viaggio,
              dati: {
                'in_viaggio': inViaggio,
                'destinazione': {
                  'nome': p.destinazione.nome,
                  'lat': p.destinazione.posizione.lat,
                  'lon': p.destinazione.posizione.lon,
                },
                'eta': ?arrivoAlle?.toUtc().toIso8601String(),
                'batteria_arrivo': ?p.viaggio.piano?.batteriaArrivo,
                if (sosta != null)
                  'prossima_sosta': {'nome': sosta.$1.colonnina.nome, 'batteria_arrivo': sosta.$1.batteriaArrivo},
              },
            ),
          )
          .catchError((Object _) {}),
    );
  }

  void _evento(String nome, [Map<String, Object?> dati = const {}]) {
    final r = auto.relay;
    if (r == null) return;
    unawaited(
      r.manda(Messaggio(tipo: TipoMessaggio.evento, dati: {'evento': nome, ...dati})).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _iscrizione?.cancel();
    super.dispose();
  }
}
