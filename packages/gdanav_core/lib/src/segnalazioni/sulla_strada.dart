import 'dart:math' as math;

import '../geo/geo.dart';
import 'segnalazioni.dart';

/* Quando e quali autovelox (e segnalazioni) avvisare.
 *
 * Dal campo: «gli autovelox li dice troppo presto, anche a 900 metri: in
 * città è troppo»; e «a volte avvisa di quelli su un'altra strada», due
 * strade quasi parallele, una sopra l'altra, a seicento metri.
 *
 * Prima si avvisava ad almeno 800 metri ovunque, e senza percorso bastava
 * stare dentro una striscia di trenta metri lungo la linea dritta davanti,
 * fino a un chilometro e mezzo: con due o tre gradi di bussola sbagliati, a
 * seicento metri, la striscia finisce sulla strada accanto.
 *
 * Adesso:
 *  * quanto prima dipende dai secondi che mancano alla velocità di adesso,
 *    tenuti fra un minimo e un massimo che dipendono dalla strada: in città
 *    pochi (al massimo 300 m), fuori di più, in autostrada di più ancora;
 *  * sul percorso conta la distanza lungo il percorso, e solo sul pezzo che
 *    si ha davanti: l'autovelox deve stare a pochi metri dalla linea del
 *    percorso, guardare chi va nella nostra direzione, e controllare un
 *    limite compatibile con quello della strada in quel punto;
 *  * senza percorso, solo quelli in una striscia stretta davanti, più
 *    stretta vicino, e con le stesse regole di direzione e di limite. Su una
 *    curva se ne perde qualcuno, mai se ne inventa. */

/// Che strada è, per quanto prima avvisare.
enum StradaAvviso {
  /// In città, o comunque piano: limite fino a 50.
  citta(15, 150, 300),

  /// Fuori città: limite fino a 90.
  fuori(20, 300, 600),

  /// Superstrade e autostrade.
  veloce(30, 600, 1200);

  const StradaAvviso(this.secondi, this.minimoM, this.massimoM);

  /// Quanti secondi prima, alla velocità di adesso.
  final int secondi;

  /// Mai meno di così: si fa in tempo anche piano.
  final double minimoM;

  /// Mai più di così: oltre, non si capisce di quale si parla.
  final double massimoM;

  /// Dal limite della strada.
  static StradaAvviso delLimite(int kmh) => kmh <= 50
      ? citta
      : kmh <= 90
          ? fuori
          : veloce;

  /// Dalla velocità: chi va a 70 non è in una via di città, anche se il
  /// limite dice 50 (e allora meglio saperlo un po' prima).
  static StradaAvviso dellaVelocita(double kmh) => kmh <= 65
      ? citta
      : kmh <= 100
          ? fuori
          : veloce;
}

/// Che strada è: la più veloce fra quella del limite (se si sa) e quella
/// della velocità.
StradaAvviso stradaAvviso(double kmh, {int? limiteKmh}) {
  final v = StradaAvviso.dellaVelocita(kmh);
  if (limiteKmh == null) return v;
  final l = StradaAvviso.delLimite(limiteKmh);
  return l.index >= v.index ? l : v;
}

/// Quanti metri prima avvisare, a [kmh], sulla strada col limite
/// [limiteKmh] (se si sa).
double distanzaAvvisoM(double kmh, {int? limiteKmh}) {
  final t = stradaAvviso(kmh, limiteKmh: limiteKmh);
  return (math.max(0.0, kmh) / 3.6 * t.secondi).clamp(t.minimoM, t.massimoM);
}

/// Il più lontano a cui si avvisa mai: fin dove guardare.
final double distanzaAvvisoMassimaM = StradaAvviso.values.map((t) => t.massimoM).reduce(math.max);

/// Quanto può stare lontano dalla linea della strada, al massimo: un
/// autovelox fisso sta sul bordo; una segnalazione la mette chi passa, col
/// GPS, e sbaglia di più. Una strada parallela, anche vicina, è più in là.
double lontanoMassimoM(Segnalazione s) => s.fissa ? 20 : 35;

