/// Quando una ZTL è accesa, dagli orari scritti in OpenStreetMap.
///
/// Gli orari arrivano in due forme: `opening_hours=Mo-Fr 07:30-19:30` sul
/// contorno della zona, oppure un divieto a tempo come
/// `motor_vehicle:conditional=no @ (Mo-Fr 07:30-19:30)`. Tutt'e due dicono
/// quando la ZTL è attiva. C'è anche il contrario, `yes @ (20:00-07:00)`:
/// sono le ore in cui si passa, e la ZTL è attiva nelle altre.
///
/// Si legge solo quello che si sa leggere bene: giorni della settimana (anche
/// scritti all'italiana, `Lu-Ve`), i festivi nazionali (`PH`), fasce orarie
/// anche a cavallo della mezzanotte, mesi e intervalli di date. Il resto non
/// si indovina. Un orario che non si capisce vale come «sempre attiva», che è
/// l'errore che non costa una multa.
library;

/// Gli orari di una ZTL, letti. Dove non ci sono, o non si capiscono, la ZTL
/// è sempre attiva, e un [OrariZtl] non c'è proprio (`leggi` torna `null`).
class OrariZtl {
  OrariZtl._(this._regole, this.testo, [this._aperture = const []]);

  /// Quando è attiva.
  final List<_Regola> _regole;

  /// Quando si passa (`yes @ …`), una lista per condizione: fuori da
  /// tutte queste ore la ZTL è attiva.
  final List<List<_Regola>> _aperture;

  /// Com'è scritto in OpenStreetMap.
  final String testo;

  /// Legge gli orari di una ZTL dai suoi tag. Prima i divieti a tempo, che
  /// sono quelli che valgono per chi guida, poi `opening_hours`. `null`:
  /// nessun orario che si capisca, e la ZTL vale come sempre attiva.
  static OrariZtl? daiTag(Map<String, Object?> tag) {
    for (final chiave in const ['motor_vehicle:conditional', 'vehicle:conditional', 'access:conditional']) {
      final v = tag[chiave];
      if (v is String && v.trim().isNotEmpty) return daCondizione(v);
    }
    final o = tag['opening_hours'];
    return o is String ? leggi(o) : null;
  }

  static const _chiudono = {'no', 'private', 'permit', 'destination', 'delivery', 'customers', 'permissive_no'};
  static const _aprono = {'yes', 'permissive', 'designated'};
  static final _condizione = RegExp(r'([a-z_]+)\s*@\s*\(([^)]*)\)|([a-z_]+)\s*@\s*([^;()]+)');

  /// Un divieto a tempo: `no @ (Mo-Fr 07:30-19:30); destination @ (Sa)`.
  /// Contano le condizioni che chiudono (`no`, `private`, `permit`,
  /// `destination`, `delivery`, `customers`): la ZTL è attiva quando ne vale
  /// una. E quelle che aprono (`yes @ (20:00-07:00)`): la ZTL è attiva fuori
  /// da quelle ore. Condizioni con altre cose (peso, durata) non si
  /// capiscono.
  static OrariZtl? daCondizione(String testo) {
    final regole = <_Regola>[];
    final aperture = <List<_Regola>>[];
    for (final m in _condizione.allMatches(testo)) {
      final valore = (m.group(1) ?? m.group(3) ?? '').trim();
      final quando = (m.group(2) ?? m.group(4) ?? '').trim();
      if (_chiudono.contains(valore)) {
        final r = _regoleDi(quando);
        // Chiusa sempre (`permit @ (24/7)`), o non si capisce: sempre attiva.
        if (r == null || r.any((x) => x.sempre)) return null;
        // Le condizioni si sommano: attiva quando ne vale almeno una. Si
        // sommano anche le regole dentro la stessa condizione, anche se per
        // `opening_hours` una prenderebbe il posto dell'altra: chi le scrive
        // intende quasi sempre «queste e anche queste», e così la ZTL è
        // attiva almeno quando lo è davvero.
        regole.addAll(r.map((x) => x.aggiunta()));
      } else if (_aprono.contains(valore)) {
        final r = _regoleDi(quando);
        if (r == null) return null;
        // Qui invece come in `opening_hours`, una regola al posto dell'altra:
        // meno ore aperte, la ZTL attiva un po' di più. Aperta sempre
        // (`yes @ (24/7)`) vuol dire mai attiva.
        aperture.add(r);
      }
    }
    if (regole.isEmpty && aperture.isEmpty) return null;
    return OrariZtl._(regole, testo.trim(), aperture);
  }

