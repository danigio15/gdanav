import 'dart:math' as math;

import '../percorso/valhalla.dart';
import '../veicolo/profilo_veicolo.dart';
import '../veicolo/stato_auto.dart';
import 'modello_consumo.dart';

/// Il tipo di strada, dalla velocità media: il consumo cambia molto fra
/// città, statali e autostrada, e così la precisione del modello.
enum TipoStrada {
  urbana('Urbane', 'sotto i 60 km/h'),
  extraurbana('Extraurbane', 'da 60 a 100 km/h'),
  autostrada('Autostrade', 'sopra i 100 km/h');

  const TipoStrada(this.nome, this.velocita);

  final String nome;
  final String velocita;

  static TipoStrada daVelocita(double kmh) => kmh < 60
      ? TipoStrada.urbana
      : kmh <= 100
          ? TipoStrada.extraurbana
          : TipoStrada.autostrada;
}

/// Quello che si è misurato su un tipo di strada.
class ConsumoStrada {
  const ConsumoStrada({
    this.fattore = 1,
    this.km = 0,
    this.previstoWh = 0,
    this.realeWh = 0,
    this.erroreWh = 0,
  });

  factory ConsumoStrada.daJson(Map<String, Object?> j) {
    double n(String k, [double d = 0]) => (j[k] as num?)?.toDouble() ?? d;
    return ConsumoStrada(
      fattore: n('fattore', 1).clamp(ConsumoImparato.minimo, ConsumoImparato.massimo).toDouble(),
      km: n('km'),
      previstoWh: n('previsto_wh'),
      realeWh: n('reale_wh'),
      erroreWh: n('errore_wh'),
    );
  }

  /// Il correttivo per queste strade.
  final double fattore;
  final double km;

  /// L'energia che il calcolo prevedeva (col correttivo di quel momento) e
  /// quella vera, sulle stesse strade.
  final double previstoWh;
  final double realeWh;

  /// La somma degli scarti, misura per misura.
  final double erroreWh;

  /// Da quanti km il correttivo di queste strade vale più di quello generale.
  static const kmPerFidarsi = 20.0;

  bool get affidabile => km >= kmPerFidarsi;

  /// Quanto ci si è presi, in percentuale: 100 = esatto.
  double? get precisionePercento => realeWh <= 0 ? null : (100 * (1 - erroreWh / realeWh)).clamp(0, 100).toDouble();

  double? get previstoKwh100 => km <= 0 ? null : previstoWh / km / 10;
  double? get realeKwh100 => km <= 0 ? null : realeWh / km / 10;

  Map<String, Object?> toJson() => {
        'fattore': fattore,
        'km': km,
        'previsto_wh': previstoWh,
        'reale_wh': realeWh,
        'errore_wh': erroreWh,
      };
}

/// Il consumo di riferimento scritto dall'utente: [whKm] a [kmh] costanti
/// (quello calibrato di ABRP, per esempio «188 Wh/km» a 110 km/h).
class RiferimentoConsumo {
  const RiferimentoConsumo({required this.whKm, required this.kmh, required this.fattore});

  final double whKm;
  final double kmh;

  /// Il correttivo che ne viene per il modello di adesso
  /// ([fattoreDaRiferimento]).
  final double fattore;

  static RiferimentoConsumo? daJson(Object? j) {
    if (j is! Map) return null;
    final wh = (j['wh_km'] as num?)?.toDouble(), kmh = (j['kmh'] as num?)?.toDouble();
    final f = (j['fattore'] as num?)?.toDouble();
    if (wh == null || kmh == null || f == null) return null;
    return RiferimentoConsumo(
      whKm: wh,
      kmh: kmh,
      fattore: f.clamp(ConsumoImparato.minimo, ConsumoImparato.massimo).toDouble(),
    );
  }

  Map<String, Object?> toJson() => {'wh_km': whKm, 'kmh': kmh, 'fattore': fattore};
}

