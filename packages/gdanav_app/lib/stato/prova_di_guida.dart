import 'dart:async';
import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_posizione.dart';

/// La prova di guida (il «test drive» di Android Auto, NF-7): una posizione
/// finta che percorre il percorso alla velocità dei suoi tratti, al posto del
/// GPS. Guida, voce, cruscotto e mappa non se ne accorgono: ricevono le
/// posizioni come se fossero vere.
class ProvaDiGuida {
  ProvaDiGuida({this.passo = const Duration(seconds: 1), this.acceleratore = 1});

  /// Ogni quanto arriva una posizione.
  final Duration passo;

  /// Quante volte più veloce del vero (nelle prove, per arrivare presto).
  final double acceleratore;

  final _punti = StreamController<Punto>.broadcast();
  final _letture = StreamController<Lettura>.broadcast();
  Timer? _timer;

  bool get attiva => _timer != null;

  /// Dove si è sul percorso, in metri dall'inizio.
  double fattiM = 0;

  /// Le posizioni per la guida: quelle finte durante la prova, altrimenti
  /// quelle del GPS.
  Stream<Punto> Function() posizioni(Stream<Punto> Function() vere) =>
      () => _unisci(vere, _punti.stream);

  /// Le letture per il segnaposto e il tachimetro, come sopra.
  Stream<Lettura> Function() letture(Stream<Lettura> Function() vere) =>
      () => _unisci(vere, _letture.stream);

  Stream<T> _unisci<T>(Stream<T> Function() vere, Stream<T> finte) {
    late StreamController<T> uscita;
    StreamSubscription<T>? a, b;
    uscita = StreamController<T>(
      onListen: () {
        a = vere().listen((v) {
          if (!attiva) uscita.add(v);
        }, onError: uscita.addError);
        b = finte.listen(uscita.add);
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return uscita.stream;
  }

  /// Si parte da [daM] metri e si va fino in fondo; arrivati, la posizione
  /// resta sulla meta finché la guida non si ferma.
  void percorri(PercorsoCalcolato percorso, {double daM = 0}) {
    ferma();
    final linea = Linea(percorso.punti);
    if (linea.punti.length < 2 || linea.lunghezzaM <= 0) return;
    final velocita = _velocita(percorso, linea.lunghezzaM);
    fattiM = daM.clamp(0, linea.lunghezzaM).toDouble();
    void avanti() {
      final kmh = velocita(fattiM);
      final ms = kmh / 3.6;
      final (punto, rotta) = puntoA(linea, fattiM);
      final fermo = fattiM >= linea.lunghezzaM;
      _letture.add(Lettura(punto, rotta: rotta, velocitaMs: fermo ? 0 : ms));
      _punti.add(punto);
      fattiM = math.min(linea.lunghezzaM, fattiM + ms * passo.inMilliseconds / 1000 * acceleratore);
    }

    _timer = Timer.periodic(passo, (_) => avanti());
    avanti();
  }

  void ferma() {
    _timer?.cancel();
    _timer = null;
  }

  /// La velocità a ogni metro: quella del tratto, fra 25 e 130 km/h. I tratti
  /// sono misurati sulle strade, la linea sulla geometria: si riportano in
  /// proporzione.
  static double Function(double) _velocita(PercorsoCalcolato p, double lunghezzaM) {
    final totale = p.tratti.fold(0.0, (s, t) => s + t.lunghezzaM);
    if (p.tratti.isEmpty || totale <= 0) return (_) => 50;
    final scala = lunghezzaM / totale;
    final fine = <double>[];
    var somma = 0.0;
    for (final t in p.tratti) {
      somma += t.lunghezzaM * scala;
      fine.add(somma);
    }
    return (m) {
      var i = 0;
      while (i < fine.length - 1 && fine[i] < m) {
        i++;
      }
      return p.tratti[i].velocitaKmh.clamp(25, 130).toDouble();
    };
  }

  /// Il punto a [m] metri lungo la linea, e la direzione in cui si va.
  static (Punto, double) puntoA(Linea linea, double m) {
    final c = linea.cumulate, punti = linea.punti;
    var basso = 0, alto = c.length - 1;
    while (alto - basso > 1) {
      final mezzo = (basso + alto) ~/ 2;
      if (c[mezzo] <= m) {
        basso = mezzo;
      } else {
        alto = mezzo;
      }
    }
    final a = punti[basso], b = punti[alto];
    final lungo = c[alto] - c[basso];
    final t = lungo <= 0 ? 0.0 : ((m - c[basso]) / lungo).clamp(0.0, 1.0);
    return (Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t), rottaGradi(a, b));
  }

  void chiudi() {
    ferma();
    _punti.close();
    _letture.close();
  }
}
