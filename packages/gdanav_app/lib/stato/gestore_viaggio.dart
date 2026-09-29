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
import 'gestore_ztl.dart';

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
    this.senzaSoste = false,
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

  /// Auto elettrica senza Premium: il percorso e basta, senza le soste di
  /// ricarica (sono Premium). La batteria resta quella scritta a mano.
  final bool senzaSoste;

  /// Solo il percorso, senza piano della batteria: termica, o elettrica
  /// senza Premium.
  bool get soloPercorso => termica || senzaSoste;

  /// Per dire l'ora d'arrivo: partenza adesso più la durata.
  final DateTime calcolatoAlle;

  DateTime? get arrivoAlle => soloPercorso
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
  // TomTom se c'è la chiave: i suoi tempi sono già quelli del traffico di
  // adesso, e le code arrivano nella stessa risposta. Valhalla resta la
  // riserva, sul server pubblico di FOSSGIS.
  final tomtom = i.percorsiDaTomTom ? ClienteTomTom(i.chiaveTomTom) : null;
  final valhalla = tomtom != null
      ? null
      : ClienteValhalla(
          Uri.parse(i.valhalla.endsWith('/') ? i.valhalla : '${i.valhalla}/'),
          chiave: i.chiaveValhalla.isEmpty ? null : i.chiaveValhalla,
        );
  // Il traffico si va a prendere a parte solo per Valhalla, che non lo
  // conosce: chiederlo due volte a TomTom sarebbe sprecare il piano e
  // sommare due volte le stesse code.
  final traffico = tomtom != null ? null : _traffico;
  // Le ZTL: TomTom non le conosce. Le gira al largo chi chiede il percorso,
  // con le «aree da evitare», quando sono attive e non si ha il permesso.
  final ztl = tomtom == null
      ? null
      : PercorsiConZtl(
          zone: archivioZtl,
          permessi: () async => GestoreZtl.attuale?.permessi ?? const {},
          calcola: (tappe, evita) => tomtom.calcola(tappe, opzioni: opzioni, evita: evita),
          alternative: (da, a, evita) => tomtom.alternative(da, a, opzioni: opzioni, evita: evita),
        );
  return PianificatoreViaggio(
    percorsi: (tappe) => ztl?.percorso(tappe) ?? valhalla!.calcola(tappe, opzioni: opzioni),
    alternative: (da, a) => ztl?.scelte(da, a) ?? valhalla!.alternative(da, a, opzioni: opzioni),
    seguendo: (p) => tomtom?.seguendo(p, opzioni: opzioni) ?? valhalla!.seguendo(p, opzioni: opzioni),
    // Il traffico di adesso sul percorso (per tutti, se c'è la chiave
    // TomTom): arrivo e soste lo mettono in conto.
    traffico: traffico?.applica,
    /* Tutte le fonti insieme, non la prima che risponde.
     *
     * Era una catena: Open Charge Map, e se rispondeva ci si fermava lì.
     * Ma le fonti non dicono la stessa cosa — intorno a Napoli Open Charge
     * Map conosce 143 colonnine, e da sola diventava tutto quello che l'app
     * sapeva, mentre l'archivio di OpenStreetMap ne ha molte di più. Adesso
     * si chiedono insieme e si fondono: quelle a meno di sessanta metri sono
     * la stessa, e resta quella che conosce più prese.
     *
     * Overpass resta solo come riserva: è lento (in CI scade anche dopo
     * cinquanta secondi) e non deve rallentare ogni viaggio. */
    colonnine: _conLoStato(
      FonteColonnineUnite(
        [
          if (i.chiaveOcm.isNotEmpty) ClienteOpenChargeMap(chiave: i.chiaveOcm),
          ColonnineLocali(archivioColonnine(), riserva: ClienteColonnineRelay(Uri.parse(Servizi.segnalazioni))),
        ],
        riserva: ClienteOverpass(),
      ),
    ),
    profilo: profilo,
    preferenze: preferenze,
    // Libere e occupate in tempo reale (Premium).
    disponibilita: GestorePremium.attivo.value ? _disponibilita : null,
  );
}

/// «Nel calcolo del percorso devi vedere quelle libere e in servizio»: con
/// Premium le colonnine lungo la strada arrivano al pianificatore con lo
/// stato di tutta Italia già dentro, e le soste si scelgono sapendolo.
FonteColonnine _conLoStato(FonteColonnine fonte) => GestorePremium.attivo.value
    ? ColonnineConStato(fonte, stati: statiDiTuttaItalia, inOrdine: () async => (await archivioColonnine()).evseInOrdine)
    : fonte;

/// La PUN, una per tutta l'app: le credenziali ospite, lo stato di tutta
/// Italia letto e quello di ogni colonnina toccata. Lo stato di tutta Italia
/// sono sette richieste e quasi nove megabyte: vale otto minuti, e chi lo
/// chiede mentre arriva — la mappa, il percorso — aspetta la stessa lettura.
final _pun = DisponibilitaPun(validitaTutti: const Duration(minutes: 8));

