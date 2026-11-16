import 'dart:async';

import 'package:flutter/foundation.dart';

import '../componenti/avviso_di_casa.dart';
import '../componenti/icone_punti.dart' show bollinoPng;

/// Gli avvisi di casa sullo schermo dell'auto: quello in vista nella coda
/// ([CodaAvvisiDiCasa]) va all'auto come `avviso_casa`, e dall'auto tornano i
/// tasti (`avviso_casa_tasto`).
///
/// Sull'auto l'avviso lo disegna il sistema: su Android Auto `Alert` con
/// `AppManager.showAlert` (API 5), su CarPlay `CPNavigationAlert`. Le regole
/// sono quelle dell'auto, più strette del telefono:
///
/// - al più **due tasti**; con uno solo, accanto «Chiudi»; senza, «Chiudi»;
/// - mai i tasti «da fermo» (quelli che vogliono il codice o aprono l'app):
///   l'auto non sa se si è fermi;
/// - un tasto con la domanda («Disinserire l'antifurto?») diventa un secondo
///   avviso «Sì / No»; il «Sì» passa poi dalle regole di chi ospita, come il
///   tasto della notifica sul telefono;
/// - l'urgente resta finché non lo si chiude ([secondi] `null`); gli altri
///   spariscono da soli, come sul telefono.
///
/// Quello che si manda (`{}` quando non c'è niente):
/// `{id, titolo, testo, urgente, importante, secondi, conferma, colore,
/// icona (PNG), tasti: [{id, etichetta, principale}]}`. Gli id dei tasti
/// «Chiudi» e «No» sono [chiudi] e [no].
class AvvisiDiCasaInAuto {
  AvvisiDiCasaInAuto(this.coda, this.manda);

  final CodaAvvisiDiCasa coda;
  final void Function(String metodo, Map<String, Object?> dati) manda;

  static const chiudi = '_chiudi';
  static const no = '_no';

  /// L'ultimo mandato, per non rimandare lo stesso a ogni novità.
  String? _firma;
  final _icone = <String, Uint8List>{};

  void avvia() {
    coda.addListener(_cambiata);
    _cambiata();
  }

  void ferma() => coda.removeListener(_cambiata);

  /// Quello da mandare adesso, senza l'icona. Pubblico per le prove.
  @visibleForTesting
  Map<String, Object?> adesso() {
    final a = coda.attuale;
    final g = coda.gruppo;
    if (a != null) {
      final (:icona, :colore) = aspettoDi(a);
      final domanda = coda.daConfermare;
      final tasti = a.tasti(inMovimento: true);
      return {
        'id': a.id,
        'titolo': domanda?.domanda ?? a.titolo,
        // Una riga corta: in auto si legge poco. Il nome della casa solo se
        // non c'è altro da dire.
        'testo': domanda != null ? a.titolo : (a.testo.isNotEmpty ? a.testo : a.casa ?? ''),
        'urgente': a.urgente,
        'importante': a.importante,
        'secondi': coda.tempo?.inSeconds,
        'conferma': domanda != null,
        'colore': colore.toARGB32(),
        'chiave_icona': '${a.categoria.name}/${a.sotto}',
        'codice_icona': icona.codePoint,
        'tasti': domanda != null
            ? [
                {'id': domanda.id, 'etichetta': 'Sì, ${_minuscola(domanda.etichetta)}', 'principale': true},
                {'id': no, 'etichetta': 'No', 'principale': false},
              ]
            : [
                for (final t in tasti) {'id': t.id, 'etichetta': t.etichetta, 'principale': t.principale},
                if (tasti.length < 2) {'id': chiudi, 'etichetta': 'Chiudi', 'principale': false},
              ],
      };
    }
    if (g != null) {
      return {
        'id': 'gruppo',
        'titolo': '${g.length} notifiche di casa',
        'testo': g.map((x) => x.titolo).join(' · '),
        'urgente': false,
        'importante': false,
        'secondi': coda.tempo?.inSeconds,
        'conferma': false,
        'colore': aspettoDi(g.first).colore.toARGB32(),
        'chiave_icona': 'gruppo',
        'codice_icona': aspettoDi(g.first).icona.codePoint,
        'tasti': [
          {'id': chiudi, 'etichetta': 'Chiudi tutte', 'principale': false},
        ],
      };
    }
    return const {};
  }

  void _cambiata() {
    final dati = adesso();
    final firma = '${dati['id']}|${dati['titolo']}|${dati['conferma']}|${dati['testo']}';
    if (firma == _firma) return;
    _firma = firma;
    if (dati.isEmpty) {
      manda('avviso_casa', const {});
      return;
    }
    unawaited(_conIcona(dati));
  }

  Future<void> _conIcona(Map<String, Object?> dati) async {
    final chiave = dati['chiave_icona'] as String;
    var png = _icone[chiave];
    if (png == null) {
      final a = coda.attuale ?? coda.gruppo?.first;
      try {
        if (a != null) {
          final (:icona, :colore) = aspettoDi(a);
          png = _icone[chiave] = await bollinoPng(colore, icona, lato: 32, glifo: 0.6);
        }
      } catch (_) {
        // Senza icona l'avviso va lo stesso.
      }
    }
    // Nel frattempo è cambiato: va quello nuovo, non questo.
    if (adesso()['id'] != dati['id']) return;
    manda('avviso_casa', {...dati, 'icona': ?png});
  }

  /// Un tasto toccato sull'auto. Vale solo per l'avviso ancora in vista, e
  /// solo se è un tasto che l'auto poteva mostrare.
  void tasto(String? id, String? tasto) {
    final a = coda.attuale;
    if (tasto == chiudi) {
      if (id == 'gruppo' ? coda.gruppo != null : a?.id == id) coda.chiudi();
      return;
    }
    if (a == null || a.id != id) return;
    if (tasto == no) {
      coda.annulla();
      return;
    }
    final domanda = coda.daConfermare;
    if (domanda != null) {
      if (domanda.id == tasto) coda.premi(domanda);
      return;
    }
    for (final t in a.tasti(inMovimento: true)) {
      if (t.id == tasto) {
        coda.premi(t);
        return;
      }
    }
  }

  static String _minuscola(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
