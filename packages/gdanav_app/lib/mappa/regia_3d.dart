import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gdanav_core/gdanav_core.dart' show Viaggio;

import '../componenti/icona_manovra.dart' show bandieraArrivoPng, puntaManovraPng;
import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../servizi.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_persone.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import 'controllo_mappa.dart';
import 'dati_viaggio.dart';
import 'ponte_3d.dart';
import 'segnaposto.dart';
import 'stile.dart';

/// Perché il 3D si è fermato, e se ricordarlo (il telefono non ce la fa) o no
/// (un intoppo di questa volta).
typedef Mappa3dNonVa = void Function(String motivo, {required bool ricorda});

/// Come vuole stare la telecamera: libera (un dito l'ha spostata) o no, e
/// quanto dello schermo coprono le schede, sopra e a sinistra (in punti).
typedef Inquadratura3d = ({bool libera, double sopra, double sinistra});

/// Cosa mandare alla mappa 3D, e quando: lo stile, il percorso con le code,
/// la freccia della manovra, colonnine, meta, autovelox e segnalazioni, la
/// strada a risparmio, le persone, la posizione una volta per lettura e la
/// telecamera. Senza WebView: chi mostra la pagina le passa i messaggi
/// ([manda]) e le gira quelli che arrivano da lei ([dallaMappa]).
///
/// La usano tutt'e due gli schermi che mostrano il 3D aumentato: il telefono
/// (`Mappa3d`, in una WebView di Flutter) e l'auto («Certo, voglio la scena
/// reale anche in macchina»: Android Auto, in una WebView sua sullo schermo
/// dell'auto). Una regia sola, così i due 3D dicono le stesse cose.
class Regia3d {
  Regia3d({
    required this.gestore,
    required this.posizione,
    required this.guida,
    required this.manda,
    required this.notte,
    required this.vista,
    required this.inquadratura,
    required this.onNonVa,
    this.segnalazioni,
    this.vicini,
    this.persone,
    this.onTocco,
    this.onToccata,
    this.orologio,
    this.attesa = const Duration(seconds: 15),
    this.piuVicina = 0,
  });

  final GestoreViaggio gestore;
  final GestorePosizione posizione;
  final GestoreGuida guida;

  /// Consegna un messaggio alla pagina.
  final void Function(Map<String, Object?>) manda;

  /// Giorno o notte, adesso.
  final bool Function() notte;

  /// La vista di adesso: inclinata o immersiva.
  final VistaMappa Function() vista;

  /// La telecamera voluta adesso.
  final Inquadratura3d Function() inquadratura;
  final Mappa3dNonVa onNonVa;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreVicini? vicini;
  final GestorePersone? persone;

  /// Un tocco su qualcosa della mappa: gli elementi come li dà MapLibre.
  final void Function(List<Map<Object?, Object?>> elementi)? onTocco;

  /// Un dito ha spostato la mappa.
  final VoidCallback? onToccata;
  final DateTime Function()? orologio;

  /// Quanto si aspetta che la pagina sia pronta, prima di lasciar perdere.
  final Duration attesa;

  /// Livelli di zoom in più rispetto al telefono. Sull'auto lo schermo è
  /// largo e basso: allo zoom del telefono l'auto era piccola, lontana, e la
  /// scena piatta («lo zoom troppo lontano e piatto»).
  final double piuVicina;

  var _caricata = false;
  var _pronta = false;
  var _finita = false;
  Timer? _attesa;
  Timer? _guardia;

  /// Quello che la pagina ha già: non si rimanda uguale.
  bool? _notte;
  Object? _viaggioMandato;
  (int, int)? _frecciaMandata = (-1, -1);
  Object? _propostaMandata = 0;
  int? _letturaMandata;
  DateTime? _lettaMandata;
  ModoCamera3d? _modoMandato;
  double? _sopraMandato;
  double? _sinistraMandata;
  VistaMappa? _vistaMandata;
  Segnaposto? _segnapostoMandato;
  Viaggio? _panoramicaDi;

  /// La pagina ha detto che è caricata.
  bool get caricata => _caricata;

  /// La pagina ha detto che disegna.
  bool get pronta => _pronta;

  /// Finita: non va, o chi la usa l'ha fermata.
  bool get finita => _finita;

  DateTime _ora() => (orologio ?? DateTime.now)();

  void avvia() {
    gestore.addListener(_viaggio);
    guida.addListener(dallaGuida);
    posizione.addListener(_dallaPosizione);
    segnalazioni?.addListener(_segnalazioni);
    guida.avvisi.addListener(_segnalazioni);
    vicini?.addListener(_vicini);
    persone?.addListener(_persone);
    guida.risparmio?.addListener(_risparmio);
    _attesa = Timer(attesa, () {
      if (!_pronta) nonVa('tempo', ricorda: false);
    });
    // Col GPS muto nessuno chiama: la telecamera la si sistema da qui.
    _guardia = Timer.periodic(const Duration(seconds: 2), (_) => dallaGuida());
  }

