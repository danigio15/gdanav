import 'dart:math' as math;

import '../motore/modello_consumo.dart';
import '../percorso/valhalla.dart';

/// La striscia del traffico: il percorso che resta, di lato, con le code.
///
/// «Mostra lateralmente la striscia del traffico con i minuti di ritardo e
/// man mano a che punto è il traffico.» In basso c'è l'auto, in cima la meta
/// (o i prossimi [finestraPredefinitaM] metri, se il viaggio è più lungo):
/// le code sono tratti colorati al loro posto, ognuna coi minuti che fa
/// ancora perdere. Man mano che si va avanti la parte fatta sparisce e le
/// code scendono verso l'auto.
///
/// Qui non c'è niente da disegnare: solo dove sta ogni coda, da 0 (l'auto) a
/// 1 (la cima della striscia), e quanto pesa.

/// Fin dove guarda la striscia, al massimo: oltre, le code di un viaggio
/// lungo diventerebbero righe di un pixel.
const finestraPredefinitaM = 100000.0;

/// Una coda sulla striscia.
class CodaInStriscia {
  const CodaInStriscia({
    required this.da,
    required this.a,
    required this.livello,
    required this.minuti,
    required this.distanzaM,
    this.tipo,
    this.secondi = 0,
  });

  /// Dove comincia e dove finisce, da 0 (l'auto) a 1 (la cima).
  final double da;
  final double a;

  /// 1 rallentamento, 2 coda, 3 coda ferma, 4 strada chiusa ([Coda.livello]).
  final int livello;

  /// Quanti minuti fa ancora perdere la parte che resta (arrotondati).
  final int minuti;

  /// Fra quanti metri comincia; 0 se ci si è dentro.
  final double distanzaM;

  /// «Lavori», «Incidente»…, se si sa.
  final String? tipo;

  /// I secondi esatti che fa ancora perdere, prima di arrotondare.
  final double secondi;

  bool get dentro => distanzaM <= 0;

  CodaInStriscia _conMinuti(int m) => CodaInStriscia(
        da: da,
        a: a,
        livello: livello,
        minuti: m,
        distanzaM: distanzaM,
        tipo: tipo,
        secondi: secondi,
      );

  @override
  String toString() => 'CodaInStriscia(${da.toStringAsFixed(3)}–${a.toStringAsFixed(3)}, '
      'livello $livello, $minuti min, a ${distanzaM.round()} m)';
}

/// La striscia intera: le code e quanta strada rappresenta.
class StrisciaTraffico {
  const StrisciaTraffico({required this.code, required this.scalaM, required this.restantiM});

  /// Dal basso verso l'alto.
  final List<CodaInStriscia> code;

  /// Quanti metri vanno dall'auto alla cima della striscia.
  final double scalaM;

  /// Quanti metri restano fino alla meta.
  final double restantiM;

  /// Il viaggio continua oltre la cima: in cima la meta non c'è.
  bool get tagliata => restantiM > scalaM + 1;

  /// I minuti delle code disegnate.
  int get minuti => code.fold(0, (s, c) => s + c.minuti);

  /// Le etichette che tornano col «+N min di traffico» scritto in basso.
  ///
  /// A 10 km la striscia diceva «+10 min» e sotto «+11 min di traffico»: la
  /// scritta in basso è il ritardo che resta, smorzato perché non balli
  /// ([RitardoMostrato]), e le etichette erano ogni coda arrotondata per
  /// conto suo. Quando il ritardo che resta sta (quasi) tutto nelle code
  /// disegnate, i [mostrati] minuti si dividono fra le code in proporzione ai
  /// loro secondi, col metodo dei resti più grandi: la somma delle etichette
  /// è esattamente il numero scritto sotto. Quando invece una parte buona del
  /// ritardo sta fuori dalle code (rallentamento sparso, code oltre la cima)
  /// le etichette restano le loro, ma mai sopra [mostrati].
  StrisciaTraffico allineataA(int mostrati, Duration ritardoDavanti) {
    if (code.isEmpty) return this;
    final inCode = code.fold(0.0, (s, c) => s + c.secondi);
    final totale = ritardoDavanti.inMilliseconds / 1000;
    if (mostrati <= 0) return _con([for (final c in code) c._conMinuti(0)]);
    if (inCode <= 0) return this;
    final tutto = totale <= 0 || inCode >= 0.8 * totale;
    if (!tutto) {
      // Le loro, ma la somma non supera quello scritto sotto.
      var resta = mostrati;
      return _con([
        for (final c in code)
          () {
            final m = math.min(c.minuti, resta);
            resta -= m;
            return c._conMinuti(m);
          }(),
      ]);
    }
    final quote = [for (final c in code) mostrati * c.secondi / inCode];
    final interi = [for (final q in quote) q.floor()];
    var mancano = mostrati - interi.fold(0, (s, m) => s + m);
    final ordine = [for (var i = 0; i < code.length; i++) i]
      ..sort((x, y) => (quote[y] - interi[y]).compareTo(quote[x] - interi[x]));
    for (final i in ordine) {
      if (mancano <= 0) break;
      interi[i] += 1;
      mancano -= 1;
    }
    return _con([for (var i = 0; i < code.length; i++) code[i]._conMinuti(interi[i])]);
  }