/// Quanto consuma davvero la tua auto rispetto al modello, imparato
/// guidando, come fa ABRP: si confronta l'energia prevista per un tratto con
/// quella tolta alla batteria (calo di percentuale per la capacità).
///
/// È una media pesata sui chilometri, con la memoria degli ultimi 300 km:
/// un viaggio d'inverno o in autostrada sposta il fattore, poi si riassesta.
/// In più, per ogni tipo di strada, un correttivo suo e la precisione.
///
/// Si parte da 1 (la scheda tecnica) o dal [riferimento] scritto
/// dall'utente, che vale come [pesoRiferimentoKm] chilometri già misurati:
/// le prime misure lo spostano, non lo cancellano.
///
/// Il fattore è un rapporto col modello di [modelloAttuale]: se il modello
/// cambia, quello imparato su un modello vecchio non vale più (correggeva
/// difetti che non ci sono più) e si riparte ([ConsumoImparato.daJson]).
class ConsumoImparato {
  const ConsumoImparato({this.fattore = 1, this.kmOsservati = 0, this.strade = const {}, this.riferimento});

  /// Un consumo di riferimento nuovo: si riparte da lì, le misure di prima
  /// restano nel conto della precisione ma il correttivo è quello nuovo.
  factory ConsumoImparato.daRiferimento(RiferimentoConsumo r) => ConsumoImparato(fattore: r.fattore, riferimento: r);

  factory ConsumoImparato.daJson(Map<String, Object?> j) {
    // Imparato su un modello di prima: non vale più, si riparte dalla scheda.
    if (j['modello'] != modelloAttuale) return const ConsumoImparato();
    final riferimento = RiferimentoConsumo.daJson(j['riferimento']);
    return ConsumoImparato(
      fattore: ((j['fattore'] as num?)?.toDouble() ?? 1).clamp(minimo, massimo).toDouble(),
      kmOsservati: (j['km'] as num?)?.toDouble() ?? 0,
      strade: {
        for (final t in TipoStrada.values)
          if ((j['strade'] as Map?)?[t.name] case final Map m) t: ConsumoStrada.daJson(m.cast()),
      },
      riferimento: riferimento,
    );
  }

  final double fattore;
  final double kmOsservati;
  final Map<TipoStrada, ConsumoStrada> strade;
  final RiferimentoConsumo? riferimento;

  static const minimo = 0.6, massimo = 1.8;
  static const memoriaKm = 300.0;

  /// Quanti km misurati vale il consumo di riferimento scritto a mano.
  static const pesoRiferimentoKm = 50.0;

  /// La versione del modello di consumo ([energiaTrattoWh]): 2 da quando
  /// conta le partenze e le frenate, e misura col clima del piano; 3 da
  /// quando misura coi kWh veri dell'auto (la sua capacità, l'energia che
  /// resta) e col suo riscaldatore. Il fattore di prima, misurato coi punti
  /// per la capacità del catalogo, si portava dentro anche l'errore della
  /// capacità: con quella vera lo correggerebbe due volte.
  static const modelloAttuale = 3;

  /// Quanti km misurati vale il consumo medio dell'auto: vedi [fattoreCon].
  static const pesoConsumoMedioKm = 50.0;

  /// Il correttivo per un tipo di strada: il suo, se misurato abbastanza,
  /// altrimenti quello generale.
  double fattorePer(TipoStrada t) {
    final s = strade[t];
    return s != null && s.affidabile ? s.fattore : fattore;
  }

  /// Il correttivo generale, tirato verso [fattoreAuto], quello che viene
  /// dal consumo medio misurato dall'auto ([fattoreDaConsumoMedio]).
  ///
  /// Con prudenza: al massimo a metà strada, prima di aver misurato niente,
  /// e sempre meno man mano che si misura (a 50 km un quarto, a 300 km il
  /// 7%). Il consumo medio dell'auto è vero, ma di settimane di guida che
  /// non sono questo viaggio, col clima di quei giorni e con le soste da
  /// ferma; le misure di gdanav sono di queste strade. Così si parte giusti
  /// prima del primo viaggio, e dopo decide quello che si misura. Il fattore
  /// salvato non cambia: questo si rifà a ogni piano.
  double fattoreCon(double? fattoreAuto) {
    if (fattoreAuto == null || !fattoreAuto.isFinite) return fattore;
    final misurati = math.min(kmOsservati, memoriaKm) + (riferimento == null ? 0 : pesoRiferimentoKm);
    final peso = 0.5 * pesoConsumoMedioKm / (pesoConsumoMedioKm + misurati);
    return (fattore + (fattoreAuto.clamp(minimo, massimo) - fattore) * peso).clamp(minimo, massimo).toDouble();
  }

