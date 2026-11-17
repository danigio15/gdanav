import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Color, IconData;

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
/// - l'urgente resta finché non lo si chiude (`secondi` `null`), e ha sempre
///   un modo di chiuderlo: con due tasti che fanno qualcosa, il secondo
///   lascia il posto a «Chiudi»; gli altri spariscono da soli, come sul
///   telefono (`secondi` è il tempo che resta, non quello intero);
/// - l'auto tiene anche l'urgente e la domanda per un tempo suo: quando li
///   toglie da sola, o non riesce a mostrarli, lo dice col tasto finto
///   [scaduto]. L'urgente allora si mette da parte
///   ([CodaAvvisiDiCasa.mettiDaParte]: sull'auto non torna e non tiene fermi
///   quelli dopo, sul telefono resta), la domanda torna all'avviso.
///
/// Quello che si manda (`{}` quando non c'è niente):
/// `{id, titolo, testo, urgente, importante, secondi, conferma, colore,
/// icona (PNG), tasti: [{id, etichetta, principale}]}`. Gli id dei tasti
/// «Chiudi» e «No» sono [chiudi] e [no].
class AvvisiDiCasaInAuto {
  AvvisiDiCasaInAuto(this.coda, this.manda, {Future<Uint8List> Function(Color colore, IconData icona)? disegna})
    : _disegna = disegna ?? _bollino;

  final CodaAvvisiDiCasa coda;
  final void Function(String metodo, Map<String, Object?> dati) manda;

  /// Come si disegna l'icona (nelle prove, una che non finisce mai).
  final Future<Uint8List> Function(Color colore, IconData icona) _disegna;

  static Future<Uint8List> _bollino(Color colore, IconData icona) => bollinoPng(colore, icona, lato: 32, glifo: 0.6);

  static const chiudi = '_chiudi';
  static const no = '_no';

  /// Il tasto finto con cui l'auto dice che l'avviso se n'è andato da solo
  /// dal suo schermo (`avviso_casa_tasto` con `tasto: '_scaduto'`, e
  /// `conferma` se era la domanda).
  static const scaduto = '_scaduto';

  /// Quanto si aspetta il disegno dell'icona prima di mandare l'avviso
  /// senza: col telefono bloccato il disegno può restare in attesa finché
  /// non lo si sblocca, e l'avviso arriverebbe scaduto.
  static const attesaIcona = Duration(milliseconds: 400);

  /// L'ultimo mandato, per non rimandare lo stesso a ogni novità.
  String? _firma;
  final _icone = <String, Uint8List>{};

  /// Le icone che si stanno disegnando, per non cominciarne due uguali.
  final _inDisegno = <String, Future<Uint8List?>>{};
  var _attivo = false;

  void avvia() {
    _attivo = true;
    coda.addListener(_cambiata);
    _cambiata();
    unawaited(_preparaLeIcone());
  }

  void ferma() {
    _attivo = false;
    coda.removeListener(_cambiata);
  }

  /// Lo schermo dell'auto si è acceso o spento. A fine sessione l'auto
  /// dimentica l'avviso che teneva: alla prossima gli si rimanda quello di
  /// allora, se c'è, anche se è lo stesso di prima.
  void schermo(bool acceso) {
    _firma = null;
    if (acceso) _cambiata();
  }

  /// Le cose precise di ogni categoria che hanno un'icona loro
  /// ([aspettoPer]): si disegnano all'avvio, con l'app davanti.
  static const _sotto = <CategoriaAvvisoDiCasa, List<String>>{
    CategoriaAvvisoDiCasa.elettrodomestici: ['lavatrice', 'asciugatrice', 'lavastoviglie', 'forno', 'frigo'],
    CategoriaAvvisoDiCasa.antifurto: ['inserito', 'disinserito', 'allarme', 'movimento'],
    CategoriaAvvisoDiCasa.aperture: ['porta', 'finestra', 'cancello', 'garage'],
    CategoriaAvvisoDiCasa.persone: ['arrivo', 'uscita'],
    CategoriaAvvisoDiCasa.energia: ['auto', 'sole', 'rete'],
    CategoriaAvvisoDiCasa.clima: ['fresco'],
    CategoriaAvvisoDiCasa.meteo: ['pioggia', 'allerta'],
    CategoriaAvvisoDiCasa.sicurezza: ['fumo', 'acqua', 'gas'],
  };

  /// Le icone delle categorie, pronte prima che servano: quando arriva
  /// l'avviso (magari col telefono bloccato) non c'è niente da disegnare.
  /// Una alla volta, senza fretta; se il disegno non riesce (nessuno
  /// schermo) ci si ferma alla prima.
  Future<void> _preparaLeIcone() async {
    for (final c in CategoriaAvvisoDiCasa.values) {
      for (final sotto in <String?>[null, ...?_sotto[c]]) {
        if (!_attivo) return;
        final (:icona, :colore) = aspettoPer(c, sotto);
        if (await _disegnata('${c.name}/$sotto', colore, icona) == null) return;
      }
    }
  }

