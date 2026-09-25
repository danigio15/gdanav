import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart' show TipoSegnalazione;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_premium.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
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
    GestorePremium.attivo.addListener(_premium);
  }

  void _premium() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.gestore.removeListener(_ridisegna);
    widget.controllo.removeListener(_comandi);
    widget.posizione.removeListener(_io);
    widget.guida?.removeListener(_io);
    widget.segnalazioni?.removeListener(_segnalazioni);
    widget.vicini?.removeListener(_vicini);
    GestorePremium.attivo.removeListener(_premium);
    super.dispose();
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
    for (final MapEntry(key: id, value: dati) in datiViaggio(viaggio).entries) {
      await m.setGeoJsonSource(id, dati.cast<String, dynamic>());
    }
    if (viaggio == null || widget.guida != null) return;
    final (so, ne) = confini(viaggio)!;
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
      // Prima i punti che sappiamo raccontare (distributori, colonnine
      // vicine, ristoranti…), poi le colonnine del viaggio.
      if (PuntoToccato.daElemento(mappa) case final p? when widget.onPunto != null) return widget.onPunto!(p);
      if (mappa case {'properties': {'id': final String id}}) return widget.onColonnina(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    // Il traffico è Premium.
    final traffico = GestorePremium.attivo.value ? Servizi.chiaveTomTom : '';
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
        if (_mappa case final m?) {
          _inclinata = widget.controllo.inclinata;
          _edifici(m);
          _immagini(m).then((_) {
            _io();
            _segnalazioni();
            _vicini();
          });
        }
        _ridisegna();
      },
      onMapClick: (p, _) => _tocco(p),
      onMapLongClick: (_, p) => widget.onPuntoScelto(p),
    );
    // In guida un dito che muove la mappa la rende libera (zoom, spostamenti).
    if (widget.guida == null) return mappa;
    return Listener(onPointerMove: (_) => widget.controllo.toccata(), child: mappa);
  }
}
