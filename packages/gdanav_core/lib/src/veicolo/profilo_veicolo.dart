import '../colonnine/colonnina.dart';

/// Un punto della curva di ricarica: con la batteria a [batteria]% l'auto
/// accetta al massimo [potenzaKw].
class PuntoCurva {
  const PuntoCurva(this.batteria, this.potenzaKw);
  final double batteria;
  final double potenzaKw;
}

/// Tutto quello che serve sapere di un modello di auto per stimarne i
/// consumi e i tempi di ricarica.
class ProfiloVeicolo {
  const ProfiloVeicolo({
    this.id = '',
    this.marca = '',
    this.modello = '',
    this.potenzaAcKw = 11,
    required this.nome,
    required this.massaKg,
    required this.cdA,
    required this.crr,
    required this.capacitaUtileKwh,
    required this.curvaRicarica,
    this.connettori = const {TipoConnettore.ccs2, TipoConnettore.tipo2},
    this.rendimentoTrazione = 0.90,
    this.rendimentoRecupero = 0.65,
    this.consumoFissoW = 300,
  });

  /// Stabile, per ricordare la scelta: `tesla-model-3-lr`.
  final String id;
  final String marca;
  final String modello;

  /// La ricarica in alternata di bordo: 11 kW quasi per tutte.
  final double potenzaAcKw;

  final String nome;

  /// Massa in ordine di marcia più il conducente.
  final double massaKg;

  /// Coefficiente aerodinamico per area frontale, in m².
  final double cdA;

  /// Coefficiente di resistenza al rotolamento.
  final double crr;

  final double capacitaUtileKwh;

  /// Punti ordinati per batteria crescente.
  final List<PuntoCurva> curvaRicarica;

  /// Le prese che l'auto accetta.
  final Set<TipoConnettore> connettori;

  /// Dalla batteria alla ruota.
  final double rendimentoTrazione;

  /// Dalla ruota alla batteria, in frenata e in discesa.
  final double rendimentoRecupero;

  /// Elettronica, luci, pompe: quello che si consuma anche da fermi, senza
  /// clima.
  final double consumoFissoW;

  /// La potenza massima accettata alla [batteria] data, interpolando la
  /// curva.
  double potenzaRicaricaKw(double batteria) {
    final c = curvaRicarica;
    if (batteria <= c.first.batteria) return c.first.potenzaKw;
    if (batteria >= c.last.batteria) return c.last.potenzaKw;
    for (var i = 1; i < c.length; i++) {
      if (batteria <= c[i].batteria) {
        final a = c[i - 1], b = c[i];
        final t = (batteria - a.batteria) / (b.batteria - a.batteria);
        return a.potenzaKw + t * (b.potenzaKw - a.potenzaKw);
      }
    }
    return c.last.potenzaKw;
  }

  /// La potenza massima in continua, il numero delle schede tecniche.
  double get piccoDcKw => curvaRicarica.map((p) => p.potenzaKw).reduce((a, b) => a > b ? a : b);

  /// Una curva di ricarica con la forma tipica delle batterie a 400 V:
  /// sale fino al picco verso il 10%, lo tiene fino al 40% e poi cala.
  static List<PuntoCurva> curvaTipica(double piccoKw) => [
    PuntoCurva(0, piccoKw * 0.8),
    PuntoCurva(10, piccoKw),
    PuntoCurva(40, piccoKw),
    PuntoCurva(60, piccoKw * 0.75),
    PuntoCurva(80, piccoKw * 0.45),
    PuntoCurva(90, piccoKw * 0.25),
    PuntoCurva(100, piccoKw * 0.08),
  ];

  /// Un'auto media di segmento C, per le prove e per chi non ha ancora
  /// scelto il suo modello.
  static const esempio = ProfiloVeicolo(
    id: 'esempio',
    marca: 'Esempio',
    modello: 'Segmento C 60 kWh',
    nome: 'Esempio segmento C (60 kWh)',
    massaKg: 1900,
    cdA: 0.62,
    crr: 0.009,
    capacitaUtileKwh: 60,
    curvaRicarica: [
      PuntoCurva(0, 110),
      PuntoCurva(10, 130),
      PuntoCurva(50, 120),
      PuntoCurva(70, 80),
      PuntoCurva(80, 55),
      PuntoCurva(90, 30),
      PuntoCurva(100, 8),
    ],
  );
}
