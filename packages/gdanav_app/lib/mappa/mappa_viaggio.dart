import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart'
    show
        Avanzamento,
        MotoSullaStrada,
        Punto,
        Rettangolo,
        TipoSegnalazione,
        TipoZona,
        Viaggio,
        diQuantoSiGira,
        telecameraLibera,
        versoDiLa,
        zoomLontanoInGuida;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../componenti/icona_manovra.dart' show bandieraArrivoPng, puntaManovraPng;
import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_persone.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_risparmio.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import '../stato/gestore_ztl.dart';
import 'controllo_mappa.dart';
import 'dati_viaggio.dart';
import 'segnaposto.dart';
import 'stile.dart';

/// La mappa vera: MapLibre con lo stile di GdANav (chiaro o scuro come il
/// telefono), gli edifici in 3D quando è inclinata, e il viaggio sopra.
class MappaViaggio extends StatefulWidget {
  const MappaViaggio({
    super.key,
    required this.gestore,
    required this.controllo,
    required this.onPuntoScelto,
    required this.onColonnina,
    required this.posizione,
    this.guida,
    this.segnalazioni,
    this.vicini,
    this.persone,
    this.ztl,
    this.risparmio,
    this.onPunto,
    this.orologio,
  });

  final GestoreViaggio gestore;
  final ControlloMappa controllo;

  /// Pressione lunga sulla mappa: «portami qui».
  final ValueChanged<LatLng> onPuntoScelto;

  /// Tocco su una colonnina o una sosta.
  final ValueChanged<String> onColonnina;

  /// Dove sei e con quale segnaposto: lo disegna la mappa, non MapLibre.
  final GestorePosizione posizione;

  /// In guida la mappa segue l'auto agganciata al percorso, inclinata e
  /// girata come la strada.
  final GestoreGuida? guida;

  /// Polizia, incidenti, traffico segnalati da chi guida.
  final GestoreSegnalazioni? segnalazioni;

  /// Distributori o colonnine intorno, sulla mappa.
  final GestoreVicini? vicini;

  /// Le persone di casa, quando GdANav sta dentro GdAHome.
  final GestorePersone? persone;

  /// Le ZTL e le aree pedonali: si disegnano quelle che si vedono, se si
  /// vogliono sulla mappa.
  final GestoreZtl? ztl;

  /// Le strade a risparmio: prima di partire quella che risparmia energia è
  /// verde; in guida la strada proposta. Senza, quelle della [guida].
  final GestoreRisparmio? risparmio;

  /// Tocco su un distributore, una colonnina vicina o un punto di interesse.
  final ValueChanged<PuntoToccato>? onPunto;

  /// L'ora, per le prove; di solito quella del telefono.
  final DateTime Function()? orologio;

  @override
  State<MappaViaggio> createState() => _MappaViaggioState();
}

class _MappaViaggioState extends State<MappaViaggio> with SingleTickerProviderStateMixin {
  MapLibreMapController? _mappa;
  var _stileCaricato = false;

  /// Il viaggio che la mappa ha davvero: si segna solo dopo averlo scritto
  /// tutto. Segnato prima, una scrittura andata male lasciava la mappa senza
  /// percorso per sempre, perché per lei era già disegnato.
  StatoViaggio? _disegnato;

  /// Il viaggio che si sta scrivendo adesso: chi chiama nel frattempo non lo
  /// riscrive una seconda volta.
  StatoViaggio? _inScrittura;

  /// Cresce a ogni scrittura del viaggio, e a ogni mappa o stile nuovo: una
  /// scrittura vecchia che finisce dopo non segna niente, e smette di
  /// scrivere su una mappa che non c'è più.
  var _giroDisegno = 0;

  /// I dati dell'ultimo viaggio scritto: la rete di sicurezza della guida li
  /// riscrive senza rifarli.
  (StatoViaggio, Map<String, Map<String, Object?>>)? _datiFatti;
  DateTime _ultimoTentativo = DateTime(0);
  DateTime _ultimaRiscrittura = DateTime(0);

  /// In guida, ogni due secondi: la rete di sicurezza del percorso, e la
  /// telecamera quando il GPS tace (allora nessun altro chiama [_io]).
  Timer? _guardia;
  var _inclinata = false;
  var _libera = false;
  var _centrate = 0;
  var _coperto = 0.0;

  /// Quale elenco di tutte le colonnine ha già la mappa: sono megabyte, e
  /// si rimandano solo quando cambiano.
  var _versioneTutte = -1;

  static const _inclinazione = 58.0;

  @override
  void initState() {
    super.initState();
    widget.gestore.addListener(_ridisegna);
    widget.controllo.addListener(_comandi);
    widget.posizione.addListener(_dallaPosizione);
    widget.guida?.addListener(_io);
    widget.segnalazioni?.addListener(_segnalazioni);
    widget.guida?.avvisi.addListener(_segnalazioni);
    widget.vicini?.addListener(_vicini);
    widget.persone?.addListener(_persone);
    widget.ztl?.addListener(_zoneDaCapo);
    _gestoreRisparmio?.addListener(_risparmio);
    // Le ZTL cambiano stato nel corso della giornata: «attiva fino alle 18».
    _orologioZone = Timer.periodic(const Duration(minutes: 5), (_) => _zoneDaCapo());
    // In guida no: lì contano le soste del percorso e quelle vicine, e
    // tutta Italia sulla strada sarebbe solo confusione.
    if (widget.guida == null) widget.vicini?.avviaTutte();
    if (widget.guida != null) _guardia = Timer.periodic(const Duration(seconds: 2), (_) => _giroDiGuardia());
    if (widget.guida != null) _fotogrammi = createTicker(_alFotogramma);
  }

