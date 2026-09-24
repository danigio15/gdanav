import 'dart:math' as math;

import '../geo/geo.dart';
import '../percorso/valhalla.dart';

/// Dove si è lungo il percorso, e cosa viene dopo.
class Avanzamento {
  const Avanzamento({
    required this.percorsiM,
    required this.restantiM,
    required this.restante,
    required this.lontanoM,
    required this.prossima,
    required this.allaProssimaM,
    required this.dopo,
    required this.fuoriPercorso,
    required this.arrivato,
    required this.posizioneSulPercorso,
    required this.rotta,
    this.daDire,
  });

  final double percorsiM;
  final double restantiM;
  final Duration restante;

  /// Quanto si è lontani dalla linea del percorso.
  final double lontanoM;

  /// La prossima manovra, e quanto manca. `null` solo all'arrivo.
  final Manovra? prossima;
  final double allaProssimaM;

  /// Quella dopo ancora, per il «poi».
  final Manovra? dopo;

  /// Si è usciti di strada da qualche lettura: si ricalcola.
  final bool fuoriPercorso;
  final bool arrivato;

  /// Il punto del percorso più vicino, per agganciarci la freccia.
  final Punto posizioneSulPercorso;

  /// La direzione della strada in quel punto, in gradi da nord in senso
  /// orario: per girare l'auto e la mappa.
  final double rotta;

  /// Una frase nuova da dire ad alta voce, se è il momento.
  final String? daDire;
}

/// Segue chi guida lungo un percorso di Valhalla: a ogni posizione GPS dice
/// a che punto si è, la prossima manovra e se è ora di annunciarla.
class Guida {
  Guida(this.percorso, {this.sogliaFuoriM = 45, this.lettureFuori = 3}) : _linea = Linea(percorso.punti) {
    _secondi = _secondiCumulati();
  }

  final PercorsoCalcolato percorso;
  final double sogliaFuoriM;
  final int lettureFuori;
  final Linea _linea;
  late final List<double> _secondi;

  var _segmento = 0;
  var _fuori = 0;
  final _annunciate = <String>{};

  /// Le distanze a cui si annuncia una manovra: da lontano e all'ultimo.
  static const _lontano = 800.0, _vicino = 150.0;

  double get lunghezzaM => _linea.lunghezzaM;

  Avanzamento aggiorna(Punto qui) {
    // Si cerca poco indietro e un bel po' avanti: su una strada che torna su
    // se stessa si resta dalla parte giusta.
    final p = _linea.proiettaTra(qui, math.max(0, _segmento - 3), _segmento + 400);
    if (p.lontanoM <= sogliaFuoriM) {
      _segmento = p.segmento;
      _fuori = 0;
    } else {
      _fuori++;
    }
    final percorsi = p.lungoM;
    final restanti = math.max(0.0, _linea.lunghezzaM - percorsi);
    final i = p.segmento;
    final secondiQui = _secondi[i] + p.t * (_secondi[math.min(i + 1, _secondi.length - 1)] - _secondi[i]);
    final restante = Duration(seconds: math.max(0, _secondi.last - secondiQui).round());

    final manovre = percorso.manovre;
    var k = manovre.indexWhere((m) => _linea.cumulate[_indice(m)] > percorsi + 1);
    final prossima = k < 0 ? null : manovre[k];
    final dopo = k < 0 || k + 1 >= manovre.length ? null : manovre[k + 1];
    final alla = prossima == null ? 0.0 : _linea.cumulate[_indice(prossima)] - percorsi;
    final arrivato = restanti < 25;

    return Avanzamento(
      percorsiM: percorsi,
      restantiM: restanti,
      restante: restante,
      lontanoM: p.lontanoM,
      prossima: prossima,
      allaProssimaM: alla,
      dopo: dopo,
      fuoriPercorso: _fuori >= lettureFuori,
      arrivato: arrivato,
      posizioneSulPercorso: _punto(i, p.t),
      rotta: _rotta(i),
      daDire: arrivato ? _una('arrivo', 'Sei arrivato.') : _annuncio(prossima, alla),
    );
  }

  String? _annuncio(Manovra? m, double alla) {
    if (m == null || m.voce.isEmpty) return null;
    final id = '${m.inizio}';
    if (alla <= _vicino) return _una('$id-vicino', m.voce);
    if (alla <= _lontano) return _una('$id-lontano', 'Tra ${distanzaParlata(alla)}, ${_minuscola(m.voce)}');
    return null;
  }

  /// Ogni frase si dice una volta sola.
  String? _una(String chiave, String frase) => _annunciate.add(chiave) ? frase : null;

  int _indice(Manovra m) => math.min(m.inizio, _linea.punti.length - 1);

  Punto _punto(int i, double t) {
    final a = _linea.punti[i], b = _linea.punti[math.min(i + 1, _linea.punti.length - 1)];
    return Punto(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon));
  }

  /// La direzione del segmento [i]; se è cortissimo, quella dei successivi.
  double _rotta(int i) {
    final n = _linea.punti.length;
    var j = math.min(i + 1, n - 1);
    while (j < n - 1 && distanzaM(_linea.punti[i], _linea.punti[j]) < 8) {
      j++;
    }
    return rottaGradi(_linea.punti[math.min(i, n - 1)], _linea.punti[j]);
  }

  /// Il tempo cumulato a ogni punto, con la velocità della manovra a cui il
  /// segmento appartiene.
  List<double> _secondiCumulati() {
    final n = _linea.punti.length;
    final velocita = List<double>.filled(math.max(n - 1, 0), 13.9);
    final manovre = percorso.manovre;
    for (var k = 0; k < manovre.length; k++) {
      final m = manovre[k];
      final fine = k + 1 < manovre.length ? manovre[k + 1].inizio : n - 1;
      final v = m.secondi > 0 && m.lunghezzaM > 0 ? m.lunghezzaM / m.secondi : 13.9;
      for (var i = m.inizio; i < fine && i < n - 1; i++) {
        velocita[i] = v;
      }
    }
    final s = <double>[0];
    for (var i = 0; i < n - 1; i++) {
      s.add(s.last + (_linea.cumulate[i + 1] - _linea.cumulate[i]) / velocita[i]);
    }
    return s;
  }

  static String _minuscola(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

/// «300 metri», «1 chilometro», «2,5 chilometri»: come si dice guidando.
String distanzaParlata(double metri) {
  if (metri < 1000) {
    final m = metri < 100 ? (metri / 10).round() * 10 : (metri / 50).round() * 50;
    return '$m metri';
  }
  final km = (metri / 100).round() / 10;
  if (km == 1) return '1 chilometro';
  final testo = km == km.roundToDouble() ? '${km.round()}' : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$testo chilometri';
}

/// «300 m», «1,2 km»: come si scrive sullo schermo.
String distanzaBreve(double metri) {
  if (metri < 1000) {
    final m = metri < 100 ? (metri / 10).round() * 10 : (metri / 50).round() * 50;
    return '$m m';
  }
  return metri < 10000
      ? '${(metri / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${(metri / 1000).round()} km';
}