/// Se l'autovelox col limite [autoveloxKmh] può stare sulla strada col
/// limite [stradaKmh]: un 50 su una strada a 110 è quello della strada di
/// sotto, o dell'uscita, non il nostro. Senza uno dei due, sì.
bool limitiCompatibili(int? autoveloxKmh, int? stradaKmh) =>
    autoveloxKmh == null || stradaKmh == null || (autoveloxKmh - stradaKmh).abs() <= 50;

/// Dove sta [s] lungo il percorso [linea], rispetto a chi ne ha già fatti
/// [percorsiM]: i metri davanti (negativi se già passata, fino a
/// [dietroM]), o `null` se non è sul percorso, o non è nel pezzo fra
/// [dietroM] dietro e [finoM] davanti.
///
/// Si guarda solo quel pezzo: un percorso che più avanti passa sotto (o
/// sopra) la strada di adesso non si confonde con questa. [limiteSul] dà il
/// limite di un segmento del percorso, se si sa.
double? sulPercorso(
  Linea linea,
  double percorsiM,
  Segnalazione s, {
  required double finoM,
  double dietroM = 250,
  int? Function(int segmento)? limiteSul,
}) {
  final n = linea.punti.length;
  if (n < 2) return null;
  final da = _segmentoA(linea, percorsiM - dietroM), a = _segmentoA(linea, percorsiM + finoM);
  final p = linea.proiettaTra(s.punto, da, a + 1);
  if (p.lontanoM > lontanoMassimoM(s)) return null;
  final i = p.segmento.clamp(0, n - 2);
  // Un autovelox fisso guarda una direzione: l'altra carreggiata, o una
  // strada che incrocia, no.
  if (s.fissa && !s.riguarda(rottaGradi(linea.punti[i], linea.punti[i + 1]))) return null;
  if (!limitiCompatibili(s.limiteKmh, limiteSul?.call(i))) return null;
  final avanti = p.lungoM - percorsiM;
  if (avanti > finoM || avanti < -dietroM) return null;
  return avanti;
}

/// Il segmento del percorso dove si è a [m] metri dall'inizio.
int _segmentoA(Linea linea, double m) {
  final c = linea.cumulate;
  var basso = 0, alto = c.length - 1;
  while (basso < alto) {
    final mezzo = (basso + alto + 1) ~/ 2;
    if (c[mezzo] <= m) {
      basso = mezzo;
    } else {
      alto = mezzo - 1;
    }
  }
  return basso.clamp(0, math.max(0, c.length - 2));
}

/// Senza percorso: i metri davanti a [s] per chi è in [qui] e va verso
/// [rotta] (gradi da nord), o `null` se non è sulla strada davanti.
///
/// Senza la strada, solo una striscia stretta lungo la direzione in cui si
/// va: larga 8 metri più il 4% della distanza (la bussola sbaglia di qualche
/// grado), mai più di [lontanoMassimoM]. Una strada parallela a 40 metri è
/// sempre fuori. [limiteStradaKmh] è il limite della strada di adesso.
double? davantiSenzaPercorso(
  Punto qui,
  double rotta,
  Segnalazione s, {
  required double finoM,
  int? limiteStradaKmh,
}) {
  final d = distanzaM(qui, s.punto);
  if (d > finoM || d < 5) return null;
  final angolo = (rottaGradi(qui, s.punto) - rotta) * math.pi / 180;
  final avanti = d * math.cos(angolo), accanto = (d * math.sin(angolo)).abs();
  if (avanti <= 0) return null;
  if (accanto > math.min(lontanoMassimoM(s), 8 + avanti * 0.04 + (s.fissa ? 0 : 10))) return null;
  if (s.fissa && !s.riguarda(rotta)) return null;
  if (!limitiCompatibili(s.limiteKmh, limiteStradaKmh)) return null;
  return avanti;
}
