import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';
import 'gestore_auto.dart';

/// A che punto è il viaggio.
sealed class StatoViaggio {
  const StatoViaggio();
}

class NessunViaggio extends StatoViaggio {
  const NessunViaggio();
}

class Calcolo extends StatoViaggio {
  const Calcolo(this.destinazione);
  final Luogo destinazione;
}

class ViaggioPronto extends StatoViaggio {
  const ViaggioPronto(this.destinazione, this.viaggio, this.batteriaPartenza);
  final Luogo destinazione;
  final Viaggio viaggio;
  final double batteriaPartenza;
}

class ErroreViaggio extends StatoViaggio {
  const ErroreViaggio(this.messaggio, {this.destinazione});
  final String messaggio;
  final Luogo? destinazione;
}

/// Costruisce il pianificatore con le impostazioni del momento: nelle prove
/// se ne passa uno finto.
typedef CostruisciPianificatore = PianificatoreViaggio Function(Impostazioni impostazioni, ProfiloVeicolo profilo);

PianificatoreViaggio pianificatoreVero(Impostazioni i, ProfiloVeicolo profilo) {
  final valhalla = ClienteValhalla(
    Uri.parse(i.valhalla.endsWith('/') ? i.valhalla : '${i.valhalla}/'),
    chiave: i.chiaveValhalla.isEmpty ? null : i.chiaveValhalla,
  );
  return PianificatoreViaggio(
    percorsi: valhalla.calcola,
    colonnine: ClienteOpenChargeMap(chiave: i.chiaveOcm),
    profilo: profilo,
  );
}

class GestoreViaggio extends ChangeNotifier {
  GestoreViaggio({
    required this.archivio,
    required this.auto,
    required this.posizione,
    this.costruisci = pianificatoreVero,
    this.profilo = ProfiloVeicolo.esempio,
    FonteLuoghi? luoghi,
  }) : luoghi = luoghi ?? ClientePhoton();

  final Archivio archivio;
  final GestoreAuto auto;

  /// Dove si è adesso. `null` se il telefono non lo sa o non lo vuole dire.
  final Future<Punto?> Function() posizione;
  final CostruisciPianificatore costruisci;
  final ProfiloVeicolo profilo;
  final FonteLuoghi luoghi;

  StatoViaggio stato = const NessunViaggio();

  /// L'ultimo punto noto, per cercare i luoghi vicino a chi cerca.
  Punto? ultimaPosizione;

  Future<void> pianifica(Luogo destinazione) async {
    final impostazioni = await archivio.impostazioni();
    if (impostazioni.mancante case final m?) return _imposta(ErroreViaggio(m, destinazione: destinazione));
    final batteria = auto.stato?.batteria;
    if (batteria == null) {
      return _imposta(
        ErroreViaggio('Non so quanta batteria hai: tocca la batteria in alto e scrivila.', destinazione: destinazione),
      );
    }
    final partenza = await posizione();
    if (partenza == null) {
      return _imposta(
        ErroreViaggio('Non so dove sei: attiva la posizione per gdanav.', destinazione: destinazione),
      );
    }
    ultimaPosizione = partenza;
    _imposta(Calcolo(destinazione));
    try {
      final viaggio = await costruisci(
        impostazioni,
        profilo,
      ).pianifica(partenza: partenza, arrivo: destinazione.posizione, batteria: batteria);
      // Nel frattempo l'utente può aver annullato o scelto un'altra meta.
      if (stato case Calcolo(destinazione: final d) when identical(d, destinazione)) {
        _imposta(ViaggioPronto(destinazione, viaggio, batteria));
      }
    } on ErroreValhalla catch (e) {
      _imposta(ErroreViaggio(_spiega(e), destinazione: destinazione));
    } catch (e) {
      _imposta(ErroreViaggio('Il viaggio non si è potuto calcolare: $e', destinazione: destinazione));
    }
  }

  void annulla() => _imposta(const NessunViaggio());

  static String _spiega(ErroreValhalla e) => switch (e.stato) {
    401 => 'Il server dei percorsi rifiuta la chiave: controllala nelle impostazioni.',
    400 when e.messaggio.contains('No path') => 'Non esiste una strada fra qui e la destinazione.',
    _ => 'Il server dei percorsi ha risposto: ${e.messaggio}',
  };

  void _imposta(StatoViaggio s) {
    stato = s;
    notifyListeners();
  }
}
