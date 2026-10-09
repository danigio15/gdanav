import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_guida.dart';
import 'gestore_ztl.dart';

/// Un avviso di ZTL mentre si guida, uguale sul telefono e sull'auto.
class AvvisoZtl {
  const AvvisoZtl({required this.zona, required this.titolo, required this.testo, this.metri, this.fuori = false});

  final ZonaLimitata zona;

  /// «ZTL Centro storico, attiva».
  final String titolo;

  /// «Il percorso la evita · fino alle 18:00».
  final String testo;

  /// Quanto manca.
  final double? metri;

  /// Fuori dal percorso, con la ZTL davanti: il più urgente.
  final bool fuori;

  /// Lo stesso avviso, a meno di cinquanta metri: non serve ridirlo all'auto.
  bool uguale(AvvisoZtl? a) =>
      a != null &&
      a.zona.id == zona.id &&
      a.titolo == titolo &&
      a.testo == testo &&
      ((a.metri ?? -50) / 50).round() == ((metri ?? -50) / 50).round();
}

/// Le ZTL attive mentre si guida (se si vogliono gli avvisi): sul percorso,
/// quella che il percorso gira al largo o in cui entra; fuori dal percorso,
/// quella che si ha davanti. Una sola per guida, condivisa fra il telefono e
/// lo schermo dell'auto, come le segnalazioni.
///
/// A voce si dice solo quello che può costare una multa: il percorso che ci
/// entra senza permesso, e la ZTL davanti quando si è usciti dal percorso.
class AvvisiZtl extends ChangeNotifier {
  AvvisiZtl._(this.guida, this.ztl, this._ora) {
    guida.addListener(_aggiorna);
    ztl.addListener(_aggiorna);
  }

  static final _perGuida = Expando<AvvisiZtl>();

  static AvvisiZtl di(GestoreGuida guida, GestoreZtl ztl, {DateTime Function()? orologio}) =>
      _perGuida[guida] ??= AvvisiZtl._(guida, ztl, orologio ?? DateTime.now);

  final GestoreGuida guida;
  final GestoreZtl ztl;
  final DateTime Function() _ora;

  /// Quanto prima si avvisa, lungo il percorso.
  static const avvisoM = 600.0;

  /// Un percorso che passa a meno di tanto dal bordo le passa accanto.
  static const accantoM = 60.0;

  /// Fuori dal percorso: quanto avanti si guarda.
  static const davantiM = 250.0;

  AvvisoZtl? avviso;

  ArchivioZtl? _zone;
  var _caricando = false;
  final _annunciate = <String>{};

  List<Punto>? _puntiLinea;
  Linea? _linea;

  /// Per il percorso di adesso: dove incontra ogni zona (i metri dalla
  /// partenza) e se ci entra; `null` se non la incontra.
  final _incontri = <String, (double, bool)?>{};
  final _bordi = <String, List<Linea>>{};

  /// L'ultima posizione fuori dal percorso, per sapere dove si va.
  Punto? _prima;

  void _aggiorna() {
    final a = guida.attiva ? guida.avanzamento : null;
    final p = guida.pronto;
    if (a == null || p == null || !ztl.scelte.avvisi) {
      if (!guida.attiva) _annunciate.clear();
      return _metti(null);
    }
    final zone = _zone;
    if (zone == null) {
      if (!_caricando) {
        _caricando = true;
        unawaited(
          ztl.zone().then((z) {
            _zone = z;
            _aggiorna();
          }),
        );
      }
      return;
    }
    if (zone.zone.isEmpty) return _metti(null);
    final fuori = a.posizioneSulPercorso == null || a.fuoriPercorso || guida.ricalcolando;
    _metti(fuori ? _davanti(zone) : _sulPercorso(zone, a, p.viaggio.percorso));
  }

