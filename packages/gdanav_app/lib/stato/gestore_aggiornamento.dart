import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../servizi.dart';
import 'archivio.dart';

/// L'app gdanav sul Play Store: lo stesso `applicationId` di
/// `app/android/app/build.gradle.kts`.
const idPlayStore = 'it.gdanav.gdanav';

/// L'ID numerico di gdanav sull'App Store (App Store Connect → l'app →
/// Informazioni sull'app → Apple ID, per esempio `6740000000`). **Da
/// scrivere** quando l'app è pubblicata: finché è vuoto il bottone apre
/// solo l'App Store.
const idAppStoreGdanav = '';

/// Il negozio da aprire per aggiornare: prima l'indirizzo dell'app del
/// negozio, poi (se non si apre) quello del sito.
List<Uri> indirizziNegozio(TargetPlatform piattaforma) => piattaforma == TargetPlatform.iOS
    ? [
        if (idAppStoreGdanav.isNotEmpty) ...[
          Uri.parse('itms-apps://apps.apple.com/app/id$idAppStoreGdanav'),
          Uri.parse('https://apps.apple.com/app/id$idAppStoreGdanav'),
        ] else
          Uri.parse('itms-apps://apps.apple.com/'),
      ]
    : [
        Uri.parse('market://details?id=$idPlayStore'),
        Uri.parse('https://play.google.com/store/apps/details?id=$idPlayStore'),
      ];

/// Il freno di emergenza per le versioni vecchie: il relay dice qual è la
/// build più vecchia ancora buona (`GET /v1/versioni`), e se questa è più
/// vecchia l'app si ferma e chiede di aggiornarla. Serve il giorno in cui
/// partono i pagamenti: le build di prova, con Premium sbloccato, smettono
/// di funzionare (vedi `docs/architettura.md`).
///
/// Si chiede all'avvio, al ritorno in primo piano e ogni sei ore; l'ultima
/// risposta si ricorda, così senza rete non si sblocca niente. Non si
/// blocca mai una build fatta a mano ([Servizi.costruzione] 0) né una di
/// debug. Dentro gdahome non c'è: vedi [GestoreAggiornamento.per].
class GestoreAggiornamento extends ChangeNotifier {
  GestoreAggiornamento({
    required this.archivio,
    http.Client? client,
    Uri? indirizzo,
    int? costruzione,
    bool? debug,
    this.ogni = const Duration(hours: 6),
    this.attesa = const Duration(seconds: 15),
    this.pausaMinima = const Duration(minutes: 10),
    DateTime Function()? orologio,
  }) : _client = client ?? http.Client(),
       indirizzo = indirizzo ?? Servizi.versioni,
       costruzione = costruzione ?? Servizi.costruzione,
       debug = debug ?? kDebugMode,
       _ora = orologio ?? DateTime.now;

  /// Solo per gdanav da sola: dentro un'altra app (gdahome, che passa
  /// [premiumOspite], [gdahome] o [senzaPremium] a `preparaGdanav`) il
  /// controllo lo fa lei, e qui non si chiede niente.
  static GestoreAggiornamento? per({
    required Archivio archivio,
    ValueListenable<bool>? premiumOspite,
    Object? gdahome,
    bool senzaPremium = false,
    http.Client? client,
    int? costruzione,
    bool? debug,
  }) => premiumOspite != null || gdahome != null || senzaPremium
      ? null
      : GestoreAggiornamento(archivio: archivio, client: client, costruzione: costruzione, debug: debug);

  final Archivio archivio;
  final http.Client _client;
  final Uri indirizzo;

  /// Il numero di questa build.
  final int costruzione;
  final bool debug;
  final Duration ogni;
  final Duration attesa;

  /// Tornando in primo piano spesso non si chiede ogni volta.
  final Duration pausaMinima;
  final DateTime Function() _ora;

  Timer? _timer;
  AppLifecycleListener? _vita;
  DateTime? _ultimaDomanda;
  var _minima = 0;

  /// L'ultima versione minima nota (0: nessuna).
  int get minima => _minima;

  /// Questa versione è troppo vecchia: va aggiornata.
  bool get daAggiornare => costruzione > 0 && !debug && costruzione < _minima;

  /// Legge l'ultima risposta salvata: il blocco vale subito, anche senza rete.
  Future<void> carica() async {
    _cambia(await archivio.versioneMinima());
  }

  /// Carica, chiede subito e poi ogni [ogni] e al ritorno in primo piano.
  Future<void> avvia() async {
    await carica();
    unawaited(controlla());
    _timer ??= Timer.periodic(ogni, (_) => controlla());
    _vita ??= AppLifecycleListener(
      onResume: () {
        final u = _ultimaDomanda;
        if (u == null || _ora().difference(u) >= pausaMinima) unawaited(controlla());
      },
    );
  }

  /// Chiede al relay la versione minima. Senza rete, o con una risposta
  /// strana, resta quella di prima.
  Future<void> controlla() async {
    _ultimaDomanda = _ora();
    try {
      final r = await _client.get(indirizzo).timeout(attesa);
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body);
      final n = j is Map ? (j['gdanav'] is Map ? j['gdanav']['minima'] : null) : null;
      if (n is! int || n < 0) return;
      if (n != _minima) await archivio.salvaVersioneMinima(n);
      _cambia(n);
    } catch (_) {
      // Niente rete: si tiene l'ultima risposta.
    }
  }

  void _cambia(int n) {
    if (n == _minima) return;
    _minima = n;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _vita?.dispose();
    _client.close();
    super.dispose();
  }
}
