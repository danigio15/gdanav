import '../geo/geo.dart';
import 'autovelox.dart';

/// Dove si è rispetto a un Tutor sul percorso.
sealed class StatoTutor {
  const StatoTutor(this.tratto);

  final TrattoTutor tratto;
}

/// Il Tutor si avvicina: comincia fra [metri].
class TutorDavanti extends StatoTutor {
  const TutorDavanti(super.tratto, this.metri);

  final double metri;
}

/// Dentro il Tutor: la media fin qui ([mediaKmh], `null` nei primi secondi)
/// e quanto manca alla fine.
class DentroTutor extends StatoTutor {
  const DentroTutor(super.tratto, {required this.mediaKmh, required this.restantiM});

  final double? mediaKmh;
  final double restantiM;

  /// Sopra il limite, con [margine] km/h di tolleranza.
  bool sopra([int margine = 0]) {
    final m = mediaKmh, l = tratto.limiteKmh;
    return m != null && l != null && m > l + margine;
  }
}

/// Appena usciti: com'è andata.
class FineTutor extends StatoTutor {
  const FineTutor(super.tratto, {required this.mediaKmh});

  final double? mediaKmh;
}

/// Segue i Tutor lungo il percorso: quello che si avvicina, la media mentre
/// ci si è dentro, e la fine.
///
/// La media è quella che misurano i portali: la strada fatta dall'ingresso
/// diviso il tempo. La strada fatta si somma passo per passo (i metri
/// percorsi sul percorso), così regge anche a un ricalcolo nel mezzo.
class SeguiTutor {
  SeguiTutor({this.avvisoM = 1000});

  /// Quanto prima si dice che arriva.
  final double avvisoM;

  /// Un capo del Tutor a più di tanto dal percorso: il percorso non ci passa.
  static const lontanoM = 60.0;

  /// Prima di tanto la media non si dice: pochi metri, troppo incerta.
  static const primaDellaMedia = Duration(seconds: 15);

  Linea? _linea;
  final _sulPercorso = <String, (double, double)?>{};

  String? _dentro;
  DateTime? _da;
  double _fatti = 0;
  double? _ultimiM;

  /// Dove si è adesso, sulla [linea] del percorso a [percorsiM] dalla
  /// partenza, all'[ora]; [vicini] i Tutor intorno.
  StatoTutor? aggiorna(Linea linea, double percorsiM, DateTime ora, List<TrattoTutor> vicini) {
    if (!identical(linea, _linea)) {
      _linea = linea;
      _sulPercorso.clear();
      // Un percorso nuovo ricomincia a contare da qui.
      _ultimiM = null;
    }
    if (_ultimiM case final u?) {
      final passo = percorsiM - u;
      // All'indietro o a salti (il GPS che torna, un ricalcolo): non conta.
      if (passo > 0 && passo < 2000) _fatti += passo;
    }
    _ultimiM = percorsiM;

    TrattoTutor? dentro;
    (double, double)? capiDentro;
    (TrattoTutor, double)? prossimo;
    for (final t in vicini) {
      final capi = _sulPercorso.putIfAbsent(t.id, () => _capi(linea, t));
      if (capi == null) continue;
      final (inizio, fine) = capi;
      if (percorsiM >= inizio && percorsiM < fine) {
        dentro = t;
        capiDentro = capi;
      } else if (inizio > percorsiM && inizio - percorsiM <= avvisoM) {
        if (prossimo == null || inizio < prossimo.$2) prossimo = (t, inizio);
      }
    }

    // Usciti dal Tutor in cui si era: com'è andata.
    final era = _dentro;
    if (era != null && dentro?.id != era) {
      final media = _media(ora);
      final t = vicini.where((v) => v.id == era).firstOrNull;
      _dentro = null;
      _da = null;
      if (t != null) return FineTutor(t, mediaKmh: media);
    }
    if (dentro != null) {
      if (_dentro != dentro.id) {
        _dentro = dentro.id;
        _da = ora;
        _fatti = 0;
      }
      return DentroTutor(dentro, mediaKmh: _media(ora), restantiM: capiDentro!.$2 - percorsiM);
    }
    if (prossimo case (final t, final inizio)) return TutorDavanti(t, inizio - percorsiM);
    return null;
  }

  double? _media(DateTime ora) {
    final da = _da;
    if (da == null) return null;
    final tempo = ora.difference(da);
    if (tempo < primaDellaMedia) return null;
    return _fatti / tempo.inMilliseconds * 3600;
  }

  /// Dove il percorso passa dai due capi, nell'ordine giusto; `null` se non
  /// ci passa, o li fa al contrario (l'altra carreggiata).
  static (double, double)? _capi(Linea linea, TrattoTutor t) {
    final a = linea.proietta(t.inizio), b = linea.proietta(t.fine);
    if (a.lontanoM > lontanoM || b.lontanoM > lontanoM) return null;
    if (b.lungoM - a.lungoM < t.lunghezzaM * 0.5) return null;
    return (a.lungoM, b.lungoM);
  }
}