  /// Le condizioni per il pianificatore: il correttivo imparato (dove si è
  /// misurato abbastanza, quello del tipo di strada), tirato verso il
  /// consumo medio dell'auto di [s] se lo dice e si sa il [profilo]
  /// ([fattoreCon]), e il clima e la batteria dell'auto
  /// ([Condizioni.conAuto]). Senza [conFattore] niente correttivo: è quello
  /// che il misuratore confronta con la batteria vera.
  Condizioni condizioni(StatoAuto? s, {ProfiloVeicolo? profilo, bool conFattore = true}) {
    final medio = s?.consumoMedioKwh100, t = s?.temperaturaEsternaC;
    final dallAuto = medio == null || profilo == null
        ? null
        : fattoreDaConsumoMedio(
            kwh100: medio,
            profilo: profilo,
            condizioni: t == null ? const Condizioni() : Condizioni.daMeteo(temperaturaC: t),
          );
    return Condizioni(
      fattoreConsumo: conFattore ? fattoreCon(dallAuto) : 1,
      fattoriStrada: conFattore
          ? {
              for (final MapEntry(:key, :value) in strade.entries)
                if (value.affidabile) key: value.fattore,
            }
          : const {},
    ).conAuto(s);
  }

  static double _media(double vecchio, double nuovo, double kmPrima, double km) =>
      vecchio + (nuovo - vecchio) * (km / (math.min(kmPrima, memoriaKm) + km));

  /// Un tratto misurato: [previstoWh] dal modello (senza correttivo),
  /// [realeWh] dalla batteria, lungo [km], su strade di tipo [tipo].
  ConsumoImparato con({required double previstoWh, required double realeWh, required double km, TipoStrada? tipo}) {
    if (previstoWh <= 0 || realeWh <= 0 || km <= 0) return this;
    final rapporto = (realeWh / previstoWh).clamp(minimo, massimo);
    final nuove = Map.of(strade);
    if (tipo != null) {
      final s = strade[tipo] ?? const ConsumoStrada();
      // Quello che il calcolo diceva davvero: col correttivo di adesso.
      final detto = previstoWh * fattorePer(tipo);
      nuove[tipo] = ConsumoStrada(
        fattore: _media(s.km == 0 ? fattore : s.fattore, rapporto, s.km, km),
        km: s.km + km,
        previstoWh: s.previstoWh + detto,
        realeWh: s.realeWh + realeWh,
        erroreWh: s.erroreWh + (realeWh - detto).abs(),
      );
    }
    final peso = riferimento == null ? 0.0 : pesoRiferimentoKm;
    return ConsumoImparato(
      fattore: _media(fattore, rapporto, kmOsservati + peso, km),
      kmOsservati: kmOsservati + km,
      strade: nuove,
      riferimento: riferimento,
    );
  }

  /// In percentuale, per dirlo all'utente: «+8%».
  int get scartoPercento => ((fattore - 1) * 100).round();

  Map<String, Object?> toJson() => {
        'modello': modelloAttuale,
        'fattore': fattore,
        'km': kmOsservati,
        if (strade.isNotEmpty)
          'strade': {for (final MapEntry(:key, :value) in strade.entries) key.name: value.toJson()},
        if (riferimento case final r?) 'riferimento': r.toJson(),
      };
}

/// Una misura del consumo su un tratto guidato.
class MisuraConsumo {
  const MisuraConsumo({required this.previstoWh, required this.realeWh, required this.km, this.velocitaKmh});
  final double previstoWh;
  final double realeWh;
  final double km;

  /// La velocità media prevista su quel tratto: dice che strade erano.
  final double? velocitaKmh;

  TipoStrada? get tipo => velocitaKmh == null ? null : TipoStrada.daVelocita(velocitaKmh!);

  double get realeWhKm => realeWh / km;
}

/// Segue il viaggio con i dati veri della batteria: a ogni lettura dice se
/// c'è una misura nuova del consumo (almeno 2 punti di batteria, o mezzo kWh
/// se l'auto dice l'energia che resta, e un chilometro dall'ultima),
/// confrontata con quello che il modello prevedeva per le stesse strade.
class MisuratoreConsumo {
  MisuratoreConsumo({
    required PercorsoCalcolato percorso,
    required this.capacitaKwh,
    required ProfiloConsumo profilo,
    this.passoPercento = 2,
    this.passoKwh = 0.5,
  }) {
    // Energia prevista cumulata lungo i tratti, senza correttivo: il fattore
    // lo si vuole misurare, non presupporre.
    var m = 0.0, wh = 0.0, sec = 0.0;
    _metri.add(0);
    _wh.add(0);
    _secondi.add(0);
    for (final t in percorso.tratti) {
      m += t.lunghezzaM;
      wh += profilo(t);
      sec += t.secondi;
      _metri.add(m);
      _wh.add(wh);
      _secondi.add(sec);
    }
  }

