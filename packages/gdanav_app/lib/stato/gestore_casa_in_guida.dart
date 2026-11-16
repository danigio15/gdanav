import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../componenti/avviso_di_casa.dart';
import '../componenti/mini_lettore.dart';
import 'archivio.dart';

/// La casa e la musica mentre si guida: gli avvisi di casa (le notifiche di
/// GdAHome) e il lettore musicale, con le loro due scelte nelle impostazioni.
///
/// - **Gli avvisi** arrivano da chi ospita GdANav come notifiche già aperte
///   ([notifiche], le stesse che il postino di GdAHome mostra sul telefono:
///   quindi già filtrate dalle preferenze delle notifiche della casa). Qui si
///   tengono solo **in guida**, e solo se «Avvisi di casa durante la guida» è
///   acceso ([scelta]); finita la guida la coda si svuota (restano sul
///   telefono). Un tasto premuto torna a chi ospita ([onAzione]), che lo
///   esegue come un tasto della notifica: passa dalle sue regole (il
///   lucchetto, la casa giusta), qui non si scavalca niente.
/// - **La musica**: il [lettore] (di solito [LettoreDelTelefono]) si accende
///   solo con «Musica nel navigatore» accesa ([musica]). Senza il permesso, il
///   riquadro in guida propone l'invito una volta sola ([invitoDaMostrare]).
class GestoreCasaInGuida extends ChangeNotifier {
  GestoreCasaInGuida({
    required this.archivio,
    Stream<Map<String, Object?>>? notifiche,
    this.onAzione,
    this.lettore,
    bool Function()? inGuida,
    this._guida,
    void Function(String frase)? voce,
    CodaAvvisiDiCasa? coda,
  }) : coda = notifiche == null && coda == null ? null : (coda ?? CodaAvvisiDiCasa(onVoce: voce)),
       _inGuida = inGuida ?? _sempre {
    final c = this.coda;
    if (c != null) {
      c.onAzione = _azione;
      _ascolto = notifiche?.listen(arrivata);
    }
    _guida?.addListener(_guidaCambiata);
  }

  static bool _sempre() => true;

  final Archivio archivio;

  /// La coda degli avvisi; `null` se chi ospita non manda notifiche (GdANav
  /// da sola): allora nelle impostazioni la voce non c'è.
  final CodaAvvisiDiCasa? coda;

  /// Il tasto premuto su un avviso: la notifica com'era arrivata e l'id del
  /// tasto. Lo esegue chi ospita.
  final void Function(Map<String, Object?> notifica, String tasto)? onAzione;

  /// Il lettore della musica; `null` dove non ce n'è (il web, le prove).
  final LettoreMusicale? lettore;

  final bool Function() _inGuida;
  final Listenable? _guida;
  StreamSubscription<Map<String, Object?>>? _ascolto;

  /// Le notifiche com'erano arrivate, per id: servono a [onAzione].
  final _buste = <String, Map<String, Object?>>{};

  SceltaAvvisiDiCasa _scelta = const SceltaAvvisiDiCasa();
  bool _musica = true;
  bool _invitoVisto = false;
  bool _caricato = false;

  /// Quali avvisi di casa passano in guida. «Avvisi di casa durante la
  /// guida» spento è [NotificheNelNavigatore.nessuna].
  SceltaAvvisiDiCasa get scelta => _scelta;

  /// L'interruttore «Avvisi di casa durante la guida».
  bool get avvisiAccesi => _scelta.modo != NotificheNelNavigatore.nessuna;

  /// L'interruttore «Musica nel navigatore».
  bool get musica => _musica;

  /// Il lettore da mostrare in guida: c'è, e la musica è accesa.
  LettoreMusicale? get lettoreInGuida => _musica ? lettore : null;

  /// Se in guida va proposto l'invito per il permesso della musica: una
  /// volta sola.
  bool get invitoDaMostrare => _musica && !_invitoVisto && lettore != null && !lettore!.permesso;

  /// Legge le scelte salvate e accende la musica se va.
  Future<void> carica() async {
    try {
      final grezzo = await archivio.avvisiDiCasa();
      _scelta = grezzo == null ? const SceltaAvvisiDiCasa() : SceltaAvvisiDiCasa.leggi(jsonDecode(grezzo));
      _musica = await archivio.musicaNelNavigatore();
      _invitoVisto = await archivio.invitoMusicaVisto();
    } catch (_) {
      // Un portachiavi che non risponde: le scelte di serie.
    }
    _caricato = true;
    coda?.scelta = _scelta;
    await lettore?.accendi(_musica);
    notifyListeners();
  }

  /// Una notifica arrivata da chi ospita. Fuori dalla guida, o con gli
  /// avvisi spenti, non si tiene: resta sul telefono come sempre.
  void arrivata(Map<String, Object?> notifica) {
    final c = coda;
    if (c == null || !_inGuida() || !avvisiAccesi) return;
    final casa = notifica['_casa'];
    final a = AvvisoDiCasa.daNotifica(notifica, casa: casa is String && casa.isNotEmpty ? casa : null);
    if (a == null) return;
    // Al più una ventina in memoria: le più vecchie non servono più.
    if (_buste.length > 20) _buste.remove(_buste.keys.first);
    _buste[a.id] = notifica;
    c.aggiungi(a);
  }

  void _azione(AvvisoDiCasa avviso, AzioneAvvisoDiCasa azione) {
    final busta = _buste[avviso.id];
    if (busta != null) onAzione?.call(busta, azione.id);
  }

  void _guidaCambiata() {
    if (!_inGuida()) {
      coda?.svuota();
      _buste.clear();
    }
  }

  /// Cambia quali avvisi passano (le impostazioni).
  Future<void> cambiaScelta(SceltaAvvisiDiCasa s) async {
    _scelta = s;
    coda?.scelta = s;
    notifyListeners();
    try {
      await archivio.salvaAvvisiDiCasa(jsonEncode(s.inJson()));
    } catch (_) {
      // Vale fino alla prossima apertura.
    }
  }

  /// L'interruttore «Avvisi di casa durante la guida»: riacceso, tornano le
  /// categorie scelte prima.
  Future<void> accendiAvvisi(bool si) => cambiaScelta(
    si
        ? _scelta.conModo(_scelta.spente.isEmpty ? NotificheNelNavigatore.tutte : NotificheNelNavigatore.scelte)
        : _scelta.conModo(NotificheNelNavigatore.nessuna),
  );

  /// L'interruttore «Musica nel navigatore».
  Future<void> cambiaMusica(bool si) async {
    _musica = si;
    notifyListeners();
    await lettore?.accendi(si);
    try {
      await archivio.salvaMusicaNelNavigatore(si);
    } catch (_) {}
  }

  /// L'invito si è visto (o toccato): non torna più.
  void segnaInvitoVisto() {
    if (_invitoVisto) return;
    _invitoVisto = true;
    notifyListeners();
    unawaited(archivio.salvaInvitoMusicaVisto().catchError((Object _) {}));
  }

  /// Se le scelte sono già state lette (per le prove).
  @visibleForTesting
  bool get caricato => _caricato;

  @override
  void dispose() {
    unawaited(_ascolto?.cancel());
    _guida?.removeListener(_guidaCambiata);
    coda?.dispose();
    super.dispose();
  }
}
