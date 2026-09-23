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

/// Mette insieme Valhalla, le colonnine e il pianificatore delle soste.
class PianificatoreViaggio {
  PianificatoreViaggio({
    required this.percorsi,
    required this.colonnine,
    required this.profilo,
    this.potenzaMinimaKw = 40,
  });

  final Future<PercorsoCalcolato> Function(List<Punto> tappe) percorsi;
  final FonteColonnine colonnine;
  final ProfiloVeicolo profilo;

  /// Sotto questa potenza una colonnina non vale la sosta in viaggio.
  final double potenzaMinimaKw;

  Future<Viaggio> pianifica({
    required Punto partenza,
    required Punto arrivo,
    required double batteria,
    Condizioni condizioni = const Condizioni(),
  }) async {
    final percorso = await percorsi([partenza, arrivo]);
    final pianificatore = PianificatoreSoste(profilo: profilo, condizioni: condizioni);

    // Se si arriva senza fermarsi, le colonnine non servono: una richiesta
    // in meno, e il piano è pronto prima.
    final senzaSoste =
        pianificatore.pianifica(percorso: percorso.tratti, batteriaPartenza: batteria, colonnine: const []);
    if (senzaSoste != null) return Viaggio(percorso: percorso, colonnine: const [], piano: senzaSoste);

    final vicine = colonnineSulPercorso(
      Linea(percorso.punti),
      await colonnine.lungo(percorso.punti),
      compatibili: profilo.connettori,
      potenzaMinimaKw: potenzaMinimaKw,
    );
    return Viaggio(
      percorso: percorso,
      colonnine: vicine,
      piano: pianificatore.pianifica(percorso: percorso.tratti, batteriaPartenza: batteria, colonnine: vicine),
    );
  }
}
