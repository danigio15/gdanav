import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../colonnine/colonnina.dart';
import '../veicolo/profilo_veicolo.dart';
import 'modello_consumo.dart';

/// Una colonnina lungo il percorso, già filtrata per connettore e stato.
class ColonninaSulPercorso {
  const ColonninaSulPercorso({
    required this.id,
    required this.nome,
    required this.distanzaM,
    required this.potenzaKw,
    this.deviazioneM = 0,
    this.disponibilita = Disponibilita.sconosciuta,
    this.obbligata = false,
    this.dettaglio,
  });

  final String id;
  final String nome;

  /// Dove si esce dal percorso, contando dalla partenza.
  final double distanzaM;

  final double potenzaKw;

  /// Dall'uscita alla colonnina, solo andata.
  final double deviazioneM;

  /// Le prese adatte all'auto, libere o no adesso.
  final Disponibilita disponibilita;

  /// L'ha scelta l'utente: ci si ferma per forza.
  final bool obbligata;

  /// La colonnina intera, per la mappa e la scheda.
  final Colonnina? dettaglio;
}

class Sosta {
  const Sosta(
      {required this.colonnina, required this.batteriaArrivo, required this.batteriaPartenza, required this.ricarica});

  final ColonninaSulPercorso colonnina;
  final double batteriaArrivo;
  final double batteriaPartenza;
  final Duration ricarica;
}

/// Un punto del grafico della batteria lungo il viaggio.
class PuntoBatteria {
  const PuntoBatteria(this.km, this.batteria);
  final double km;
  final double batteria;
}

class PianoViaggio {
  const PianoViaggio({
    required this.soste,
    required this.batteriaArrivo,
    required this.durata,
    this.profiloBatteria = const [],
    this.energiaKwh = 0,
  });

  final List<Sosta> soste;
  final double batteriaArrivo;

  /// Guida più ricariche più il tempo fisso di ogni sosta.
  final Duration durata;

  /// La batteria lungo la strada: scende guidando, sale alle soste.
  final List<PuntoBatteria> profiloBatteria;

  /// L'energia presa dalla batteria per tutto il viaggio.
  final double energiaKwh;

  Duration get ricarica => soste.fold(Duration.zero, (t, s) => t + s.ricarica);
}

/// Trova le soste che portano a destinazione nel minor tempo, senza mai
/// scendere sotto le soglie di sicurezza.
///
/// È un cammino minimo (Dijkstra) sugli stati «colonnina, batteria
/// all'arrivo», con la batteria a passi dell'1% arrotondati per difetto:
/// meglio arrivare con un punto in più che con uno in meno.
class PianificatoreSoste {
  PianificatoreSoste({
    required this.profilo,
    this.condizioni = const Condizioni(),
    this.minimoSosta = 10,
    this.minimoArrivo = 15,
    this.massimoRicarica = 90,
    this.passoRicarica = 5,
    this.tempoFissoSosta = const Duration(minutes: 4),
    this.velocitaDeviazioneKmh = 40,
    this.attesaSeOccupata = const Duration(minutes: 15),
  });

  final ProfiloVeicolo profilo;
  final Condizioni condizioni;

  /// Batteria minima con cui si arriva a una colonnina.
  final double minimoSosta;

  /// Batteria minima con cui si arriva a destinazione.
  final double minimoArrivo;

  /// Oltre questa soglia la ricarica rapida è così lenta che non conviene.
  final double massimoRicarica;

  final int passoRicarica;
  final Duration tempoFissoSosta;
  final double velocitaDeviazioneKmh;

  /// Quanto si conta di aspettare a una colonnina tutta occupata adesso.
  /// Zero per non tenerne conto.
  final Duration attesaSeOccupata;

