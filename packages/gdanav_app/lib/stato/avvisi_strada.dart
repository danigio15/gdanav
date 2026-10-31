import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_guida.dart';
import 'gestore_segnalazioni.dart';
import 'scelte_avvisi.dart';

/// Le segnalazioni lungo la strada mentre si guida: quella che si avvicina
/// (detta a voce una volta) e quella appena passata a cui chiedere «c'è
/// ancora?»; e il Tutor, con la media. Una sola per guida, condivisa fra il
/// telefono e lo schermo dell'auto: si guida anche con il telefono in tasca.
///
/// Anche senza percorso: chi va in macchina senza una meta sente lo stesso
/// gli autovelox e le segnalazioni che ha davanti, nella direzione in cui va.
class AvvisiStrada extends ChangeNotifier {
  AvvisiStrada._(this.guida, this.segnalazioni) {
    guida.addListener(_aggiorna);
    segnalazioni.addListener(_aggiorna);
    segnalazioni.posizione.addListener(_aggiorna);
    guida.avvisi.addListener(_aggiorna);
  }

  static final _perGuida = Expando<AvvisiStrada>();

  static AvvisiStrada di(GestoreGuida guida, GestoreSegnalazioni segnalazioni) =>
      _perGuida[guida] ??= AvvisiStrada._(guida, segnalazioni);

  final GestoreGuida guida;
  final GestoreSegnalazioni segnalazioni;

  /// Quanto prima si avvisa, alla velocità di adesso, sulla strada col
  /// limite [limiteKmh] (se si sa): una quindicina di secondi in città (mai
  /// più di 300 m), venti fuori (300–600 m), trenta in autostrada
  /// (600–1200 m). Vedi [distanzaAvvisoM].
  static double avvisoAlla(double kmh, {int? limiteKmh}) => distanzaAvvisoM(kmh, limiteKmh: limiteKmh);

  /// Sopra il limite dell'autovelox di tanto, «rallenta».
  static const oltreKmh = 3;

  /// E se a tanti metri si è ancora sopra, lo si ridice.
  static const ridireM = 300.0;

  /// Senza percorso si avvisa solo in macchina: sopra questa velocità.
  static const senzaPercorsoDaKmh = 25.0;

  /// La prossima davanti, entro l'avviso, con i metri che mancano.
  (Segnalazione, double)? davanti;

  /// Appena passata (non un autovelox fisso): «c'è ancora?».
  Segnalazione? passata;

  /// Il Tutor che arriva, o quello in cui si è: con la media.
  StatoTutor? tutor;

  Linea? _linea;
  List<Punto>? _puntiLinea;
  final _annunciate = <String>{};
  final _rallentate = <String>{};
  final _chieste = <String>{};
  final _tutorDetti = <String>{};
  final _tutorSopra = <String>{};
  final _seguiTutor = SeguiTutor();

  double get _kmh => segnalazioni.posizione.velocitaAdesso();

  void _aggiorna() {
    final a = guida.attiva ? guida.avanzamento : null, punti = guida.pronto?.viaggio.percorso.punti;
    final tutte = segnalazioni.vicine;
    (Segnalazione, double)? primo;
    Segnalazione? dietro;
    StatoTutor? nuovoTutor;
    if (a != null && punti != null) {
      if (!identical(punti, _puntiLinea)) {
        _puntiLinea = punti;
        _linea = Linea(punti);
      }
      final linea = _linea!;
      (primo, dietro) = _sulPercorso(linea, a.percorsiM, a.limiteKmh, tutte);
      nuovoTutor = _tutor(linea, a.percorsiM);
    } else if (!guida.attiva) {
      primo = _senzaPercorso(tutte);
    }
    if (primo case (final s, final m)) _dici(s, m);
    if (primo?.$1.id != davanti?.$1.id ||
        primo?.$2 != davanti?.$2 ||
        dietro?.id != passata?.id ||
        !_stessoTutor(nuovoTutor, tutor)) {
      davanti = primo;
      passata = dietro;
      tutor = nuovoTutor;
      notifyListeners();
    }
  }

  /// Sul percorso: la prima davanti entro l'avviso, e quella appena passata.
  /// Conta la distanza lungo il percorso, non in linea d'aria: vedi
  /// [sulPercorso].
  ((Segnalazione, double)?, Segnalazione?) _sulPercorso(
    Linea linea,
    double percorsiM,
    int? limiteKmh,
    List<Segnalazione> tutte,
  ) {
    final entro = avvisoAlla(_kmh, limiteKmh: limiteKmh);
    final percorso = guida.pronto?.viaggio.percorso;
    (Segnalazione, double)? primo;
    Segnalazione? dietro;
    for (final s in tutte) {
      // Gli avvisi scelti spenti non si mostrano e non si dicono.
      if (guida.avvisi.spento(Avviso.diSegnalazione(s.tipo))) continue;
      final avanti = sulPercorso(linea, percorsiM, s, finoM: entro, limiteSul: percorso?.limiteSul);
      if (avanti == null) continue;
      if (avanti > 0 && (primo == null || avanti < primo.$2)) primo = (s, avanti);
      if (!s.fissa && avanti <= 0 && !_chieste.contains(s.id)) dietro = s;
    }
    return (primo, dietro);
  }

