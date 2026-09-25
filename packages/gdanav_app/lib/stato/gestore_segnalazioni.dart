import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../servizi.dart';
import 'gestore_posizione.dart';
import '../risorse.dart';
import 'gestore_premium.dart';

/// Le segnalazioni della comunità intorno a te: si scaricano a ogni nuova
/// posizione, se sono passati due minuti o cinque chilometri; si aggiungono
/// col bottone giallo, si confermano passando.
class GestoreSegnalazioni extends ChangeNotifier {
  GestoreSegnalazioni({
    required this.posizione,
    ClienteSegnalazioni? cliente,
    bool? cablato,
    DateTime Function()? orologio,
    this.autovelox,
  }) : _ora = orologio ?? DateTime.now,
       cliente =
           cliente ??
           ((cablato ?? Servizi.segnalazioni.isNotEmpty)
               ? ClienteSegnalazioni(Uri.parse(Servizi.segnalazioni))
               : null) {
    // Premium cambia: gli autovelox compaiono o spariscono.
    GestorePremium.attivo.addListener(notifyListeners);
  }

  final GestorePosizione posizione;

  /// `null` finché il servizio non è pubblicato.
  final ClienteSegnalazioni? cliente;

  /// Gli autovelox fissi dentro l'app: ci sono anche senza rete.
  final Future<ArchivioAutovelox>? autovelox;

  final DateTime Function() _ora;

  /// Quelle della comunità e gli autovelox fissi, intorno a te.
  List<Segnalazione> get vicine => GestorePremium.attivo.value
      ? [..._comunita, ..._fisse]
      // Gli autovelox (fissi e segnalati) sono Premium.
      : [
          for (final s in _comunita)
            if (s.tipo != TipoSegnalazione.autovelox) s,
        ];
  var _comunita = <Segnalazione>[];
  var _fisse = <Segnalazione>[];
  var _avviato = false;
  Punto? _ultimaRichiesta;
  DateTime _ultimaVolta = DateTime(0);

  bool get attivo => cliente != null || autovelox != null;

  void avvia() {
    if (!attivo || _avviato) return;
    _avviato = true;
    posizione.addListener(_forse);
    _forse();
  }

  void _forse() {
    final qui = posizione.qui;
    if (qui == null) return;
    final u = _ultimaRichiesta;
    if (u == null || distanzaM(u, qui) > 5000 || _ora().difference(_ultimaVolta) > const Duration(minutes: 2)) {
      aggiorna();
    }
  }

  Future<void> aggiorna() async {
    final c = cliente, qui = posizione.qui;
    if (qui == null) return;
    _ultimaRichiesta = qui;
    _ultimaVolta = _ora();
    if (autovelox case final a?) {
      _fisse = (await a).vicini(qui, 30000);
      notifyListeners();
    }
    if (c == null) return;
    try {
      _comunita = await c.vicine(qui);
      notifyListeners();
    } catch (_) {
      // Senza rete si tengono quelle che si hanno.
    }
  }

  /// Segnala dove sei. Restituisce cosa dire a chi ha toccato.
  Future<String> segnala(TipoSegnalazione tipo) async {
    final c = cliente, qui = posizione.qui;
    if (c == null) return 'Le segnalazioni non sono ancora attive in questa versione.';
    if (qui == null) return 'Non so dove sei: attiva la posizione.';
    try {
      final s = await c.invia(tipo, qui);
      _comunita = [..._comunita, s];
      notifyListeners();
      return 'Grazie! ${tipo.nome} segnalato a chi arriva dopo di te.';
    } catch (e) {
      return 'Non è partita: ${'$e'.replaceFirst('Exception: ', '')}';
    }
  }

  Future<void> vota(Segnalazione s, {required bool ancora}) async {
    final c = cliente;
    if (c == null || s.fissa) return;
    try {
      final n = await c.vota(s, ancora: ancora);
      _comunita = [
        for (final v in _comunita)
          if (v.id != s.id) v else ?n,
      ];
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    posizione.removeListener(_forse);
    GestorePremium.attivo.removeListener(notifyListeners);
    cliente?.chiudi();
    super.dispose();
  }
}

/// Gli autovelox fissi dentro l'app: si leggono una volta, su un altro filo.
Future<ArchivioAutovelox> archivioAutovelox() => _autovelox ??= _leggiAutovelox();
Future<ArchivioAutovelox>? _autovelox;

Future<ArchivioAutovelox> _leggiAutovelox() async {
  try {
    final testo = await rootBundle.loadString('$radiceRisorse/autovelox.json');
    return await Isolate.run(() => ArchivioAutovelox.leggi(testo));
  } catch (e) {
    debugPrint('archivio autovelox: $e');
    return ArchivioAutovelox.vuoto;
  }
}