  DateTime _ora() => (widget.orologio ?? DateTime.now)();

  @override
  void dispose() {
    widget.gestore.removeListener(_ridisegna);
    widget.controllo.removeListener(_comandi);
    widget.posizione.removeListener(_dallaPosizione);
    widget.guida?.removeListener(_io);
    widget.segnalazioni?.removeListener(_segnalazioni);
    widget.guida?.avvisi.removeListener(_segnalazioni);
    widget.vicini?.removeListener(_vicini);
    widget.persone?.removeListener(_persone);
    widget.ztl?.removeListener(_zoneDaCapo);
    _gestoreRisparmio?.removeListener(_risparmio);
    _orologioZone?.cancel();
    _guardia?.cancel();
    _fotogrammi?.dispose();
    _fotogrammi = null;
    // Quello che era ancora in corso (le immagini, una scrittura) non scrive
    // più su una mappa che non c'è.
    _mappa = null;
    _stileCaricato = false;
    _giroDisegno++;
    super.dispose();
  }

  Timer? _orologioZone;

  /// Il riquadro di cui la mappa ha già le zone (più largo di quello che si
  /// vede, per non rimandarle a ogni spostamento), se c'erano i puntini, e se
  /// sulla mappa ce n'è qualcuna.
  Rettangolo? _zoneDisegnate;
  var _zoneConPedonali = false;
  var _zoneSullaMappa = false;

  /// Sotto questo zoom le ZTL non si disegnano: sono troppo piccole.
  static const _zoomZone = 10.0;

  /// Da qui in su anche le aree pedonali (sono migliaia).
  static const _zoomPedonali = 13.0;

  void _zoneDaCapo() {
    _zoneDisegnate = null;
    unawaited(_zone());
  }

  /// Le ZTL e le aree pedonali che si vedono, a mappa ferma.
  Future<void> _zone() async {
    final m = _mappa, g = widget.ztl;
    if (m == null || !_stileCaricato || g == null) return;
    final zoom = (await m.queryCameraPosition())?.zoom ?? 0;
    final vuote = !g.scelte.sullaMappa || zoom < _zoomZone;
    if (vuote) {
      _zoneDisegnate = null;
      if (_zoneSullaMappa) {
        _zoneSullaMappa = false;
        await m.setGeoJsonSource(sorgenteZtl, datiZtl(const [], DateTime.now()).cast<String, dynamic>());
      }
      return;
    }
    final b = await m.getVisibleRegion();
    final visto = Rettangolo(
      b.southwest.latitude,
      b.southwest.longitude,
      b.northeast.latitude,
      b.northeast.longitude,
    );
    final pedonali = zoom >= _zoomPedonali;
    final gia = _zoneDisegnate;
    if (gia != null &&
        pedonali == _zoneConPedonali &&
        gia.contiene(Punto(visto.sud, visto.ovest)) &&
        gia.contiene(Punto(visto.nord, visto.est))) {
      return;
    }
    // Mezzo schermo in più per lato: spostandosi un poco non si rimanda niente.
    final alto = visto.nord - visto.sud, largo = visto.est - visto.ovest;
    final dove = Rettangolo(visto.sud - alto / 2, visto.ovest - largo / 2, visto.nord + alto / 2, visto.est + largo / 2);
    _zoneDisegnate = dove;
    _zoneConPedonali = pedonali;
    final archivio = await g.zone();
    final zone = [
      for (final z in archivio.nel(dove))
        if (pedonali || z.tipo == TipoZona.ztl) z,
    ];
    if (!mounted || !identical(_zoneDisegnate, dove)) return;
    _zoneSullaMappa = true;
    await m.setGeoJsonSource(sorgenteZtl, datiZtl(zone.take(2500), DateTime.now()).cast<String, dynamic>());
  }