  StrisciaTraffico _con(List<CodaInStriscia> nuove) =>
      StrisciaTraffico(code: nuove, scalaM: scalaM, restantiM: restantiM);
}

/// Le code del [percorso] davanti a chi ha già fatto [percorsiM] metri, in
/// una striscia lunga al massimo [finestraM].
///
/// Una coda già passata non c'è più; una in cui si è dentro conta per la
/// parte che resta. I minuti sono quelli che la coda fa perdere davvero coi
/// tempi del percorso, quando si ha la versione senza traffico per
/// confrontarli ([PercorsoCalcolato.senzaTraffico]); se no (i tempi di
/// TomTom) quelli che la coda dichiara, per la sua parte non fatta — come
/// [ritardoTrafficoAvanti]. Le code che cominciano oltre la cima non si
/// disegnano. `null` se davanti non c'è nessuna coda da mostrare: la
/// striscia non si mette.
StrisciaTraffico? strisciaTraffico(
  PercorsoCalcolato percorso, {
  required double percorsiM,
  double finestraM = finestraPredefinitaM,
}) {
  final lunghezza = percorso.lunghezzaM;
  final fatti = percorsiM.clamp(0.0, lunghezza);
  final restanti = math.max(0.0, lunghezza - fatti);
  if (restanti <= 0 || percorso.code.isEmpty) return null;
  final scala = math.min(restanti, math.max(1.0, finestraM));
  final base = percorso.senzaTraffico;
  final code = <CodaInStriscia>[];
  for (final c in percorso.code) {
    if (c.aM <= fatti || c.aM <= c.daM) continue;
    final inizio = math.max(c.daM, fatti);
    if (inizio - fatti >= scala) continue;
    // La parte della coda che resta davanti.
    final resta = ((c.aM - inizio) / c.lunghezzaM).clamp(0.0, 1.0);
    final secondi = base == null
        ? c.ritardo.inMilliseconds / 1000 * resta
        : _persiNellaCoda(percorso.tratti, base.tratti, c.daM, c.aM) * resta;
    code.add(
      CodaInStriscia(
        da: ((inizio - fatti) / scala).clamp(0.0, 1.0),
        a: ((c.aM - fatti) / scala).clamp(0.0, 1.0),
        livello: c.livello,
        minuti: (secondi / 60).round(),
        distanzaM: math.max(0.0, c.daM - fatti),
        tipo: c.tipo,
        secondi: secondi,
      ),
    );
  }
  if (code.isEmpty) return null;
  code.sort((x, y) => x.da.compareTo(y.da));
  return StrisciaTraffico(code: code, scalaM: scala, restantiM: restanti);
}

/// Quanti secondi fa perdere la coda da [daM] ad [aM], coi tempi col
/// traffico ([conTraffico]) contro quelli senza ([senza]).
///
/// [PercorsoCalcolato.conTraffico] rallenta i tratti interi che la coda
/// tocca: si confrontano quei tratti, uno per uno, così il ritardo che finisce
/// sul pezzo di tratto fuori dalla coda resta suo. Se i tratti non si
/// corrispondono (non dovrebbe), si confronta il tempo fra [daM] e [aM].
double _persiNellaCoda(List<Tratto> conTraffico, List<Tratto> senza, double daM, double aM) {
  if (conTraffico.length != senza.length) {
    return math.max(0.0, _secondiFra(conTraffico, daM, aM) - _secondiFra(senza, daM, aM));
  }
  var m = 0.0, persi = 0.0;
  for (var i = 0; i < conTraffico.length; i++) {
    final fine = m + conTraffico[i].lunghezzaM;
    if (fine > daM && m < aM) persi += _secondi(conTraffico[i]) - _secondi(senza[i]);
    if (fine >= aM) break;
    m = fine;
  }
  return math.max(0.0, persi);
}

double _secondi(Tratto t) => t.velocitaKmh > 0 ? t.lunghezzaM / (t.velocitaKmh / 3.6) : 0;

/// Quanti secondi ci vogliono da [daM] ad [aM] coi [tratti], a velocità
/// costante dentro ogni tratto.
double _secondiFra(List<Tratto> tratti, double daM, double aM) {
  var m = 0.0, secondi = 0.0;
  for (final t in tratti) {
    final fine = m + t.lunghezzaM;
    final dentro = math.min(fine, aM) - math.max(m, daM);
    if (dentro > 0 && t.velocitaKmh > 0) secondi += dentro / (t.velocitaKmh / 3.6);
    if (fine >= aM) break;
    m = fine;
  }
  return secondi;
}