  /// Se il testo dice proprio «sempre»: `24/7`, `permit @ (24/7)`, o un
  /// divieto senza orario (`permit`). Anche lì [daiTag] torna `null`, ma
  /// perché è scritto così, non perché non si capisce.
  static bool sempre(String testo) {
    final t = testo.trim();
    if (t == '24/7' || _chiudono.contains(t)) return true;
    final m = _condizione.allMatches(t).toList();
    return m.isNotEmpty &&
        m.every((c) =>
            _chiudono.contains((c.group(1) ?? c.group(3) ?? '').trim()) &&
            (c.group(2) ?? c.group(4) ?? '').trim() == '24/7');
  }

  /// Legge un orario nel formato di `opening_hours`. `null` se c'è qualcosa
  /// che non si sa leggere, o se dice «sempre» (`24/7`): la ZTL allora vale
  /// come sempre attiva.
  static OrariZtl? leggi(String testo) {
    final regole = _regoleDi(testo);
    if (regole == null || regole.any((r) => r.sempre)) return null;
    return OrariZtl._(regole, testo.trim());
  }

  /// Le regole di un orario, o `null` se c'è qualcosa che non si sa
  /// leggere.
  static List<_Regola>? _regoleDi(String testo) {
    final pulito = testo.replaceAll(RegExp(r'"[^"]*"'), '').replaceAll('||', ';').trim();
    if (pulito.isEmpty) return null;
    final regole = <_Regola>[];
    for (final pezzo in pulito.split(';')) {
      final r = pezzo.trim();
      if (r.isEmpty) continue;
      final regola = _Regola.leggi(r);
      if (regola == null) return null;
      regole.add(regola);
    }
    return regole.isEmpty ? null : regole;
  }

  /// Se la ZTL è attiva a [quando].
  bool attivaAlle(DateTime quando) {
    if (_dentro(_regole, quando)) return true;
    return _aperture.isNotEmpty && !_aperture.any((a) => _dentro(a, quando));
  }

  /// Se [quando] cade in una fascia di [regole].
  static bool _dentro(List<_Regola> regole, DateTime quando) {
    final minuto = quando.hour * 60 + quando.minute;
    final oggi = _Giorno(quando.year, quando.month, quando.day);
    if (_fasce(regole, oggi).any((f) => f.$1 <= minuto && minuto < f.$2)) return true;
    // Una fascia di ieri che passa la mezzanotte (20:00-02:00).
    return _fasce(regole, oggi.prima()).any((f) => f.$2 > 1440 && minuto < f.$2 - 1440);
  }

  /// Fino a quando resta attiva, se lo è a [quando]: il primo minuto in cui
  /// si spegne. `null` se non si spegne nella settimana che viene.
  DateTime? finoAlle(DateTime quando) {
    if (!attivaAlle(quando)) return null;
    final inizio = DateTime(quando.year, quando.month, quando.day, quando.hour, quando.minute);
    for (var t = inizio; t.difference(inizio).inDays < 8;) {
      final prossimo = _prossimoCambio(t);
      if (prossimo == null) return null;
      if (!attivaAlle(prossimo)) return prossimo;
      t = prossimo;
    }
    return null;
  }

  /// Da quando sarà attiva, se non lo è a [quando]. `null` se non si
  /// accende nella settimana che viene.
  DateTime? dalle(DateTime quando) {
    if (attivaAlle(quando)) return null;
    final inizio = DateTime(quando.year, quando.month, quando.day, quando.hour, quando.minute);
    for (var t = inizio; t.difference(inizio).inDays < 8;) {
      final prossimo = _prossimoCambio(t);
      if (prossimo == null) return null;
      if (attivaAlle(prossimo)) return prossimo;
      t = prossimo;
    }
    return null;
  }

  /// Il primo inizio o fine di fascia dopo [t], al minuto.
  DateTime? _prossimoCambio(DateTime t) {
    final minuto = t.hour * 60 + t.minute;
    final oggi = _Giorno(t.year, t.month, t.day);
    final tutte = [_regole, ..._aperture];
    for (var giorni = 0; giorni < 9; giorni++) {
      final g = oggi.dopo(giorni);
      final bordi = <int>{
        for (final regole in tutte) ...[
          for (final f in _fasce(regole, g)) ...[f.$1, f.$2],
          for (final f in _fasce(regole, g.prima()))
            if (f.$2 > 1440) f.$2 - 1440,
        ],
        0,
      }.where((b) => b <= 1440).toList()
        ..sort();
      for (final b in bordi) {
        if (giorni == 0 && b <= minuto) continue;
        // Con le ore e i minuti, non sommando minuti alla mezzanotte: il
        // giorno del cambio dell'ora ha 23 o 25 ore.
        return DateTime(g.anno, g.mese, g.giorno, b ~/ 60, b % 60);
      }
    }
    return null;
  }