  Future<void> _comandi() async {
    final m = _mappa;
    if (m == null) return;
    if (widget.controllo.inclinata != _inclinata) {
      _inclinata = widget.controllo.inclinata;
      await _edifici(m);
      await m.animateCamera(CameraUpdate.tiltTo(_inclinata ? _inclinazione : 0));
      // Tornati in 2D fuori dalla guida: il nord di nuovo in su, come prima
      // che la mappa girasse dietro a chi guida.
      if (!_inclinata && widget.guida == null) await m.animateCamera(CameraUpdate.bearingTo(0));
      _seguita = null;
    }
    // Tornati a seguire l'auto: subito, senza aspettare il GPS.
    var seguita = false;
    if (widget.controllo.libera != _libera) {
      _libera = widget.controllo.libera;
      if (!_libera) {
        seguita = true;
        _ultimaCamera = DateTime(0);
        _seguita = null;
        // Anche la strada intera, col GPS muto: «Riprendi» la rimette.
        _suTuttaLaStrada = null;
        await _io();
      }
    }
    // Un popup copre la parte alta: il centro della mappa scende.
    if (widget.controllo.coperto != _coperto) {
      _coperto = widget.controllo.coperto;
      await m.updateContentInsets(EdgeInsets.only(top: _coperto * 0.8), true);
    }
    if (widget.controllo.richiesteCentra != _centrate) {
      _centrate = widget.controllo.richiesteCentra;
      final qui = widget.posizione.qui;
      // In 3D «Dove sono» vuol dire anche «seguimi»: ci pensa chi segue.
      if (_seguiFuoriGuida) {
        // Era libera: ci ha appena pensato il ritorno qui sopra.
        if (seguita) return;
        _seguita = null;
        _ultimaCamera = DateTime(0);
        await _io();
      } else if (qui != null) {
        await m.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(qui.lat, qui.lon), zoom: 16, tilt: _inclinata ? _inclinazione : 0),
          ),
        );
      }
    }
  }

  var _primaPosizione = true;
  DateTime _ultimaCamera = DateTime(0);

  /// La lettura che la telecamera ha già seguito: si muove una volta per
  /// posizione nuova, non a ogni novità della guida o del segnaposto.
  Object? _seguita;

  /* Chi muove il segnaposto. Fuori dalla guida la posizione; in guida la
   * guida, appena ha la sua prima posizione.
   *
   * Prima in guida lo muovevano tutte e due, a ogni lettura del GPS: la
   * posizione arrivava per prima, e la telecamera partiva con l'avanzamento
   * della lettura prima — un secondo indietro — consumando il suo turno;
   * subito dopo la guida, con quello giusto, trovava il turno già preso. */
  void _dallaPosizione() {
    if (widget.guida?.avanzamento != null) return;
    unawaited(_io());
  }

  /// Fuori dalla guida, in 3D, la mappa segue chi guida: girata come va,
  /// inclinata, come in guida. Non mentre si guarda un viaggio da fare (la
  /// sua strada intera), né quando la si è spostata col dito o si guarda una
  /// persona di casa ([ControlloMappa.libera]).
  bool get _seguiFuoriGuida =>
      widget.guida == null &&
      _inclinata &&
      !widget.controllo.libera &&
      widget.gestore.stato is! ViaggioPronto &&
      widget.persone?.daMostrare == null;

  /* ─── In guida, l'auto che scorre ───────────────────────────────────────
   *
   * Il segnaposto si scriveva una volta per posizione, mentre la telecamera
   * scorreva: a 90 all'ora l'auto saltava avanti di 25 metri a ogni lettura
   * e poi tornava al centro mentre la mappa la raggiungeva. Un dente di sega
   * al secondo: la posizione «a scatti».
   *
   * Adesso, come sullo schermo dell'auto, segnaposto e telecamera si muovono
   * insieme a ogni fotogramma: verso dove l'auto è adesso
   * ([GestoreGuida.metriStimati], che va avanti lungo la strada con la
   * velocità fra una lettura e l'altra), inseguita da [MotoSullaStrada] (in
   * gdanav_core, con le sue prove): una lettura nuova diventa una correzione
   * morbida, mai un passo indietro lungo la strada.
   *
   * Dal campo: «la freccia non è fluida, prende pause e poi cammina». I
   * fotogrammi li dava un `Timer` ogni 40 ms, che non va d'accordo con lo
   * schermo (due nello stesso fotogramma, poi nessuno) e che girava anche da
   * fermi, o con la mappa dietro un'altra schermata. Adesso li dà lo schermo
   * (un `Ticker`): uno ogni [_fotogrammaMinimo] al più, spento da solo quando
   * la mappa non si vede, e spento da noi quando l'auto è ferma e la freccia
   * è arrivata ([MotoSullaStrada.fermo]); la posizione dopo lo riaccende ([_io]). */

  /// Al più un fotogramma ogni tanto: trenta al secondo bastano per un moto
  /// continuo, e scaldano la metà dei sessanta (o dei centoventi) dello schermo.
  static const _fotogrammaMinimo = Duration(milliseconds: 30);

  /// Quanto la rotta della mappa insegue quella della strada: come la freccia.
  static const _tauRotta = 200.0;

  Ticker? _fotogrammi;
  var _disegnando = false;
  final _moto = MotoSullaStrada();

  /// La stima della guida al fotogramma prima (in metri lungo il percorso):
  /// per sapere se va ancora avanti.
  double? _ultimaStimata;
  Duration? _ultimaStimataAlle;

  /// Il tempo dei fotogrammi: va solo avanti, anche fra uno spegnimento e
  /// l'altro del [Ticker] (che a ogni accensione riparte da zero).
  var _tempo = Duration.zero, _ultimoTick = Duration.zero;
  Duration? _ultimoDisegno;

  /// Com'è girata la mappa adesso.
  double _rottaMappaMostrata = 0;

  /// Lo zoom della guida adesso: si allontana piano in autostrada, con la
  /// prossima manovra lontana ([_zoomInGuida]).
  double? _zoomMostrato;

  /// Quanto ci mette lo zoom a cambiare: lento, che non sembri un salto.
  static const _tauZoom = 1500.0;

  /// Lo zoom che si vuole in guida: vicino, e più lontano su una strada veloce
  /// con la prossima manovra lontana (`zoomLontanoInGuida`, come sull'auto).
  /// La strada la dice il percorso, non il tachimetro: frenando in autostrada
  /// la mappa non si avvicina.
  double _zoomInGuida(GestoreGuida g) =>
      (_inclinata ? 17.0 : 16.0) +
      zoomLontanoInGuida(
        velocitaStradaKmh: g.avanzamento?.velocitaStradaKmh ?? 0,
        allaProssimaM: _allaProssima(g.avanzamento),
      );

  /// Fin dove non si gira: la prossima manovra, o l'arrivo se non ce ne sono più.
  static double _allaProssima(Avanzamento? a) =>
      a == null ? 0 : (a.prossima == null ? a.restantiM : a.allaProssimaM);

  /// Se l'auto la muovono i fotogrammi: in guida, con la mappa che la segue,
  /// agganciata alla strada, e senza lo schermo dell'auto acceso (lì la mappa
  /// del telefono si sposta di rado, apposta).
  bool get _scorre {
    final g = widget.guida;
    return g != null &&
        g.attiva &&
        g.avanzamento?.posizioneSulPercorso != null &&
        !widget.controllo.libera &&
        !widget.gestore.auto.schermoDellAutoAcceso;
  }

  /// Riaccende i fotogrammi, se servono e sono spenti.
  void _accendiFotogrammi() {
    final t = _fotogrammi;
    if (t == null || t.isActive || !_scorre) return;
    _ultimoTick = Duration.zero;
    t.start();
  }

  void _alFotogramma(Duration trascorso) {
    _tempo += trascorso - _ultimoTick;
    _ultimoTick = trascorso;
    final ultimo = _ultimoDisegno;
    if (_disegnando || (ultimo != null && _tempo - ultimo < _fotogrammaMinimo)) return;
    unawaited(_fotogramma(_tempo));
  }

  Future<void> _fotogramma(Duration adesso) async {
    final m = _mappa, g = widget.guida;
    if (m == null || g == null || !_stileCaricato || !_scorre) {
      _moto.dimentica();
      _ultimoDisegno = null;
      _fotogrammi?.stop();
      return;
    }
    final strada = g.strada, stimata = g.metriStimati();
    if (strada == null || stimata == null) return;
    final a = g.avanzamento;
    // La guida porta già avanti l'auto lungo la strada: qui la si insegue,
    // sulla linea del percorso (agli svincoli e nelle rotonde non si taglia).
    // Sotto 1,5 m/s la guida non la porta avanti, e l'auto è ferma.
    _moto.strada(strada);
    final v = g.velocitaMs ?? 0;
    final primo = _moto.mostrataM == null;
    // La stima che non va più avanti come la strada (la guida non la porta
    // oltre un tanto dalla lettura, col GPS in ritardo): per la freccia è un
    // punto fermo, da raggiungere e lì restare. Con la velocità della strada
    // [MotoSullaStrada] la porterebbe oltre, aspettandosi che continui a muoversi.
    final ultima = _ultimaStimata, quando = _ultimaStimataAlle;
    final dtStima = quando == null ? 0.0 : (adesso - quando).inMicroseconds / 1e6;
    final ferma = ultima != null && dtStima > 0 && (stimata - ultima).abs() < 0.5 * v * dtStima;
    _ultimaStimata = stimata;
    _ultimaStimataAlle = adesso;
    _moto.posizione(stimata, velocitaMs: v < 1.5 || ferma ? 0 : v, alle: adesso);
    final f = _moto.fotogramma(adesso)!;
    final rottaMappa = a?.rottaMappa ?? f.rotta;
    final prima = _ultimoDisegno;
    _ultimoDisegno = adesso;
    final zoomVoluto = _zoomInGuida(g);
    if (primo || prima == null) {
      _rottaMappaMostrata = rottaMappa;
      _zoomMostrato ??= zoomVoluto;
    } else {
      final dt = (adesso - prima).inMicroseconds / 1000;
      _rottaMappaMostrata = versoDiLa(_rottaMappaMostrata, rottaMappa, 1 - math.exp(-dt.clamp(0, 100) / _tauRotta));
      final z = _zoomMostrato ?? zoomVoluto;
      _zoomMostrato = z + (zoomVoluto - z) * (1 - math.exp(-dt.clamp(0, 100) / _tauZoom));
    }
    final zoom = _zoomMostrato ?? zoomVoluto;
    final qui = f.punto;
    _disegnando = true;
    try {
      await m.setGeoJsonSource(sorgenteIo, datiIo(qui, f.rotta, widget.posizione.segnaposto).cast<String, dynamic>());
      if (!identical(m, _mappa) || !mounted) return;
      await m.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(qui.lat, qui.lon),
            zoom: zoom,
            tilt: _inclinata ? _inclinazione : 0,
            bearing: _rottaMappaMostrata,
          ),
        ),
      );
      _seguita = g.letture;
      _ultimaCamera = _ora();
    } catch (e) {
      debugPrint('mappa, fotogramma: $e');
    } finally {
      _disegnando = false;
    }
    // Ferma e arrivata: niente fotogrammi fino alla posizione dopo.
    if (_moto.fermo &&
        diQuantoSiGira(_rottaMappaMostrata, rottaMappa).abs() < 0.5 &&
        (zoom - zoomVoluto).abs() < 0.01) {
      _fotogrammi?.stop();
    }
  }

  /// Il segnaposto: in guida agganciato al percorso, portato avanti di
  /// quanto si è andati dalla lettura ([GestoreGuida.posizioneStimata]) e
  /// girato come la strada; altrimenti dove dice il GPS.
  Future<void> _io() async {
    final m = _mappa;
    if (m == null || !_stileCaricato) return;
    _guardiaPercorso();
    final a = widget.guida?.avanzamento;
    final stimata = widget.guida?.posizioneStimata();
    final qui = stimata?.punto ?? a?.posizioneSulPercorso ?? widget.posizione.qui;
    final rotta = stimata?.rotta ?? a?.rotta ?? widget.posizione.rotta;
    // In guida, con l'auto agganciata alla strada, segnaposto e telecamera li
    // muovono i fotogrammi: qui solo la freccia della manovra.
    if (_scorre) {
      _accendiFotogrammi();
      try {
        await _freccia(m);
      } catch (e) {
        debugPrint('mappa, freccia: $e');
      }
      return;
    }
    // Segnaposto e freccia per conto loro: se una sorgente non si scrive, la
    // telecamera deve muoversi lo stesso. Prima un errore qui fermava tutto,
    // e la mappa restava dov'era.
    try {
      await m.setGeoJsonSource(sorgenteIo, datiIo(qui, rotta, widget.posizione.segnaposto).cast<String, dynamic>());
    } catch (e) {
      debugPrint('mappa, segnaposto: $e');
    }
    try {
      await _freccia(m);
    } catch (e) {
      debugPrint('mappa, freccia: $e');
    }
    // Nel frattempo la mappa è stata rifatta (il tema): ci pensa la nuova.
    if (!identical(m, _mappa) || !mounted) return;
    try {
      await _telecamera(m, a, qui, rotta);
    } catch (e) {
      debugPrint('mappa, telecamera: $e');
    }
  }

  Future<void> _telecamera(MapLibreMapController m, Avanzamento? a, Punto? qui, double rotta) async {
    if (widget.guida case final g?) {
      // Mappa libera: la si lascia dove l'ha messa chi guida.
      if (widget.controllo.libera) return;
      // Nessun punto sul percorso e il GPS muto da dieci secondi: il punto che
      // si ha è vecchio, o non c'è (e la mappa nasce su Roma). Meglio tutta la
      // strada che restare parcheggiati lì, lontano dalla linea.
      if (a == null && widget.posizione.tace(const Duration(seconds: 10))) return _tuttaLaStrada(m, g);
      _suTuttaLaStrada = null;
      if (qui == null) return;
      // Guarda un po' avanti: in curva la manovra resta in vista.
      final zoom = _zoomInGuida(g);
      _zoomMostrato = zoom;
      await _segui(m, g.letture, qui, zoom: zoom, rotta: a?.rottaMappa ?? rotta);
    } else if (qui != null && _seguiFuoriGuida) {
      _primaPosizione = false;
      // Senza percorso vicina come in guida, un poco più lontana solo andando
      // forte (`telecameraLibera`, la stessa dello schermo dell'auto).
      final zoom = telecameraLibera(
        velocitaMs: widget.posizione.velocitaAdesso() / 3.6,
        tridimensionale: _inclinata,
      ).zoom;
      await _segui(m, widget.posizione.lettoAlle, qui, zoom: zoom, rotta: rotta);
    } else if (qui != null && _primaPosizione && widget.gestore.stato is! ViaggioPronto) {
      _primaPosizione = false;
      await m.animateCamera(CameraUpdate.newLatLngZoom(LatLng(qui.lat, qui.lon), 15));
    }
  }

  /* La telecamera che segue: una volta per posizione nuova ([lettura]), con
   * un moto lineare lungo quanto passa fra due posizioni.
   *
   * Prima si muoveva al più una volta ogni 900 ms, con un'animazione di 900 ms
   * che accelera e frena: una posizione su due cadeva nel turno sbagliato e
   * aspettava la successiva, e fra una e l'altra la mappa partiva, frenava e
   * si fermava. Il risultato era una mappa a scatti e un secondo indietro.
   * Lineare e lunga quanto l'intervallo, la mappa arriva quando arriva la
   * posizione dopo, e il moto resta continuo (come sull'auto). */
  /// Ogni quanto la mappa del telefono segue l'auto quando GdANav è sullo
  /// schermo dell'auto.
  static const _conLAutoOgni = Duration(seconds: 2);

  Future<void> _segui(
    MapLibreMapController m,
    Object? lettura,
    Punto qui, {
    required double zoom,
    required double rotta,
  }) async {
    if (lettura != null && lettura == _seguita) return;
    final ora = _ora();
    final posizione = CameraPosition(
      target: LatLng(qui.lat, qui.lon),
      zoom: zoom,
      tilt: _inclinata ? _inclinazione : 0,
      bearing: _inclinata || widget.guida != null ? rotta : 0,
    );
    /* Con GdANav sullo schermo dell'auto, la mappa che scorre è quella: il
     * telefono nel supporto, con lo schermo acceso, ridisegnava la sua a ogni
     * fotogramma in più, ed era metà del calore. Qui si sposta ogni due
     * secondi, senza animazione: chi guarda guarda l'auto. */
    if (widget.gestore.auto.schermoDellAutoAcceso) {
      if (ora.difference(_ultimaCamera) < _conLAutoOgni) return;
      _seguita = lettura;
      _ultimaCamera = ora;
      await m.moveCamera(CameraUpdate.newCameraPosition(posizione));
      return;
    }
    _seguita = lettura;
    final passo = ora.difference(_ultimaCamera);
    _ultimaCamera = ora;
    // Lunga quanto l'intervallo fra due letture: un telefono a un secondo ne
    // dà spesso a 1,1–1,3 s, e tagliarla lì fermava la mappa mezzo secondo
    // a ogni lettura. Solo dopo un vero silenzio si riparte da un secondo.
    final durata = passo > const Duration(seconds: 2)
        ? const Duration(milliseconds: 1000)
        : passo < const Duration(milliseconds: 300)
        ? const Duration(milliseconds: 300)
        : passo > const Duration(milliseconds: 1500)
        ? const Duration(milliseconds: 1500)
        : passo;
    await m.easeCamera(
      CameraUpdate.newCameraPosition(posizione),
      duration: durata,
      interpolation: CameraAnimationInterpolation.linear,
    );
  }

  /// Il viaggio di cui la telecamera mostra già tutta la strada: non la si
  /// rimette a ogni giro, così chi la guarda può anche avvicinarsi.
  Viaggio? _suTuttaLaStrada;

  Future<void> _tuttaLaStrada(MapLibreMapController m, GestoreGuida g) async {
    final v = g.pronto?.viaggio;
    if (v == null || identical(v, _suTuttaLaStrada)) return;
    final riquadro = confini(v);
    if (riquadro == null) return;
    final (so, ne) = riquadro;
    _suTuttaLaStrada = v;
    try {
      await m.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(so.lat, so.lon), northeast: LatLng(ne.lat, ne.lon)),
          left: 48,
          top: 200,
          right: 72,
          // Sotto ci sono il tachimetro e la scheda dell'arrivo.
          bottom: MediaQuery.sizeOf(context).height * 0.4,
        ),
      );
    } catch (e) {
      _suTuttaLaStrada = null;
      rethrow;
    }
  }

  /// La freccia che c'è sulla mappa. Questa vuol dire «non si sa»: una mappa o
  /// uno stile nuovo nascono con la sorgente vuota, e una scrittura andata male
  /// non ha lasciato quello che si voleva. La prossima volta si riscrive.
  static const _frecciaIgnota = (-1, -1);
  (int, int)? _frecciaDisegnata = _frecciaIgnota;

  /// La freccia della prossima manovra sul percorso, avvicinandosi.
  Future<void> _freccia(MapLibreMapController m) async {
    final g = widget.guida;
    final v = g?.pronto?.viaggio, a = g?.avanzamento;
    final chiave = chiaveFreccia(v, a?.prossima, a?.allaProssimaM, ricalcolo: g?.ricalcolando ?? false);
    if (chiave == _frecciaDisegnata) return;
    // Segnata prima, perché chi arriva nel frattempo non la riscriva.
    _frecciaDisegnata = chiave;
    final dati = chiave == null ? datiManovra(null, null) : datiManovra(v, a?.prossima);
    try {
      await m.setGeoJsonSource(sorgenteManovra, dati.cast<String, dynamic>());
    } catch (_) {
      if (_frecciaDisegnata == chiave) _frecciaDisegnata = _frecciaIgnota;
      rethrow;
    }
  }

  /// Le immagini dello stile: una che non si carica non tiene fuori le altre,
  /// né quello che si fa dopo (il segnaposto, le segnalazioni, i vicini).
  Future<void> _immagini(MapLibreMapController m) async {
    Future<void> una(String nome, Future<Uint8List> Function() png) async {
      try {
        await m.addImage(nome, await png());
      } catch (e) {
        debugPrint('mappa, immagine $nome: $e');
      }
    }

    for (final s in Segnaposto.values) {
      await una(s.immagine, () async => (await rootBundle.load(s.asset)).buffer.asUint8List());
    }
    for (final t in TipoSegnalazione.values) {
      await una(nomeIcona(t), () => iconaSegnalazionePng(t));
    }
    await una(immaginePuntaManovra, puntaManovraPng);
    await una(immagineBandieraArrivo, bandieraArrivoPng);
    try {
      for (final MapEntry(:key, :value) in (await iconePunti()).entries) {
        await una(key, () async => value);
      }
    } catch (e) {
      debugPrint('mappa, icone dei punti: $e');
    }
  }

  /* ─── La rete di sicurezza del percorso, in guida ───────────────────────────
   *
   * Dal campo: appena partiti, sulla mappa della guida c'era il traffico e
   * nessuna linea blu. Non era fuori dallo schermo: la sorgente era vuota
   * davvero. Una scrittura andata male, una mappa rifatta mentre si scriveva,
   * e niente la rimetteva più.
   *
   * Così, a ogni posizione e a ogni giro dell'orologio: se la mappa non ha il
   * viaggio di adesso lo si riscrive (al più ogni tre secondi, se continua a
   * non andare); e anche se ce l'ha, ogni venticinque secondi lo si riscrive
   * coi dati già fatti, che sono pochi. Fuori dalla guida no: lì riscrivere il
   * viaggio vuol dire anche rimettere la telecamera sul percorso, e la mappa
   * scapperebbe di mano a chi la sta guardando.
   */

  void _giroDiGuardia() {
    if (!mounted) return;
    _guardiaPercorso();
    // Col GPS muto nessuno chiama _io: la telecamera la si sistema da qui.
    if (widget.posizione.tace()) unawaited(_io());
  }

  void _guardiaPercorso() {
    if (widget.guida == null || _mappa == null || !_stileCaricato) return;
    final ora = _ora();
    if (!identical(widget.gestore.stato, _disegnato)) {
      if (ora.difference(_ultimoTentativo) >= const Duration(seconds: 3)) unawaited(_ridisegna());
    } else if (ora.difference(_ultimaRiscrittura) >= const Duration(seconds: 25)) {
      _ultimaRiscrittura = ora;
      unawaited(_ridisegna(ancora: true));
    }
  }

  Future<void> _vicini() async {
    final m = _mappa, v = widget.vicini;
    if (m == null || !_stileCaricato || v == null) return;
    for (final MapEntry(:key, :value) in v.dati().entries) {
      await m.setGeoJsonSource(key, value.cast<String, dynamic>());
    }
    if (widget.guida == null && v.versioneTutte != _versioneTutte) {
      // Segnata prima di mandarla: una seconda chiamata nel frattempo non
      // rimanda gli stessi megabyte.
      _versioneTutte = v.versioneTutte;
      await m.setGeoJsonSource(sorgenteTutte, v.datiTutte().cast<String, dynamic>());
    }
  }

  /// Quante richieste «mostra» ha già seguito la mappa: all'inizio nessuna,
  /// così una chiesta prima che la mappa ci fosse si segue appena c'è.
  var _mostrate = 0;

  /// Le persone di casa sulla mappa, e la telecamera su quella da mostrare.
  Future<void> _persone() async {
    final m = _mappa, g = widget.persone;
    if (m == null || !_stileCaricato || g == null) return;
    try {
      await m.setGeoJsonSource(sorgentePersone, datiPersone(g.persone).cast<String, dynamic>());
    } catch (e) {
      debugPrint('mappa, persone: $e');
    }
    if (g.richiesteMostra == _mostrate || !identical(m, _mappa) || !mounted) return;
    _mostrate = g.richiesteMostra;
    // Mostrata una persona, il primo GPS non riporta la mappa su di te.
    _primaPosizione = false;
    // La mappa smette di seguire: in guida torna da sola dopo un po', fuori
    // resta sulla persona finché non si chiede «Dove sono».
    widget.controllo.toccata(torna: widget.guida != null);
    final una = g.daMostrare;
    if (una != null) {
      await m.animateCamera(CameraUpdate.newLatLngZoom(LatLng(una.posizione.lat, una.posizione.lon), 15));
      return;
    }
    final punti = [for (final p in g.persone) p.posizione, ?widget.posizione.qui];
    if (punti.isEmpty) return;
    if (punti.length == 1) {
      await m.animateCamera(CameraUpdate.newLatLngZoom(LatLng(punti.first.lat, punti.first.lon), 15));
      return;
    }
    var sud = 90.0, ovest = 180.0, nord = -90.0, est = -180.0;
    for (final p in punti) {
      if (p.lat < sud) sud = p.lat;
      if (p.lat > nord) nord = p.lat;
      if (p.lon < ovest) ovest = p.lon;
      if (p.lon > est) est = p.lon;
    }
    await m.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(sud, ovest), northeast: LatLng(nord, est)),
        left: 60,
        top: 200,
        right: 60,
        bottom: MediaQuery.sizeOf(context).height * 0.3,
      ),
    );
  }

  Future<void> _segnalazioni() async {
    final m = _mappa, g = widget.segnalazioni;
    if (m == null || !_stileCaricato || g == null) return;
    await m.setGeoJsonSource(sorgenteSegnalazioni, datiSegnalazioni(g.vicine, widget.guida?.avvisi).cast<String, dynamic>());
  }

  GestoreRisparmio? get _gestoreRisparmio => widget.risparmio ?? widget.guida?.risparmio;

  /// La strada proposta in guida, verde col suo fumetto; o più niente.
  Future<void> _risparmio() async {
    final m = _mappa, r = _gestoreRisparmio;
    if (widget.guida == null) return;
    if (m == null || !_stileCaricato || r == null) return;
    final p = r.proposta;
    await m.setGeoJsonSource(
      sorgenteRisparmio,
      datiRisparmio(
        p,
        widget.guida?.pronto?.viaggio.percorso,
        p == null ? '' : sintesiProposta(p, r.unita, meno: '-'),
      ).cast<String, dynamic>(),
    );
  }

  Future<void> _edifici(MapLibreMapController m) async {
    if (!_stileCaricato) return;
    await m.setLayerVisibility(stratoEdifici2d, !_inclinata);
    await m.setLayerVisibility(stratoEdifici3d, _inclinata);
  }

  /// Una mappa o uno stile nuovi: le sorgenti sono vuote, e le scritture
  /// ancora in corso erano per quelle di prima.
  void _sorgentiVuote() {
    _disegnato = null;
    _inScrittura = null;
    _giroDisegno++;
    _frecciaDisegnata = _frecciaIgnota;
    _suTuttaLaStrada = null;
  }

  /// Il viaggio sulla mappa: percorso, colonnine, arrivo, code, tappe.
  /// [ancora]: lo stesso viaggio di prima, riscritto coi dati già fatti (la
  /// rete di sicurezza della guida), senza toccare la telecamera.
  Future<void> _ridisegna({bool ancora = false}) async {
    final m = _mappa;
    final stato = widget.gestore.stato;
    if (m == null || !_stileCaricato || identical(stato, _inScrittura)) return;
    if (!ancora && identical(stato, _disegnato)) return;
    final giro = ++_giroDisegno;
    _inScrittura = stato;
    _ultimoTentativo = _ora();
    var tutto = true;
    // Una sorgente alla volta, il percorso per primo: se un'altra non si
    // scrive (le code, le colonnine) la strada sulla mappa c'è lo stesso.
    for (final MapEntry(key: id, value: dati) in _datiDel(stato, ancora: ancora).entries) {
      try {
        await m.setGeoJsonSource(id, dati.cast<String, dynamic>());
      } catch (e) {
        tutto = false;
        debugPrint('mappa, sorgente $id: $e');
      }
      // Nel frattempo è partita una scrittura più nuova, o la mappa è un'altra.
      if (giro != _giroDisegno) return;
    }
    _inScrittura = null;
    // Qualcosa non è andato: la mappa non ha di sicuro questo viaggio, e la
    // prossima chiamata lo riscrive.
    if (!tutto) {
      _disegnato = null;
      return;
    }
    _disegnato = stato;
    _ultimaRiscrittura = _ora();
    final viaggio = stato is ViaggioPronto ? stato.viaggio : null;
    if (ancora || viaggio == null || widget.guida != null || !mounted) return;
    final riquadro = confini(viaggio, anche: stato is ViaggioPronto ? stato.scelte : const []);
    if (riquadro == null) return;
    final (so, ne) = riquadro;
    await m.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(so.lat, so.lon), northeast: LatLng(ne.lat, ne.lon)),
        left: 48,
        top: 190,
        right: 72,
        bottom: MediaQuery.sizeOf(context).height * 0.45,
      ),
    );
    if (_inclinata) await m.animateCamera(CameraUpdate.tiltTo(_inclinazione));
  }

  /// I dati delle sorgenti del viaggio per [stato]. [ancora]: quelli già
  /// fatti, se sono suoi; altrimenti si rifanno (le strade da proporre, per
  /// esempio, arrivano dopo il viaggio).
  Map<String, Map<String, Object?>> _datiDel(StatoViaggio stato, {required bool ancora}) {
    if (_datiFatti case (final s, final fatti) when ancora && identical(s, stato)) return fatti;
    final viaggio = stato is ViaggioPronto ? stato.viaggio : null;
    final dati = stato is ViaggioPronto && widget.guida == null
        ? datiViaggio(
            viaggio,
            scelte: stato.scelte,
            scelta: stato.scelta,
            tappe: stato.tappe,
            passandoci: true,
            // Quella che risparmia energia, verde come nelle schede.
            eco: stradaCheRisparmia(stato.scelte, _gestoreRisparmio),
          )
        : datiViaggio(viaggio, tappe: stato is ViaggioPronto ? stato.tappe : const []);
    _datiFatti = (stato, dati);
    return dati;
  }

  Future<void> _tocco(Point<double> punto) async {
    final m = _mappa;
    if (m == null) return;
    final trovati = await m.queryRenderedFeatures(punto, stratiToccabili, null);
    for (final f in trovati) {
      // A seconda della piattaforma arriva già decodificata o come JSON.
      final mappa = f is String ? jsonDecode(f) : f;
      if (mappa is! Map) continue;
      // Un gruppo di colonnine: ci si avvicina, e si separano.
      if (mappa case {
        'properties': {'point_count': _},
        'geometry': {'coordinates': [final num lon, final num lat, ...]},
      }) {
        final zoom = (await m.queryCameraPosition())?.zoom ?? 5;
        await m.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat.toDouble(), lon.toDouble()), zoom + 2));
        return;
      }
      // Una colonnina di tutta la mappa: sulla mappa c'è solo dove e quanti
      // kW, il nome e il resto sono nell'archivio.
      if (mappa case {'properties': {'id': final String id, 'kw': _}} when widget.onPunto != null) {
        if (widget.vicini?.colonnina(id) case final c?) {
          return widget.onPunto!(PuntoToccato(tipo: 'colonnina', id: c.id, nome: c.nome, posizione: c.posizione));
        }
      }
      // Prima i punti che sappiamo raccontare (distributori, colonnine
      // vicine, ristoranti…), poi le colonnine del viaggio.
      // Una strada alternativa: si sceglie quella.
      if (mappa case {'properties': {'alternativa': final num i}}) return widget.gestore.scegli(i.toInt());
      if (PuntoToccato.daElemento(mappa) case final p? when widget.onPunto != null) return widget.onPunto!(p);
      if (mappa case {'properties': {'id': final String id}}) return widget.onColonnina(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    // Il traffico è per tutti: c'è se c'è la chiave TomTom.
    const traffico = Servizi.chiaveTomTom;
    final mappa = MapLibreMap(
      // Cambia stile col tema (e col traffico): la chiave rifà la mappa.
      key: ValueKey((scuro, traffico.isNotEmpty)),
      styleString: jsonEncode(stileMappa(scuro: scuro, chiaveTraffico: traffico)),
      initialCameraPosition: widget.guida != null
          ? CameraPosition(
              target: const LatLng(41.9, 12.5),
              zoom: 17,
              tilt: widget.controllo.inclinata ? _inclinazione : 0,
            )
          : CameraPosition(
              target: const LatLng(41.9, 12.5),
              zoom: 5,
              tilt: widget.controllo.inclinata ? _inclinazione : 0,
            ),
      // Il puntino di MapLibre no: il segnaposto lo disegna lo stile.
      myLocationEnabled: false,
      compassEnabled: true,
      attributionButtonPosition: AttributionButtonPosition.topLeft,
      attributionButtonMargins: const Point(12, 200),
      onMapCreated: (c) {
        // Una mappa nuova (il tema): finché il suo stile non è pronto non le
        // si scrive niente. Prima restava acceso lo «stile caricato» della
        // vecchia, e le scritture partivano verso una mappa ancora vuota.
        _mappa = c;
        _stileCaricato = false;
        _ultimaCamera = DateTime(0);
        _seguita = null;
        // Una mappa nuova (il tema) nasce su Roma: la prima posizione ce la
        // riporta sopra, come la prima volta.
        _primaPosizione = true;
        _sorgentiVuote();
      },
      onStyleLoadedCallback: () {
        _stileCaricato = true;
        // Uno stile nuovo (il tema, il traffico) nasce con le sorgenti vuote.
        _sorgentiVuote();
        _versioneTutte = -1;
        _zoneDisegnate = null;
        _zoneConPedonali = false;
        _zoneSullaMappa = false;
        if (_mappa case final m?) {
          _inclinata = widget.controllo.inclinata;
          unawaited(_edifici(m).catchError((Object e) => debugPrint('mappa, edifici: $e')));
          // Lo stile nuovo non sa dell'inclinazione: la si rimette.
          unawaited(
            m
                .animateCamera(CameraUpdate.tiltTo(_inclinata ? _inclinazione : 0))
                .then((_) {}, onError: (Object e) => debugPrint('mappa, inclinazione: $e')),
          );
          _seguita = null;
          _immagini(m).then((_) {
            _io();
            _segnalazioni();
            _vicini();
            _persone();
            _zone();
            _risparmio();
          });
        }
        _ridisegna();
      },
      onCameraIdle: () => unawaited(_zone()),
      onMapClick: (p, _) => _tocco(p),
      onMapLongClick: (_, p) => widget.onPuntoScelto(p),
    );
    // Un dito che muove la mappa la rende libera (zoom, spostamenti): in
    // guida, e fuori quando in 3D la mappa ti segue. «Dove sono», o venti
    // secondi senza tocchi, e si torna a seguire.
    return Listener(onPointerMove: (_) => widget.controllo.toccata(), child: mappa);
  }
}