/// Lo stato di adesso di ogni punto di ricarica d'Italia (con Premium),
/// EVSE ID → `AVAILABLE`, `CHARGING`…: la mappa ne colora le colonnine, il
/// percorso ne sceglie le soste. Senza Premium, niente.
Future<Map<String, String>> statiDiTuttaItalia() =>
    GestorePremium.attivo.value ? _pun.statiDiTutti() : Future.value(const <String, String>{});

/// Libere e occupate adesso: dalla PUN per le colonnine che ne hanno gli EVSE
/// ID — gratis, punto per punto, chiesto da questo telefono —, da TomTom per
/// le altre, se c'è la chiave.
final FonteDisponibilita _disponibilita = DisponibilitaConPun(
  _pun,
  altra: Servizi.chiaveTomTom.isEmpty ? null : DisponibilitaTomTom(Servizi.chiaveTomTom),
);
final _traffico = Servizi.chiaveTomTom.isEmpty ? null : TrafficoTomTom(Servizi.chiaveTomTom);

class GestoreViaggio extends ChangeNotifier {
  GestoreViaggio({
    required this.archivio,
    required this.auto,
    required this.posizione,
    this.costruisci = pianificatoreVero,
    this.consumo,
    this.ztl,
    FonteLuoghi? luoghi,
    DateTime Function()? orologio,
  }) : luoghi = luoghi ?? ClientePhoton(),
       _ora = orologio ?? DateTime.now;

  /// I permessi delle ZTL: la risposta alla domanda del percorso si ricorda
  /// lì. `null` nelle prove che non le guardano.
  final GestoreZtl? ztl;

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

  /// Il meteo previsto lungo la strada (per tutti), per il consumo: freddo,
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

  /// Il traffico di adesso sul percorso (per tutti, con la chiave TomTom);
  /// nelle prove se ne passa uno finto.
  Future<PercorsoCalcolato> Function(PercorsoCalcolato percorso)? trafficoFinto;

  Future<PercorsoCalcolato> Function(PercorsoCalcolato percorso)? get _trafficoAdesso =>
      trafficoFinto ?? _traffico?.applica;

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
      senzaSoste: s.senzaSoste,
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

