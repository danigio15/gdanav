import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../schermate/scheda_punto.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_persone.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import 'controllo_mappa.dart';
import 'ponte_3d.dart';
import 'regia_3d.dart';

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
    this.persone,
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

  /// Le persone di casa (da GdAHome): a terra come sulla mappa di sempre, e
  /// sui viadotti all'altezza dell'impalcato.
  final GestorePersone? persone;
  final ValueChanged<PuntoToccato>? onPunto;
  final DateTime Function()? orologio;

  /// Quanto si aspetta che la pagina sia pronta, prima di lasciar perdere.
  static const attesa = Duration(seconds: 15);

  @override
  State<Mappa3d> createState() => _Mappa3dState();
}

class _Mappa3dState extends State<Mappa3d> {
  late final WebViewController _web;
  late final Regia3d _regia;
  var _notte = false;
  AppLifecycleListener? _vita;

  @override
  void initState() {
    super.initState();
    _web = WebViewController();
    _regia = Regia3d(
      gestore: widget.gestore,
      posizione: widget.posizione,
      guida: widget.guida,
      manda: (m) =>
          _web.runJavaScript(chiamata3d(m)).catchError((Object e) => debugPrint('mappa 3D, ${m['tipo']}: $e')),
      notte: () => _notte,
      vista: () => widget.controllo.vista,
      inquadratura: () => (
        libera: widget.controllo.libera,
        sopra: widget.controllo.coperto,
        sinistra: widget.controllo.copertoSinistra,
      ),
      onNonVa: (motivo, {required ricorda}) => widget.onNonVa(motivo, ricorda: ricorda),
      segnalazioni: widget.segnalazioni,
      vicini: widget.vicini,
      persone: widget.persone,
      onTocco: _tocco,
      onToccata: widget.controllo.toccata,
      orologio: widget.orologio,
      attesa: Mappa3d.attesa,
    )..avvia();
    unawaited(_avvia());
    widget.controllo.addListener(_comandi);
    _vita = AppLifecycleListener(onHide: () => _regia.pausa(true), onShow: () => _regia.pausa(false));
  }

  Future<void> _avvia() async {
    try {
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _web.addJavaScriptChannel(canale3d, onMessageReceived: (m) => _regia.dallaMappa(m.message));
      await _web.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? false) _regia.nonVa('pagina', ricorda: false);
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
      _regia.nonVa('webview', ricorda: true);
    }
  }

  @override
  void dispose() {
    _regia.ferma();
    widget.controllo.removeListener(_comandi);
    _vita?.dispose();
    super.dispose();
  }

  void _comandi() => _regia.comandi();

  /// Un tocco su un punto: come sulla mappa di sempre.
  void _tocco(List<Map<Object?, Object?>> elementi) {
    for (final e in elementi) {
      if (e case {'properties': {'id': final String id, 'kw': _}} when widget.onPunto != null) {
        if (widget.vicini?.colonnina(id) case final c?) {
          return widget.onPunto!(PuntoToccato(tipo: 'colonnina', id: c.id, nome: c.nome, posizione: c.posizione));
        }
      }
      if (PuntoToccato.daElemento(e) case final p? when widget.onPunto != null) {
        // L'arrivo col nome della meta.
        final meta = widget.gestore.destinazione;
        if (p.tipo == 'arrivo' && meta != null) {
          return widget.onPunto!(
            PuntoToccato(tipo: 'arrivo', nome: meta.nome, posizione: p.posizione, proprieta: p.proprieta),
          );
        }
        return widget.onPunto!(p);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Il tema (giorno o notte) arriva da qui.
    _notte = Theme.of(context).brightness == Brightness.dark;
    _regia.opzioni();
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