  /// Sul percorso: la prima ZTL attiva che incontra entro [avvisoM].
  AvvisoZtl? _sulPercorso(ArchivioZtl zone, Avanzamento a, PercorsoCalcolato percorso) {
    _prima = null;
    final punti = percorso.punti;
    if (punti.length < 2) return null;
    if (!identical(punti, _puntiLinea)) {
      _puntiLinea = punti;
      _linea = Linea(punti);
      _incontri.clear();
    }
    final linea = _linea!;
    final qui = a.posizioneSulPercorso!;
    final ora = _ora();
    // Il pezzo di percorso davanti, fino al primo punto oltre [avvisoM]: su
    // una strada dritta i punti possono essere lontani un chilometro.
    final davanti = <Punto>[qui];
    for (var i = 0; i < punti.length; i++) {
      if (linea.cumulate[i] < a.percorsiM) continue;
      davanti.add(punti[i]);
      if (linea.cumulate[i] > a.percorsiM + avvisoM) break;
    }
    AvvisoZtl? primo;
    for (final z in zone.nel(Rettangolo.di(davanti).allargato(accantoM))) {
      if (z.tipo != TipoZona.ztl || !z.attivaAlle(ora) || z.contiene(qui)) continue;
      final incontro = _incontri.putIfAbsent(z.id, () => _incontra(z, punti, linea));
      if (incontro == null) continue;
      final (dove, entra) = incontro;
      final metri = dove - a.percorsiM;
      // Passata (qualche metro di tolleranza per chi la sta affiancando), o
      // ancora lontana.
      if (metri < -30 || metri > avvisoM) continue;
      final permesso = ztl.permessi[z.chiave] == true;
      final testo = !entra
          ? 'Il percorso la evita'
          : permesso
          ? 'Hai il permesso: il percorso ci passa'
          : 'Il percorso ci entra: non c\'era un\'altra strada';
      final av = AvvisoZtl(
        zona: z,
        titolo: '${z.titolo}, attiva',
        testo: _conOrario(testo, z, ora),
        metri: math.max(0.0, metri),
      );
      if (primo == null || av.metri! < primo.metri!) primo = av;
      if (entra && !permesso) _annuncia(z, '${z.titolo} attiva: il percorso ci entra.');
    }
    return primo;
  }

  /// Dove il percorso incontra [z] la prima volta — il primo punto dentro, o
  /// a meno di [accantoM] dal bordo — e se ci entra. Non conta quella da cui
  /// si parte.
  (double, bool)? _incontra(ZonaLimitata z, List<Punto> punti, Linea linea) {
    if (z.contiene(punti.first)) return null;
    final r = z.riquadro.allargato(accantoM);
    double? accanto;
    for (var i = 1; i < punti.length; i++) {
      final a = punti[i - 1], b = punti[i];
      if (!r.tocca(Rettangolo.di([a, b]))) continue;
      // Un tratto lungo si guarda ogni venti metri: i punti del percorso
      // possono stare prima e dopo la zona, senza nessuno accanto.
      final lungo = linea.cumulate[i] - linea.cumulate[i - 1];
      final passi = math.max(1, (lungo / 20).ceil());
      for (var k = 0; k <= passi; k++) {
        final t = k / passi;
        final q = Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
        if (!r.contiene(q)) continue;
        final m = linea.cumulate[i - 1] + lungo * t;
        if (z.contiene(q)) return (accanto ?? m, true);
        if (accanto == null && _vicino(z, q)) accanto = m;
      }
    }
    // Le passa solo accanto.
    return accanto == null ? null : (accanto, false);
  }

  bool _vicino(ZonaLimitata z, Punto q) =>
      (_bordi[z.id] ??= [for (final a in z.anelli) Linea([...a, a.first])]).any((l) => l.proietta(q).lontanoM <= accantoM);

  /// Fuori dal percorso: la ZTL attiva, senza permesso, che si ha davanti
  /// nella direzione in cui si va.
  AvvisoZtl? _davanti(ArchivioZtl zone) {
    final qui = guida.ultimaPosizione;
    if (qui == null) return null;
    final prima = _prima;
    if (prima == null || distanzaM(prima, qui) < 15) {
      _prima ??= qui;
      // Fermi, o quasi: resta quello che c'era.
      return avviso?.fuori ?? false ? avviso : null;
    }
    _prima = qui;
    final rotta = rottaGradi(prima, qui) * math.pi / 180;
    final ora = _ora();
    final permessi = ztl.permessi;
    for (var m = 25.0; m <= davantiM; m += 25) {
      final q = Punto(
        qui.lat + m * math.cos(rotta) / 111320,
        qui.lon + m * math.sin(rotta) / (111320 * math.cos(qui.lat * math.pi / 180)),
      );
      for (final z in zone.vicine(q, 5)) {
        if (z.tipo != TipoZona.ztl || permessi[z.chiave] == true || !z.attivaAlle(ora)) continue;
        if (z.contiene(qui) || !z.contiene(q)) continue;
        _annuncia(z, 'Attenzione: ${z.titolo} attiva, qui davanti.');
        return AvvisoZtl(
          zona: z,
          titolo: '${z.titolo}, attiva',
          testo: _conOrario('Qui davanti, e non hai il permesso', z, ora),
          metri: m,
          fuori: true,
        );
      }
    }
    return null;
  }

  /// « · fino alle 18:00», se si sa.
  static String _conOrario(String testo, ZonaLimitata z, DateTime ora) {
    final (:attiva, :cambia) = z.statoAlle(ora);
    return attiva && cambia != null ? '$testo · fino alle ${oraLunga(cambia)}' : testo;
  }

  void _annuncia(ZonaLimitata z, String frase) {
    if (_annunciate.add(z.chiave)) guida.annunciaAvviso(frase);
  }

  void _metti(AvvisoZtl? nuovo) {
    if (nuovo == null ? avviso == null : nuovo.uguale(avviso)) return;
    avviso = nuovo;
    notifyListeners();
  }
}