  /// `null` se non c'è modo di arrivare.
  PianoViaggio? pianifica({
    required List<Tratto> percorso,
    required double batteriaPartenza,
    required List<ColonninaSulPercorso> colonnine,
  }) {
    final prog = _Progressivo(percorso, profilo, condizioni);
    final ordinate = colonnine.where((c) => c.distanzaM >= 0 && c.distanzaM <= prog.lunghezza).toList()
      ..sort((a, b) => a.distanzaM.compareTo(b.distanzaM));
    final n = ordinate.length;
    final cap = profilo.capacitaUtileKwh;
    // Da ogni punto non si può andare oltre la prossima sosta obbligata.
    final limite = List<int>.filled(n + 1, n);
    for (var i = n - 1; i >= 0; i--) {
      limite[i] = ordinate[i].obbligata ? i : limite[i + 1];
    }

    // Nodi: 0..n-1 le colonnine, n la destinazione. La partenza è a parte.
    final costo = <(int, int), double>{};
    final da = <(int, int), (int, int, int)?>{}; // nodo -> (nodo precedente, partenza%)
    final coda = PriorityQueue<(double, int, int)>((a, b) => a.$1.compareTo(b.$1));

    void rilassa(int verso, int arrivo, double secondi, (int, int, int)? precedente) {
      final chiave = (verso, arrivo);
      if (secondi < (costo[chiave] ?? double.infinity)) {
        costo[chiave] = secondi;
        da[chiave] = precedente;
        coda.add((secondi, verso, arrivo));
      }
    }

    void guida(
        {required double dalM,
        required double deviazioneDaM,
        required double batteria,
        required double secondi,
        required int indiceDa,
        required (int, int, int)? precedente}) {
      for (var j = indiceDa; j <= limite[indiceDa]; j++) {
        final destinazione = j == n;
        final alM = destinazione ? prog.lunghezza : ordinate[j].distanzaM;
        final deviazioneA = destinazione ? 0.0 : ordinate[j].deviazioneM;
        final kWh = prog.energiaKwh(dalM, alM) + _deviazioneKwh(deviazioneDaM) + _deviazioneKwh(deviazioneA);
        final arrivo = batteria - kWh / cap * 100;
        // L'energia cresce con la distanza: se non si arriva qui, più in là
        // nemmeno, salvo discese lunghe. Si prova comunque tutto, n è piccolo.
        if (arrivo < (destinazione ? minimoArrivo : minimoSosta)) continue;
        final t =
            secondi + prog.secondi(dalM, alM) + _deviazioneSecondi(deviazioneDaM) + _deviazioneSecondi(deviazioneA);
        rilassa(j, arrivo.floor(), t, precedente);
      }
    }

    guida(dalM: 0, deviazioneDaM: 0, batteria: batteriaPartenza, secondi: 0, indiceDa: 0, precedente: null);

    while (coda.isNotEmpty) {
      final (secondi, i, arrivo) = coda.removeFirst();
      if (secondi > (costo[(i, arrivo)] ?? double.infinity)) continue;
      if (i == n) return _ricostruisci(ordinate, da, (i, arrivo), secondi, prog, batteriaPartenza);

      final c = ordinate[i];
      // A una colonnina tutta guasta non si ricarica.
      if (c.disponibilita.guasta) continue;
      final primo = ((arrivo ~/ passoRicarica) + 1) * passoRicarica;
      // A una sosta scelta dall'utente ci si ferma comunque, anche se la
      // batteria è già sopra il massimo abituale.
      final ultimo = c.obbligata ? math.max(massimoRicarica.toInt(), math.min(primo, 100)) : massimoRicarica;
      final attesa = c.disponibilita.piena ? attesaSeOccupata.inSeconds : 0;
      for (var partenza = primo; partenza <= ultimo; partenza += passoRicarica) {
        final ricarica = _secondiRicarica(arrivo.toDouble(), partenza.toDouble(), c.potenzaKw);
        guida(
          dalM: c.distanzaM,
          deviazioneDaM: c.deviazioneM,
          batteria: partenza.toDouble(),
          secondi: secondi + ricarica + attesa + tempoFissoSosta.inSeconds,
          indiceDa: i + 1,
          precedente: (i, arrivo, partenza),
        );
      }
    }
    return null;
  }

