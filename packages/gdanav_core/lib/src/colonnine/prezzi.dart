/// Il tipo di corrente di un prezzo, come lo divide la PUN: alternata,
/// continua, continua ad alta potenza.
enum Corrente { ac, dc, hpc }

/// Da quanto a quanto: una colonnina con più punti può avere prezzi
/// diversi, e allora si dice il più basso e il più alto.
typedef Forchetta = ({double da, double a});

/// I prezzi di un tipo di corrente: l'energia in €/kWh, la ricarica a tempo
/// e la sosta in €/min, l'avvio in €. Quello che il gestore non dice resta
/// `null`.
class Tariffa {
  const Tariffa({this.energia, this.tempo, this.avvio, this.sosta});

  final Forchetta? energia;
  final Forchetta? tempo;
  final Forchetta? avvio;
  final Forchetta? sosta;
}

/// Quanto costa ricaricare a una colonnina, come il gestore lo comunica alla
/// PUN (`punTariffsDetails` di `/v1/chargepoints/group`), per tipo di
/// corrente.
///
/// Lo comunicano in pochi: nella prova sul server vero, su 40 gestori, lo
/// mandavano A2A, Acea, Emobitaly e Convergenze — 156 punti su 1.200 —, e
/// Plenitude manda i campi vuoti. Su `Colonnina.prezzi` `null` vuol dire
/// che non si è chiesto; [Prezzi] vuoti, che si è chiesto e il gestore non li
/// manda.
class Prezzi {
  const Prezzi(this.perCorrente);

  static const nessuno = Prezzi({});

  final Map<Corrente, Tariffa> perCorrente;

  bool get vuoti => perCorrente.isEmpty;

  /// I prezzi dei punti di ricarica di una colonnina, come li dà la PUN.
  static Prezzi daiPunti(Iterable<Map> punti) {
    final raccolti = {for (final c in Corrente.values) c: _Raccolta()};
    for (final r in punti) {
      if (r['punTariffsDetails'] case final Map t) {
        for (final c in Corrente.values) {
          if (t['${c.name}Tariff'] case final Map v) raccolti[c]!.aggiungi(v);
        }
      }
    }
    return Prezzi({
      for (final c in Corrente.values)
        if (raccolti[c]!.tariffa case final t?) c: t,
    });
  }
}

class _Raccolta {
  final _valori = <String, List<double>>{};

  /// I prezzi scritti a zero o fuori misura si lasciano: un'energia a
  /// 40 €/kWh è un errore di chi l'ha scritta, e «0,00 €» non dice niente.
  static const _massimi = {'energy': 5.0, 'time': 5.0, 'activation': 20.0, 'parking': 5.0};

  void aggiungi(Map v) {
    for (final MapEntry(key: campo, value: massimo) in _massimi.entries) {
      if (v[campo] case final num n when n > 0 && n <= massimo) (_valori[campo] ??= []).add(n.toDouble());
    }
  }

  Forchetta? _forchetta(String campo) {
    final l = _valori[campo];
    if (l == null || l.isEmpty) return null;
    l.sort();
    return (da: l.first, a: l.last);
  }

  Tariffa? get tariffa {
    if (_valori.isEmpty) return null;
    return Tariffa(
      energia: _forchetta('energy'),
      tempo: _forchetta('time'),
      avvio: _forchetta('activation'),
      sosta: _forchetta('parking'),
    );
  }
}
