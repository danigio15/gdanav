import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../componenti/avviso_di_casa.dart';
import '../componenti/mini_lettore.dart';
import 'archivio.dart';

/// La casa e la musica nel navigatore: gli avvisi di casa (le notifiche di
/// GdAHome) e il lettore musicale, con le loro due scelte nelle impostazioni.
///
/// - **Gli avvisi** arrivano da chi ospita GdANav come notifiche già aperte
///   ([notifiche], le stesse che il postino di GdAHome mostra sul telefono:
///   quindi già filtrate dalle preferenze delle notifiche della casa). Qui si
///   tengono **mentre il navigatore è in uso** ([inUso]): in guida, con lo
///   schermo dell'auto acceso anche senza percorso ([schermoDellAuto]: la
///   mappa libera di Android Auto e CarPlay), o con la mappa del telefono in
///   vista ([mappaInVista]); e solo se «Avvisi di casa durante la guida» è
///   acceso ([scelta]). Quando il navigatore non è più in uso la coda si
///   svuota (restano sul telefono). A voce solo in guida o in auto: a mappa
///   libera sul telefono basta la scheda. Un tasto premuto torna a chi
///   ospita ([onAzione]), che lo esegue come un tasto della notifica: passa
///   dalle sue regole (il lucchetto, la casa giusta), qui non si scavalca
///   niente.
/// - **La musica**: il [lettore] (di solito [LettoreDelTelefono]) si accende
///   solo con «Musica nel navigatore» accesa ([musica]), in guida e a mappa
///   libera. Senza il permesso, da fermi, l'invito una volta sola
///   ([invitoDaMostrare]).
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
      // A voce solo in guida o in auto: col telefono in mano, a mappa
      // libera, la scheda basta.
      if (c.onVoce case final v?) {
        c.onVoce = (frase) {
          if (_inGuida() || _inAuto) v(frase);
        };
      }
    }
    _guida?.addListener(_usoCambiato);
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
  bool _inAuto = false;
  bool _mappaInVista = false;

  /// Se il navigatore è in uso: in guida, con lo schermo dell'auto acceso
  /// (anche a mappa libera), o con la mappa del telefono davanti.
  bool get inUso => _inGuida() || _inAuto || _mappaInVista;

  /// Lo schermo di Android Auto o di CarPlay si è acceso o spento (`in_auto`
  /// dal ponte): acceso, gli avvisi passano anche senza un percorso.
  ///
  /// Spento, se il navigatore non è più in uso (né guida, né mappa del
  /// telefono davanti) la coda si svuota: quello che era lì solo per l'auto
  /// non aspetta il viaggio dopo. Acceso, gli urgenti rimasti da troppo se
  /// ne vanno ([CodaAvvisiDiCasa.scartaVecchi]).
  void schermoDellAuto(bool acceso) {
    if (acceso == _inAuto) return;
    _inAuto = acceso;
    _usoCambiato();
  }

  /// La mappa del telefono è **davvero** davanti o no: l'app in primo piano
  /// e la sezione del navigatore in vista. Lo dice la schermata principale;
  /// dentro un'altra app (GdAHome) la mappa resta montata anche quando si
  /// guarda un'altra sezione, e lì non è in vista.
  void mappaInVista(bool si) {
    if (si == _mappaInVista) return;
    _mappaInVista = si;
    _usoCambiato();
  }

  /// Quali avvisi di casa passano in guida. «Avvisi di casa durante la
  /// guida» spento è [NotificheNelNavigatore.nessuna].
  SceltaAvvisiDiCasa get scelta => _scelta;

  /// L'interruttore «Avvisi di casa durante la guida».
  bool get avvisiAccesi => _scelta.modo != NotificheNelNavigatore.nessuna;

  /// L'interruttore «Musica nel navigatore».
  bool get musica => _musica;

  /// Il lettore da mostrare, in guida e a mappa libera: c'è, e la musica è
  /// accesa.
  LettoreMusicale? get lettoreInGuida => _musica ? lettore : null;

  /// Se va proposto l'invito per il permesso della musica (da fermi, in guida
  /// o a mappa libera): una volta sola.
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
    // L'invito già visto sul telefono («Non ora»): nemmeno l'auto insiste.
    if (_invitoVisto) unawaited(lettore?.invitoVisto());
    notifyListeners();
  }

  /// Una notifica arrivata da chi ospita. Col navigatore non in uso, o con
  /// gli avvisi spenti, non si tiene: resta sul telefono come sempre.
  void arrivata(Map<String, Object?> notifica) {
    final c = coda;
    if (c == null || !inUso || !avvisiAccesi) return;
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

  void _usoCambiato() {
    if (!inUso) {
      coda?.svuota();
      _buste.clear();
    } else {
      // Qualcuno torna a guardare: un urgente rimasto lì da troppo (l'allarme
      // del viaggio di prima) non si ripresenta.
      coda?.scartaVecchi();
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
    // Anche al lato nativo: l'auto non ripete un invito già rifiutato.
    unawaited(lettore?.invitoVisto());
  }

  /// Se le scelte sono già state lette (per le prove).
  @visibleForTesting
  bool get caricato => _caricato;

  @override
  void dispose() {
    unawaited(_ascolto?.cancel());
    _guida?.removeListener(_usoCambiato);
    coda?.dispose();
    super.dispose();
  }
}