  /// Le fasce di [g], in minuti dalla mezzanotte (la fine può passare 1440).
  /// Come in OpenStreetMap: una regola che vale per quel giorno prende il
  /// posto di quelle prima, a meno che si sommi (le condizioni).
  static List<(int, int)> _fasce(List<_Regola> regole, _Giorno g) {
    var fasce = <(int, int)>[];
    for (final r in regole) {
      if (!r.valePer(g)) continue;
      fasce = r.somma ? [...fasce, ...r.fasce] : r.fasce;
    }
    return fasce;
  }

  @override
  String toString() => testo;
}

/// Un giorno del calendario, senza ore né fuso.
class _Giorno {
  const _Giorno(this.anno, this.mese, this.giorno);

  final int anno, mese, giorno;

  DateTime get _data => DateTime.utc(anno, mese, giorno);

  _Giorno dopo(int giorni) {
    final d = _data.add(Duration(days: giorni));
    return _Giorno(d.year, d.month, d.day);
  }

  _Giorno prima() => dopo(-1);

  /// 1 = lunedì … 7 = domenica.
  int get settimana => _data.weekday;

  /// Le feste nazionali: capodanno, Epifania, Pasquetta, 25 aprile, 1°
  /// maggio, 2 giugno, Ferragosto, Ognissanti, Immacolata, Natale, Santo
  /// Stefano. I patroni cambiano da città a città, e non si sanno.
  bool get festivo {
    const fisse = {(1, 1), (1, 6), (4, 25), (5, 1), (6, 2), (8, 15), (11, 1), (12, 8), (12, 25), (12, 26)};
    if (fisse.contains((mese, giorno))) return true;
    final pasqua = _pasqua(anno);
    final pasquetta = pasqua.add(const Duration(days: 1));
    return pasquetta.month == mese && pasquetta.day == giorno;
  }

  /// La domenica di Pasqua (algoritmo di Meeus/Jones/Butcher).
  static DateTime _pasqua(int y) {
    final a = y % 19, b = y ~/ 100, c = y % 100, d = b ~/ 4, e = b % 4;
    final f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3, h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final mese = (h + l - 7 * m + 114) ~/ 31, giorno = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime.utc(y, mese, giorno);
  }
}

/// Una regola: per quali giorni (mesi, giorni della settimana, festivi) e in
/// quali fasce. Senza fasce vuol dire tutto il giorno; `off` nessuna.
class _Regola {
  _Regola({
    this.mesi,
    this.settimana,
    this.festivi = false,
    this.soloFestivi = false,
    required this.fasce,
    this.sempre = false,
    this.somma = false,
  });

  /// Intervalli di date (mese*100+giorno), anche a cavallo dell'anno.
  final List<(int, int)>? mesi;

  /// I giorni della settimana, 1 = lunedì. `null`: tutti.
  final Set<int>? settimana;

  /// Se vale anche nei festivi (`Mo-Sa,PH`), o solo lì (`PH off`).
  final bool festivi;
  final bool soloFestivi;

  final List<(int, int)> fasce;
  final bool sempre;

  /// Si somma alle altre invece di prenderne il posto (le condizioni).
  final bool somma;

  _Regola aggiunta() => _Regola(
        mesi: mesi,
        settimana: settimana,
        festivi: festivi,
        soloFestivi: soloFestivi,
        fasce: fasce,
        sempre: sempre,
        somma: true,
      );

  bool valePer(_Giorno g) {
    final m = mesi;
    if (m != null) {
      final oggi = g.mese * 100 + g.giorno;
      if (!m.any((r) => r.$1 <= r.$2 ? (oggi >= r.$1 && oggi <= r.$2) : (oggi >= r.$1 || oggi <= r.$2))) {
        return false;
      }
    }
    if (soloFestivi) return g.festivo;
    final s = settimana;
    if (s == null) return true;
    return s.contains(g.settimana) || (festivi && g.festivo);
  }

