import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_guida.dart';
import 'gestore_segnalazioni.dart';

/// Le segnalazioni lungo la strada mentre si guida: quella che si avvicina
/// (detta a voce una volta) e quella appena passata a cui chiedere «c'è
/// ancora?». Una sola per guida, condivisa fra il telefono e lo schermo
/// dell'auto: si guida anche con il telefono in tasca.
class AvvisiStrada extends ChangeNotifier {
  AvvisiStrada._(this.guida, this.segnalazioni) {
    guida.addListener(_aggiorna);
    segnalazioni.addListener(_aggiorna);
  }

  static final _perGuida = Expando<AvvisiStrada>();

  static AvvisiStrada di(GestoreGuida guida, GestoreSegnalazioni segnalazioni) =>
      _perGuida[guida] ??= AvvisiStrada._(guida, segnalazioni);

  final GestoreGuida guida;
  final GestoreSegnalazioni segnalazioni;

  /// Quanto prima si avvisa.
  static const avvisoM = 800.0;

  /// La prossima davanti, entro [avvisoM], con i metri che mancano.
  (Segnalazione, double)? davanti;

  /// Appena passata (non un autovelox fisso): «c'è ancora?».
  Segnalazione? passata;

  Linea? _linea;
  List<Punto>? _puntiLinea;
  final _annunciate = <String>{};
  final _chieste = <String>{};

  void _aggiorna() {
    final a = guida.attiva ? guida.avanzamento : null, punti = guida.pronto?.viaggio.percorso.punti;
    final tutte = segnalazioni.vicine;
    if (a == null || punti == null || tutte.isEmpty) {
      if (davanti != null || passata != null) {
        davanti = null;
        passata = null;
        notifyListeners();
      }
      return;
    }
    if (!identical(punti, _puntiLinea)) {
      _puntiLinea = punti;
      _linea = Linea(punti);
    }
    (Segnalazione, double)? primo;
    Segnalazione? dietro;
    final linea = _linea!;
    for (final s in tutte) {
      final p = linea.proietta(s.punto);
      // Un autovelox fisso sta sul bordo della strada: più vicino, e solo
      // se guarda chi va nella nostra direzione (non l'altra carreggiata).
      if (p.lontanoM > (s.fissa ? 30 : 40)) continue;
      if (s.fissa) {
        final i = p.segmento.clamp(0, linea.punti.length - 2);
        if (!s.riguarda(rottaGradi(linea.punti[i], linea.punti[i + 1]))) continue;
      }
      final avanti = p.lungoM - a.percorsiM;
      if (avanti > 0 && avanti <= avvisoM && (primo == null || avanti < primo.$2)) primo = (s, avanti);
      if (!s.fissa && avanti <= 0 && avanti > -250 && !_chieste.contains(s.id)) dietro = s;
    }
    if (primo case (final s, final m) when _annunciate.add(s.id)) {
      guida.annuncia('${s.avviso} tra ${distanzaParlata(m)}.');
    }
    if (primo?.$1.id != davanti?.$1.id || primo?.$2 != davanti?.$2 || dietro?.id != passata?.id) {
      davanti = primo;
      passata = dietro;
      notifyListeners();
    }
  }

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