  PianoViaggio _ricostruisci(
    List<ColonninaSulPercorso> ordinate,
    Map<(int, int), (int, int, int)?> da,
    (int, int) fine,
    double secondi,
    _Progressivo prog,
    double batteriaPartenza,
  ) {
    final soste = <Sosta>[];
    var passo = da[fine];
    while (passo != null) {
      final (i, arrivo, partenza) = passo;
      final c = ordinate[i];
      soste.add(Sosta(
        colonnina: c,
        batteriaArrivo: arrivo.toDouble(),
        batteriaPartenza: partenza.toDouble(),
        ricarica: Duration(seconds: _secondiRicarica(arrivo.toDouble(), partenza.toDouble(), c.potenzaKw).round()),
      ));
      passo = da[(i, arrivo)];
    }
    final ordinateSoste = soste.reversed.toList();
    return PianoViaggio(
      soste: ordinateSoste,
      batteriaArrivo: fine.$2.toDouble(),
      durata: Duration(seconds: secondi.round()),
      profiloBatteria: _profilo(ordinateSoste, prog, batteriaPartenza, fine.$2.toDouble()),
      energiaKwh: prog.energiaKwh(0, prog.lunghezza),
    );
  }

  /// Il grafico: a ogni tratto fra due soste la batteria scende come dice il
  /// modello; alla sosta sale di colpo.
  List<PuntoBatteria> _profilo(List<Sosta> soste, _Progressivo prog, double partenza, double arrivo) {
    final cap = profilo.capacitaUtileKwh;
    final passo = math.max(500.0, prog.lunghezza / 150);
    final punti = <PuntoBatteria>[];
    var daM = 0.0, batteria = partenza;
    void tratto(double aM, double fine) {
      for (var m = daM; m < aM; m += passo) {
        punti.add(PuntoBatteria(m / 1000, batteria - prog.energiaKwh(daM, m) / cap * 100));
      }
      punti.add(PuntoBatteria(aM / 1000, fine));
    }

    for (final s in soste) {
      tratto(s.colonnina.distanzaM, s.batteriaArrivo);
      punti.add(PuntoBatteria(s.colonnina.distanzaM / 1000, s.batteriaPartenza));
      daM = s.colonnina.distanzaM;
      batteria = s.batteriaPartenza;
    }
    tratto(prog.lunghezza, arrivo);
    return punti;
  }

  /// Si integra la curva a passi di mezzo punto: la potenza è il minimo fra
  /// quella che l'auto accetta e quella che la colonnina dà.
  double _secondiRicarica(double da, double a, double potenzaColonnina) {
    const passo = 0.5;
    final kWhPerPasso = profilo.capacitaUtileKwh * passo / 100;
    var s = 0.0;
    for (var b = da; b < a; b += passo) {
      final kw = math.min(profilo.potenzaRicaricaKw(b + passo / 2), potenzaColonnina);
      s += kWhPerPasso / kw * 3600;
    }
    return s;
  }

  double _deviazioneKwh(double m) => m <= 0
      ? 0
      : energiaTrattoWh(Tratto(lunghezzaM: m, velocitaKmh: velocitaDeviazioneKmh), profilo, condizioni) / 1000;

  double _deviazioneSecondi(double m) => m <= 0 ? 0 : m / (velocitaDeviazioneKmh / 3.6);
}

/// Distanza, energia e tempo cumulati lungo il percorso, per chiedere
/// quanto costa andare da un punto qualsiasi a un altro.
class _Progressivo {
  _Progressivo(List<Tratto> tratti, ProfiloVeicolo p, Condizioni c) {
    _m.add(0);
    _kWh.add(0);
    _s.add(0);
    for (final t in tratti) {
      _m.add(_m.last + t.lunghezzaM);
      _kWh.add(_kWh.last + energiaTrattoWh(t, p, c) / 1000);
      _s.add(_s.last + t.secondi);
    }
  }

  final _m = <double>[];
  final _kWh = <double>[];
  final _s = <double>[];

  double get lunghezza => _m.last;

  double energiaKwh(double da, double a) => _a(_kWh, a) - _a(_kWh, da);
  double secondi(double da, double a) => _a(_s, a) - _a(_s, da);

  double _a(List<double> serie, double m) {
    if (m <= 0) return serie.first;
    if (m >= lunghezza) return serie.last;
    final i = lowerBound(_m, m);
    if (_m[i] == m) return serie[i];
    final t = (m - _m[i - 1]) / (_m[i] - _m[i - 1]);
    return serie[i - 1] + t * (serie[i] - serie[i - 1]);
  }
}
