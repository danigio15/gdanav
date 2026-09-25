import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../mappa/dati_viaggio.dart';
import '../mappa/stile.dart';
import 'icona_manovra.dart';

/// Le manovre che meritano la vista dello svincolo: uscite, rampe e bivi.
const tipiSvincolo = {18, 19, 20, 21, 23, 24};

bool haSvincolo(Manovra m) => tipiSvincolo.contains(m.tipo);

/// Da dove si guarda lo svincolo: un po' prima, alti e inclinati, nella
/// direzione in cui si arriva.
class InquadraturaSvincolo {
  const InquadraturaSvincolo({required this.centro, required this.rotta, this.zoom = 16.3, this.inclinazione = 60});

  final Punto centro;
  final double rotta;
  final double zoom;
  final double inclinazione;

  Map<String, Object?> toJson() => {
    'lat': centro.lat,
    'lon': centro.lon,
    'rotta': rotta,
    'zoom': zoom,
    'inclinazione': inclinazione,
  };
}

const sorgenteFreccia = 'svincolo-freccia';
const sorgentePunta = 'svincolo-punta';
const immaginePunta = 'svincolo-punta';

/// Lo svincolo in 3D sulla mappa vera: lo stile dell'app con il percorso,
/// gli edifici in rilievo, e sopra la freccia bianca che passa per lo
/// svincolo e prosegue sul ramo giusto, disegnata dentro la mappa (quindi in
/// prospettiva, sulla strada). Con l'inquadratura da cui guardarlo.
({Map<String, Object> stile, InquadraturaSvincolo inquadratura}) scenaSvincolo(
  Viaggio v,
  Manovra m, {
  required bool scuro,
}) {
  final punti = v.percorso.punti;
  final linea = Linea(punti);
  final s = linea.cumulate[m.inizio.clamp(0, punti.length - 1)];
  Punto lungo(double metri) {
    final d = metri.clamp(0.0, linea.lunghezzaM);
    var i = 1;
    while (i < punti.length - 1 && linea.cumulate[i] < d) {
      i++;
    }
    final a = punti[i - 1], b = punti[i];
    final tratto = linea.cumulate[i] - linea.cumulate[i - 1];
    final t = tratto <= 0 ? 0.0 : (d - linea.cumulate[i - 1]) / tratto;
    return Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  // La freccia: da 120 m prima a 320 m dopo, dove i rami si sono separati;
  // fitta di punti per le curve.
  final freccia = [for (var d = s - 120; d <= s + 320; d += 8) lungo(d)];
  final ultimo = freccia.last, penultimo = freccia[freccia.length - 2];

  final stile = jsonDecode(jsonEncode(stileMappa(scuro: scuro))) as Map<String, Object?>;
  final sorgenti = stile['sources']! as Map<String, Object?>;
  sorgenti[sorgentePercorso] = {'type': 'geojson', 'data': datiViaggio(v)[sorgentePercorso]};
  sorgenti[sorgenteFreccia] = {
    'type': 'geojson',
    'data': {
      'type': 'Feature',
      'properties': <String, Object>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final p in freccia) [p.lon, p.lat],
        ],
      },
    },
  };
  sorgenti[sorgentePunta] = {
    'type': 'geojson',
    'data': {
      'type': 'Feature',
      'properties': {'rotta': rottaGradi(penultimo, ultimo)},
      'geometry': {
        'type': 'Point',
        'coordinates': [ultimo.lon, ultimo.lat],
      },
    },
  };
  final strati = (stile['layers']! as List).cast<Map<String, Object?>>();
  for (final l in strati) {
    // In rilievo: gli edifici 3D, non quelli piatti.
    if (l['id'] == stratoEdifici2d) l['layout'] = {...?(l['layout'] as Map?), 'visibility': 'none'};
    if (l['id'] == stratoEdifici3d) l['layout'] = {...?(l['layout'] as Map?), 'visibility': 'visible'};
  }
  List<Object> largo(double a, double b) => [
    'interpolate',
    ['exponential', 2],
    ['zoom'],
    14,
    a,
    18,
    b,
  ];
  stile['layers'] = [
    for (final l in strati)
      if (l['id'] != 'io') l,
    {
      'id': 'svincolo-freccia-bordo',
      'type': 'line',
      'source': sorgenteFreccia,
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {'line-color': '#123E91', 'line-width': largo(6, 34)},
    },
    {
      'id': 'svincolo-freccia',
      'type': 'line',
      'source': sorgenteFreccia,
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {'line-color': '#FFFFFF', 'line-width': largo(4, 24)},
    },
    {
      'id': 'svincolo-punta',
      'type': 'symbol',
      'source': sorgentePunta,
      'layout': {
        'icon-image': immaginePunta,
        'icon-rotate': ['get', 'rotta'],
        'icon-rotation-alignment': 'map',
        'icon-pitch-alignment': 'map',
        'icon-allow-overlap': true,
        'icon-ignore-placement': true,
        'icon-size': largo(0.45, 2.2),
      },
    },
  ];
  // Si guarda nella direzione d'arrivo, centrati poco oltre lo svincolo:
  // si vede la strada che arriva, dove si separa e il ramo giusto.
  final da = lungo(s - 250), verso = lungo(s + 60);
  return (
    stile: stile.cast<String, Object>(),
    inquadratura: InquadraturaSvincolo(centro: lungo(s + 110), rotta: rottaGradi(da, verso)),
  );
}

