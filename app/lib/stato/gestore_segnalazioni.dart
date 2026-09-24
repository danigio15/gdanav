import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../servizi.dart';
import 'gestore_posizione.dart';

/// Le segnalazioni della comunità intorno a te: si scaricano a ogni nuova
/// posizione, se sono passati due minuti o cinque chilometri; si aggiungono
/// col bottone giallo, si confermano passando.
class GestoreSegnalazioni extends ChangeNotifier {
  GestoreSegnalazioni({
    required this.posizione,
    ClienteSegnalazioni? cliente,
    bool? cablato,
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now,
       cliente =
           cliente ??
           ((cablato ?? Servizi.segnalazioni.isNotEmpty) ? ClienteSegnalazioni(Uri.parse(Servizi.segnalazioni)) : null);

  final GestorePosizione posizione;

  /// `null` finché il servizio non è pubblicato.
  final ClienteSegnalazioni? cliente;

  final DateTime Function() _ora;
  var vicine = <Segnalazione>[];
  var _avviato = false;
  Punto? _ultimaRichiesta;
  DateTime _ultimaVolta = DateTime(0);

  bool get attivo => cliente != null;

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
    if (c == null || qui == null) return;
    _ultimaRichiesta = qui;
    _ultimaVolta = _ora();
    try {
      vicine = await c.vicine(qui);
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
      vicine = [...vicine, s];
      notifyListeners();
      return 'Grazie! ${tipo.nome} segnalato a chi arriva dopo di te.';
    } catch (e) {
      return 'Non è partita: ${'$e'.replaceFirst('Exception: ', '')}';
    }
  }

  Future<void> vota(Segnalazione s, {required bool ancora}) async {
    final c = cliente;
    if (c == null) return;
    try {
      final n = await c.vota(s, ancora: ancora);
      vicine = [
        for (final v in vicine)
          if (v.id != s.id) v else ?n,
      ];
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    posizione.removeListener(_forse);
    cliente?.chiudi();
    super.dispose();
  }
}