  void ferma() {
    _finita = true;
    gestore.removeListener(_viaggio);
    guida.removeListener(dallaGuida);
    posizione.removeListener(_dallaPosizione);
    segnalazioni?.removeListener(_segnalazioni);
    guida.avvisi.removeListener(_segnalazioni);
    vicini?.removeListener(_vicini);
    persone?.removeListener(_persone);
    guida.risparmio?.removeListener(_risparmio);
    _attesa?.cancel();
    _guardia?.cancel();
  }

  /// Il 3D non va: si ferma, e chi lo mostra torna alla mappa di sempre.
  void nonVa(String motivo, {required bool ricorda}) {
    if (_finita) return;
    _finita = true;
    _attesa?.cancel();
    debugPrint('mappa 3D: non va ($motivo), torna la mappa di sempre');
    onNonVa(motivo, ricorda: ricorda);
  }

  /// Manda un messaggio alla pagina (se c'è).
  void _manda(Map<String, Object?> m) {
    if (!_caricata || _finita) return;
    manda(m);
  }

  /// La pagina che va in secondo piano (o torna): smette di disegnare.
  void pausa(bool si) => _manda(msgPausa(si));

  /// Un messaggio dalla pagina, così come arriva.
  void dallaMappa(String testo) {
    switch (MessaggioDalla3d.leggi(testo)) {
      case Caricata3d():
        _caricata = true;
        unawaited(_tutto());
      case Pronta3d():
        _pronta = true;
        _attesa?.cancel();
      case final Errore3d e:
        final (motivo, ricorda) = nonVaPer(e)!;
        nonVa(motivo, ricorda: ricorda);
      case final Prestazioni3d p:
        debugPrint('mappa 3D: ${p.fps} fotogrammi al secondo, ${p.triangoli} triangoli');
        if (nonVaPer(p) case (final motivo, final ricorda)) nonVa(motivo, ricorda: ricorda);
      case Toccata3d():
        onToccata?.call();
      case Tocco3d(:final elementi):
        onTocco?.call(elementi);
      case null:
        break;
    }
  }

  /// La pagina c'è: tutto da capo (le opzioni prima dello stile).
  Future<void> _tutto() async {
    _viaggioMandato = null;
    _frecciaMandata = (-1, -1);
    _propostaMandata = 0;
    _letturaMandata = null;
    _lettaMandata = null;
    _modoMandato = null;
    _sopraMandato = null;
    opzioni(forza: true);
    _stile();
    // Le persone sono un cerchio e due scritte, senza immagini: subito.
    _persone();
    await _immagini();
    if (_finita) return;
    _viaggio();
    _segnalazioni();
    _vicini();
    _risparmio();
    comandi();
    dallaGuida();
  }

  /// Giorno o notte, la vista e il segnaposto: solo se cambiano.
  void opzioni({bool forza = false}) {
    if (!_caricata) return;
    final n = notte();
    final v = vista(), segnaposto = posizione.segnaposto;
    if (!forza && n == _notte && v == _vistaMandata && segnaposto == _segnapostoMandato) return;
    final cambiaNotte = _notte != null && n != _notte;
    _notte = n;
    _vistaMandata = v;
    _segnapostoMandato = segnaposto;
    _manda(msgOpzioni(notte: n, vista: v, segnaposto: segnaposto));
    if (cambiaNotte) _stile();
  }

  void _stile() {
    _manda(msgStile(stileMappa(scuro: _notte ?? false, chiaveTraffico: Servizi.chiaveTomTom)));
  }

  /// Le immagini dello stile: le stesse della mappa di sempre.
  Future<void> _immagini() async {
    Future<void> una(String nome, Future<Uint8List> Function() png) async {
      try {
        _manda(msgImmagine(nome, await png()));
      } catch (e) {
        debugPrint('mappa 3D, immagine $nome: $e');
      }
    }

    for (final s in Segnaposto.values) {
      await una(s.immagine, () async => (await rootBundle.load(s.asset)).buffer.asUint8List());
    }
    await una(immaginePuntaManovra, puntaManovraPng);
    await una(immagineBandieraArrivo, bandieraArrivoPng);
    try {
      for (final MapEntry(:key, :value) in (await iconeSegnalazioni()).entries) {
        _manda(msgImmagine(key, value));
      }
      for (final MapEntry(:key, :value) in (await iconePunti()).entries) {
        _manda(msgImmagine(key, value));
      }
    } catch (e) {
      debugPrint('mappa 3D, icone: $e');
    }
  }

