import 'dart:math' as math;

import '../geo/geo.dart';

/* ─── L'auto sulla strada, anche senza percorso ─────────────────────────────
 *
 * Dal campo: «capita che il simbolino dell'auto non sia sulla strada ma a
 * fianco, vicino. Gli altri navigatori mettono sempre la macchina sulla
 * strada anche quando il GPS la darebbe fuori, se è molto vicina». In guida
 * l'auto si aggancia al percorso ([Guida], entro venti metri); senza
 * destinazione, o uscendo dal percorso, si disegnava dove diceva il GPS: fra
 * i palazzi cinque, quindici metri di lato, sul marciapiede o nelle case.
 *
 * [AggancioStrada] è un map matching leggero: dalla lettura del GPS e dalle
 * strade che ci sono attorno (le tessere della mappa) il punto più vicino
 * della strada giusta. Con quattro prudenze:
 *  - **mai lontano**: oltre [AggancioStrada.sogliaM] non si aggancia (un
 *    parcheggio, una strada che la mappa non ha), e si disegna il GPS;
 *  - **mai di traverso**: andando, la strada deve andare come l'auto (entro
 *    [AggancioStrada.direzioneGradi]); a un incrocio la traversa più vicina
 *    non ruba l'auto a quella su cui si va;
 *  - **mai contromano** su un senso unico: lì si è sull'altra carreggiata;
 *  - **non si salta fra due parallele**: la strada su cui si è si tiene
 *    finché un'altra non è più vicina di [AggancioStrada.margineCambioM]
 *    metri per [AggancioStrada.lettureCambio] letture di fila. */

/// Un pezzo di strada attorno all'auto: i suoi punti, e il verso in cui si
/// può andare ([senso] 1 nel verso dei punti, -1 al contrario, 0 tutti e due).
class TrattoStrada {
  const TrattoStrada(this.punti, {this.senso = 0});

  final List<Punto> punti;
  final int senso;
}

/// Dove si è agganciati: il [punto] sulla strada, la [rotta] della strada
/// nel verso in cui si va, e quanto era lontano il GPS ([lontanoM]).
typedef Agganciato = ({Punto punto, double rotta, double lontanoM});

/// Vedi sopra.
class AggancioStrada {
  AggancioStrada({
    this.sogliaM = 25,
    this.direzioneGradi = 50,
    this.margineCambioM = 4,
    this.lettureCambio = 2,
    this.andandoDaMs = 2,
  });

  /// Più lontani di così dalla strada non ci si aggancia.
  final double sogliaM;

  /// Andando, quanto può girare la strada rispetto a dove si va.
  final double direzioneGradi;

  /// Di quanto deve essere più vicina un'altra strada per passarci.
  final double margineCambioM;

  /// E per quante letture di fila.
  final int lettureCambio;

  /// Sopra questa velocità la direzione dell'auto vuol dire qualcosa.
  final double andandoDaMs;

  Agganciato? _ultimo;
  var _altrove = 0;

  /// L'ultimo aggancio, o `null` se l'ultima lettura non si è agganciata.
  Agganciato? get ultimo => _ultimo;

  /// Si ricomincia (un salto, la mappa rifatta).
  void dimentica() {
    _ultimo = null;
    _altrove = 0;
  }

