import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../servizi.dart';
import 'archivio.dart';
import 'gestore_auto.dart';
import 'gestore_consumo.dart';
import 'gestore_premium.dart';

/// A che punto è il viaggio.
sealed class StatoViaggio {
  const StatoViaggio();
}

class NessunViaggio extends StatoViaggio {
  const NessunViaggio();
}

class Calcolo extends StatoViaggio {
  Calcolo(this.destinazione);
  final Luogo destinazione;

  /// A che punto è: cambia mentre si calcola.
  FaseViaggio fase = FaseViaggio.percorso;
}

class ViaggioPronto extends StatoViaggio {
  const ViaggioPronto(this.destinazione, this.viaggio, this.batteriaPartenza, {required this.calcolatoAlle});
  final Luogo destinazione;
  final Viaggio viaggio;
  final double batteriaPartenza;

  /// Per dire l'ora d'arrivo: partenza adesso più la durata.
  final DateTime calcolatoAlle;

  DateTime? get arrivoAlle => viaggio.piano == null ? null : calcolatoAlle.add(viaggio.piano!.durata);
}

class ErroreViaggio extends StatoViaggio {
  const ErroreViaggio(this.messaggio, {this.destinazione});
  final String messaggio;
  final Luogo? destinazione;
}

/// Costruisce il pianificatore con le impostazioni del momento: nelle prove
/// se ne passa uno finto.
typedef CostruisciPianificatore = PianificatoreViaggio Function(
  Impostazioni impostazioni,
  ProfiloVeicolo profilo,
  PreferenzeRicarica preferenze,
  OpzioniPercorso opzioni,
);

/// L'archivio delle colonnine dentro l'app: si legge una volta, su un altro
/// filo (sono decine di migliaia).
Future<ArchivioColonnine> archivioColonnine() => _archivio ??= _leggiArchivio();
Future<ArchivioColonnine>? _archivio;

Future<ArchivioColonnine> _leggiArchivio() async {
  try {
    final testo = await rootBundle.loadString('assets/colonnine.json');
    return await Isolate.run(() => ArchivioColonnine.leggi(testo));
  } catch (e) {
    debugPrint('archivio colonnine: $e');
    return ArchivioColonnine.vuoto;
  }
}

PianificatoreViaggio pianificatoreVero(
  Impostazioni i,
  ProfiloVeicolo profilo,
  PreferenzeRicarica preferenze,
  OpzioniPercorso opzioni,
) {
  final valhalla = ClienteValhalla(
    Uri.parse(i.valhalla.endsWith('/') ? i.valhalla : '${i.valhalla}/'),
    chiave: i.chiaveValhalla.isEmpty ? null : i.chiaveValhalla,
  );
  return PianificatoreViaggio(
    percorsi: (tappe) => valhalla.calcola(tappe, opzioni: opzioni),
    // Open Charge Map se c'è la chiave (ha anche lo stato delle prese), e
    // comunque OpenStreetMap: dall'archivio dentro l'app, fuori archivio dal
    // relay di gdanav, e se tutto manca direttamente da Overpass.
    colonnine: FonteColonnineConRiserva([
      if (i.chiaveOcm.isNotEmpty) ClienteOpenChargeMap(chiave: i.chiaveOcm),
      ColonnineLocali(archivioColonnine(), riserva: ClienteColonnineRelay(Uri.parse(Servizi.segnalazioni))),
      ClienteOverpass(),
    ]),
    profilo: profilo,
    preferenze: preferenze,
    // Libere e occupate in tempo reale (Premium), se c'è la chiave TomTom.
    disponibilita: GestorePremium.attivo.value ? _disponibilita : null,
  );
}

final _disponibilita = Servizi.chiaveTomTom.isEmpty ? null : DisponibilitaTomTom(Servizi.chiaveTomTom);

class GestoreViaggio extends ChangeNotifier {
  GestoreViaggio({
    required this.archivio,
    required this.auto,
    required this.posizione,
    this.costruisci = pianificatoreVero,
    this.consumo,
    FonteLuoghi? luoghi,
    DateTime Function()? orologio,
  }) : luoghi = luoghi ?? ClientePhoton(),
       _ora = orologio ?? DateTime.now;

  final Archivio archivio;
  final GestoreAuto auto;

  /// Dove si è adesso. `null` se il telefono non lo sa o non lo vuole dire.
  final Future<Punto?> Function() posizione;
  final CostruisciPianificatore costruisci;

  /// Il consumo imparato e la temperatura: le soste si calcolano su come
  /// consuma davvero la tua auto.
  final GestoreConsumo? consumo;
  final FonteLuoghi luoghi;
  final DateTime Function() _ora;

  StatoViaggio stato = const NessunViaggio();

  /// Il meteo previsto lungo la strada (Premium), per il consumo: freddo,
  /// caldo e vento contro. `null`, o risposta `null`: si pianifica senza.
  Future<({double temperaturaC, double ventoControMs})?> Function(Punto da, Punto a)? stimaMeteo;

  /// Oltre questo si smette di aspettare e lo si dice.
  static const tempoMassimo = Duration(minutes: 2);

  /// Come si calcola il percorso: veloce o risparmio, cosa evitare.
  OpzioniPercorso opzioni = const OpzioniPercorso();

  /// Cambiate le opzioni si salvano e, se c'è un viaggio, si ricalcola.
  Future<void> cambiaOpzioni(OpzioniPercorso o) async {
    final strade = !mapEquals(o.valhalla, opzioni.valhalla);
    opzioni = o;
    notifyListeners();
    await archivio.salvaOpzioniPercorso(o);
    if (strade && destinazione != null) await pianifica(destinazione!);
  }

