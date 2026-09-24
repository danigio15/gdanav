import 'dart:isolate';

import '../colonnine/colonnina.dart';
import '../colonnine/lungo_percorso.dart';
import '../geo/geo.dart';
import '../motore/modello_consumo.dart';
import '../motore/pianificatore_soste.dart';
import '../percorso/valhalla.dart';
import '../veicolo/profilo_veicolo.dart';

/// Il viaggio completo: percorso, colonnine lungo la strada, soste.
class Viaggio {
  const Viaggio({required this.percorso, required this.colonnine, required this.piano});

  final PercorsoCalcolato percorso;

  /// Tutte quelle utili, per mostrarle sulla mappa.
  final List<ColonninaSulPercorso> colonnine;

  /// `null` se non si arriva nemmeno fermandosi.
  final PianoViaggio? piano;
}

/// Come si preferisce ricaricare. Si sceglie nelle impostazioni.
class PreferenzeRicarica {
  const PreferenzeRicarica({
    this.minimoArrivo = 15,
    this.minimoSosta = 10,
    this.massimoRicarica = 80,
    this.potenzaMinimaKw = 50,
    this.evitaOccupate = true,
  });

  factory PreferenzeRicarica.daJson(Map<String, Object?> j) {
    const d = PreferenzeRicarica();
    double n(String k, double v) => (j[k] as num?)?.toDouble() ?? v;
    return PreferenzeRicarica(
      minimoArrivo: n('minimo_arrivo', d.minimoArrivo),
      minimoSosta: n('minimo_sosta', d.minimoSosta),
      massimoRicarica: n('massimo_ricarica', d.massimoRicarica),
      potenzaMinimaKw: n('potenza_minima_kw', d.potenzaMinimaKw),
      evitaOccupate: j['evita_occupate'] as bool? ?? d.evitaOccupate,
    );
  }

  /// Batteria con cui arrivare a destinazione.
  final double minimoArrivo;

  /// Batteria con cui arrivare a una colonnina.
  final double minimoSosta;

  /// Fin dove ricaricare alle soste: oltre, la ricarica rapida rallenta.
  final double massimoRicarica;

  /// Le colonnine più lente non si propongono come soste.
  final double potenzaMinimaKw;

  /// Mette in conto un'attesa alle colonnine tutte occupate adesso, così si
  /// preferiscono quelle libere.
  final bool evitaOccupate;

  PreferenzeRicarica copia({
    double? minimoArrivo,
    double? minimoSosta,
    double? massimoRicarica,
    double? potenzaMinimaKw,
    bool? evitaOccupate,
  }) =>
      PreferenzeRicarica(
        minimoArrivo: minimoArrivo ?? this.minimoArrivo,
        minimoSosta: minimoSosta ?? this.minimoSosta,
        massimoRicarica: massimoRicarica ?? this.massimoRicarica,
        potenzaMinimaKw: potenzaMinimaKw ?? this.potenzaMinimaKw,
        evitaOccupate: evitaOccupate ?? this.evitaOccupate,
      );

  Map<String, Object?> toJson() => {
        'minimo_arrivo': minimoArrivo,
        'minimo_sosta': minimoSosta,
        'massimo_ricarica': massimoRicarica,
        'potenza_minima_kw': potenzaMinimaKw,
        'evita_occupate': evitaOccupate,
      };
}

/// A che punto è il calcolo, per dirlo a chi aspetta.
enum FaseViaggio { percorso, colonnine, soste }

/// Mette insieme Valhalla, le colonnine e il pianificatore delle soste.
class PianificatoreViaggio {
  PianificatoreViaggio({
    required this.percorsi,
    required this.colonnine,
    required this.profilo,
    this.preferenze = const PreferenzeRicarica(),
  });

  final Future<PercorsoCalcolato> Function(List<Punto> tappe) percorsi;
  final FonteColonnine colonnine;
  final ProfiloVeicolo profilo;
  final PreferenzeRicarica preferenze;

  /// [obbligate]: gli id delle colonnine dove l'utente vuole fermarsi.
  Future<Viaggio> pianifica({
    required Punto partenza,
    required Punto arrivo,
    required double batteria,
    Condizioni condizioni = const Condizioni(),
    Set<String> obbligate = const {},
    void Function(FaseViaggio fase)? avanzamento,
  }) async {
    avanzamento?.call(FaseViaggio.percorso);
    final percorso = await percorsi([partenza, arrivo]);
    final p = preferenze;
    final pianificatore = PianificatoreSoste(
      profilo: profilo,
      condizioni: condizioni,
      minimoArrivo: p.minimoArrivo,
      minimoSosta: p.minimoSosta,
      massimoRicarica: p.massimoRicarica,
      attesaSeOccupata: p.evitaOccupate ? const Duration(minutes: 15) : Duration.zero,
    );
    final senzaSoste = obbligate.isEmpty
        ? pianificatore.pianifica(percorso: percorso.tratti, batteriaPartenza: batteria, colonnine: const [])
        : null;

    // Le colonnine si chiedono sempre, anche quando non servono: sulla mappa
    // si vedono lungo la strada, e se ne può scegliere una. Ma se il servizio
    // non risponde e la batteria basta, il viaggio si fa lo stesso.
    avanzamento?.call(FaseViaggio.colonnine);
    List<Colonnina> trovate;
    try {
      trovate = await colonnine.lungo(percorso.punti);
    } catch (_) {
      if (senzaSoste == null) rethrow;
      trovate = const [];
    }
    // Proiettare migliaia di colonnine e cercare le soste è lavoro pesante:
    // si fa su un altro filo, così l'interfaccia non si blocca.
    avanzamento?.call(FaseViaggio.soste);
    final prese = profilo.connettori;
    final (vicine, piano) = await Isolate.run(() {
      final vicine = colonnineSulPercorso(
        Linea(percorso.punti),
        trovate,
        compatibili: prese,
        potenzaMinimaKw: p.potenzaMinimaKw,
        obbligate: obbligate,
      );
      return (
        vicine,
        senzaSoste ?? pianificatore.pianifica(percorso: percorso.tratti, batteriaPartenza: batteria, colonnine: vicine),
      );
    });
    return Viaggio(percorso: percorso, colonnine: vicine, piano: piano);
  }
}
