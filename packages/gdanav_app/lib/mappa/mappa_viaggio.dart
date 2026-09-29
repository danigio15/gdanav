import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart' show Punto, Rettangolo, TipoSegnalazione, TipoZona;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import '../stato/gestore_ztl.dart';
import 'controllo_mappa.dart';
import 'dati_viaggio.dart';
import 'segnaposto.dart';
import 'stile.dart';

/// La mappa vera: MapLibre con lo stile di gdanav (chiaro o scuro come il
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
    this.ztl,
    this.onPunto,
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

  /// Le ZTL e le aree pedonali: si disegnano quelle che si vedono, se si
  /// vogliono sulla mappa.
  final GestoreZtl? ztl;

  /// Tocco su un distributore, una colonnina vicina o un punto di interesse.
  final ValueChanged<PuntoToccato>? onPunto;

  @override
  State<MappaViaggio> createState() => _MappaViaggioState();
}

class _MappaViaggioState extends State<MappaViaggio> {
  MapLibreMapController? _mappa;
  var _stileCaricato = false;
  StatoViaggio? _disegnato;
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
    widget.posizione.addListener(_io);
    widget.guida?.addListener(_io);
    widget.segnalazioni?.addListener(_segnalazioni);
    widget.vicini?.addListener(_vicini);
    widget.ztl?.addListener(_zoneDaCapo);
    // Le ZTL cambiano stato nel corso della giornata: «attiva fino alle 18».
    _orologioZone = Timer.periodic(const Duration(minutes: 5), (_) => _zoneDaCapo());
    // In guida no: lì contano le soste del percorso e quelle vicine, e
    // tutta Italia sulla strada sarebbe solo confusione.
    if (widget.guida == null) widget.vicini?.avviaTutte();
  }

  @override
  void dispose() {
    widget.gestore.removeListener(_ridisegna);
    widget.controllo.removeListener(_comandi);
    widget.posizione.removeListener(_io);
    widget.guida?.removeListener(_io);
    widget.segnalazioni?.removeListener(_segnalazioni);
    widget.vicini?.removeListener(_vicini);
    widget.ztl?.removeListener(_zoneDaCapo);
    _orologioZone?.cancel();
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
    }
    // In guida, tornati a seguire l'auto: subito, senza aspettare il GPS.
    if (widget.controllo.libera != _libera) {
      _libera = widget.controllo.libera;
      if (!_libera) {
        _ultimaCamera = DateTime(0);
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
      if (qui != null) {
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

  /// Il segnaposto: in guida agganciato al percorso e girato come la
  /// strada, altrimenti dove dice il GPS.
  Future<void> _io() async {
    final m = _mappa;
    if (m == null || !_stileCaricato) return;
    final a = widget.guida?.avanzamento;
    final qui = a?.posizioneSulPercorso ?? widget.posizione.qui;
    final rotta = a?.rotta ?? widget.posizione.rotta;
    await m.setGeoJsonSource(sorgenteIo, datiIo(qui, rotta, widget.posizione.segnaposto).cast<String, dynamic>());
    await _freccia(m);
    if (qui == null) return;
    if (widget.guida != null) {
      // Mappa libera: la si lascia dove l'ha messa chi guida.
      if (widget.controllo.libera) return;
      // La telecamera segue l'auto; al massimo un movimento al secondo.
      final ora = DateTime.now();
      if (ora.difference(_ultimaCamera) < const Duration(milliseconds: 900)) return;
      _ultimaCamera = ora;
      await m.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(qui.lat, qui.lon),
            zoom: _inclinata ? 17 : 16,
            tilt: _inclinata ? _inclinazione : 0,
            // Guarda un po' avanti: in curva la manovra resta in vista.
            bearing: a?.rottaMappa ?? rotta,
          ),
        ),
        duration: const Duration(milliseconds: 900),
      );
    } else if (_primaPosizione && widget.gestore.stato is! ViaggioPronto) {
      _primaPosizione = false;
      await m.animateCamera(CameraUpdate.newLatLngZoom(LatLng(qui.lat, qui.lon), 15));
    }
  }

  (int, int)? _frecciaDisegnata;

  /// La freccia della prossima manovra sul percorso, avvicinandosi.
  Future<void> _freccia(MapLibreMapController m) async {
    final g = widget.guida;
    final v = g?.pronto?.viaggio, a = g?.avanzamento;
    final chiave = chiaveFreccia(v, a?.prossima, a?.allaProssimaM, ricalcolo: g?.ricalcolando ?? false);
    if (chiave == _frecciaDisegnata) return;
    _frecciaDisegnata = chiave;
    final dati = chiave == null ? datiManovra(null, null) : datiManovra(v, a?.prossima);
    await m.setGeoJsonSource(sorgenteManovra, dati.cast<String, dynamic>());
  }

  Future<void> _immagini(MapLibreMapController m) async {
    for (final s in Segnaposto.values) {
      final byte = await rootBundle.load(s.asset);
      await m.addImage(s.immagine, byte.buffer.asUint8List());
    }
    for (final t in TipoSegnalazione.values) {
      await m.addImage(nomeIcona(t), await iconaSegnalazionePng(t));
    }
    for (final MapEntry(:key, :value) in (await iconePunti()).entries) {
      await m.addImage(key, value);
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

  Future<void> _segnalazioni() async {
    final m = _mappa, g = widget.segnalazioni;
    if (m == null || !_stileCaricato || g == null) return;
    await m.setGeoJsonSource(sorgenteSegnalazioni, datiSegnalazioni(g.vicine).cast<String, dynamic>());
  }

  Future<void> _edifici(MapLibreMapController m) async {
    if (!_stileCaricato) return;
    await m.setLayerVisibility(stratoEdifici2d, !_inclinata);
    await m.setLayerVisibility(stratoEdifici3d, _inclinata);
  }

  Future<void> _ridisegna() async {
    final m = _mappa;
    final stato = widget.gestore.stato;
    if (m == null || !_stileCaricato || identical(stato, _disegnato)) return;
    _disegnato = stato;
    final basso = MediaQuery.sizeOf(context).height * 0.45;
    final viaggio = stato is ViaggioPronto ? stato.viaggio : null;
    final dati = stato is ViaggioPronto && widget.guida == null
        ? datiViaggio(viaggio, scelte: stato.scelte, scelta: stato.scelta, tappe: stato.tappe, passandoci: true)
        : datiViaggio(viaggio, tappe: stato is ViaggioPronto ? stato.tappe : const []);
    for (final MapEntry(key: id, value: dati) in dati.entries) {
      await m.setGeoJsonSource(id, dati.cast<String, dynamic>());
    }
    if (viaggio == null || widget.guida != null) return;
    final (so, ne) = confini(viaggio, anche: stato is ViaggioPronto ? stato.scelte : const [])!;
    await m.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(so.lat, so.lon), northeast: LatLng(ne.lat, ne.lon)),
        left: 48,
        top: 190,
        right: 72,
        bottom: basso,
      ),
    );
    if (_inclinata) await m.animateCamera(CameraUpdate.tiltTo(_inclinazione));
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
          ? const CameraPosition(target: LatLng(41.9, 12.5), zoom: 17, tilt: _inclinazione)
          : const CameraPosition(target: LatLng(41.9, 12.5), zoom: 5),
      // Il puntino di MapLibre no: il segnaposto lo disegna lo stile.
      myLocationEnabled: false,
      compassEnabled: true,
      attributionButtonPosition: AttributionButtonPosition.topLeft,
      attributionButtonMargins: const Point(12, 200),
      onMapCreated: (c) => _mappa = c,
      onStyleLoadedCallback: () {
        _stileCaricato = true;
        _disegnato = null;
        // Uno stile nuovo (il tema, il traffico) nasce con le sorgenti vuote.
        _versioneTutte = -1;
        _zoneDisegnate = null;
        _zoneConPedonali = false;
        _zoneSullaMappa = false;
        if (_mappa case final m?) {
          _inclinata = widget.controllo.inclinata;
          _edifici(m);
          _immagini(m).then((_) {
            _io();
            _segnalazioni();
            _vicini();
            _zone();
          });
        }
        _ridisegna();
      },
      onCameraIdle: () => unawaited(_zone()),
      onMapClick: (p, _) => _tocco(p),
      onMapLongClick: (_, p) => widget.onPuntoScelto(p),
    );
    // In guida un dito che muove la mappa la rende libera (zoom, spostamenti).
    if (widget.guida == null) return mappa;
    return Listener(onPointerMove: (_) => widget.controllo.toccata(), child: mappa);
  }
}
