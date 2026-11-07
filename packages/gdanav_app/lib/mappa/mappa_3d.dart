import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart' show Viaggio;
import 'package:webview_flutter/webview_flutter.dart';

import '../componenti/icona_manovra.dart' show bandieraArrivoPng, puntaManovraPng;
import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import 'controllo_mappa.dart';
import 'dati_viaggio.dart';
import 'ponte_3d.dart';
import 'segnaposto.dart';
import 'stile.dart';

/// Si può provare il 3D su questo telefono? Serve una WebView (Android o
/// iPhone, e il plugin registrato: nelle prove non c'è).
bool get mappa3dPossibile {
  if (provaMappa3dPossibile case final p?) return p;
  if (kIsWeb) return false;
  try {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
  } catch (_) {
    return false;
  }
  return WebViewPlatform.instance != null;
}

/// Solo per le prove e per le immagini del cruscotto (`test_render`): fa
/// credere che la WebView ci sia (o no). `null`: si guarda davvero.
bool? provaMappa3dPossibile;

/// Perché il 3D si è fermato, e se ricordarlo (il telefono non ce la fa) o no
/// (un intoppo di questa volta).
typedef Mappa3dNonVa = void Function(String motivo, {required bool ricorda});

/// La mappa 3D della guida: viadotti in quota, alberi, edifici con le
/// finestre, il percorso all'altezza della strada e l'auto rossa. La disegna
/// la pagina di `assets/web3d` (MapLibre GL JS e three.js) in una WebView;
/// qui le si mandano i dati, gli stessi della mappa di sempre
/// ([MappaViaggio]): lo stile, il percorso con le code, la freccia della
/// manovra, le colonnine, la meta, gli autovelox, il traffico, la posizione.
/// Sopra resta il cruscotto di Flutter.
///
/// Se la pagina dice che non ce la fa (WebGL che manca, o troppo lenta), o
/// non risponde, [onNonVa]: chi la usa torna alla mappa di sempre.
class Mappa3d extends StatefulWidget {
  const Mappa3d({
    super.key,
    required this.gestore,
    required this.controllo,
    required this.posizione,
    required this.guida,
    required this.onNonVa,
    this.segnalazioni,
    this.vicini,
    this.onPunto,
    this.orologio,
  });

  final GestoreViaggio gestore;
  final ControlloMappa controllo;
  final GestorePosizione posizione;
  final GestoreGuida guida;
  final Mappa3dNonVa onNonVa;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreVicini? vicini;
  final ValueChanged<PuntoToccato>? onPunto;
  final DateTime Function()? orologio;

  /// Quanto si aspetta che la pagina sia pronta, prima di lasciar perdere.
  static const attesa = Duration(seconds: 15);

  @override
  State<Mappa3d> createState() => _Mappa3dState();
}

class _Mappa3dState extends State<Mappa3d> {
  late final WebViewController _web;
  var _caricata = false;
  var _pronta = false;
  var _finita = false;
  bool? _notte;
  Timer? _attesa;
  Timer? _guardia;
  AppLifecycleListener? _vita;

  /// Quello che la pagina ha già: non si rimanda uguale.
  Object? _viaggioMandato;
  (int, int)? _frecciaMandata = (-1, -1);
  Object? _propostaMandata = 0;
  int? _letturaMandata;
  DateTime? _lettaMandata;
  ModoCamera3d? _modoMandato;
  double? _sopraMandato;
  VistaMappa? _vistaMandata;
  Segnaposto? _segnapostoMandato;
  Viaggio? _panoramicaDi;

  DateTime _ora() => (widget.orologio ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _web = WebViewController();
    unawaited(_avvia());
    widget.gestore.addListener(_viaggio);
    widget.guida.addListener(_dallaGuida);
    widget.posizione.addListener(_dallaPosizione);
    widget.controllo.addListener(_comandi);
    widget.segnalazioni?.addListener(_segnalazioni);
    widget.guida.avvisi.addListener(_segnalazioni);
    widget.vicini?.addListener(_vicini);
    widget.guida.risparmio?.addListener(_risparmio);
    _attesa = Timer(Mappa3d.attesa, () {
      if (!_pronta) _nonVa('tempo', ricorda: false);
    });
    // Col GPS muto nessuno chiama: la telecamera la si sistema da qui.
    _guardia = Timer.periodic(const Duration(seconds: 2), (_) => _dallaGuida());
    _vita = AppLifecycleListener(onHide: () => _manda(msgPausa(true)), onShow: () => _manda(msgPausa(false)));
  }

