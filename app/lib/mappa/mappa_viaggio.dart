import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../stato/gestore_viaggio.dart';
import 'controllo_mappa.dart';
import 'dati_viaggio.dart';
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
  });

  final GestoreViaggio gestore;
  final ControlloMappa controllo;

  /// Pressione lunga sulla mappa: «portami qui».
  final ValueChanged<LatLng> onPuntoScelto;

  /// Tocco su una colonnina o una sosta.
  final ValueChanged<String> onColonnina;

  @override
  State<MappaViaggio> createState() => _MappaViaggioState();
}

class _MappaViaggioState extends State<MappaViaggio> {
  MapLibreMapController? _mappa;
  var _stileCaricato = false;
  StatoViaggio? _disegnato;
  var _inclinata = false;
  var _centrate = 0;

  static const _inclinazione = 58.0;

  @override
  void initState() {
    super.initState();
    widget.gestore.addListener(_ridisegna);
    widget.controllo.addListener(_comandi);
  }

  @override
  void dispose() {
    widget.gestore.removeListener(_ridisegna);
    widget.controllo.removeListener(_comandi);
    super.dispose();
  }

  Future<void> _comandi() async {
    final m = _mappa;
    if (m == null) return;
    if (widget.controllo.inclinata != _inclinata) {
      _inclinata = widget.controllo.inclinata;
      await m.animateCamera(CameraUpdate.tiltTo(_inclinata ? _inclinazione : 0));
    }
    if (widget.controllo.richiesteCentra != _centrate) {
      _centrate = widget.controllo.richiesteCentra;
      final qui = await m.requestMyLocationLatLng();
      if (qui != null) {
        await m.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(target: qui, zoom: 16, tilt: _inclinata ? _inclinazione : 0)),
        );
      }
    }
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
    if (viaggio == null) return;
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
      final id = (f as Map)['properties']?['id'];
      if (id is String) return widget.onColonnina(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return MapLibreMap(
      // Cambia stile col tema: la chiave rifà la mappa.
      key: ValueKey(scuro),
      styleString: jsonEncode(stileMappa(scuro: scuro)),
      initialCameraPosition: const CameraPosition(target: LatLng(41.9, 12.5), zoom: 5),
      myLocationEnabled: true,
      myLocationTrackingMode: MyLocationTrackingMode.tracking,
      compassEnabled: true,
      attributionButtonPosition: AttributionButtonPosition.topLeft,
      attributionButtonMargins: const Point(12, 200),
      onMapCreated: (c) => _mappa = c,
      onStyleLoadedCallback: () {
        _stileCaricato = true;
        _disegnato = null;
        _ridisegna();
      },
      onMapClick: (p, _) => _tocco(p),
      onMapLongClick: (_, p) => widget.onPuntoScelto(p),
    );
  }
}
