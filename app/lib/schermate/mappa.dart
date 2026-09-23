import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../stato/gestore_viaggio.dart';

/// Lo stile di OpenFreeMap: gratis, senza chiave, anche per uso commerciale.
const stileMappa = 'https://tiles.openfreemap.org/styles/liberty';

/// La mappa, col viaggio disegnato sopra quando c'è: la linea del percorso,
/// le soste in verde e la destinazione.
class MappaViaggio extends StatefulWidget {
  const MappaViaggio({super.key, required this.gestore, required this.onPuntoScelto});

  final GestoreViaggio gestore;

  /// Pressione lunga sulla mappa: «portami qui».
  final ValueChanged<Punto> onPuntoScelto;

  @override
  State<MappaViaggio> createState() => _MappaViaggioState();
}

class _MappaViaggioState extends State<MappaViaggio> {
  MapLibreMapController? _mappa;
  var _stileCaricato = false;
  StatoViaggio? _disegnato;

  @override
  void initState() {
    super.initState();
    widget.gestore.addListener(_ridisegna);
  }

  @override
  void dispose() {
    widget.gestore.removeListener(_ridisegna);
    super.dispose();
  }

  Future<void> _ridisegna() async {
    final m = _mappa;
    final stato = widget.gestore.stato;
    if (m == null || !_stileCaricato || identical(stato, _disegnato)) return;
    _disegnato = stato;
    await m.clearLines();
    await m.clearCircles();
    if (stato is! ViaggioPronto) return;

    final punti = [for (final p in stato.viaggio.percorso.punti) LatLng(p.lat, p.lon)];
    if (punti.length < 2) return;
    await m.addLine(LineOptions(geometry: punti, lineColor: '#1D5BA8', lineWidth: 6, lineOpacity: 0.9));
    final linea = Linea(stato.viaggio.percorso.punti);
    for (final s in stato.viaggio.piano?.soste ?? const <Sosta>[]) {
      final p = _puntoA(linea, s.colonnina.distanzaM);
      await m.addCircle(
        CircleOptions(
          geometry: LatLng(p.lat, p.lon),
          circleRadius: 9,
          circleColor: '#23794C',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );
    }
    await m.addCircle(
      CircleOptions(
        geometry: punti.last,
        circleRadius: 9,
        circleColor: '#A63A2E',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
    await m.animateCamera(
      CameraUpdate.newLatLngBounds(_confini(punti), left: 48, top: 140, right: 48, bottom: 320),
    );
  }

  /// Il punto del percorso a [metri] dalla partenza.
  static Punto _puntoA(Linea l, double metri) {
    for (var i = 1; i < l.punti.length; i++) {
      if (l.cumulate[i] >= metri) return l.punti[i];
    }
    return l.punti.last;
  }

  static LatLngBounds _confini(List<LatLng> punti) {
    var s = punti.first.latitude, n = s, o = punti.first.longitude, e = o;
    for (final p in punti) {
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      o = math.min(o, p.longitude);
      e = math.max(e, p.longitude);
    }
    return LatLngBounds(southwest: LatLng(s, o), northeast: LatLng(n, e));
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: stileMappa,
      initialCameraPosition: const CameraPosition(target: LatLng(41.9, 12.5), zoom: 5),
      myLocationEnabled: true,
      myLocationTrackingMode: MyLocationTrackingMode.tracking,
      onMapCreated: (c) => _mappa = c,
      onStyleLoadedCallback: () {
        _stileCaricato = true;
        _disegnato = null;
        _ridisegna();
      },
      onMapLongClick: (_, p) => widget.onPuntoScelto(Punto(p.latitude, p.longitude)),
    );
  }
}
