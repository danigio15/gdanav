import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_auto.dart';
import 'gestore_consumo.dart';
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
    this.consumo,
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now;

  /// Il consumo imparato: in guida lo si misura e lo si corregge.
  final GestoreConsumo? consumo;

  /// Di quanti punti la batteria vera può scostarsi dal piano prima di
  /// ricalcolare le soste.
  static const scartoPerRicalcolo = 3.0;

  /// E non più spesso di così.
  static const intervalloRicalcolo = Duration(minutes: 2);

  /// Ogni quanto, in viaggio, si chiedono dati freschi a Home Assistant.
  static const intervalloDatiAuto = Duration(minutes: 1);
  DateTime _ultimaRichiestaDati = DateTime(0);

  /// Si chiede a ogni posizione, se è passato un minuto: niente timer.
  void _forseChiediDati() {
    final ora = _ora();
    if (ora.difference(_ultimaRichiestaDati) < intervalloDatiAuto) return;
    _ultimaRichiestaDati = ora;
    unawaited(auto.chiediAggiornamento());
  }

  MisuratoreConsumo? _misuratore;
  double? _batteriaInizio;
  var _kmMisurati = 0.0, _whMisurati = 0.0;
  DateTime _ultimoRicalcolo = DateTime(0);
  double _fattorePiano = 1;

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

  /// Con il ricalcolo automatico spento: perché converrebbe ricalcolare. Si
  /// mostra una scheda con «Ricalcola» e «No».
  String? proposta;
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

  DateTime? _partitoAlle;

  /// La batteria quando si è partiti (anche dopo un ricalcolo).
  double? get batteriaPartenza => _batteriaInizio ?? pronto?.batteriaPartenza;

  /// La batteria adesso: quella vera se l'auto l'ha mandata dopo la
  /// partenza (Home Assistant, Android Auto), altrimenti la stima del piano
  /// al punto in cui si è.
  ({double valore, bool misurata})? get batteriaOra {
    final p = pronto;
    if (p == null || p.termica) return null;
    final s = auto.stato, partito = _partitoAlle;
    if (s != null &&
        partito != null &&
        !s.letto.isBefore(partito) &&
        s.sorgente != TipoSorgente.manuale &&
        s.sorgente != TipoSorgente.stima) {
      return (valore: s.batteria, misurata: true);
    }
    return (valore: _prevista(p, (avanzamento?.percorsiM ?? 0) / 1000), misurata: false);
  }

  /// La batteria all'arrivo: quella del piano, spostata di quanto la vera
  /// si discosta da quella prevista.
  double? get batteriaArrivo {
    final p = pronto, ora = batteriaOra, piano = p?.viaggio.piano;
    if (p == null || piano == null || ora == null) return null;
    if (!ora.misurata) return piano.batteriaArrivo;
    final scarto = ora.valore - _prevista(p, (avanzamento?.percorsiM ?? 0) / 1000);
    return (piano.batteriaArrivo + scarto).clamp(0, 100).toDouble();
  }

  /// L'autonomia adesso: quella dell'auto se la dice (Home Assistant,
  /// Android Auto, OBD) ed è recente; altrimenti la batteria di adesso diviso
  /// il consumo del viaggio (vero, o previsto); senza viaggio la stima a 90
  /// km/h.
  ({double km, bool dallAuto})? get autonomiaOra {
    if (!auto.elettrica || (pronto?.termica ?? false)) return null;
    final s = auto.stato;
    if (s != null &&
        s.autonomiaKm != null &&
        s.sorgente != TipoSorgente.stima &&
        s.sorgente != TipoSorgente.manuale &&
        _ora().difference(s.letto) < const Duration(minutes: 10)) {
      return (km: s.autonomiaKm!, dallAuto: true);
    }
    final b = batteriaOra?.valore ?? s?.batteria, c = consumoKwh100;
    if (b != null && c != null && c > 5) {
      return (km: b / 100 * auto.veicolo.capacitaUtileKwh / c * 100, dallAuto: false);
    }
    final k = auto.autonomiaKm();
    return k == null ? null : (km: k, dallAuto: false);
  }

  /// Il consumo in kWh ogni 100 km: quello vero dopo qualche chilometro con i
  /// dati dell'auto, altrimenti quello previsto per il viaggio.
  double? get consumoKwh100 {
    final p = pronto, ora = batteriaOra;
    if (p == null) return null;
    // Misurato sui tratti guidati con i dati dell'auto, ricariche escluse.
    if (ora != null && ora.misurata && _kmMisurati >= 3) return _whMisurati / _kmMisurati / 10;
    final piano = p.viaggio.piano, totale = p.viaggio.percorso.lunghezzaM / 1000;
    if (piano == null || totale <= 0 || piano.energiaKwh <= 0) return null;
    return piano.energiaKwh / totale * 100;
  }

  /// Il profilo del piano al chilometro [km], fra i due punti vicini.
  static double _prevista(ViaggioPronto p, double km) {
    final profilo = p.viaggio.piano?.profiloBatteria ?? const <PuntoBatteria>[];
    if (profilo.isEmpty) return p.batteriaPartenza;
    if (km <= profilo.first.km) return profilo.first.batteria;
    for (var i = 1; i < profilo.length; i++) {
      final a = profilo[i - 1], b = profilo[i];
      if (km <= b.km) {
        final t = b.km == a.km ? 1.0 : (km - a.km) / (b.km - a.km);
        return a.batteria + t * (b.batteria - a.batteria);
      }
    }
    return profilo.last.batteria;
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
    _partitoAlle = _ora();
    _vicinoDetto = false;
    _guida = Guida(p.viaggio.percorso);
    _batteriaInizio = p.batteriaPartenza;
    _kmMisurati = 0;
    _whMisurati = 0;
    _nuovoPiano(p);
    auto.addListener(_datiAuto);
    _iscrizione = posizioni().listen(_posizione);
    _ultimaRichiestaDati = DateTime(0);
    _forseChiediDati();
    _evento('partenza');
    _racconta();
    notifyListeners();
  }

  Future<void> ferma() async {
    attiva = false;
    auto.removeListener(_datiAuto);
    _misuratore = null;
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
    _forseChiediDati();
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

  /// Si comincia a misurare sul piano nuovo, col modello senza correttivo.
  void _nuovoPiano(ViaggioPronto p) {
    // Auto termica: niente batteria da misurare.
    if (p.termica) {
      _misuratore = null;
      return;
    }
    final senza = consumo?.condizioni(auto.stato, conFattore: false) ?? const Condizioni();
    _fattorePiano = consumo?.imparato.fattore ?? 1;
    _misuratore = MisuratoreConsumo(
      percorso: p.viaggio.percorso,
      capacitaKwh: auto.veicolo.capacitaUtileKwh,
      profilo: (t) => energiaTrattoWh(t, auto.veicolo, senza),
    );
  }

  /// Una lettura vera dall'auto: si misura il consumo e, se la batteria si
  /// allontana dal piano, si ricalcolano le soste da dove si è.
  void _datiAuto() {
    final p = pronto, s = auto.stato, ora = batteriaOra;
    if (!attiva || p == null || p.termica || s == null || ora == null || !ora.misurata) return;
    final metri = avanzamento?.percorsiM ?? 0;
    final misura = _misuratore?.registra(batteria: s.batteria, metri: metri, inCarica: s.inCarica == true);
    if (misura != null) {
      _kmMisurati += misura.km;
      _whMisurati += misura.realeWh;
      unawaited(consumo?.registra(misura));
    }
    if (s.inCarica == true || ricalcolando) return;
    if (_ora().difference(_ultimoRicalcolo) < intervalloRicalcolo) return;
    final scarto = (ora.valore - _prevista(p, metri / 1000)).abs();
    final fattoreCambiato = ((consumo?.imparato.fattore ?? 1) - _fattorePiano).abs() > 0.05;
    if (scarto < scartoPerRicalcolo && !fattoreCambiato) return;
    if (viaggio.opzioni.ricalcoloAutomatico) {
      unawaited(_ricalcola(perConsumo: true));
    } else if (proposta == null) {
      // Si chiede una volta; se si dice di no, se ne riparla fra due minuti.
      _ultimoRicalcolo = _ora();
      proposta = ora.valore < _prevista(p, metri / 1000)
          ? 'Consumi più del previsto: ricalcolo le soste?'
          : 'Consumi meno del previsto: ricalcolo le soste?';
      notifyListeners();
    }
  }

  /// «Ricalcola», dal bottone o dalla scheda: da dove si è, con la batteria
  /// di adesso.
  Future<void> ricalcolaOra() async {
    proposta = null;
    if (!muto) unawaited(voce.parla('Ricalcolo il viaggio.'));
    await _ricalcola(perConsumo: true, detto: true);
  }

  /// «No» alla proposta.
  void lasciaCosi() {
    proposta = null;
    notifyListeners();
  }

  Future<void> _ricalcola({bool perConsumo = false, bool detto = false}) async {
    final d = viaggio.destinazione;
    if (d == null) return;
    ricalcolando = true;
    _ultimoRicalcolo = _ora();
    final prima = pronto?.viaggio.piano?.soste.map((s) => s.colonnina.id).toList();
    // Le soste scelte già passate non valgono più: si riparte da qui.
    final fatti = avanzamento?.percorsiM ?? 0;
    for (final c in pronto?.viaggio.colonnine ?? const <ColonninaSulPercorso>[]) {
      if (c.distanzaM <= fatti) viaggio.obbligate.remove(c.id);
    }
    notifyListeners();
    if (!perConsumo && !muto) unawaited(voce.parla('Ricalcolo il percorso.'));
    await viaggio.pianifica(d);
    ricalcolando = false;
    if (pronto case final p?) {
      _guida = Guida(p.viaggio.percorso);
      _nuovoPiano(p);
      final dopo = p.viaggio.piano?.soste.map((s) => s.colonnina.id).toList();
      if (perConsumo && !detto && !listEquals(prima, dopo) && !muto) {
        unawaited(voce.parla('Ho aggiornato le soste in base al consumo reale.'));
      }
    }
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