  /// Senza percorso: quelle che si hanno davanti, nella direzione in cui si
  /// va, in una striscia stretta lungo la linea dritta. Su una curva se ne
  /// perde qualcuna, mai se ne inventa. Vedi [davantiSenzaPercorso].
  (Segnalazione, double)? _senzaPercorso(List<Segnalazione> tutte) {
    final p = segnalazioni.posizione, qui = p.qui;
    if (qui == null || !p.rottaConosciuta || _kmh < senzaPercorsoDaKmh) return null;
    final limite = p.limiteKmh, entro = avvisoAlla(_kmh, limiteKmh: limite);
    (Segnalazione, double)? primo;
    for (final s in tutte) {
      if (guida.avvisi.spento(Avviso.diSegnalazione(s.tipo))) continue;
      final avanti = davantiSenzaPercorso(qui, p.rotta, s, finoM: entro, limiteStradaKmh: limite);
      if (avanti != null && (primo == null || avanti < primo.$2)) primo = (s, avanti);
    }
    return primo;
  }

  /// La voce: una volta quando arriva; per un autovelox col limite, se si
  /// va più forte, «rallenta», e di nuovo a [ridireM] se si è ancora sopra.
  void _dici(Segnalazione s, double m) {
    final quale = Avviso.diSegnalazione(s.tipo);
    final limite = s.tipo == TipoSegnalazione.autovelox ? s.limiteKmh : null;
    final sopra = limite != null && _kmh > limite + oltreKmh;
    if (_annunciate.add(s.id)) {
      guida.annunciaAvviso('${s.avviso} tra ${distanzaParlata(m)}.${sopra ? ' Rallenta.' : ''}', quale: quale);
      if (m <= ridireM) _rallentate.add(s.id);
      return;
    }
    if (sopra && m <= ridireM && _rallentate.add(s.id)) {
      guida.annunciaAvviso('Rallenta, limite $limite.', quale: quale);
    }
  }

  /// Il Tutor sul percorso: quando arriva, la media sopra il limite, la fine.
  StatoTutor? _tutor(Linea linea, double percorsiM) {
    if (guida.avvisi.spento(Avviso.tutor)) return null;
    final stato = _seguiTutor.aggiorna(linea, percorsiM, guida.ora(), segnalazioni.tutor);
    final t = stato?.tratto, limite = t?.limiteKmh;
    final conLimite = limite == null ? '' : ', limite $limite';
    switch (stato) {
      case TutorDavanti(:final metri) when _tutorDetti.add(t!.id):
        guida.annunciaAvviso('Tutor tra ${distanzaParlata(metri)}$conLimite.', quale: Avviso.tutor);
      case final DentroTutor d when d.sopra(oltreKmh) && _tutorSopra.add(t!.id):
        guida.annunciaAvviso('La media è ${d.mediaKmh!.round()}$conLimite: rallenta.', quale: Avviso.tutor);
      case FineTutor(:final mediaKmh):
        _tutorDetti.remove(t!.id);
        _tutorSopra.remove(t.id);
        guida.annunciaAvviso(
          mediaKmh == null ? 'Fine Tutor.' : 'Fine Tutor, media ${mediaKmh.round()}.',
          quale: Avviso.tutor,
        );
        return null;
      default:
    }
    return stato;
  }

  static bool _stessoTutor(StatoTutor? a, StatoTutor? b) => switch ((a, b)) {
    (null, null) => true,
    (TutorDavanti(), TutorDavanti()) =>
      a!.tratto.id == b!.tratto.id && (a as TutorDavanti).metri == (b as TutorDavanti).metri,
    (final DentroTutor x, final DentroTutor y) =>
      x.tratto.id == y.tratto.id && x.mediaKmh == y.mediaKmh && x.restantiM == y.restantiM,
    _ => false,
  };

  /// «C'è ancora?» Sì o No.
  void rispondi(Segnalazione s, bool ancora) {
    _chieste.add(s.id);
    segnalazioni.vota(s, ancora: ancora);
    if (passata?.id == s.id) {
      passata = null;
      notifyListeners();
    }
  }
}