  /// La risposta a «Hai il permesso per entrare?» di una ZTL sul percorso:
  /// si ricorda per quella ZTL. Col permesso si rifà il percorso, che ci
  /// passa; senza, il percorso è già quello giusto e la domanda sparisce.
  Future<void> rispondiZtl(ZonaLimitata zona, bool permesso) async {
    await ztl?.rispondi(zona, permesso);
    final d = destinazione;
    if (d == null) return;
    if (permesso) return pianifica(d, conScelte: _daPassare.isEmpty);
    final s = stato;
    if (s is! ViaggioPronto) return;
    PercorsoCalcolato senza(PercorsoCalcolato p) =>
        p.ztl?.daChiedere?.chiave == zona.chiave ? p.conZtl(p.ztl!.senzaDomanda()) : p;
    _scelte = [for (final p in _scelte) senza(p)];
    _imposta(
      ViaggioPronto(
        s.destinazione,
        Viaggio(percorso: senza(s.viaggio.percorso), colonnine: s.viaggio.colonnine, piano: s.viaggio.piano),
        s.batteriaPartenza,
        calcolatoAlle: s.calcolatoAlle,
        termica: s.termica,
        senzaSoste: s.senzaSoste,
        scelte: _scelte,
        scelta: s.scelta,
        tappe: s.tappe,
      ),
    );
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

  /// La strada proposta in guida, e presa: il viaggio si rifà su quella da
  /// dove si è, soste comprese.
  Future<void> seguiStrada(PercorsoCalcolato strada) async {
    final d = destinazione;
    if (d == null) return;
    await pianifica(d, strada: strada);
  }

  /// [conScelte]: si cercano anche le strade alternative (una meta nuova,
  /// opzioni cambiate); in guida no, si ricalcola e basta. [strada]: il
  /// percorso c'è già (una strada a risparmio presa in guida).
  Future<void> pianifica(Luogo destinazione, {bool conScelte = false, PercorsoCalcolato? strada}) async {
    final impostazioni = await archivio.impostazioni();
    if (impostazioni.mancante case final m?) return _imposta(ErroreViaggio(m, destinazione: destinazione));
    if (conScelte) {
      _scelte = const [];
      _scelta = 0;
    }
    if (!auto.elettrica) return _percorsoSolo(destinazione, impostazioni, conScelte: conScelte, strada: strada);
    // Le soste di ricarica sono Premium: senza, l'elettrica ha il percorso
    // come la termica (e la scheda dice che le soste sono con Premium).
    if (!GestorePremium.attivo.value) {
      return _percorsoSolo(destinazione, impostazioni, conScelte: conScelte, senzaSoste: true, strada: strada);
    }
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
      final scelto = strada ?? await _scegli(pianificatore, partenza, destinazione, conScelte);
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
    } on ErrorePercorso catch (e) {
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

  /// Auto termica: il percorso e basta, come un navigatore normale. Anche
  /// per l'elettrica senza Premium ([senzaSoste]).
  Future<void> _percorsoSolo(
    Luogo destinazione,
    Impostazioni impostazioni, {
    bool conScelte = false,
    bool senzaSoste = false,
    PercorsoCalcolato? strada,
  }) async {
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
      final scelto = strada ?? await _scegli(pianificatore, partenza, destinazione, conScelte);
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
            senzaSoste ? auto.stato?.batteria ?? 0 : 0,
            calcolatoAlle: _ora(),
            termica: !senzaSoste,
            senzaSoste: senzaSoste,
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
    } on ErrorePercorso catch (e) {
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

  static String _spiega(ErrorePercorso e) => switch (e.stato) {
    401 || 403 => 'Il server dei percorsi non ci fa entrare in questo momento. Riprova tra poco.',
    429 => 'Il server dei percorsi è molto carico. Riprova tra un minuto.',
    400 when _senzaStrada(e.messaggio) => 'Non esiste una strada fra qui e la destinazione.',
    _ => 'Il server dei percorsi ha risposto: ${e.messaggio}',
  };

  /// «Non c'è strada»: Valhalla lo dice «No path», TomTom «NO_ROUTE_FOUND».
  static bool _senzaStrada(String m) =>
      m.contains('No path') || m.toUpperCase().contains('NO_ROUTE') || m.contains('ROUTE_NOT_FOUND');

  void _imposta(StatoViaggio s) {
    stato = s;
    notifyListeners();
  }
}

/// Le colonnine rapide intorno a [qui] adatte all'auto, dalla più vicina; con
/// Premium anche libere e occupate adesso. Per «Colonnine vicine» sull'auto e
/// sul telefono: senza Premium l'elenco c'è lo stesso, con lo stato che dice
/// la fonte (spesso nessuno) invece di quello in tempo reale.
///
/// [operatoriEsclusi] e [potenzaMinimaKw] sono la scelta fatta nelle
/// preferenze di ricarica: quello che non si vuole vedere non si vede nemmeno
/// qui. Senza, si vede tutto — è il comportamento di sempre.
Future<List<Colonnina>> colonnineVicine(
  Punto qui,
  ProfiloVeicolo veicolo, {
  double km = 15,
  int quante = 8,
  int conStato = 10,
  Set<String> operatoriEsclusi = const {},
  double potenzaMinimaKw = 0,
}) async {
  final fonte = ColonnineLocali(archivioColonnine(), riserva: ClienteColonnineRelay(Uri.parse(Servizi.segnalazioni)));
  final adatte = [
    for (final c in await fonte.lungo([qui], distanzaKm: km))
      if (c.potenzaNominalePer(veicolo.connettori) >= (potenzaMinimaKw > 0 ? potenzaMinimaKw : 0.1) &&
          !operatoreEscluso(c, operatoriEsclusi) &&
          distanzaM(qui, c.posizione) <= km * 1000)
        c,
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

/// Le colonnine vicine filtrate come si è scelto in «Ricarica»: la potenza
/// minima e gli operatori che non si vogliono vedere.
///
/// È la porta da cui passano l'elenco del telefono e quello dell'auto, così
/// la scelta vale in tutt'e due senza che nessuno se la debba ricordare.
Future<List<Colonnina>> colonnineVicineComeSiVuole(
  Punto qui,
  ProfiloVeicolo veicolo,
  Archivio archivio, {
  double km = 15,
  int quante = 8,
}) async {
  final p = await archivio.preferenze();
  return colonnineVicine(
    qui,
    veicolo,
    km: km,
    quante: quante,
    operatoriEsclusi: p.operatoriEsclusi,
    potenzaMinimaKw: p.minimaIntorno,
  );
}

/// Tutte le colonnine dell'archivio adatte a [veicolo], filtrate come si è
/// scelto in «Ricarica»: per la mappa di tutta Italia. Con «Tutte» nessun
/// minimo di potenza, come intorno a te.
Future<List<Colonnina>> colonnineDellArchivioComeSiVuole(
  ProfiloVeicolo veicolo,
  Archivio archivio, {
  Future<ArchivioColonnine>? da,
}) async {
  final p = await archivio.preferenze();
  final a = await (da ?? archivioColonnine());
  final minima = p.minimaIntorno > 0 ? p.minimaIntorno : 0.1;
  return [
    for (final c in a.tutte)
      if (c.potenzaNominalePer(veicolo.connettori) >= minima && !operatoreEscluso(c, p.operatoriEsclusi)) c,
  ];
}

/// Lo stato di adesso di una colonnina (con Premium); senza, com'era.
Future<Colonnina> statoColonninaAdesso(Colonnina c) async {
  final d = GestorePremium.attivo.value ? _disponibilita : null;
  if (d == null) return c;
  return d.aggiorna(c).timeout(const Duration(seconds: 10));
}