  /// L'icona di [chiave], dalla memoria o disegnata adesso (una volta sola,
  /// anche se la chiedono in due); `null` se il disegno non riesce.
  Future<Uint8List?> _disegnata(String chiave, Color colore, IconData icona) {
    if (_icone[chiave] case final pronta?) return Future.value(pronta);
    if (_inDisegno[chiave] case final inCorso?) return inCorso;
    final nuova = () async {
      try {
        return _icone[chiave] = await _disegna(colore, icona);
      } catch (_) {
        // Senza icona l'avviso va lo stesso.
        return null;
      }
    }();
    _inDisegno[chiave] = nuova;
    unawaited(nuova.whenComplete(() => _inDisegno.remove(chiave)));
    return nuova;
  }

  /// L'icona per un avviso che deve partire: quella pronta, o quella che
  /// arriva entro [attesaIcona]; se no `null`, e l'avviso va senza (quando
  /// poi arriva, resta per la volta dopo).
  Future<Uint8List?> _icona(String chiave, Color colore, IconData icona) =>
      _disegnata(chiave, colore, icona).timeout(attesaIcona, onTimeout: () => null);

  /// Quello da mandare adesso, senza l'icona. Pubblico per le prove.
  @visibleForTesting
  Map<String, Object?> adesso() {
    final g = coda.gruppo;
    // Un urgente messo da parte sull'auto non torna: resta sul telefono.
    final a = switch (coda.attuale) {
      final x? when !coda.daParte(x.id) => x,
      _ => null,
    };
    if (a != null) {
      final (:icona, :colore) = aspettoDi(a);
      final domanda = coda.daConfermare;
      var tasti = a.tasti(inMovimento: true);
      // L'urgente non se ne va da solo: sull'auto ha sempre un modo di
      // chiuderlo. Con due tasti che fanno qualcosa resta il primo, e
      // accanto «Chiudi».
      if (coda.tempo == null && tasti.length == 2 && !tasti.any((t) => t.innocuo)) tasti = [tasti.first];
      return {
        'id': a.id,
        'titolo': domanda?.domanda ?? a.titolo,
        // Una riga corta: in auto si legge poco. Il nome della casa solo se
        // non c'è altro da dire.
        'testo': domanda != null ? a.titolo : (a.testo.isNotEmpty ? a.testo : a.casa ?? ''),
        'urgente': a.urgente,
        'importante': a.importante,
        'secondi': _secondi(),
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
        'secondi': _secondi(),
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

  /// I secondi che restano a quello in vista (in su: l'auto non lo toglie
  /// prima del telefono); `null`: finché non lo si chiude.
  int? _secondi() => switch (coda.resta) {
    final r? => (r.inMilliseconds / 1000).ceil(),
    _ => null,
  };

  static String _firmaDi(Map<String, Object?> dati) =>
      '${dati['id']}|${dati['titolo']}|${dati['conferma']}|${dati['testo']}';

  void _cambiata() {
    final dati = adesso();
    final firma = _firmaDi(dati);
    if (firma == _firma) return;
    _firma = firma;
    if (dati.isEmpty) {
      manda('avviso_casa', const {});
      return;
    }
    unawaited(_conIcona(dati));
  }

  Future<void> _conIcona(Map<String, Object?> dati) async {
    final a = coda.attuale ?? coda.gruppo?.first;
    Uint8List? png;
    if (a != null) {
      final (:icona, :colore) = aspettoDi(a);
      // Al più [attesaIcona]: poi l'avviso parte senza.
      png = await _icona(dati['chiave_icona'] as String, colore, icona);
    }
    // Nel frattempo è cambiato: va quello nuovo, non questo.
    if (!_attivo || _firmaDi(adesso()) != _firmaDi(dati)) return;
    manda('avviso_casa', {...dati, 'icona': ?png});
  }

  /// Un tasto toccato sull'auto. Vale solo per l'avviso ancora in vista, e
  /// solo se è un tasto che l'auto poteva mostrare. [conferma]: con
  /// [scaduto], se l'auto parla della domanda «Sì / No» (`null`: un'auto che
  /// non lo dice).
  void tasto(String? id, String? tasto, {bool? conferma}) {
    final a = coda.attuale;
    if (tasto == scaduto) {
      // L'auto l'ha tolto da sola. Chi ha un tempo suo se ne va col tempo
      // del telefono; chi non ce l'ha non deve tenere fermi quelli dopo.
      if (a == null || a.id != id || coda.daParte(a.id)) return;
      final domanda = coda.daConfermare != null;
      if (conferma != null && conferma != domanda) return;
      if (domanda) {
        coda.annulla();
      } else if (coda.tempo == null) {
        coda.mettiDaParte(a.id);
      }
      return;
    }
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