  /// Il viaggio: il percorso (con le code) per il 3D, e le sorgenti di sempre
  /// (colonnine, meta, tappe; e il percorso per la vista da lontano).
  void _viaggio() {
    final stato = gestore.stato;
    if (identical(stato, _viaggioMandato) || !_caricata) return;
    _viaggioMandato = stato;
    final v = stato is ViaggioPronto ? stato.viaggio : null;
    _manda(msgPercorso(v));
    for (final MapEntry(key: id, value: dati) in datiViaggio(
      v,
      tappe: stato is ViaggioPronto ? stato.tappe : const [],
    ).entries) {
      _manda(msgSorgente(id, dati));
    }
    _frecciaMandata = (-1, -1);
    dallaGuida();
  }

  /// A ogni novità della guida: la posizione (una volta per lettura), la
  /// freccia della manovra, la telecamera.
  void dallaGuida() {
    if (!_caricata || _finita) return;
    final g = guida;
    final v = g.pronto?.viaggio, a = g.avanzamento;
    // La freccia della prossima manovra, avvicinandosi.
    final chiave = chiaveFreccia(v, a?.prossima, a?.allaProssimaM, ricalcolo: g.ricalcolando);
    if (chiave != _frecciaMandata) {
      _frecciaMandata = chiave;
      _manda(chiave == null ? msgManovra(null, null) : msgManovra(v, a?.prossima));
    }
    // Nessun punto sul percorso e il GPS muto da dieci secondi: tutta la strada.
    if (a == null && posizione.tace(const Duration(seconds: 10)) && v != null) {
      final c = inquadratura();
      if (!identical(v, _panoramicaDi) && !c.libera) {
        _panoramicaDi = v;
        _modoMandato = ModoCamera3d.panoramica;
        _manda(msgCamera(ModoCamera3d.panoramica, sopra: c.sopra, riquadro: confini(v)));
      }
      return;
    }
    if (_panoramicaDi != null) {
      _panoramicaDi = null;
      comandi(forza: true);
    }
    final metri = g.metriStimati();
    final stimata = g.posizioneStimata();
    final qui = stimata?.punto ?? a?.posizioneSulPercorso ?? posizione.qui;
    if (qui == null) return;
    if (g.letture == _letturaMandata && posizione.lettoAlle == _lettaMandata) return;
    _letturaMandata = g.letture;
    _lettaMandata = posizione.lettoAlle;
    _manda(
      msgPosizione(
        qui: qui,
        rotta: stimata?.rotta ?? a?.rotta ?? posizione.rotta,
        metri: metri,
        velocitaMs: (g.velocitaMs ?? posizione.velocitaAdesso() / 3.6),
        zoom:
            zoom3d(
              vista(),
              velocitaStradaKmh: a?.velocitaStradaKmh ?? 0,
              allaProssimaM: a == null ? 0 : (a.prossima == null ? a.restantiM : a.allaProssimaM),
            ) +
            piuVicina,
        // La stima è già portata ad adesso (`metriStimati`).
        quando: _ora(),
      ),
    );
  }

  /// Senza guida agganciata la posizione la dà il GPS.
  void _dallaPosizione() {
    if (guida.avanzamento != null) return;
    dallaGuida();
    if (posizione.segnaposto != _segnapostoMandato) opzioni();
  }

  /// La telecamera (e le opzioni): solo se cambia qualcosa.
  void comandi({bool forza = false}) {
    if (!_caricata) return;
    opzioni();
    final c = inquadratura();
    final modo = c.libera ? ModoCamera3d.libera : ModoCamera3d.segui;
    if (_panoramicaDi != null && !forza) return;
    if (!forza && modo == _modoMandato && c.sopra == _sopraMandato && c.sinistra == _sinistraMandata) return;
    _modoMandato = modo;
    _sopraMandato = c.sopra;
    _sinistraMandata = c.sinistra;
    _manda(msgCamera(modo, sopra: c.sopra, sinistra: c.sinistra));
  }

  void _segnalazioni() {
    final g = segnalazioni;
    if (g == null) return;
    _manda(msgSorgente(sorgenteSegnalazioni, datiSegnalazioni(g.vicine, guida.avvisi)));
  }

  void _vicini() {
    final v = vicini;
    if (v == null) return;
    for (final MapEntry(:key, :value) in v.dati().entries) {
      _manda(msgSorgente(key, value));
    }
  }

  void _persone() {
    final g = persone;
    if (g == null) return;
    _manda(msgSorgente(sorgentePersone, datiPersone(g.persone)));
  }

  void _risparmio() {
    final p = guida.risparmio?.proposta;
    if (identical(p, _propostaMandata)) return;
    _propostaMandata = p;
    _manda(msgRisparmio(p));
  }
}