/// La punta della freccia, bianca col bordo blu, che punta in su (nord):
/// la mappa la gira come la strada.
Future<Uint8List> puntaPng({double lato = 96}) async {
  final registro = ui.PictureRecorder();
  final canvas = Canvas(registro);
  final punta = Path()
    ..moveTo(lato / 2, lato * 0.06)
    ..lineTo(lato * 0.94, lato * 0.9)
    ..lineTo(lato * 0.06, lato * 0.9)
    ..close();
  canvas.drawPath(
    punta,
    Paint()
      ..color = const Color(0xFF123E91)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lato * 0.09
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(punta, Paint()..color = Colors.white);
  final immagine = await registro.endRecording().toImage(lato.round(), lato.round());
  return (await immagine.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// La mappa 3D dello svincolo, ferma: si guarda, non si tocca.
class MappaSvincolo extends StatefulWidget {
  const MappaSvincolo({super.key, required this.viaggio, required this.manovra});

  final Viaggio viaggio;
  final Manovra manovra;

  @override
  State<MappaSvincolo> createState() => _MappaSvincoloState();
}

class _MappaSvincoloState extends State<MappaSvincolo> {
  MapLibreMapController? _controllo;

  @override
  Widget build(BuildContext context) {
    final scena = scenaSvincolo(widget.viaggio, widget.manovra, scuro: Theme.of(context).brightness == Brightness.dark);
    final q = scena.inquadratura;
    return MapLibreMap(
      key: ValueKey(widget.manovra.inizio),
      styleString: jsonEncode(scena.stile),
      initialCameraPosition: CameraPosition(
        target: LatLng(q.centro.lat, q.centro.lon),
        zoom: q.zoom,
        tilt: q.inclinazione,
        bearing: q.rotta,
      ),
      compassEnabled: false,
      rotateGesturesEnabled: false,
      scrollGesturesEnabled: false,
      zoomGesturesEnabled: false,
      tiltGesturesEnabled: false,
      doubleClickZoomEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.topRight,
      onMapCreated: (c) => _controllo = c,
      onStyleLoadedCallback: () async {
        await _controllo?.addImage(immaginePunta, await puntaPng());
      },
    );
  }
}

/// Costruisce la mappa dentro il popup: quella vera, o altro nelle prove.
typedef CostruisciMappaSvincolo = Widget Function(Viaggio v, Manovra m);

/// Il popup sul telefono: lo svincolo in 3D sulla mappa vera, sopra il
/// cartello (uscita e direzione), in basso le corsie giuste e i metri che
/// mancano con la barra che si accorcia, e la X per chiuderlo.
class PopupSvincolo extends StatelessWidget {
  const PopupSvincolo({
    super.key,
    required this.viaggio,
    required this.manovra,
    required this.metri,
    required this.onChiudi,
    this.mappa,
  });

  final Viaggio viaggio;
  final Manovra manovra;
  final double metri;
  final VoidCallback onChiudi;
  final CostruisciMappaSvincolo? mappa;

  static const daMetri = 800.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      key: const Key('popup-svincolo'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 5 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              mappa?.call(viaggio, manovra) ?? MappaSvincolo(viaggio: viaggio, manovra: manovra),
              // In alto il cartello e la X.
              Positioned(
                left: 10,
                top: 10,
                right: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: manovra.verso.isNotEmpty || manovra.uscita.isNotEmpty
                      ? CartelloSvincolo(manovra: manovra)
                      : const SizedBox.shrink(),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filled(
                  key: const Key('chiudi-svincolo'),
                  iconSize: 20,
                  constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xCC202633)),
                  onPressed: onChiudi,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              // In basso i metri che mancano e le corsie.
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE6202633),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            distanzaBreve(metri),
                            style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          SizedBox(
                            width: 64,
                            child: LinearProgressIndicator(
                              value: (metri / daMetri).clamp(0.0, 1.0),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (manovra.corsieUtili) CorsieSvincolo(corsie: manovra.corsie, lato: 20),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
