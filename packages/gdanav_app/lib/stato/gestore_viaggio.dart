import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../servizi.dart';
import 'archivio.dart';
import 'gestore_auto.dart';
import 'gestore_consumo.dart';
import '../risorse.dart';
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
  const ViaggioPronto(
    this.destinazione,
    this.viaggio,
    this.batteriaPartenza, {
    required this.calcolatoAlle,
    this.termica = false,
    this.scelte = const [],
    this.scelta = 0,
    this.tappe = const [],
  });
  final Luogo destinazione;
  final Viaggio viaggio;
  final double batteriaPartenza;

  /// I percorsi fra cui scegliere (col traffico, se c'è), e quale si sta
  /// usando. Vuota con le tappe o se il server ne dà uno solo.
  final List<PercorsoCalcolato> scelte;
  final int scelta;

  /// Dove si passa prima della meta, in ordine.
  final List<Luogo> tappe;

  /// Auto termica: solo il percorso, senza batteria né soste.
  final bool termica;

  /// Per dire l'ora d'arrivo: partenza adesso più la durata.
  final DateTime calcolatoAlle;

  DateTime? get arrivoAlle => termica
      ? calcolatoAlle.add(viaggio.percorso.durata)
      : viaggio.piano == null
      ? null
      : calcolatoAlle.add(viaggio.piano!.durata);
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
    final testo = await rootBundle.loadString('$radiceRisorse/colonnine.json');
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
  final traffico = GestorePremium.attivo.value ? _traffico : null;
  return PianificatoreViaggio(
    percorsi: (tappe) => valhalla.calcola(tappe, opzioni: opzioni),
    alternative: (da, a) => valhalla.alternative(da, a, opzioni: opzioni),
    seguendo: (p) => valhalla.seguendo(p, opzioni: opzioni),
    // Il traffico di adesso sul percorso (Premium): arrivo e soste lo
    // mettono in conto.
    traffico: traffico?.applica,
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
final _traffico = Servizi.chiaveTomTom.isEmpty ? null : TrafficoTomTom(Servizi.chiaveTomTom);

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
  /// Con quanta batteria arrivare (in %), come nelle preferenze di ricarica;
  /// `null` finché non si è letto.
  double? minimoArrivo;

  /// Cambia la batteria all'arrivo (anche dall'auto): si salva e, se c'è una
  /// meta, si ricalcolano le soste.
  Future<void> cambiaMinimoArrivo(double percento) async {
    final p = await archivio.preferenze();
    await archivio.salvaPreferenze(p.copia(minimoArrivo: percento));
    minimoArrivo = percento;
    notifyListeners();
    if (destinazione case final d?) await pianifica(d);
  }

  Future<void> cambiaOpzioni(OpzioniPercorso o) async {
    final strade = !mapEquals(o.valhalla, opzioni.valhalla);
    opzioni = o;
    notifyListeners();
    await archivio.salvaOpzioniPercorso(o);
    if (strade && destinazione != null) await pianifica(destinazione!, conScelte: true);
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

  /// Auto termica: un distributore dove passare prima della meta.
  Luogo? tappa;

  /// Le tappe del viaggio, prima della meta, in ordine.
  final tappe = <Luogo>[];

  /// Tutte quelle da cui passare: il distributore (se c'è), poi le tappe.
  List<Luogo> get _daPassare => [?tappa, ...tappe];

  /// I percorsi fra cui scegliere per questa meta, e quello scelto.
  List<PercorsoCalcolato> _scelte = const [];
  int _scelta = 0;

  /// Una meta nuova: le soste scelte per la vecchia non valgono più.
  Future<void> vaiA(Luogo destinazione) {
    obbligate.clear();
    tappa = null;
    tappe.clear();
    return pianifica(destinazione, conScelte: true);
  }

  /// Il traffico di adesso sul percorso (Premium, con la chiave TomTom);
  /// nelle prove se ne passa uno finto.
  Future<PercorsoCalcolato> Function(PercorsoCalcolato percorso)? trafficoFinto;

  Future<PercorsoCalcolato> Function(PercorsoCalcolato percorso)? get _trafficoAdesso =>
      trafficoFinto ?? (GestorePremium.attivo.value ? _traffico?.applica : null);

  /// Rilegge il traffico sul viaggio pronto (in guida, ogni tanto): stessa
  /// strada, tempi e code nuovi. `null` se non si può o non è cambiato
  /// niente.
  Future<ViaggioPronto?> aggiornaTraffico() async {
    final s = stato;
    final t = _trafficoAdesso;
    if (s is! ViaggioPronto || t == null) return null;
    final PercorsoCalcolato p;
    try {
      p = await t(s.viaggio.percorso).timeout(const Duration(seconds: 25));
    } catch (_) {
      return null;
    }
    // Nel frattempo si è ricalcolato o annullato: il traffico vecchio non serve.
    if (!identical(stato, s)) return null;
    final nuovo = ViaggioPronto(
      s.destinazione,
      Viaggio(percorso: p, colonnine: s.viaggio.colonnine, piano: s.viaggio.piano),
      s.batteriaPartenza,
      calcolatoAlle: s.calcolatoAlle,
      termica: s.termica,
      scelte: s.scelte,
      scelta: s.scelta,
      tappe: s.tappe,
    );
    _imposta(nuovo);
    return nuovo;
  }

  /// Partiti, le strade proposte non servono più: i ricalcoli partono da
  /// dove si è.
  void dimenticaScelte() {
    _scelte = const [];
    _scelta = 0;
  }

  /// Un'altra delle strade proposte: si rifanno le soste su quella.
  Future<void> scegli(int i) async {
    final d = destinazione;
    if (d == null || i < 0 || i >= _scelte.length || i == _scelta) return;
    _scelta = i;
    obbligate.clear();
    await pianifica(d);
  }

  /// Una tappa in più, prima della meta (in fondo, o in [posizione]).
  Future<void> aggiungiTappa(Luogo l, {int? posizione}) async {
    tappe.insert((posizione ?? tappe.length).clamp(0, tappe.length), l);
    _scelte = const [];
    final d = destinazione;
    if (d != null) await pianifica(d);
  }

  Future<void> togliTappa(int i) async {
    if (i < 0 || i >= tappe.length) return;
    tappe.removeAt(i);
    _scelte = const [];
    final d = destinazione;
    if (d != null) await pianifica(d, conScelte: tappe.isEmpty);
  }

  /// Cambia l'ordine: la tappa [da] va in [a].
  Future<void> spostaTappa(int da, int a) async {
    if (da < 0 || da >= tappe.length) return;
    final t = tappe.removeAt(da);
    tappe.insert(a.clamp(0, tappe.length), t);
    final d = destinazione;
    if (d != null) await pianifica(d);
  }

  /// La meta diventa una tappa e [nuova] la meta: «aggiungi una
  /// destinazione dopo».
  Future<void> proseguiVerso(Luogo nuova) async {
    final d = destinazione;
    if (d == null) return vaiA(nuova);
    tappe.add(d);
    _scelte = const [];
    await pianifica(nuova);
  }

  /// Le tappe raggiunte o già passate (entro [fattiM] del percorso) si
  /// tolgono: da qui si va verso la prossima.
  void tappeFatte(Punto qui, {double? fattiM}) {
    final p = stato is ViaggioPronto ? (stato as ViaggioPronto).viaggio.percorso : null;
    final linea = p == null ? null : Linea(p.punti);
    bool fatta(Luogo t) =>
        distanzaM(qui, t.posizione) < 60 ||
        (fattiM != null && linea != null && linea.proietta(t.posizione).lungoM <= fattiM);
    if (tappa case final t? when fatta(t)) tappa = null;
    while (tappe.isNotEmpty && fatta(tappe.first)) {
      tappe.removeAt(0);
    }
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

  /// [conScelte]: si cercano anche le strade alternative (una meta nuova,
  /// opzioni cambiate); in guida no, si ricalcola e basta.
  Future<void> pianifica(Luogo destinazione, {bool conScelte = false}) async {
    final impostazioni = await archivio.impostazioni();
    if (impostazioni.mancante case final m?) return _imposta(ErroreViaggio(m, destinazione: destinazione));
    if (conScelte) {
      _scelte = const [];
      _scelta = 0;
    }
    if (!auto.elettrica) return _percorsoSolo(destinazione, impostazioni, conScelte: conScelte);
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
    minimoArrivo = preferenze.minimoArrivo;
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
      final pianificatore = costruisci(impostazioni, auto.veicolo, preferenze, opzioni);
      final scelto = await _scegli(pianificatore, partenza, destinazione, conScelte);
      final viaggio = await pianificatore
          .pianifica(
            partenza: partenza,
            arrivo: destinazione.posizione,
            tappe: [for (final t in _daPassare) t.posizione],
            scelto: scelto,
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
        _imposta(
          ViaggioPronto(
            destinazione,
            viaggio,
            batteria,
            calcolatoAlle: _ora(),
            scelte: _scelte,
            scelta: _scelta,
            tappe: List.of(tappe),
          ),
        );
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

  /// Auto termica: il percorso e basta, come un navigatore normale.
  Future<void> _percorsoSolo(Luogo destinazione, Impostazioni impostazioni, {bool conScelte = false}) async {
    final partenza = await posizione();
    if (partenza == null) {
      return _imposta(ErroreViaggio('Non so dove sei: attiva la posizione per gdanav.', destinazione: destinazione));
    }
    ultimaPosizione = partenza;
    opzioni = await archivio.opzioniPercorso();
    final calcolo = Calcolo(destinazione);
    _imposta(calcolo);
    condizioni = null;
    try {
      final pianificatore = costruisci(impostazioni, auto.veicolo, await archivio.preferenze(), opzioni);
      final scelto = await _scegli(pianificatore, partenza, destinazione, conScelte);
      final percorso = await pianificatore
          .percorso(
            partenza: partenza,
            arrivo: destinazione.posizione,
            tappe: [for (final t in _daPassare) t.posizione],
            scelto: scelto,
          )
          .timeout(tempoMassimo);
      if (identical(stato, calcolo)) {
        _imposta(
          ViaggioPronto(
            destinazione,
            Viaggio(percorso: percorso, colonnine: const [], piano: null),
            0,
            calcolatoAlle: _ora(),
            termica: true,
            scelte: _scelte,
            scelta: _scelta,
            tappe: List.of(tappe),
          ),
        );
      }
    } on TimeoutException {
      if (identical(stato, calcolo)) {
        _imposta(
          ErroreViaggio(
            'Il calcolo ci mette troppo: i server sono lenti. Riprova tra poco.',
            destinazione: destinazione,
          ),
        );
      }
    } on ErroreValhalla catch (e) {
      if (identical(stato, calcolo)) _imposta(ErroreViaggio(_spiega(e), destinazione: destinazione));
    } catch (e) {
      if (identical(stato, calcolo)) {
        _imposta(ErroreViaggio('Il viaggio non si è potuto calcolare: $e', destinazione: destinazione));
      }
    }
  }

  /// Il percorso da usare fra quelli proposti: senza tappe, con
  /// [conScelte] si chiedono le alternative (col traffico, la più veloce
  /// prima); poi si usa quella scelta. `null`: si calcola il percorso
  /// normale.
  Future<PercorsoCalcolato?> _scegli(
    PianificatoreViaggio pianificatore,
    Punto partenza,
    Luogo destinazione,
    bool conScelte,
  ) async {
    if (_daPassare.isNotEmpty) {
      _scelte = const [];
      return null;
    }
    if (conScelte && pianificatore.alternative != null) {
      try {
        _scelte = await pianificatore
            .scelte(partenza: partenza, arrivo: destinazione.posizione)
            .timeout(const Duration(seconds: 60));
      } catch (_) {
        _scelte = const [];
      }
      _scelta = 0;
    }
    if (_scelte.length < 2) {
      _scelte = const [];
      return null;
    }
    return _scelte[_scelta.clamp(0, _scelte.length - 1)];
  }

  void annulla() {
    obbligate.clear();
    tappa = null;
    tappe.clear();
    _scelte = const [];
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
Future<List<Colonnina>> colonnineVicine(
  Punto qui,
  ProfiloVeicolo veicolo, {
  double km = 15,
  int quante = 8,
  int conStato = 10,
}) async {
  final fonte = ColonnineLocali(archivioColonnine(), riserva: ClienteColonnineRelay(Uri.parse(Servizi.segnalazioni)));
  final adatte = [
    for (final c in await fonte.lungo([qui], distanzaKm: km))
      if (c.potenzaNominalePer(veicolo.connettori) > 0 && distanzaM(qui, c.posizione) <= km * 1000) c,
  ]..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
  final prime = adatte.take(quante).toList();
  final d = GestorePremium.attivo.value ? _disponibilita : null;
  if (d == null) return prime;
  // Lo stato solo per le più vicine (TomTom le serve una alla volta e ne
  // regala poche al giorno); le altre quando si toccano.
  return Future.wait([
    for (final (i, c) in prime.indexed)
      i < conStato ? d.aggiorna(c).timeout(const Duration(seconds: 30)).catchError((Object _) => c) : Future.value(c),
  ]);
}

/// Lo stato di adesso di una colonnina (con Premium); senza, com'era.
Future<Colonnina> statoColonninaAdesso(Colonnina c) async {
  final d = GestorePremium.attivo.value ? _disponibilita : null;
  if (d == null) return c;
  return d.aggiorna(c).timeout(const Duration(seconds: 10));
}