  /// Con cosa si è calcolato l'ultimo viaggio: temperatura, vento, correttivi.
  Condizioni? condizioni;

  /// Le colonnine dove l'utente ha deciso di fermarsi, per questo viaggio.
  final obbligate = <String>{};

  /// L'ultimo punto noto, per cercare i luoghi vicino a chi cerca.
  Punto? ultimaPosizione;

  Luogo? get destinazione => switch (stato) {
    NessunViaggio() => null,
    Calcolo(:final destinazione) || ViaggioPronto(:final destinazione) => destinazione,
    ErroreViaggio(:final destinazione) => destinazione,
  };

  /// Una meta nuova: le soste scelte per la vecchia non valgono più.
  Future<void> vaiA(Luogo destinazione) {
    obbligate.clear();
    return pianifica(destinazione);
  }

  /// «Fermati qui»: la colonnina diventa una sosta, e si ricalcola.
  Future<void> fermatiA(String idColonnina) async {
    final d = destinazione;
    if (d == null) return;
    obbligate.add(idColonnina);
    await pianifica(d);
  }

  Future<void> togliSosta(String idColonnina) async {
    final d = destinazione;
    if (d == null) return;
    obbligate.remove(idColonnina);
    await pianifica(d);
  }

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
      return _imposta(ErroreViaggio('Non so dove sei: attiva la posizione per gdanav.', destinazione: destinazione));
    }
    ultimaPosizione = partenza;
    final preferenze = await archivio.preferenze();
    opzioni = await archivio.opzioniPercorso();
    final calcolo = Calcolo(destinazione);
    _imposta(calcolo);
    try {
      var condizioni = consumo?.condizioni(auto.stato) ?? const Condizioni();
      if (await stimaMeteo?.call(partenza, destinazione.posizione) case final m?) {
        condizioni = Condizioni.daMeteo(
          temperaturaC: m.temperaturaC,
          ventoControMs: m.ventoControMs,
          fattoreConsumo: condizioni.fattoreConsumo,
          fattoriStrada: condizioni.fattoriStrada,
        );
      }
      this.condizioni = condizioni;
      final viaggio = await costruisci(impostazioni, auto.veicolo, preferenze, opzioni)
          .pianifica(
            partenza: partenza,
            arrivo: destinazione.posizione,
            batteria: batteria,
            condizioni: condizioni,
            obbligate: Set.of(obbligate),
            avanzamento: (f) {
              if (!identical(stato, calcolo)) return;
              calcolo.fase = f;
              notifyListeners();
            },
          )
          .timeout(tempoMassimo);
      // Nel frattempo l'utente può aver annullato o scelto un'altra meta.
      if (identical(stato, calcolo)) {
        _imposta(ViaggioPronto(destinazione, viaggio, batteria, calcolatoAlle: _ora()));
      }
    } on TimeoutException {
      if (identical(stato, calcolo)) {
        _imposta(
          ErroreViaggio(switch (calcolo.fase) {
            FaseViaggio.colonnine => 'I server delle colonnine non rispondono. Riprova tra poco.',
            _ => 'Il calcolo ci mette troppo: i server sono lenti. Riprova tra poco.',
          }, destinazione: destinazione),
        );
      }
    } on ErroreValhalla catch (e) {
      if (identical(stato, calcolo)) _imposta(ErroreViaggio(_spiega(e), destinazione: destinazione));
    } catch (e) {
      if (identical(stato, calcolo)) {
        final messaggio = '$e'.contains('colonnine')
            ? 'Per questo viaggio servono soste, ma le colonnine non sono arrivate. Riprova tra poco.'
            : 'Il viaggio non si è potuto calcolare: $e';
        _imposta(ErroreViaggio(messaggio, destinazione: destinazione));
      }
    }
  }

  void annulla() {
    obbligate.clear();
    _imposta(const NessunViaggio());
  }

  static String _spiega(ErroreValhalla e) => switch (e.stato) {
    401 || 403 => 'Il server dei percorsi non ci fa entrare in questo momento. Riprova tra poco.',
    429 => 'Il server dei percorsi è molto carico. Riprova tra un minuto.',
    400 when e.messaggio.contains('No path') => 'Non esiste una strada fra qui e la destinazione.',
    _ => 'Il server dei percorsi ha risposto: ${e.messaggio}',
  };

  void _imposta(StatoViaggio s) {
    stato = s;
    notifyListeners();
  }
}

/// Le colonnine rapide intorno a [qui] adatte all'auto, dalla più vicina; con
/// Premium anche libere e occupate adesso. Per «Colonnine vicine» sull'auto.
Future<List<Colonnina>> colonnineVicine(Punto qui, ProfiloVeicolo veicolo, {double km = 15, int quante = 8}) async {
  final fonte = ColonnineLocali(archivioColonnine(), riserva: ClienteColonnineRelay(Uri.parse(Servizi.segnalazioni)));
  final adatte = [
    for (final c in await fonte.lungo([qui], distanzaKm: km))
      if (c.potenzaNominalePer(veicolo.connettori) > 0 && distanzaM(qui, c.posizione) <= km * 1000) c,
  ]..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
  final prime = adatte.take(quante).toList();
  final d = GestorePremium.attivo.value ? _disponibilita : null;
  if (d == null) return prime;
  return Future.wait([
    for (final c in prime) d.aggiorna(c).timeout(const Duration(seconds: 8)).catchError((Object _) => c),
  ]);
}