  final double capacitaKwh;

  /// Quanti punti di batteria servono per una misura: la batteria si legge
  /// all'1%, sotto i 2 punti l'errore è troppo grande.
  final double passoPercento;

  /// Lo stesso con l'energia che resta, che l'auto dice a un decimo di kWh
  /// o meglio: mezzo kWh è un punto scarso di una batteria da 60, e su mezzo
  /// kWh un decimo pesa meno di un punto su due.
  final double passoKwh;

  final _metri = <double>[];
  final _wh = <double>[];
  final _secondi = <double>[];

  /// Le letture sono in kWh (l'energia dell'auto) o in punti di batteria.
  /// Le due non si mescolano: se l'auto smette di dire l'energia, o comincia,
  /// si riparte come dopo una ricarica.
  bool _inKwh = false;
  ({double livello, double metri})? _da;

  /// La prima lettura, finché la batteria non cambia: vedi [registra].
  ({double livello, double metri})? _prima;

  /// L'energia prevista dall'inizio fino a [metri] lungo il percorso.
  double previstaFinoA(double metri) => _fino(_wh, metri);

  double _fino(List<double> valori, double metri) {
    if (metri <= 0) return 0;
    if (metri >= _metri.last) return valori.last;
    var lo = 0, hi = _metri.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_metri[mid] <= metri) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (metri - _metri[lo]) / (_metri[hi] - _metri[lo]);
    return valori[lo] + t * (valori[hi] - valori[lo]);
  }

  /// Una lettura della batteria vera a [metri] dall'inizio del percorso.
  /// Durante una ricarica non si misura: si riparte da dopo.
  ///
  /// **Si parte da un cambio di punto.** La batteria arriva a punti interi:
  /// una lettura di 63% vuol dire «fra 63 e 64», e non si sa dove. Il punto
  /// dopo invece si legge proprio quando lo si passa. Partire dalla prima
  /// lettura e fermarsi a un cambio contava in media mezzo punto di troppo
  /// a misura: su una misura di due punti, il 25% di consumo in più, che il
  /// correttivo imparava come vero. Così la prima lettura (e la prima dopo
  /// una ricarica) aspetta che la batteria cambi, e da lì si misura fra un
  /// cambio e l'altro.
  ///
  /// Con [energiaKwh] (l'auto dice l'energia che resta) si misura in kWh
  /// veri, senza passare dalla capacità, e bastano [passoKwh]: il calo vero
  /// si vede dopo pochi chilometri, non dopo due punti. Il resto è uguale.
  MisuraConsumo? registra({
    required double batteria,
    required double metri,
    bool inCarica = false,
    double? energiaKwh,
  }) {
    final inKwh = energiaKwh != null && energiaKwh.isFinite;
    final livello = inKwh ? energiaKwh : batteria;
    if (inKwh != _inKwh) {
      _inKwh = inKwh;
      _da = null;
      _prima = null;
    }
    final da = _da;
    if (inCarica || (da != null && (livello > da.livello || metri < da.metri))) {
      _da = null;
      _prima = inCarica ? null : (livello: livello, metri: metri);
      return null;
    }
    if (da == null) {
      final prima = _prima;
      if (prima == null || livello > prima.livello || metri < prima.metri) {
        _prima = (livello: livello, metri: metri);
      } else if (livello < prima.livello) {
        _da = (livello: livello, metri: metri);
      }
      return null;
    }
    final calo = da.livello - livello;
    final percorsi = metri - da.metri;
    if (calo < (inKwh ? passoKwh : passoPercento) || percorsi < 1000) return null;
    _da = (livello: livello, metri: metri);
    final previsto = previstaFinoA(metri) - previstaFinoA(da.metri);
    final secondi = _fino(_secondi, metri) - _fino(_secondi, da.metri);
    return MisuraConsumo(
      previstoWh: previsto,
      realeWh: inKwh ? calo * 1000 : calo / 100 * capacitaKwh * 1000,
      km: percorsi / 1000,
      velocitaKmh: secondi > 0 ? percorsi / secondi * 3.6 : null,
    );
  }
}

/// L'energia di un tratto, in Wh: di solito [energiaTrattoWh] con il profilo
/// dell'auto e le condizioni del momento.
typedef ProfiloConsumo = double Function(Tratto t);