  Future<void> _avvia() async {
    try {
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _web.addJavaScriptChannel(canale3d, onMessageReceived: (m) => _dallaMappa(m.message));
      await _web.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? false) _nonVa('pagina', ricorda: false);
          },
          // La pagina è dentro l'app: niente si apre altrove.
          onNavigationRequest: (r) => r.url.startsWith('file:') || r.url.startsWith('about:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      await _web.loadFlutterAsset(paginaMappa3d);
    } catch (e) {
      debugPrint('mappa 3D, avvio: $e');
      _nonVa('webview', ricorda: true);
    }
  }

  @override
  void dispose() {
    _finita = true;
    widget.gestore.removeListener(_viaggio);
    widget.guida.removeListener(_dallaGuida);
    widget.posizione.removeListener(_dallaPosizione);
    widget.controllo.removeListener(_comandi);
    widget.segnalazioni?.removeListener(_segnalazioni);
    widget.guida.avvisi.removeListener(_segnalazioni);
    widget.vicini?.removeListener(_vicini);
    widget.guida.risparmio?.removeListener(_risparmio);
    _attesa?.cancel();
    _guardia?.cancel();
    _vita?.dispose();
    super.dispose();
  }

  void _nonVa(String motivo, {required bool ricorda}) {
    if (_finita) return;
    _finita = true;
    _attesa?.cancel();
    debugPrint('mappa 3D: non va ($motivo), torna la mappa di sempre');
    widget.onNonVa(motivo, ricorda: ricorda);
  }

  /// Manda un messaggio alla pagina (se c'è).
  void _manda(Map<String, Object?> m) {
    if (!_caricata || _finita) return;
    _web.runJavaScript(chiamata3d(m)).catchError((Object e) => debugPrint('mappa 3D, ${m['tipo']}: $e'));
  }

  void _dallaMappa(String testo) {
    switch (MessaggioDalla3d.leggi(testo)) {
      case Caricata3d():
        _caricata = true;
        unawaited(_tutto());
      case Pronta3d():
        _pronta = true;
        _attesa?.cancel();
      case Errore3d(:final motivo):
        // Senza WebGL, o col rendering in software, non andrà mai: lo si
        // ricorda. Un contesto perso (memoria) è di questa volta.
        _nonVa(motivo, ricorda: const {'webgl2', 'software', 'trame', 'memoria', 'mappa', 'webview'}.contains(motivo));
      case Prestazioni3d(:final lento, :final fps, :final triangoli):
        debugPrint('mappa 3D: $fps fotogrammi al secondo, $triangoli triangoli');
        if (lento) _nonVa('lento', ricorda: true);
      case Toccata3d():
        widget.controllo.toccata();
      case Tocco3d(:final elementi):
        _tocco(elementi);
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
    _opzioni(forza: true);
    _stile();
    await _immagini();
    if (_finita) return;
    _viaggio();
    _segnalazioni();
    _vicini();
    _risparmio();
    _comandi();
    _dallaGuida();
  }

  void _opzioni({bool forza = false}) {
    final notte = Theme.of(context).brightness == Brightness.dark;
    final vista = widget.controllo.vista, segnaposto = widget.posizione.segnaposto;
    if (!forza && notte == _notte && vista == _vistaMandata && segnaposto == _segnapostoMandato) return;
    final cambiaNotte = _notte != null && notte != _notte;
    _notte = notte;
    _vistaMandata = vista;
    _segnapostoMandato = segnaposto;
    _manda(msgOpzioni(notte: notte, vista: vista, segnaposto: segnaposto));
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
    final stato = widget.gestore.stato;
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
    _dallaGuida();
  }

  /// A ogni novità della guida: la posizione (una volta per lettura), la
  /// freccia della manovra, la telecamera.
  void _dallaGuida() {
    if (!_caricata || !mounted || _finita) return;
    final g = widget.guida;
    final v = g.pronto?.viaggio, a = g.avanzamento;
    // La freccia della prossima manovra, avvicinandosi.
    final chiave = chiaveFreccia(v, a?.prossima, a?.allaProssimaM, ricalcolo: g.ricalcolando);
    if (chiave != _frecciaMandata) {
      _frecciaMandata = chiave;
      _manda(chiave == null ? msgManovra(null, null) : msgManovra(v, a?.prossima));
    }
    // Nessun punto sul percorso e il GPS muto da dieci secondi: tutta la strada.
    if (a == null && widget.posizione.tace(const Duration(seconds: 10)) && v != null) {
      if (!identical(v, _panoramicaDi) && !widget.controllo.libera) {
        _panoramicaDi = v;
        _modoMandato = ModoCamera3d.panoramica;
        _manda(msgCamera(ModoCamera3d.panoramica, sopra: widget.controllo.coperto, riquadro: confini(v)));
      }
      return;
    }
    if (_panoramicaDi != null) {
      _panoramicaDi = null;
      _comandi(forza: true);
    }
    final metri = g.metriStimati();
    final stimata = g.posizioneStimata();
    final qui = stimata?.punto ?? a?.posizioneSulPercorso ?? widget.posizione.qui;
    if (qui == null) return;
    if (g.letture == _letturaMandata && widget.posizione.lettoAlle == _lettaMandata) return;
    _letturaMandata = g.letture;
    _lettaMandata = widget.posizione.lettoAlle;
    _manda(
      msgPosizione(
        qui: qui,
        rotta: stimata?.rotta ?? a?.rotta ?? widget.posizione.rotta,
        metri: metri,
        velocitaMs: (g.velocitaMs ?? widget.posizione.velocitaAdesso() / 3.6),
        zoom: zoom3d(
          widget.controllo.vista,
          velocitaStradaKmh: a?.velocitaStradaKmh ?? 0,
          allaProssimaM: a == null ? 0 : (a.prossima == null ? a.restantiM : a.allaProssimaM),
        ),
        // La stima è già portata ad adesso (`metriStimati`).
        quando: _ora(),
      ),
    );
  }

  /// Senza guida agganciata la posizione la dà il GPS.
  void _dallaPosizione() {
    if (widget.guida.avanzamento != null) return;
    _dallaGuida();
    if (widget.posizione.segnaposto != _segnapostoMandato) _opzioni();
  }

  void _comandi({bool forza = false}) {
    if (!_caricata) return;
    _opzioni();
    final c = widget.controllo;
    final modo = c.libera ? ModoCamera3d.libera : ModoCamera3d.segui;
    if (_panoramicaDi != null && !forza) return;
    if (!forza && modo == _modoMandato && c.coperto == _sopraMandato) return;
    _modoMandato = modo;
    _sopraMandato = c.coperto;
    _manda(msgCamera(modo, sopra: c.coperto));
  }

  void _segnalazioni() {
    final g = widget.segnalazioni;
    if (g == null) return;
    _manda(msgSorgente(sorgenteSegnalazioni, datiSegnalazioni(g.vicine, widget.guida.avvisi)));
  }

  void _vicini() {
    final v = widget.vicini;
    if (v == null) return;
    for (final MapEntry(:key, :value) in v.dati().entries) {
      _manda(msgSorgente(key, value));
    }
  }

  void _risparmio() {
    final p = widget.guida.risparmio?.proposta;
    if (identical(p, _propostaMandata)) return;
    _propostaMandata = p;
    _manda(msgRisparmio(p));
  }

  /// Un tocco su un punto: come sulla mappa di sempre.
  void _tocco(List<Map<Object?, Object?>> elementi) {
    for (final e in elementi) {
      if (e case {'properties': {'id': final String id, 'kw': _}} when widget.onPunto != null) {
        if (widget.vicini?.colonnina(id) case final c?) {
          return widget.onPunto!(PuntoToccato(tipo: 'colonnina', id: c.id, nome: c.nome, posizione: c.posizione));
        }
      }
      if (PuntoToccato.daElemento(e) case final p? when widget.onPunto != null) return widget.onPunto!(p);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Il tema (giorno o notte) arriva da qui.
    if (_caricata) _opzioni();
  }

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      // Prima che la pagina disegni: il colore della foschia, non un lampo bianco.
      color: scuro ? const Color(0xFF1D2740) : const Color(0xFFE2EAF1),
      child: WebViewWidget(
        controller: _web,
        // Tutti i gesti alla mappa: trascinare, avvicinare, girare.
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
      ),
    );
  }
}
