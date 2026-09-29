import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/dati_viaggio.dart';
import 'archivio.dart';
import 'distributori.dart';
import 'gestore_auto.dart';
import 'gestore_posizione.dart';
import 'gestore_viaggio.dart';

/// Quello che c'è intorno a te, sulla mappa: i distributori coi prezzi se
/// l'auto è termica, le colonnine adatte se è elettrica. Si ricerca
/// quando ci si sposta di un paio di chilometri o si cambia auto.
class GestoreVicini extends ChangeNotifier {
  GestoreVicini({
    required this.auto,
    required this.posizione,
    Archivio? archivio,
    Future<List<Distributore>> Function(Punto qui)? distributori,
    Future<List<Colonnina>> Function(Punto qui, ProfiloVeicolo v)? colonnine,
    Future<List<Colonnina>> Function(ProfiloVeicolo v)? tutte,
    Future<Colonnina> Function(Colonnina c)? statoAdesso,
    Future<Map<String, String>> Function()? statiDiTutti,
    Future<bool> Function()? evseInOrdine,
    this.ogniQuanto = const Duration(minutes: 10),
  }) : _statoAdesso = statoAdesso ?? statoColonninaAdesso,
       _statiDiTutti = statiDiTutti ?? statiDiTuttaItalia,
       _evseInOrdine = evseInOrdine ?? (() async => (await archivioColonnine()).evseInOrdine),
       _cercaTutte = tutte ?? ((v) => colonnineDellArchivioComeSiVuole(v, archivio ?? Archivio())),
       _cercaDistributori = distributori ?? distributoriVicini,
       /* Con la scelta fatta in «Ricarica»: gli operatori che non si vogliono
        * vedere non si vedono nemmeno qui intorno. */
       _cercaColonnine =
           colonnine ?? ((q, v) => colonnineVicineComeSiVuole(q, v, archivio ?? Archivio(), km: 12, quante: 25)) {
    auto.addListener(_forse);
    auto.addListener(_forseTutte);
    posizione.addListener(_forse);
    Archivio.preferenzeCambiate.addListener(_sceltaCambiata);
    _forse();
  }

  final GestoreAuto auto;
  final GestorePosizione posizione;
  final Future<List<Distributore>> Function(Punto qui) _cercaDistributori;
  final Future<List<Colonnina>> Function(Punto qui, ProfiloVeicolo v) _cercaColonnine;
  final Future<Colonnina> Function(Colonnina c) _statoAdesso;
  final Future<List<Colonnina>> Function(ProfiloVeicolo v) _cercaTutte;
  final Future<Map<String, String>> Function() _statiDiTutti;
  final Future<bool> Function() _evseInOrdine;

  /// Ogni quanto, con l'app davanti, si rilegge lo stato di tutta Italia per
  /// la mappa (zero: mai da sé). Una lettura sono sette richieste e quasi
  /// nove megabyte: con l'app dietro, o solo sull'auto, non si rilegge.
  final Duration ogniQuanto;

  List<Distributore> distributori = const [];
  List<Colonnina> colonnine = const [];

  /// Le colonnine di tutta la mappa, dall'archivio dentro l'app: quelle
  /// adatte all'auto, anche le lente, tolti gli operatori spenti in
  /// «Ricarica». Sono decine di migliaia:
  /// si rifanno solo quando cambia l'auto o la scelta, e la mappa le
  /// raggruppa da sé quando si guarda da lontano. Partono quando le chiede
  /// la mappa ([avviaTutte]): chi non ha la mappa non le carica.
  List<Colonnina> tutte = const [];

  /// Cresce a ogni elenco nuovo: la mappa rimanda i dati solo quando cambia.
  int versioneTutte = 0;
  Map<String, Colonnina> _perId = const {};
  var _tutteAvviate = false;
  (bool, String)? _tuttePer;
  var _giroTutte = 0;

  /// Le colonnine di tutta la mappa come le dà l'archivio, senza stato. Lo
  /// stato di tutta Italia si mette sempre su queste: così uno vecchio non
  /// resta attaccato a un punto che nella lettura nuova non c'è.
  List<Colonnina> _tutteDallArchivio = const [];

  /// L'ultimo stato di tutta Italia (EVSE ID → parola della PUN) e quando è
  /// arrivato.
  Map<String, String> _stati = const {};
  var _statiInOrdine = false;
  DateTime? statiLetti;
  Timer? _ogniTanto;
  AppLifecycleListener? _vita;

  void avviaTutte() {
    if (_tutteAvviate) return;
    _tutteAvviate = true;
    _forseTutte();
    // «Voglio lo stato di tutte sempre»: finché l'app è davanti si rilegge,
    // e tornando davanti dopo un po' si rilegge subito.
    if (ogniQuanto > Duration.zero) {
      _ogniTanto = Timer.periodic(ogniQuanto, (_) {
        if (_davanti) unawaited(aggiornaStati());
      });
    }
    _vita = AppLifecycleListener(
      onResume: () {
        final l = statiLetti;
        if (l == null || DateTime.now().difference(l) >= ogniQuanto) unawaited(aggiornaStati());
      },
    );
  }