  /// La lettura [gps], che va verso [rotta] (gradi da nord, se si sa) a
  /// [velocitaMs], agganciata a una delle [strade]; `null` se nessuna è
  /// abbastanza vicina e va nel verso giusto.
  Agganciato? aggancia(Punto gps, {double? rotta, double velocitaMs = 0, required Iterable<TrattoStrada> strade}) {
    final andando = rotta != null && rotta.isFinite && velocitaMs >= andandoDaMs;
    final prima = _ultimo;
    _Candidato? meglio, stessa;
    for (final s in strade) {
      final p = s.punti;
      for (var i = 0; i + 1 < p.length; i++) {
        final c = _proietta(gps, p[i], p[i + 1]);
        if (c == null || c.lontanoM > sogliaM) continue;
        // Il verso della strada in cui si va: quello dei punti o il contrario.
        var verso = c.rotta;
        var scarto = 0.0;
        if (andando) {
          final avanti = diQuantoSiGira(c.rotta, rotta).abs();
          final indietro = 180 - avanti;
          final puoAvanti = s.senso >= 0, puoIndietro = s.senso <= 0;
          if (puoAvanti && (avanti <= indietro || !puoIndietro)) {
            scarto = avanti;
          } else if (puoIndietro) {
            scarto = indietro;
            verso = (c.rotta + 180) % 360;
          } else {
            continue;
          }
          if (scarto > direzioneGradi) continue;
        } else if (prima != null) {
          // Fermi: il verso di prima, se la strada è la stessa.
          if (diQuantoSiGira(c.rotta, prima.rotta).abs() > 90) verso = (c.rotta + 180) % 360;
        } else if (s.senso < 0) {
          verso = (c.rotta + 180) % 360;
        }
        // Un poco di più per la strada che gira rispetto all'auto: a pari
        // distanza vince quella dritta.
        final costo = c.lontanoM + scarto * 0.08;
        final cand = _Candidato(c.punto, verso, c.lontanoM, costo);
        if (meglio == null || costo < meglio.costo) meglio = cand;
        if (prima != null && _proseguimento(prima, c)) {
          if (stessa == null || costo < stessa.costo) stessa = cand;
        }
      }
    }
    if (meglio == null) {
      dimentica();
      return null;
    }
    var scelto = meglio;
    if (stessa != null && !identical(stessa, meglio)) {
      // L'isteresi: si resta sulla strada di prima finché l'altra non è più
      // vicina di un margine, per qualche lettura.
      if (meglio.costo < stessa.costo - margineCambioM) {
        _altrove++;
        if (_altrove < lettureCambio) scelto = stessa;
      } else {
        _altrove = 0;
        scelto = stessa;
      }
    } else {
      _altrove = 0;
    }
    if (identical(scelto, meglio) && stessa != null && !identical(stessa, meglio)) _altrove = 0;
    final out = (punto: scelto.punto, rotta: scelto.rotta, lontanoM: scelto.lontanoM);
    _ultimo = out;
    return out;
  }

  /// Se il pezzo [c] continua la strada dell'aggancio [prima]: va come lei e
  /// le passa a pochi metri (la stessa strada spezzata in due tessere, o la
  /// curva dopo).
  static bool _proseguimento(Agganciato prima, _Proiezione c) {
    final giro = diQuantoSiGira(c.rotta, prima.rotta).abs();
    if (math.min(giro, 180 - giro) > 30) return false;
    // Quanto il punto di prima sta di lato alla retta del pezzo.
    final (dx, dy) = _metri(c.a, prima.punto);
    final (sx, sy) = _metri(c.a, c.b);
    final l = math.sqrt(sx * sx + sy * sy);
    if (l < 1e-6) return false;
    final lato = (dx * sy - dy * sx).abs() / l;
    return lato < 3.5;
  }

  static const _metriPerGrado = 111195.08;

  static (double, double) _metri(Punto da, Punto a) {
    final coslat = math.cos(da.lat * math.pi / 180);
    return ((a.lon - da.lon) * _metriPerGrado * coslat, (a.lat - da.lat) * _metriPerGrado);
  }

  static _Proiezione? _proietta(Punto q, Punto a, Punto b) {
    final (bx, by) = _metri(a, b);
    final l2 = bx * bx + by * by;
    if (l2 < 0.01) return null;
    final (qx, qy) = _metri(a, q);
    final t = ((qx * bx + qy * by) / l2).clamp(0.0, 1.0);
    final px = bx * t, py = by * t;
    final coslat = math.cos(a.lat * math.pi / 180);
    final punto = Punto(a.lat + py / _metriPerGrado, a.lon + px / (_metriPerGrado * coslat));
    final rotta = (math.atan2(bx, by) * 180 / math.pi + 360) % 360;
    return _Proiezione(punto, rotta, math.sqrt((qx - px) * (qx - px) + (qy - py) * (qy - py)), a, b);
  }
}

class _Proiezione {
  const _Proiezione(this.punto, this.rotta, this.lontanoM, this.a, this.b);
  final Punto punto;
  final double rotta;
  final double lontanoM;
  final Punto a, b;
}

class _Candidato {
  _Candidato(this.punto, this.rotta, this.lontanoM, this.costo);
  final Punto punto;
  final double rotta;
  final double lontanoM;
  final double costo;
}
