import '../veicolo/stato_auto.dart';

/// Cosa si legge da una richiesta.
enum CampoObd { batteria, velocita, temperaturaEsterna, potenza, contachilometri, inCarica }

/// Una lettura: a chi chiedere, cosa chiedere e come leggere i byte.
class LetturaObd {
  const LetturaObd(this.campo, this.pid, this.formula, {this.intestazione, this.ogni = 1});

  final CampoObd campo;
  final String pid;
  final String? intestazione;

  /// Dai byte dei dati (dopo servizio e PID) al valore, nelle unità di
  /// [StatoAuto]: %, km/h, °C, kW, km. `null` se i byte non bastano.
  final double? Function(List<int> b) formula;

  /// Ogni quanti giri: il contachilometri non serve a ogni giro.
  final int ogni;
}

/// Come leggere una famiglia di auto. Quelli specifici di un modello si
/// aggiungono qui, provati sull'auto vera.
class ProfiloObd {
  const ProfiloObd({required this.id, required this.nome, required this.letture, this.marche = const {}});

  final String id;
  final String nome;

  /// Le marche per cui proporlo da solo.
  final Set<String> marche;
  final List<LetturaObd> letture;
}

double? _a(List<int> b, double Function(int a) f) => b.isEmpty ? null : f(b[0]);

/// I PID OBD-II standard (SAE J1979): li hanno quasi tutte le auto, anche se
/// per la batteria di trazione molte elettriche non rispondono al 015B e
/// servono i PID del costruttore.
const profiloStandard = ProfiloObd(
  id: 'obd2-standard',
  nome: 'OBD-II standard',
  letture: [
    // «Vita residua del pacco batteria ibrido»: su molte elettriche è la
    // percentuale di carica.
    LetturaObd(CampoObd.batteria, '015B', _batteria015B),
    LetturaObd(CampoObd.velocita, '010D', _velocita010D),
    LetturaObd(CampoObd.temperaturaEsterna, '0146', _temperatura0146, ogni: 12),
    LetturaObd(CampoObd.contachilometri, '01A6', _odometro01A6, ogni: 30),
  ],
);

double? _batteria015B(List<int> b) => _a(b, (a) => a * 100 / 255);
double? _velocita010D(List<int> b) => _a(b, (a) => a.toDouble());
double? _temperatura0146(List<int> b) => _a(b, (a) => a - 40.0);
double? _odometro01A6(List<int> b) => b.length < 4 ? null : ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) / 10;

const profiliObd = [profiloStandard];

/// Il profilo per una marca, o quello standard.
ProfiloObd profiloPerMarca(String marca) =>
    profiliObd.where((p) => p.marche.contains(marca)).firstOrNull ?? profiloStandard;

/// Mette insieme le letture di un giro in uno [StatoAuto]; `null` senza la
/// batteria, che è il minimo per pianificare.
StatoAuto? statoDaObd(Map<CampoObd, double> valori, DateTime letto) {
  final batteria = valori[CampoObd.batteria];
  if (batteria == null) return null;
  return StatoAuto(
    sorgente: TipoSorgente.obd,
    letto: letto,
    batteria: batteria.clamp(0, 100).toDouble(),
    velocitaKmh: valori[CampoObd.velocita],
    temperaturaEsternaC: valori[CampoObd.temperaturaEsterna],
    potenzaKw: valori[CampoObd.potenza],
    odometroKm: valori[CampoObd.contachilometri],
    inCarica: switch (valori[CampoObd.inCarica]) {
      null => null,
      final v => v > 0,
    },
  );
}