  static bool get _davanti {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  void _forseTutte() {
    if (!_tutteAvviate || (auto.elettrica, auto.veicolo.id) == _tuttePer) return;
    unawaited(_rifaiTutte());
  }

  /// Cambiata una scelta in «Ricarica»: si rifà tutto subito, invece di
  /// aspettare il prossimo spostamento di due chilometri.
  void _sceltaCambiata() {
    _cercatoDa = null;
    _forse();
    if (_tutteAvviate) unawaited(_rifaiTutte());
  }

  Future<void> _rifaiTutte() async {
    final giro = ++_giroTutte;
    _tuttePer = (auto.elettrica, auto.veicolo.id);
    try {
      final elenco = auto.elettrica ? await _cercaTutte(auto.veicolo) : const <Colonnina>[];
      // Ne è partito un altro nel frattempo: vale quello.
      if (giro != _giroTutte) return;
      _tutteDallArchivio = elenco;
      _metti();
      notifyListeners();
      if (elenco.isNotEmpty) unawaited(aggiornaStati());
    } catch (e) {
      if (giro == _giroTutte) _tuttePer = null;
      debugPrint('tutte le colonnine: $e');
    }
  }

  /// Lo stato di tutta Italia sulle colonnine della mappa: libere, piene,
  /// guaste. Una lettura vale qualche minuto, e chi la chiede nel frattempo
  /// — il percorso — trova la stessa. Senza Premium, o se la PUN non
  /// risponde, la mappa resta com'era.
  Future<void> aggiornaStati() async {
    if (!_tutteAvviate || _tutteDallArchivio.isEmpty) return;
    final giro = _giroTutte;
    try {
      final stati = await _statiDiTutti();
      if (stati.isEmpty || giro != _giroTutte) return;
      final inOrdine = await _evseInOrdine();
      if (giro != _giroTutte) return;
      _stati = stati;
      _statiInOrdine = inOrdine;
      statiLetti = DateTime.now();
      _metti();
      colonnine = [for (final c in colonnine) _conStati(c)];
      notifyListeners();
    } catch (e) {
      debugPrint('stato di tutta Italia: $e');
    }
  }

  void _metti() {
    tutte = _stati.isEmpty
        ? _tutteDallArchivio
        : [for (final c in _tutteDallArchivio) DisponibilitaPun.conStati(c, _stati, inOrdine: _statiInOrdine)];
    _perId = {for (final c in tutte) c.id: c};
    versioneTutte++;
  }

  /// Una colonnina intorno a te con lo stato di tutta Italia, se non ne ha
  /// già uno chiesto per lei: quello è più fresco.
  Colonnina _conStati(Colonnina c) => _stati.isEmpty || c.connettori.any((p) => p.stato != StatoPresa.sconosciuto)
      ? c
      : DisponibilitaPun.conStati(c, _stati, inOrdine: _statiInOrdine);

  /// Dove e per che auto si è cercato l'ultima volta.
  Punto? _cercatoDa;
  (bool, String, Carburante)? _perAuto;
  var _cercando = false;

  void _forse() {
    final qui = posizione.qui;
    if (qui == null || _cercando) return;
    final perAuto = (auto.elettrica, auto.veicolo.id, auto.carburante);
    final lontano = _cercatoDa == null || distanzaM(_cercatoDa!, qui) > 2000;
    if (!lontano && perAuto == _perAuto) return;
    unawaited(_cerca(qui, perAuto));
  }

  Future<void> _cerca(Punto qui, (bool, String, Carburante) perAuto) async {
    _cercando = true;
    _cercatoDa = qui;
    _perAuto = perAuto;
    try {
      if (auto.elettrica) {
        colonnine = [for (final c in await _cercaColonnine(qui, auto.veicolo)) _conStati(c)];
        distributori = const [];
      } else {
        distributori = await _cercaDistributori(qui);
        colonnine = const [];
      }
      notifyListeners();
    } catch (e) {
      // Senza rete si riprova al prossimo spostamento.
      _cercatoDa = null;
      debugPrint('vicini: $e');
    } finally {
      _cercando = false;
    }
  }

  Distributore? distributore(String id) => distributori.where((d) => d.id == id).firstOrNull;
  /// Una colonnina intorno a te, o una qualunque di tutta la mappa.
  Colonnina? colonnina(String id) => colonnine.where((c) => c.id == id).firstOrNull ?? _perId[id];

  /// Libere e occupate adesso per la colonnina toccata: quello della ricerca
  /// può avere qualche minuto.
  Future<Colonnina?> statoAdesso(String id) async {
    final c = colonnina(id);
    if (c == null) return null;
    try {
      final nuova = await _statoAdesso(c);
      colonnine = [for (final x in colonnine) x.id == id ? nuova : x];
      /* Una toccata sulla mappa di tutta Italia, lontana da qui, non è fra
       * quelle intorno: lo stato si metteva solo lì, e la scheda — che la
       * ritrova in [colonnina] — continuava a leggere quella dell'archivio,
       * senza libere e occupate. */
      if (_perId.containsKey(id)) _perId[id] = nuova;
      notifyListeners();
      return nuova;
    } catch (e) {
      debugPrint('stato colonnina: $e');
      return c;
    }
  }

  /// Le due sorgenti della mappa, in GeoJSON.
  Map<String, Map<String, Object?>> dati() => {
    'gdanav-distributori': datiDistributori(distributori, auto.carburante),
    'gdanav-vicine': datiColonnineVicine(colonnine, auto.veicolo.connettori),
  };

  /// Tutte le colonnine della mappa, in GeoJSON. A parte da [dati]: sono
  /// megabyte, e si mandano solo quando [versioneTutte] cambia — non a ogni
  /// spostamento, e non allo schermo dell'auto.
  Map<String, Object?> datiTutte() => datiColonnineTutte(tutte, auto.veicolo.connettori);

  @override
  void dispose() {
    _ogniTanto?.cancel();
    _vita?.dispose();
    auto.removeListener(_forse);
    auto.removeListener(_forseTutte);
    posizione.removeListener(_forse);
    Archivio.preferenzeCambiate.removeListener(_sceltaCambiata);
    super.dispose();
  }
}