  /// Anche all'italiana, come capita di trovarli: `Lu-Ve`, `Do`.
  static const _giorni = {
    'Mo': 1, 'Tu': 2, 'We': 3, 'Th': 4, 'Fr': 5, 'Sa': 6, 'Su': 7,
    'Lu': 1, 'Ma': 2, 'Me': 3, 'Gi': 4, 'Ve': 5, 'Do': 7, //
  };
  static const _mesi = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12, //
  };

  /// Per le espressioni: un giorno della settimana, un mese.
  static final _giorno = _giorni.keys.join('|');
  static final _mese = _mesi.keys.join('|');

  static _Regola? leggi(String testo) {
    var resto = testo.trim();
    if (resto == '24/7') return _Regola(fasce: const [(0, 1440)], sempre: true);

    // Mesi e date: «Jun-Sep», «Apr 01-Oct 31», «Dec 24-Jan 06», anche coi
    // due punti dopo («Jul 15-Sep 15: Mo-Su …»). Il giorno non è l'ora che
    // viene dopo: «Jun 20:00-…» è giugno, dalle venti.
    List<(int, int)>? mesi;
    const giornoDelMese = r'(?:\s*\d{1,2}(?!\d|:\d))?';
    final perMesi = RegExp('^((?:(?:$_mese)$giornoDelMese(?:\\s*-\\s*(?:$_mese)?$giornoDelMese)?)'
        '(?:\\s*,\\s*(?:$_mese)$giornoDelMese(?:\\s*-\\s*(?:$_mese)?$giornoDelMese)?)*)(?:\\s*:)?\\s*');
    final mm = perMesi.firstMatch(resto);
    if (mm != null && mm.group(1)!.isNotEmpty) {
      mesi = [];
      for (final parte in mm.group(1)!.split(',')) {
        final r = _intervalloDate(parte.trim());
        if (r == null) return null;
        mesi.add(r);
      }
      resto = resto.substring(mm.end).trim();
    }

    // Giorni: «Mo-Fr», «Mo,We,Fr», «Sa,Su,PH», «PH», «Lu-Ve».
    Set<int>? settimana;
    var festivi = false;
    var soloFestivi = false;
    final perGiorni = RegExp('^((?:$_giorno|PH|SH)(?:\\s*-\\s*(?:$_giorno))?'
        '(?:\\s*,\\s*(?:$_giorno|PH|SH)(?:\\s*-\\s*(?:$_giorno))?)*)(?:\\s*:)?\\s*');
    final mg = perGiorni.firstMatch(resto);
    if (mg != null && mg.group(1)!.isNotEmpty) {
      final giorni = <int>{};
      var scolastiche = false;
      for (final parte in mg.group(1)!.split(',')) {
        final p = parte.trim();
        if (p == 'PH') {
          festivi = true;
        } else if (p == 'SH') {
          scolastiche = true;
        } else if (p.contains('-')) {
          final [da, a] = p.split('-').map((x) => _giorni[x.trim()]!).toList();
          for (var d = da;; d = d % 7 + 1) {
            giorni.add(d);
            if (d == a) break;
          }
        } else {
          giorni.add(_giorni[p]!);
        }
      }
      resto = resto.substring(mg.end).trim();
      // Le vacanze scolastiche non si sanno: una regola che le tocca non si
      // indovina.
      if (scolastiche) return null;
      if (giorni.isEmpty) {
        soloFestivi = festivi;
        festivi = false;
      } else {
        settimana = giorni;
      }
    }

    // Fasce: «07:30-19:30», «08:00-13:00,15:00-19:00», «off», niente = tutto il giorno.
    final fasce = <(int, int)>[];
    if (resto.isEmpty) {
      if (mesi == null && settimana == null && !soloFestivi) return null;
      fasce.add((0, 1440));
    } else if (resto == 'off' || resto == 'closed') {
      // Nessuna fascia.
    } else {
      for (final parte in resto.replaceFirst(RegExp(r'\s+open$'), '').split(',')) {
        final m = RegExp(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\+?$').firstMatch(parte.trim());
        if (m == null) return null;
        final inizio = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
        var fine = int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
        if (inizio > 1440 || fine > 2880) return null;
        // 20:00-02:00: fino alle due del giorno dopo.
        if (fine <= inizio) fine += 1440;
        fasce.add((inizio, fine));
      }
    }
    return _Regola(mesi: mesi, settimana: settimana, festivi: festivi, soloFestivi: soloFestivi, fasce: fasce);
  }

  /// «Jun», «Jun-Sep», «Apr 01-Oct 31», «Dec 24-Jan 06»: da-a come
  /// mese*100+giorno.
  static (int, int)? _intervalloDate(String testo) {
    final m =
        RegExp(r'^([A-Z][a-z]{2})(?:\s*(\d{1,2}))?(?:\s*-\s*([A-Z][a-z]{2})?(?:\s*(\d{1,2}))?)?$').firstMatch(testo);
    if (m == null) return null;
    final da = _mesi[m.group(1)];
    if (da == null) return null;
    final gDa = m.group(2) == null ? 1 : int.parse(m.group(2)!);
    final haFine = m.group(3) != null || m.group(4) != null;
    if (!haFine) return (da * 100 + gDa, da * 100 + (m.group(2) == null ? 31 : gDa));
    final a = m.group(3) == null ? da : _mesi[m.group(3)];
    if (a == null) return null;
    final gA = m.group(4) == null ? 31 : int.parse(m.group(4)!);
    return (da * 100 + gDa, a * 100 + gA);
  }
}
