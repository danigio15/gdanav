import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';
import 'gestore_auto.dart';
import 'gestore_consumo.dart';
import 'gestore_risparmio.dart';
import 'gestore_viaggio.dart';
import 'scelte_avvisi.dart';
import 'strade_osm.dart';
import 'voce.dart';

/// La guida passo-passo: segue la posizione, dice le manovre, ricalcola se
/// si esce di strada e racconta il viaggio a Home Assistant.
class GestoreGuida extends ChangeNotifier {
  GestoreGuida({
    required this.viaggio,
    required this.auto,
    required this.posizioni,
    required this.voce,
    this.consumo,
    this.risparmio,
    this.archivio,
    ModoAudio audioIniziale = ModoAudio.tutto,
    ScelteAvvisi? avvisi,
    DateTime Function()? orologio,
    this.stimaInGalleria = true,
    this.strade,
  }) : _ora = orologio ?? DateTime.now,
       avvisi = avvisi ?? ScelteAvvisi() {
    audio = audioIniziale;
  }

  /// Il consumo imparato: in guida lo si misura e lo si corregge.
  final GestoreConsumo? consumo;

  /// Le strade a risparmio: ogni tanto la strada che si fa si confronta con
  /// le altre, e se una vale la pena la si propone.
  final GestoreRisparmio? risparmio;

  /// Archivio delle preferenze persistenti del navigatore.
  final Archivio? archivio;

  /// Le strade di OpenStreetMap lungo il percorso, per non portare mai
  /// contromano (vedi «Mai contromano» più sotto): quelle attorno ai punti
  /// dati (`StradeOsm.attorno`). `null`: non si guarda.
  final Future<List<TrattoStrada>> Function(List<Punto> punti)? strade;

  /// Quali avvisi si vogliono, e come: a voce, solo a schermo o spenti.
  final ScelteAvvisi avvisi;

  /// Ogni quanto si confrontano le strade.
  static const intervalloStrade = Duration(minutes: 5);
  DateTime? _ultimoControlloStrade;

  /// Cambia a ogni ricalcolo: una proposta arrivata dopo non vale più.
  var _giroStrade = 0;

  /// Di quanti punti la batteria vera può scostarsi dal piano prima di
  /// ricalcolare le soste.
  static const scartoPerRicalcolo = 3.0;

  /// E non più spesso di così.
  static const intervalloRicalcolo = Duration(minutes: 2);

  /// Ogni quanto, in viaggio, si chiedono dati freschi a Home Assistant.
  static const intervalloDatiAuto = Duration(minutes: 1);

  /// Ogni quanto, in viaggio, si rilegge il traffico sul percorso.
  static const intervalloTraffico = Duration(minutes: 5);
  DateTime? _ultimoTraffico;
  DateTime _ultimaRichiestaDati = DateTime(0);

  /// Si chiede a ogni posizione, se è passato un minuto: niente timer.
  void _forseChiediDati() {
    final ora = _ora();
    if (ora.difference(_ultimaRichiestaDati) < intervalloDatiAuto) return;
    _ultimaRichiestaDati = ora;
    unawaited(auto.chiediAggiornamento());
    // La casa non aveva risposto alla partenza: glielo si richiede.
    if (_energiaDiCasa == null) unawaited(_prendiLEnergiaDiCasa());
  }

  MisuratoreConsumo? _misuratore;
  double? _batteriaInizio;
  var _kmMisurati = 0.0, _whMisurati = 0.0;
  DateTime _ultimoRicalcolo = DateTime(0);
  double _fattorePiano = 1;

  final GestoreViaggio viaggio;
  final GestoreAuto auto;

  /// Le posizioni GPS mentre si guida.
  final Stream<Punto> Function() posizioni;
  final Voce voce;
  final DateTime Function() _ora;

  Guida? _guida;
  StreamSubscription<Punto>? _iscrizione;
  Avanzamento? avanzamento;
  var attiva = false;
  var ricalcolando = false;

  /// Cosa si sente: vedi [ModoAudio].
  var audio = ModoAudio.tutto;

  /// La voce di guida (manovre, messaggi del viaggio) è spenta.
  bool get muto => audio.senzaGuida;

  /// Con il ricalcolo automatico spento: perché converrebbe ricalcolare. Si
  /// mostra una scheda con «Ricalcola» e «No».
  String? proposta;
  DateTime? _ultimoRacconto;
  var _vicinoDetto = false;

  ViaggioPronto? get pronto => switch (viaggio.stato) {
    final ViaggioPronto p => p,
    _ => null,
  };

  /// L'ora d'arrivo con quello che resta, più le ricariche ancora da fare.
  DateTime? get arrivoAlle {
    final a = avanzamento, p = pronto;
    if (a == null || p == null) return p?.arrivoAlle;
    final ricariche = (p.viaggio.piano?.soste ?? const <Sosta>[])
        .where((s) => s.colonnina.distanzaM > a.percorsiM)
        .fold(Duration.zero, (t, s) => t + s.ricarica);
    return _ora().add(a.restante + ricariche);
  }

  /// Quanti minuti del tempo che resta sono per il traffico di adesso,
  /// interi e senza ballare a ogni lettura ([RitardoMostrato]): «+7 min di
  /// traffico» accanto all'arrivo. Prima di partire, quello di tutto il
  /// percorso. Zero: niente da dire.
  int get minutiDiTraffico => _ritardoMostrato.aggiorna(ritardoDavanti);

  /// Il ritardo del traffico che resta davanti, esatto: quello da cui
  /// vengono sia [minutiDiTraffico] sia le etichette della striscia.
  Duration get ritardoDavanti {
    final a = avanzamento, p = pronto;
    return a?.ritardoTraffico ?? p?.viaggio.percorso.ritardoTraffico ?? Duration.zero;
  }

  final _ritardoMostrato = RitardoMostrato();

  /// La batteria quando si è partiti (anche dopo un ricalcolo).
  double? get batteriaPartenza => _batteriaInizio ?? pronto?.batteriaPartenza;

  /// La batteria adesso: quella che ha detto l'auto, com'è, finché è l'ultima
  /// parola dell'auto (`misurata`); fra una lettura e l'altra la stima che
  /// parte da lì e scende col consumo del piano (vedi [_consuma] e
  /// `ArbitroSorgenti.registraConsumo`), e che si riallinea appena l'auto
  /// manda un dato nuovo. Senza nessuna lettura, il piano.
  ///
  /// Dal campo: l'auto diceva 23% e 95 km, GdANav 21% e 88 km. Una lettura
  /// datata prima della partenza (Home Assistant la data col suo ultimo
  /// cambio, non con l'arrivo) qui non contava: si mostrava il piano dal
  /// chilometro zero, che scende come crede lui e non si riallinea mai, e
  /// l'autonomia vera dell'auto si scalava su quello (95 × 21,3 / 23 = 88).
  /// Dopo un ricalcolo era peggio: il piano nuovo partiva dalla stima.
  ({double valore, bool misurata})? get batteriaOra {
    final p = pronto;
    if (p == null || p.soloPercorso) return null;
    final s = auto.stato;
    if (s == null) return (valore: _prevista(p, (avanzamento?.percorsiM ?? 0) / 1000), misurata: false);
    return (valore: s.batteria, misurata: _dallAuto(s.sorgente));
  }

  /// Una sorgente che è l'auto: non la stima, non la batteria scritta a mano.
  static bool _dallAuto(TipoSorgente? t) => t != null && t != TipoSorgente.stima && t != TipoSorgente.manuale;

  /// La batteria di adesso parte da una lettura dell'auto, anche se stimata.
  bool get _ancorataAllAuto {
    final s = auto.stato;
    if (s == null) return false;
    return _dallAuto(s.sorgente) || (s.sorgente == TipoSorgente.stima && _dallAuto(s.stimataDa));
  }

  /// La batteria all'arrivo: il piano, con la pendenza corretta da quanto la
  /// macchina beve davvero. Il conto è in [batteriaAllArrivo].
  double? get batteriaArrivo {
    final p = pronto, ora = batteriaOra, piano = p?.viaggio.piano;
    if (p == null || piano == null || ora == null) return null;
    if (!ora.misurata && !_ancorataAllAuto) return piano.batteriaArrivo;
    final km = (avanzamento?.percorsiM ?? 0) / 1000;
    return batteriaAllArrivo(
      adesso: ora.valore,
      pianoAdesso: _prevista(p, km),
      pianoArrivo: piano.batteriaArrivo,
      fattore: _fattoreDelConsumo,
      dopoLUltimaSosta: _dopoLUltimaSosta(piano, km),
    );
  }

  /// Fin dove (in km del piano di adesso) l'energia consumata è già stata
  /// detta all'auto ([_consuma]).
  double _kmConsumo = 0;

  /// Il piano di cui sono quei chilometri. Durante un ricalcolo il viaggio
  /// nuovo arriva prima della guida nuova: finché la guida è quella di prima,
  /// i suoi chilometri non sono del piano nuovo, e non si contano. Il
  /// traffico riletto dà un viaggio nuovo con lo stesso piano e la stessa
  /// strada: lì il conto continua ([aggiornaTraffico]).
  ViaggioPronto? _pianoConsumo;

  /// Quanto si è consumato da [_kmConsumo] a [km], secondo il piano: lo si
  /// dice all'auto, che ne fa la stima fra due letture. Con le soste del
  /// piano la curva risale: è la ricarica prevista, che conta come prima.
  void _consuma(ViaggioPronto p, double km) {
    if (p.soloPercorso || p.viaggio.piano == null || !identical(p, _pianoConsumo)) return;
    final da = _kmConsumo;
    // Un passo indietro del GPS non ricarica la batteria.
    if (km <= da) return;
    _kmConsumo = km;
    auto.consumato((_prevista(p, da) - _prevista(p, km)) / 100 * auto.veicolo.capacitaUtileKwh);
  }

  /// Quanto la macchina beve davvero rispetto al piano, o niente se non si è
  /// ancora guidato abbastanza per dirlo.
  double? get _fattoreDelConsumo {
    final p = pronto, piano = p?.viaggio.piano;
    final totale = (p?.viaggio.percorso.lunghezzaM ?? 0) / 1000;
    if (piano == null || totale <= 0) return null;
    return fattoreDelConsumo(
      kmMisurati: _kmMisurati,
      whMisurati: _whMisurati,
      kwh100DelPiano: piano.energiaKwh / totale * 100,
    );
  }

  /// La batteria con cui il piano riparte dall'ultima sosta ancora davanti:
  /// da lì in poi quello che si è consumato prima non conta più.
  static double? _dopoLUltimaSosta(PianoViaggio piano, double km) {
    double? batteria;
    for (final s in piano.soste) {
      if (s.colonnina.distanzaM / 1000 > km) batteria = s.batteriaPartenza;
    }
    return batteria;
  }

  /// L'autonomia adesso: quella dell'auto, se la dice (Home Assistant,
  /// GdAHome, Android Auto, OBD), com'è se è recente e altrimenti portata
  /// alla batteria di adesso ([autonomiaDellAuto]); se non la dice, la
  /// batteria di adesso diviso il consumo, quello vero o quello del viaggio
  /// ma mai sotto il riferimento del modello; senza viaggio, la stima di
  /// [GestoreAuto.autonomiaKm]. È la stessa sullo schermo dell'auto.
  ({double km, bool dallAuto})? get autonomiaOra {
    if (!auto.elettrica || (pronto?.termica ?? false)) return null;
    final s = auto.stato;
    final b = batteriaOra?.valore ?? s?.batteria;
    if (autonomiaDellAuto(s, batteriaAdesso: b, ora: _ora()) case final km?) return (km: km, dallAuto: true);
    final c = _consumoMisurato ?? _consumoDelPianoPerAutonomia;
    if (b != null && c != null && c > 5) {
      return (km: b / 100 * auto.veicolo.capacitaUtileKwh / c * 100, dallAuto: false);
    }
    final k = auto.autonomiaKm();
    return k == null ? null : (km: k, dallAuto: false);
  }

  /// I km di autonomia che resteranno all'arrivo: l'autonomia di adesso
  /// ([autonomiaOra]) in proporzione alla batteria che resterà
  /// ([batteriaArrivo]), soste comprese. Nella riga del viaggio, al posto dei
  /// km di adesso: «nel riquadro info viaggi cambia i km auto con quelli
  /// attuali in quelli all'arrivo». `null` se manca uno dei tre.
  double? get autonomiaArrivoKm {
    final km = autonomiaOra?.km, arrivo = batteriaArrivo;
    final ora = batteriaOra?.valore ?? auto.stato?.batteria;
    if (km == null || arrivo == null || ora == null || ora <= 0) return null;
    return math.max(0, km * arrivo / ora);
  }

  /// Il consumo in kWh ogni 100 km: quello vero dopo qualche chilometro con i
  /// dati dell'auto, altrimenti quello previsto per il viaggio.
  double? get consumoKwh100 => _consumoMisurato ?? _consumoDelPiano;

  /// Misurato sui tratti guidati con i dati dell'auto, ricariche escluse.
  double? get _consumoMisurato {
    final ora = batteriaOra;
    if (pronto == null || ora == null || !ora.misurata || _kmMisurati < 3) return null;
    return _whMisurati / _kmMisurati / 10;
  }

  double? get _consumoDelPiano {
    final p = pronto;
    if (p == null) return null;
    final piano = p.viaggio.piano, totale = p.viaggio.percorso.lunghezzaM / 1000;
    if (piano == null || totale <= 0 || piano.energiaKwh <= 0) return null;
    return piano.energiaKwh / totale * 100;
  }

  /// Il consumo del piano per dire l'autonomia, ma mai sotto quello di
  /// riferimento del modello (a 90 km/h in piano, lo stesso che usa la
  /// schermata principale quando l'auto non dice niente).
  ///
  /// Il piano non conosce le partenze e le frenate: per un giro corto in
  /// città dice 6-8 kWh/100 km, che nel traffico vero nessuna elettrica fa.
  /// Diviso per quello, il 53% diventava 421 km. Un numero fisso andrebbe
  /// bene per alcune auto e non per altre (nel catalogo il riferimento va da
  /// 11 a 25 kWh/100 km): il pavimento è quello dell'auto scelta. Per dire
  /// quanto si consuma in questo viaggio resta il piano ([consumoKwh100]).
  double? get _consumoDelPianoPerAutonomia {
    final piano = _consumoDelPiano;
    if (piano == null) return null;
    final riferimento = auto.consumoDiRiferimentoKwh100();
    return piano < riferimento ? riferimento : piano;
  }

  /// Il profilo del piano al chilometro [km], fra i due punti vicini.
  static double _prevista(ViaggioPronto p, double km) {
    final profilo = p.viaggio.piano?.profiloBatteria ?? const <PuntoBatteria>[];
    if (profilo.isEmpty) return p.batteriaPartenza;
    if (km <= profilo.first.km) return profilo.first.batteria;
    for (var i = 1; i < profilo.length; i++) {
      final a = profilo[i - 1], b = profilo[i];
      if (km <= b.km) {
        final t = b.km == a.km ? 1.0 : (km - a.km) / (b.km - a.km);
        return a.batteria + t * (b.batteria - a.batteria);
      }
    }
    return profilo.last.batteria;
  }

  /// Il pedaggio ancora da pagare (stimato, con classe e tariffa delle
  /// opzioni): il tratto in cui si è conta tutto, si paga all'uscita.
  CostoPedaggio? get pedaggioDavanti {
    final p = pronto;
    if (p == null) return null;
    return viaggio.opzioni.tariffaPedaggio.stima(p.viaggio.percorso, daM: avanzamento?.percorsiM ?? 0);
  }

  /// La prossima sosta ancora davanti, e quanto manca.
  (Sosta, double)? get prossimaSosta {
    final a = avanzamento, p = pronto;
    if (p == null) return null;
    final fatti = a?.percorsiM ?? 0;
    for (final s in p.viaggio.piano?.soste ?? const <Sosta>[]) {
      if (s.colonnina.distanzaM > fatti) return (s, s.colonnina.distanzaM - fatti);
    }
    return null;
  }

  /// La strada fatta da quando è partita la guida: le posizioni, una ogni
  /// [_passoTraccia] metri. Resta dopo un ricalcolo (il percorso nuovo parte
  /// da dove si è), e si vuota alla fine. [versioneTraccia] cresce a ogni
  /// punto nuovo: chi la disegna la riscrive solo quando cambia.
  final List<Punto> traccia = [];
  var versioneTraccia = 0;
  static const _passoTraccia = 8.0;
  static const _puntiTracciaMassimi = 6000;

  void _allungaTraccia(Punto qui) {
    if (traccia.isNotEmpty && distanzaM(traccia.last, qui) < _passoTraccia) return;
    traccia.add(qui);
    // Un viaggio lunghissimo: un punto su due, la forma resta.
    if (traccia.length > _puntiTracciaMassimi) {
      final meta = [for (var i = 0; i < traccia.length; i += 2) traccia[i]];
      traccia
        ..clear()
        ..addAll(meta);
    }
    versioneTraccia++;
  }

  void avvia() {
    final p = pronto;
    if (p == null || attiva) return;
    attiva = true;
    traccia.clear();
    versioneTraccia++;
    _vicinoDetto = false;
    // Una proposta di ricalcolo del viaggio di prima non vale per questo.
    proposta = null;
    _guida = Guida(p.viaggio.percorso);
    // Il riepilogo dell'arrivo comincia qui.
    riepilogo = null;
    _partitoAlle = _ora();
    _metriPrima = 0;
    _euroPedaggioPrima = 0;
    _pedaggioPrimaStimato = false;
    // L'avanzamento rimasto è del viaggio di prima: fino alla prima posizione
    // la guida nuova non ne ha, e lo schermo e la mappa devono saperlo.
    avanzamento = null;
    // Partiti: i ricalcoli partono da dove si è, non dalle strade proposte.
    viaggio.dimenticaScelte();
    // Un viaggio nuovo: le strade rifiutate nell'altro si possono riproporre,
    // e il primo confronto è fra cinque minuti.
    risparmio?.dimentica();
    _ultimoControlloStrade = _ora();
    _batteriaInizio = p.batteriaPartenza;
    _kmMisurati = 0;
    _whMisurati = 0;
    // Il costo vero dell'energia: la ricarica di casa con cui si parte, e le
    // soste che si faranno.
    _ricaricaDiCasa = null;
    _energiaDiCasa = null;
    _viaggioN++;
    _inCarica = null;
    ricaricheInViaggio.clear();
    daChiedere = null;
    unawaited(_prendiLEnergiaDiCasa());
    _nuovoPiano(p);
    auto.addListener(_datiAuto);
    auto.addListener(_seguiLeRicariche);
    // Un errore del GPS non deve finire nel vuoto né chiudere la guida: la
    // posizione dopo arriva lo stesso.
    _iscrizione = posizioni().listen(_posizione, onError: (Object e) => debugPrint('posizioni in guida: $e'));
    // I sensi unici dei primi chilometri si guardano subito, senza aspettare
    // la prima posizione: si parte spesso a due passi dall'incrocio, e
    // guardandoli dopo la linea giusta arrivava quando l'auto era già lì.
    if (strade != null && !_sensiInCorso) {
      _sensiDi = p.viaggio.percorso;
      _sensiFinoA = finestraSensiM;
      _sensiRiprovaDopo = null;
      unawaited(_correggiISensi(daM: 0, aM: finestraSensiM, protettoM: 0));
    }
    _ultimaRichiestaDati = DateTime(0);
    _forseChiediDati();
    _evento('partenza');
    _racconta();
    notifyListeners();
  }

  /// Chiude la guida. [zittisci]: quello che si sta dicendo si ferma; non
  /// all'arrivo, dove la frase che si sta dicendo è proprio «Sei arrivato.».
  Future<void> ferma({bool zittisci = true}) async {
    attiva = false;
    proposta = null;
    traccia.clear();
    versioneTraccia++;
    _giroStrade++;
    risparmio?.lascia();
    auto.removeListener(_datiAuto);
    auto.removeListener(_seguiLeRicariche);
    _misuratore = null;
    await _iscrizione?.cancel();
    _iscrizione = null;
    _svegliaStima?.cancel();
    _svegliaStima = null;
    _stima.dimentica();
    // La velocità della guida è di quando si guidava: finita, non vale più
    // («senza navigazione di nuovo fermo, non cammina»: restava lo zero
    // dell'arrivo, e la mappa 3D lo prendeva per la velocità di adesso).
    _velocitaMs = null;
    _velocitaGps = null;
    if (zittisci) await voce.zitta();
    _racconta(inViaggio: false);
    notifyListeners();
  }

  /// L'ora della guida (nelle prove, quella finta).
  DateTime ora() => _ora();

  /// Un messaggio del viaggio fuori dalle manovre: tace con la voce di guida.
  void annuncia(String frase) {
    if (!muto) unawaited(voce.parla(frase));
  }

  /// Un avviso: autovelox, segnalazioni, ZTL, limite. Si sente anche con la
  /// voce di guida spenta («Solo avvisi»); tace col silenzio, e quando
  /// [quale] è scelto solo a schermo o spento. Scelto col beep, un beep al
  /// posto della frase.
  void annunciaAvviso(String frase, {Avviso? quale}) {
    if (audio.senzaAvvisi) return;
    if (quale != null && avvisi.colBeep(quale)) {
      unawaited(voce.suona());
      return;
    }
    if (quale != null && !avvisi.aVoce(quale)) return;
    unawaited(voce.parla(frase));
  }

  /// Il tasto dell'audio: Tutto → Solo avvisi → Silenzio → Tutto.
  void alternaVoce() => scegliAudio(audio.dopo);

  /// Un modo dell'audio scelto direttamente (il menu dell'auto).
  void scegliAudio(ModoAudio m) {
    audio = m;
    if (archivio case final a?) unawaited(a.salvaModoAudio(audio));
    // Quello che si sta dicendo si ferma: col tasto appena toccato, una frase
    // lunga che continua sembra un tasto che non va.
    if (audio != ModoAudio.tutto) unawaited(voce.zitta());
    notifyListeners();
  }

  /* ─── Il limite di velocità, a voce ─────────────────────────────────────
   *
   * Il tachimetro diventava rosso e basta: guardare il tachimetro è proprio
   * quello che non si fa quando si guida. Adesso un avviso, come gli
   * autovelox: oltre il limite di [oltreIlLimiteKmh] per almeno [oltrePer],
   * una volta sola per ogni tratto col suo limite. Il margine e l'attesa sono
   * per non parlare a ogni sorpasso, né per un GPS che salta di un colpo. */

  /// Di quanto oltre il limite prima di dirlo.
  static const oltreIlLimiteKmh = 5;

  /// E per quanto tempo di fila.
  static const oltrePer = Duration(seconds: 3);

  int? _limiteVisto;
  DateTime? _oltreDa;
  var _limiteDetto = false;

  void _controllaLimite(int? limite, double? kmh) {
    if (limite != _limiteVisto) {
      // Un tratto nuovo, con un limite suo: se ne può riparlare.
      _limiteVisto = limite;
      _oltreDa = null;
      _limiteDetto = false;
    }
    if (limite == null || kmh == null || kmh <= limite + oltreIlLimiteKmh) {
      _oltreDa = null;
      return;
    }
    if (_limiteDetto) return;
    final da = _oltreDa ??= _ora();
    if (_ora().difference(da) < oltrePer) return;
    _limiteDetto = true;
    annunciaAvviso('Attenzione, il limite è $limite.', quale: Avviso.limite);
  }

  /// Quanto si va: il tachimetro dell'auto se lo dice, se no il GPS.
  double? _velocitaKmh(Punto qui) {
    if (auto.velocitaAuto() case final v?) return v;
    if (qui case PuntoInMoto(:final velocitaMs?)) return velocitaMs * 3.6;
    return null;
  }

  /// L'ultima posizione vista in guida.
  Punto? _ultimaPosizione;

  /// Dove si è, anche fuori dal percorso (lì il segnaposto non si aggancia).
  Punto? get ultimaPosizione => _ultimaPosizione;

  /* ─── L'auto dov'è adesso, non dov'era ────────────────────────────────────
   *
   * Il GPS dice dov'era l'auto quando l'ha letta. Fra quella lettura e il
   * disegno passano centinaia di millisecondi, e la telecamera ci metteva un
   * altro secondo ad arrivarci: a novanta all'ora il segnaposto stava trenta,
   * quaranta metri dietro, e le svolte arrivavano prima della freccia. Sulla
   * strada però si sa dove si va: il punto agganciato si porta avanti lungo
   * il percorso di velocità × (età della lettura + [anticipo]). Con prudenza:
   * solo agganciati, solo andando (sopra 1,5 m/s), mai più di
   * [avantiAlPiuM]. Fuori dalla strada resta il punto del GPS, com'è. */

  /// Quanto si guarda avanti oltre l'età della lettura: il tempo che la
  /// mappa ci mette a disegnare, più il ritardo del GPS stesso.
  ///
  /// Dal campo: «arrivi all'incrocio e la freccia non c'è ancora, va in
  /// ritardo sul percorso». Erano 300 ms, il solo disegno. Ma la posizione
  /// del telefono è già filtrata (il fornitore della posizione la liscia, e
  /// liscia vuol dire indietro): a 50 all'ora la freccia restava una decina
  /// di metri dietro, e all'incrocio si arrivava prima di lei. Si guarda
  /// avanti di quasi un secondo: frenando prima di una svolta si rischia al
  /// più qualche metro in avanti, e da fermi (sotto 1,5 m/s) non si
  /// anticipa niente, la freccia si ferma dove si è.
  static const anticipo = Duration(milliseconds: 900);

  /// Mai più avanti di così: un GPS che tace non deve far correre l'auto da
  /// sola lungo la strada.
  static const avantiAlPiuM = 60.0;

  /// Cresce a ogni posizione: chi segue l'auto (la telecamera) si muove una
  /// volta per posizione, non a ogni novità della guida.
  int get letture => _letture;
  var _letture = 0;
  DateTime? _lettaAlle;
  double? _velocitaMs;

  /// Quanto si va, in m/s (il tachimetro dell'auto se lo dice, se no il
  /// GPS), all'ultima posizione; `null` se non si sa.
  double? get velocitaMs => _velocitaMs;

  /// La lettura del GPS com'era, sul percorso: dov'era l'auto (metri lungo
  /// il percorso), quando il GPS l'ha letta, a che velocità (del GPS, letta
  /// insieme alla posizione) e con che precisione. Senza portarla avanti:
  /// lo fa il filtro della scena 3D (`web3d/src/filtro.js`), che sa il
  /// ritardo del GPS e ha la velocità del cruscotto. `null` fuori percorso.
  ({double metri, DateTime alle, double? velocitaMs, double? precisioneM})? get letturaSulPercorso {
    final a = avanzamento, alle = _lettaAlle;
    if (a == null || _guida == null || a.posizioneSulPercorso == null || alle == null) return null;
    return (metri: a.percorsiM, alle: alle, velocitaMs: _velocitaGps, precisioneM: _precisioneM);
  }

  double? _velocitaGps;
  double? _precisioneM;

  /// Dove disegnare l'auto adesso e la direzione della strada lì; `null`
  /// se non si è agganciati alla strada (si disegna il punto del GPS).
  ({Punto punto, double rotta})? posizioneStimata() {
    final a = avanzamento, g = _guida, sulla = a?.posizioneSulPercorso, rotta = a?.rotta;
    final metri = metriStimati();
    if (a == null || g == null || sulla == null || rotta == null || metri == null) return null;
    if (metri == a.percorsiM) return (punto: sulla, rotta: rotta);
    return g.avanti(metri, 0);
  }

  /// Come [posizioneStimata], in metri lungo il percorso ([strada]); `null`
  /// se non si è agganciati alla strada.
  double? metriStimati() {
    final a = avanzamento;
    if (a == null || _guida == null || a.posizioneSulPercorso == null || a.rotta == null) return null;
    final v = _velocitaMs, alle = _lettaAlle;
    if (v == null || alle == null || v < 1.5) return a.percorsiM;
    var eta = _ora().difference(alle);
    if (eta.isNegative) eta = Duration.zero;
    if (eta > const Duration(seconds: 2)) eta = const Duration(seconds: 2);
    final metri = v * (eta + anticipo).inMilliseconds / 1000;
    return a.percorsiM + (metri > avantiAlPiuM ? avantiAlPiuM : metri);
  }

  /// La linea del percorso che si sta seguendo, su cui la freccia scorre
  /// ([MotoSullaStrada]): agli svincoli e nelle rotonde non esce di strada.
  Linea? get strada => _guida?.linea;

  /* ─── La linea sulle strade della mappa ───────────────────────────────────
   *
   * «Linee fuori strada.» La mappa di sempre e la vista immersiva disegnano
   * le strade di OpenStreetMap, e il percorso di TomTom ci sta di lato di
   * cinque, dieci metri. Con le strade vere che si leggono già per i sensi
   * unici ([strade]) la linea da DISEGNARE si appoggia su quelle
   * ([SullaMappa]), un pezzo alla volta davanti all'auto; la guida resta sul
   * percorso. La scena 3D lo fa da sé, e usa [strada]. */

  SullaMappa? _sullaMappa;

  /// Quante volte è cambiata la linea sulla mappa: per chi la disegna.
  final versioneSullaMappa = ValueNotifier(0);

  /// La linea del percorso [p] sulle strade della mappa, coi metri del
  /// percorso; `null` se non è di [p] o non è spostata.
  Linea? sullaMappaDi(PercorsoCalcolato? p) {
    final s = _sullaMappa;
    if (p == null || s == null || !identical(s.percorso, p.punti) || !s.spostata) return null;
    return s.linea;
  }

  /// La classe della strada della mappa sotto il percorso [p] a [metri]
  /// («motorway», «primary»…), se si sa: le corsie ne prendono il colore.
  String? classeSullaMappa(PercorsoCalcolato? p, double metri) {
    final s = _sullaMappa;
    if (p == null || s == null || !identical(s.percorso, p.punti)) return null;
    return s.classeA(metri);
  }

  /// La linea su cui la freccia scorre nella mappa di sempre: [strada], ma
  /// sulle strade della mappa se si sa.
  Linea? get stradaSullaMappa => sullaMappaDi(pronto?.viaggio.percorso) ?? strada;

  /// Il punto della mappa di sempre a [metri] lungo il percorso.
  Punto? sullaMappaA(double metri) {
    final l = stradaSullaMappa;
    return l == null ? null : sullaStrada(l, metri).punto;
  }

  /// La linea del percorso [p] appoggiata sulle [rete] fra [daM] e [aM].
  void _allinea(PercorsoCalcolato p, List<TrattoStrada> rete, double daM, double aM) {
    try {
      final prima = _sullaMappa;
      final base = prima != null && identical(prima.percorso, p.punti) ? prima : SullaMappa(p.punti);
      final nuova = base.allineata(rete, daM: daM, aM: aM);
      if (identical(nuova, prima)) return;
      _sullaMappa = nuova;
      if (nuova.spostata || (prima?.spostata ?? false)) versioneSullaMappa.value++;
    } catch (e) {
      debugPrint('linea sulla mappa: $e');
    }
  }

  /* ─── In galleria, senza GPS ──────────────────────────────────────────────
   *
   * «In galleria si perde, va per un po' nel vuoto e poi si blocca, per poi
   * riprendersi quando si esce.» Senza GPS la stima qui sopra si fermava dopo
   * due secondi e sessanta metri; e le posizioni larghe che il telefono manda
   * in galleria (dalle celle, centinaia di metri) staccavano l'auto dal
   * percorso: la mappa la disegnava dove diceva il telefono, nel vuoto.
   *
   * Adesso ([StimaSenzaGps], in gdanav_core): una lettura larga, avendone una
   * buona sulla strada da poco, non si usa; e senza letture buone da due
   * secondi l'auto va avanti lungo il percorso alla velocità di prima (o a
   * quella del tachimetro dell'auto, se la dice), una «lettura stimata» al
   * secondo, come se il GPS ci fosse: le manovre, la voce, la scena 3D e
   * l'auto vanno avanti con lei. Per al più tre minuti; poi ci si ferma, e
   * sullo schermo «GPS assente». Quando il GPS torna, la freccia si
   * riallinea piano ([MotoSullaStrada]). */
  final _stima = StimaSenzaGps();
  Timer? _svegliaStima;

  /// Se senza GPS si stima la posizione (vedi sopra). Spenta solo nelle
  /// prove che non la guardano: la sveglia della stima è un `Timer`.
  final bool stimaInGalleria;
  DateTime? _tachimetroVisto;

  /// Si sta stimando la posizione senza GPS (in galleria): la si mostra, ma
  /// senza dire «GPS assente».
  bool get stimaSenzaGps => attiva && _stima.stima(_ora());

  /// La stima senza GPS è finita (tre minuti senza letture buone).
  bool get gpsPersoInGuida => attiva && _stima.persa(_ora());

  void _armaStima(Duration fra) {
    _svegliaStima?.cancel();
    if (!stimaInGalleria) return;
    _svegliaStima = Timer(fra, _passoDiStima);
  }

  /// Una «lettura stimata»: dove si è, senza GPS, lungo il percorso.
  void _passoDiStima() {
    _svegliaStima = null;
    final g = _guida;
    if (!attiva || g == null) return;
    final ora = _ora();
    final kmh = auto.velocitaAuto(), letto = auto.velocitaLettaAlle;
    if (kmh != null && letto != null && letto != _tachimetroVisto) {
      _tachimetroVisto = letto;
      _stima.tachimetro(kmh / 3.6, letto);
    }
    if (_stima.persa(ora)) {
      // Finita: si dice una volta, e si aspetta il GPS.
      notifyListeners();
      return;
    }
    if (!_stima.stima(ora)) {
      _armaStima(const Duration(milliseconds: 500));
      return;
    }
    final metri = _stima.metri(ora, lunghezzaM: g.lunghezzaM);
    if (metri != null) {
      final dove = g.avanti(metri, 0);
      final v = kmh != null ? kmh / 3.6 : (_velocitaMs ?? 0);
      unawaited(
        _posizione(
          PuntoInMoto(dove.punto.lat, dove.punto.lon, rotta: dove.rotta, velocitaMs: v, alle: ora),
          stimata: true,
        ),
      );
    }
    _armaStima(const Duration(seconds: 1));
  }

  Future<void> _posizione(Punto qui, {bool stimata = false}) async {
    if (!stimata) {
      final precisione = qui is PuntoInMoto ? qui.precisioneM : null;
      // Una lettura larga (in galleria, dalle celle) con una buona sulla
      // strada da poco: non dice niente di più della stima, e staccherebbe
      // l'auto dal percorso.
      if (!_stima.buona(precisione) &&
          _guida != null &&
          attiva &&
          !_stima.persa(_ora()) &&
          _stima.metri(_ora()) != null) {
        return;
      }
    }
    _ultimaPosizione = qui;
    _letture++;
    final ora = _ora();
    // L'ora della lettura del GPS, se è credibile; altrimenti adesso.
    final letta = qui is PuntoInMoto ? qui.alle : null;
    _lettaAlle = letta != null && !letta.isAfter(ora) && ora.difference(letta) < const Duration(seconds: 5)
        ? letta
        : ora;
    final kmh = auto.velocitaAuto();
    _velocitaGps = qui is PuntoInMoto ? qui.velocitaMs : null;
    _precisioneM = qui is PuntoInMoto ? qui.precisioneM : null;
    _velocitaMs = kmh != null ? kmh / 3.6 : _velocitaGps;
    _forseChiediDati();
    final g = _guida;
    if (g == null || !attiva) return;
    final a = g.aggiorna(qui);
    avanzamento = a;
    if (!stimata) {
      if (a.posizioneSulPercorso != null && _stima.buona(_precisioneM)) {
        _stima.lettura(metri: a.percorsiM, alle: _lettaAlle!, velocitaMs: _velocitaMs);
        _armaStima(_stima.dopo + const Duration(milliseconds: 100));
      } else if (a.posizioneSulPercorso == null) {
        // Fuori dal percorso non si stima lungo il percorso.
        _stima.dimentica();
        _svegliaStima?.cancel();
      }
    }
    _allungaTraccia(qui);
    if (pronto case final p?) _consuma(p, a.percorsiM / 1000);
    _controllaLimite(a.limiteKmh, _velocitaKmh(qui));
    // Arrivati al distributore: da qui si prosegue verso la meta.
    // Arrivati a una tappa (o al distributore): da qui si prosegue.
    viaggio.tappeFatte(qui);
    if (a.daDire case final frase? when !muto) unawaited(voce.parla(frase));
    if (a.arrivato) {
      _evento('arrivo');
      // «All'arrivo la navigazione si deve interrompere con scritto arrivo,
      // e un riepilogo del viaggio: durata, consumo e costi.»
      // Resta (anche sull'auto) finché non si preme «Fine» o si riparte.
      if (pronto case final p?) {
        _arrivo = (p, a);
        riepilogo = _ilRiepilogo(p, a);
        // La casa non ha mai risposto in viaggio: un'ultima volta adesso, e
        // se risponde il riepilogo si rifà col prezzo vero.
        if (_energiaDiCasa == null) unawaited(_prendiLEnergiaDiCasa());
      }
      notifyListeners();
      await ferma(zittisci: false);
      return;
    }
    if (!_vicinoDetto && a.restante.inMinutes < 10) {
      _vicinoDetto = true;
      _evento('arrivo_vicino', {'minuti': a.restante.inMinutes});
    }
    if (!stimata) _guardaAvantiISensi(p0: a);
    if (a.fuoriPercorso && !ricalcolando) unawaited(_fuoriStrada(qui, a));
    final ultimo = _ultimoTraffico ??= _ora();
    if (!ricalcolando && _ora().difference(ultimo) >= intervalloTraffico) {
      _ultimoTraffico = _ora();
      unawaited(aggiornaTraffico());
    }
    final ultimoConfronto = _ultimoControlloStrade ??= _ora();
    if (risparmio != null && !ricalcolando && _ora().difference(ultimoConfronto) >= intervalloStrade) {
      _ultimoControlloStrade = _ora();
      unawaited(controllaStrade());
    }
    if (_ultimoRacconto == null || _ora().difference(_ultimoRacconto!) > const Duration(minutes: 1)) _racconta();
    notifyListeners();
  }

  /// Il viaggio appena finito, da mostrare all'arrivo (telefono e auto);
  /// `null` in viaggio, e dopo «Chiudi».
  RiepilogoViaggio? riepilogo;

  /// «Fine» sul riepilogo.
  void chiudiRiepilogo() {
    if (riepilogo == null) return;
    riepilogo = null;
    notifyListeners();
  }

  DateTime? _partitoAlle;

  /// I metri e il pedaggio delle guide di prima nello stesso viaggio: a ogni
  /// ricalcolo la guida nuova riparte da zero metri.
  var _metriPrima = 0.0, _euroPedaggioPrima = 0.0;

  /// Vero se nel pedaggio delle guide di prima c'è una parte stimata a km.
  var _pedaggioPrimaStimato = false;

  /// Una guida nuova sullo stesso viaggio (un ricalcolo, una strada presa):
  /// quello fatto sulla vecchia resta nel conto del riepilogo.
  ///
  /// E l'avanzamento si rifà sul percorso nuovo, dall'ultima posizione.
  /// Restava quello del vecchio: [posizioneStimata] ne prendeva i metri e li
  /// portava sul nuovo, che parte da dove si è, e fino alla lettura dopo la
  /// freccia stava chilometri più avanti (a telefono e in auto). E un secondo
  /// cambio prima di quella lettura contava quei metri due volte nel
  /// riepilogo. Lo si rifà con una guida da buttare: quella vera non deve
  /// segnare come già dette le frasi di quella posizione, che la lettura dopo
  /// dirà.
  void _cambiaGuida(PercorsoCalcolato nuovo) {
    final vecchia = _guida, fatti = avanzamento?.percorsiM ?? 0;
    if (vecchia != null && attiva) {
      _metriPrima += fatti;
      final tariffa = viaggio.opzioni.tariffaPedaggio;
      final tutto = tariffa.stima(vecchia.percorso);
      final pagato = math.max(0.0, tutto.euro - tariffa.stima(vecchia.percorso, daM: fatti).euro);
      _euroPedaggioPrima += pagato;
      if (pagato > 0 && tutto.stimato) _pedaggioPrimaStimato = true;
    }
    _guida = Guida(nuovo);
    final qui = _ultimaPosizione;
    avanzamento = qui == null ? null : Guida(nuovo).aggiorna(qui);
  }

  /* ─── Mai contromano ──────────────────────────────────────────────────────
   *
   * «Ancora con questo incrocio»: al bivio di due sensi unici la linea di
   * TomTom tirava dritto fino al vertice e girava stretta sul ramo vietato.
   * In guida si guardano le strade vere dei prossimi due chilometri
   * ([finestraSensiM], tessere di OpenStreetMap, `StradeOsm`) e, se il
   * percorso fa un pezzo contromano, lo si rifà sul ramo giusto
   * (`correggiContromano` in gdanav_core): linea, manovra («Al bivio tieni
   * la destra»), distanza e voce cambiano insieme, sul telefono, in auto e
   * nella scena 3D, che leggono tutti lo stesso viaggio. Senza ricalcolo: la
   * meta, le soste e le manovre lontane restano quelle.
   *
   * E se il controllo non ha fatto in tempo e l'auto prende il ramo giusto,
   * prima di ricalcolare si riguarda lì: se rifatto il percorso ci passa,
   * nessun «Ricalcolo il percorso». */

  /// Quanto avanti si guardano i sensi unici.
  static const finestraSensiM = 2000.0;

  PercorsoCalcolato? _sensiDi;
  var _sensiFinoA = -1.0;
  var _sensiInCorso = false;

  /// Senza strade (niente rete, tessera che non arriva) si riprova dopo.
  DateTime? _sensiRiprovaDopo;

  void _guardaAvantiISensi({required Avanzamento p0}) {
    final p = pronto;
    if (strade == null || p == null || _sensiInCorso) return;
    final percorso = p.viaggio.percorso;
    if (!identical(_sensiDi, percorso)) {
      // Un percorso nuovo (un ricalcolo): si ricomincia da dove si è.
      _sensiDi = percorso;
      _sensiFinoA = -1;
    }
    final qui = p0.percorsiM;
    if (qui + finestraSensiM / 2 <= _sensiFinoA) return;
    if (_sensiRiprovaDopo case final t? when _ora().isBefore(t)) return;
    final da = math.max(qui, _sensiFinoA - 100);
    _sensiFinoA = qui + finestraSensiM;
    unawaited(_correggiISensi(daM: da, aM: _sensiFinoA, protettoM: qui + 30));
  }

  /// Fuori strada: prima di ricalcolare, si guarda se si è sul ramo giusto
  /// di un pezzo che il percorso faceva contromano.
  Future<void> _fuoriStrada(Punto qui, Avanzamento a) async {
    if (_fuoriInCorso) return;
    if (strade == null) return _ricalcola();
    // Si sta già guardando avanti: decide la prossima lettura.
    if (_sensiInCorso) return;
    _fuoriInCorso = true;
    try {
      final fatti = a.percorsiM;
      final corretto = await _correggiISensi(
        daM: math.max(0, fatti - 50),
        aM: fatti + 400,
        protettoM: math.max(0, fatti - 250),
      );
      if (corretto) {
        final p = pronto?.viaggio.percorso;
        if (p != null && Guida(p).aggiorna(qui).lontanoM <= 25) return;
      }
    } finally {
      _fuoriInCorso = false;
    }
    if (!ricalcolando && attiva) await _ricalcola();
  }

  var _fuoriInCorso = false;

  /// Corregge il percorso fra [daM] e [aM] se ci va contromano; `true` se
  /// l'ha corretto.
  Future<bool> _correggiISensi({required double daM, required double aM, required double protettoM}) async {
    final s = strade, p = pronto, g = _guida;
    if (s == null || p == null || g == null || !attiva || _sensiInCorso) return false;
    final percorso = p.viaggio.percorso;
    _sensiInCorso = true;
    try {
      final c = g.linea.cumulate, punti = g.linea.punti;
      final pezzo = [
        for (var i = 0; i < punti.length; i++)
          if (c[i] >= daM - 250 && c[i] <= aM + 150) punti[i],
      ];
      if (pezzo.isEmpty) return false;
      final rete = await s(pezzo);
      if (rete.isEmpty) {
        diarioSensi.scrivi('nessuna strada vera attorno al percorso: si riprova fra 15 s');
        // Non si è visto niente: quel pezzo resta da guardare, fra un poco.
        _sensiRiprovaDopo = _ora().add(const Duration(seconds: 15));
        if (identical(_sensiDi, percorso)) _sensiFinoA = math.min(_sensiFinoA, daM);
        return false;
      }
      // Nel frattempo è cambiato il percorso, o si è finito.
      if (!attiva || !identical(pronto?.viaggio.percorso, percorso) || !identical(_guida, g)) return false;
      final corretto = correggiContromano(
        percorso,
        rete,
        daM: daM,
        aM: aM,
        protettoM: protettoM,
        diario: diarioSensi.scrivi,
      );
      String km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');
      // La linea da disegnare, sulle strade appena lette (anche dove l'auto è).
      if (corretto == null) {
        _allinea(percorso, rete, math.max(0, daM - 150), aM);
        diarioSensi.scrivi('guardato da ${km(daM)} a ${km(aM)} km (${rete.length} strade): niente da correggere');
        return false;
      }
      final vecchio = pronto;
      final nuovo = viaggio.sostituisciPercorso(percorso, corretto.percorso);
      if (nuovo == null) return false;
      if (identical(_pianoConsumo, vecchio)) _pianoConsumo = nuovo;
      _guida = g.conCorrezione(corretto);
      _sensiDi = corretto.percorso;
      _sensiFinoA = corretto.metriNuovi(_sensiFinoA);
      if (_ultimaPosizione case final qui?) avanzamento = Guida(corretto.percorso).aggiorna(qui);
      debugPrint('contromano evitato: ${corretto.deviazioni}');
      for (final d in corretto.deviazioni) {
        diarioSensi.scrivi('contromano evitato a ${km(d.daM)} km: rifatto sul ramo giusto (${d.lunghezzaM.round()} m)');
      }
      notifyListeners();
      // Il percorso è nuovo: la sua linea sulla mappa da dove è l'auto, con le
      // strade anche di lì (le tessere sono già lette).
      final qui = avanzamento?.percorsiM ?? daM;
      final daQui = math.max(0.0, math.min(qui, daM) - 150);
      final altre = daQui < daM - 250
          ? await s([
              for (var i = 0; i < punti.length; i++)
                if (c[i] >= daQui - 100 && c[i] <= daM) punti[i],
            ])
          : const <TrattoStrada>[];
      if (identical(pronto?.viaggio.percorso, corretto.percorso)) {
        _allinea(corretto.percorso, [...altre, ...rete], daQui, corretto.metriNuovi(aM));
      }
      return true;
    } catch (e) {
      debugPrint('sensi unici: $e');
      return false;
    } finally {
      _sensiInCorso = false;
    }
  }

  /* ─── Le ricariche: quella di casa e quelle per strada ───────────────────
   *
   * Dal campo: «per il costo del viaggio, soprattutto se elettrico, considera
   * se si parte da casa al 100% e verifica l'ultima ricarica a casa, come è
   * stata caricata; e capisci, o chiedi, quanto si è speso se ci si ferma a
   * ricaricare in autostrada o per strada. Da lì il conto preciso».
   *
   * La ricarica di casa la dice la casa (GdAHome: kWh, quanti col sole, gli
   * euro di rete); vale se è finita da poco e la batteria alla partenza è
   * quella che ha lasciato. Le soste le vede l'auto: «in carica» durante il
   * viaggio, da quanto a quanto. Il prezzo lo stima la tariffa della
   * colonnina, se il gestore la dice; e finita la ricarica il telefono chiede
   * quanto si è pagato davvero ([daChiedere]), con la stima già scritta. */

  RicaricaDiCasa? _ricaricaDiCasa;

  /// L'ultima ricarica a casa, se si è partiti con quella.
  RicaricaDiCasa? get ricaricaDiCasa => _ricaricaDiCasa;

  /// Quello che la casa ha risposto per questo viaggio; `null` finché non
  /// risponde (e in GdANav da sola).
  EnergiaDiCasa? _energiaDiCasa;

  /// Il viaggio di adesso: una risposta della casa arrivata tardi, a viaggio
  /// cambiato, non è di questo.
  var _viaggioN = 0;
  var _chiedendoAllaCasa = false;

  /// Le ricariche fatte durante questo viaggio.
  final ricaricheInViaggio = <RicaricaInViaggio>[];

  /// Quale ricarica chiedere a chi guida («quanto hai speso?»), se c'è.
  int? daChiedere;

  ({double socDa, double socA, double? energiaDa, double? energiaA, double percorsiM})? _inCarica;

  /// L'arrivo, per rifare il riepilogo quando si dice quanto si è pagato.
  (ViaggioPronto, Avanzamento)? _arrivo;

  /// Chiede alla casa l'energia con cui si parte.
  ///
  /// Si chiedeva una volta sola, alla partenza: ma è proprio il momento in
  /// cui il telefono lascia il Wi-Fi di casa, e una casa che non rispondeva
  /// lì non veniva più sentita; il viaggio finiva col prezzo delle opzioni.
  /// Ora si richiede ogni minuto finché non risponde ([_forseChiediDati]), e
  /// un'ultima volta all'arrivo: se risponde lì, il riepilogo si rifà.
  Future<void> _prendiLEnergiaDiCasa() async {
    final casa = auto.gdahome;
    if (casa == null || _chiedendoAllaCasa) return;
    final quale = _viaggioN;
    final partenza = _partitoAlle ?? _ora();
    _chiedendoAllaCasa = true;
    final EnergiaDiCasa? e;
    try {
      e = await casa.energiaDiCasa();
    } finally {
      _chiedendoAllaCasa = false;
    }
    if (e == null || quale != _viaggioN || !(attiva || riepilogo != null)) return;
    _energiaDiCasa = e;
    final r = e.ricarica;
    _ricaricaDiCasa = r != null && r.valePer(partenza: partenza, batteriaPartenza: _batteriaInizio) ? r : null;
    _rifaiIlRiepilogo();
    notifyListeners();
  }

  /// Dopo l'ultima ricarica a casa si è caricato altrove: l'energia con cui
  /// si è partiti non ha il prezzo di casa, nemmeno quello della tariffa.
  bool get _caricatoAltrove => _energiaDiCasa?.ricarica?.superataDa(_batteriaInizio) ?? false;

  /// Perché il prezzo dell'energia non è quello della ricarica di casa, da
  /// dire nel riepilogo; `null` se lo è, e in GdANav da sola.
  SenzaPrezzoVero? get _senzaPrezzoVero {
    final casa = auto.gdahome;
    if (casa == null || casa.chiedi == null) return null;
    final e = _energiaDiCasa;
    if (e == null) return SenzaPrezzoVero.casaMuta;
    final r = _ricaricaDiCasa;
    if (r?.euroAlKwh != null) return null;
    if (e.conTariffa == false) return SenzaPrezzoVero.senzaTariffa;
    if (e.autoSeguita == false) return SenzaPrezzoVero.autoNonSeguita;
    if (e.ricarica == null) return SenzaPrezzoVero.senzaRicarica;
    if (_caricatoAltrove) return SenzaPrezzoVero.ricaricaAltrove;
    if (r == null) return SenzaPrezzoVero.ricaricaNonVale;
    // La ricarica vale ma non ha il suo prezzo: la casa non l'aveva quando
    // l'ha vista. Se adesso c'è la tariffa, il conto si fa con quella.
    return e.euroAlKwh == null ? SenzaPrezzoVero.senzaTariffa : null;
  }

  /// A ogni lettura dell'auto: comincia, segue e chiude le ricariche.
  void _seguiLeRicariche() {
    final s = auto.stato;
    if (!attiva || s == null || !_dallAuto(s.sorgente)) return;
    final c = _inCarica;
    if (s.inCarica == true) {
      _inCarica = (
        socDa: c?.socDa ?? s.batteria,
        socA: s.batteria,
        energiaDa: c?.energiaDa ?? s.energiaKwh,
        energiaA: s.energiaKwh,
        percorsiM: c?.percorsiM ?? (avanzamento?.percorsiM ?? 0),
      );
      return;
    }
    if (c == null) return;
    _inCarica = null;
    final dallEnergia = c.energiaDa != null && c.energiaA != null ? c.energiaA! - c.energiaDa! : null;
    final kwh = dallEnergia != null && dallEnergia > 0
        ? dallEnergia
        : (c.socA - c.socDa) / 100 * auto.veicolo.capacitaUtileKwh;
    if (kwh < 1) return;
    final (nome, stima) = _laColonninaA(c.percorsiM, kwh);
    ricaricheInViaggio.add(RicaricaInViaggio(dove: nome, kwh: kwh, euroStimati: stima));
    daChiedere = ricaricheInViaggio.length - 1;
    _rifaiIlRiepilogo();
    notifyListeners();
  }

  /// La colonnina del viaggio dove si è caricato (entro mezzo chilometro sul
  /// percorso), e il prezzo dalla sua tariffa se il gestore la dice.
  (String, double?) _laColonninaA(double percorsiM, double kwh) {
    final p = pronto;
    ColonninaSulPercorso? vicina;
    for (final c in p?.viaggio.colonnine ?? const <ColonninaSulPercorso>[]) {
      final quanto = (c.distanzaM - percorsiM).abs();
      if (quanto <= 500 && (vicina == null || quanto < (vicina.distanzaM - percorsiM).abs())) vicina = c;
    }
    if (vicina == null) return ('Ricarica per strada', null);
    final corrente = vicina.potenzaKw >= 150 ? Corrente.hpc : (vicina.potenzaKw >= 50 ? Corrente.dc : Corrente.ac);
    final t = vicina.dettaglio?.prezzi?.perCorrente[corrente];
    final energia = t?.energia;
    if (energia == null) return (vicina.nome, null);
    final avvio = t?.avvio;
    final euro = kwh * (energia.da + energia.a) / 2 + (avvio == null ? 0.0 : (avvio.da + avvio.a) / 2);
    return (vicina.nome, euro);
  }

  /// «Quanto hai speso?»: la risposta di chi guida per la ricarica [i].
  void pagaRicarica(int i, double euro) {
    if (i < 0 || i >= ricaricheInViaggio.length || euro < 0) return;
    ricaricheInViaggio[i] = ricaricheInViaggio[i].pagata(euro);
    if (daChiedere == i) daChiedere = null;
    _rifaiIlRiepilogo();
    notifyListeners();
  }

  /// «Dopo»: la domanda si chiude, la stima resta.
  void nonOra() {
    daChiedere = null;
    notifyListeners();
  }

  void _rifaiIlRiepilogo() {
    final arrivo = _arrivo;
    if (riepilogo != null && arrivo != null) riepilogo = _ilRiepilogo(arrivo.$1, arrivo.$2);
  }

  RiepilogoViaggio _ilRiepilogo(ViaggioPronto p, Avanzamento a) {
    final metri = _metriPrima + a.percorsiM;
    final elettrica = auto.elettrica && !p.termica;
    final o = viaggio.opzioni;
    // Il pedaggio della strada **fatta**: quello pagato sulle guide di prima
    // ([_cambiaGuida]) più quello dell'ultima, per intero (si è arrivati).
    final ultimo = o.tariffaPedaggio.stima(p.viaggio.percorso);
    final pedaggio = _euroPedaggioPrima + ultimo.euro;
    // Stimato solo se una parte è a km: un prezzo di listino (la Tangenziale
    // di Napoli) si scrive senza «~».
    final pedaggioStimato = _pedaggioPrimaStimato || (ultimo.euro > 0 && ultimo.stimato);
    final consumo = elettrica ? _kwhDelViaggio(p, metri) : null;
    final inizio = _batteriaInizio;
    final energia = consumo == null
        ? null
        : costoDellEnergia(
            consumatiKwh: consumo.kwh,
            partenzaKwh: inizio == null ? null : inizio / 100 * auto.veicolo.capacitaUtileKwh,
            casa: _ricaricaDiCasa,
            euroAlKwhDiCasa: _caricatoAltrove ? null : _energiaDiCasa?.euroAlKwh,
            soste: List.of(ricaricheInViaggio),
            euroAlKwhDiRiserva: o.euroAlKwh,
          );
    return RiepilogoViaggio(
      destinazione: p.destinazione.nome,
      durata: _ora().difference(_partitoAlle ?? _ora()),
      metri: metri,
      elettrica: elettrica,
      kwh: consumo?.kwh,
      litri: elettrica ? null : _litriDelViaggio(p, metri),
      consumoStimato: consumo?.stimato ?? true,
      kwhPiuOMeno: consumo?.piuOMeno,
      euroAlKwh: o.euroAlKwh,
      euroAlLitro: o.euroAlLitro,
      pedaggio: pedaggio > 0 ? CostoPedaggio(euro: pedaggio, classe: o.classePedaggio, stimato: pedaggioStimato) : null,
      energia: energia,
      senzaPrezzoVero: energia == null ? null : _senzaPrezzoVero,
      soste: List.of(ricaricheInViaggio),
    );
  }

  /// L'energia del viaggio: misurata dall'auto, se l'ha detta; se no dalla
  /// batteria (senza ricariche nel mezzo); se no dal modello sul percorso.
  /// `piuOMeno`: quanto è larga la misura, in kWh
  /// ([RiepilogoViaggio.kwhPiuOMeno]).
  ///
  /// Dal campo: 13,6 km, partito all'82% e arrivato al 78%, e il riepilogo
  /// diceva «3,5 kWh · 25,8 kWh/100 km». La misura dell'auto
  /// ([MisuratoreConsumo]) conta fra un cambio di punto e l'altro, almeno due
  /// punti per volta: su un viaggio di quattro punti ne aveva misurati due, e
  /// quel consumo lo si stendeva su tutti i chilometri. Con la batteria a
  /// punti interi è una misura larga la metà di sé stessa; i quattro punti
  /// dalla partenza all'arrivo lo sono un quarto. Così, quando le due misure
  /// si parlano (stanno una nell'incertezza dell'altra), vale la più stretta;
  /// se non si parlano (una partenza letta vecchia) resta quella dell'auto. E
  /// quanto è larga lo si dice.
  ({double kwh, bool stimato, double? piuOMeno})? _kwhDelViaggio(ViaggioPronto p, double metri) {
    final inizio = _batteriaInizio, ora = batteriaOra;
    final capacita = auto.veicolo.capacitaUtileKwh;
    // Un punto di batteria, in kWh: quanto è larga una lettura.
    final punto = capacita / 100;
    final ricariche = (p.viaggio.piano?.soste.isNotEmpty ?? false) || ricaricheInViaggio.isNotEmpty;
    // Dalla partenza all'arrivo, senza ricariche nel mezzo.
    final scesi = inizio != null && ora != null && ora.misurata && !ricariche && inizio > ora.valore
        ? (inizio - ora.valore) / 100 * capacita
        : null;
    if (_kmMisurati > 1 && _whMisurati > 0) {
      final kwh = _whMisurati / 1000 / _kmMisurati * metri / 1000;
      // In kWh veri (l'auto dice l'energia che resta) la misura è stretta.
      final largo = auto.stato?.energiaKwh != null ? 0.0 : kwh * math.min(1.0, punto / (_whMisurati / 1000));
      if (scesi != null && punto < largo && (scesi - kwh).abs() <= punto + largo) {
        return (kwh: scesi, stimato: false, piuOMeno: punto);
      }
      return (kwh: kwh, stimato: false, piuOMeno: largo > 0 ? largo : null);
    }
    // Con le ricariche viste: quella scesa più quella presa per strada.
    if (inizio != null && ora != null && ora.misurata && ricaricheInViaggio.isNotEmpty) {
      final presi = ricaricheInViaggio.fold(0.0, (s, r) => s + r.kwh);
      final kwh = (inizio - ora.valore) / 100 * capacita + presi;
      if (kwh > 0) return (kwh: kwh, stimato: false, piuOMeno: punto);
    }
    if (scesi != null) return (kwh: scesi, stimato: false, piuOMeno: punto);
    final tratti = p.viaggio.percorso.tratti;
    final lunghezza = tratti.fold(0.0, (s, t) => s + t.lunghezzaM);
    if (lunghezza <= 0) return null;
    final condizioni = viaggio.condizioni ?? const Condizioni();
    final wh = tratti.fold(0.0, (s, t) => s + energiaTrattoWh(t, auto.veicolo, condizioni));
    return (kwh: wh / 1000 * metri / lunghezza, stimato: true, piuOMeno: null);
  }

  /// I litri del viaggio, dal modello della termica sul percorso.
  double? _litriDelViaggio(ViaggioPronto p, double metri) {
    final tratti = p.viaggio.percorso.tratti;
    final lunghezza = tratti.fold(0.0, (s, t) => s + t.lunghezzaM);
    if (lunghezza <= 0) return null;
    final litri = tratti.fold(
      0.0,
      (s, t) => s + ModelloConsumoTomTom.litriTratto(t.lunghezzaM, t.velocitaKmh, auto.carburante, ibrida: auto.ibrida),
    );
    return litri * metri / lunghezza;
  }

  /// Si comincia a misurare sul piano nuovo, col modello senza correttivo.
  void _nuovoPiano(ViaggioPronto p) {
    // Il piano nuovo parte da qui: i suoi chilometri ricominciano da zero.
    _kmConsumo = 0;
    _pianoConsumo = p;
    // Auto termica, o elettrica senza soste: niente piano da misurare.
    if (p.soloPercorso) {
      _misuratore = null;
      return;
    }
    // Le condizioni del piano (col clima dal meteo), senza correttivo: se
    // no il clima finiva dentro il correttivo e si contava due volte.
    final senza =
        viaggio.condizioni?.senzaCorrettivo ?? consumo?.condizioni(auto.stato, conFattore: false) ?? const Condizioni();
    _fattorePiano = consumo?.imparato.fattore ?? 1;
    _misuratore = MisuratoreConsumo(
      percorso: p.viaggio.percorso,
      capacitaKwh: auto.veicolo.capacitaUtileKwh,
      profilo: (t) => energiaTrattoWh(t, auto.veicolo, senza),
    );
  }

  /// Una lettura vera dall'auto: si misura il consumo e, se la batteria si
  /// allontana dal piano, si ricalcolano le soste da dove si è.
  void _datiAuto() {
    final p = pronto, s = auto.stato, ora = batteriaOra;
    if (!attiva || p == null || p.soloPercorso || s == null || ora == null || !ora.misurata) return;
    final metri = avanzamento?.percorsiM ?? 0;
    final misura = _misuratore?.registra(
      batteria: s.batteria,
      metri: metri,
      inCarica: s.inCarica == true,
      energiaKwh: s.energiaKwh,
    );
    if (misura != null) {
      _kmMisurati += misura.km;
      _whMisurati += misura.realeWh;
      unawaited(consumo?.registra(misura));
    }
    if (s.inCarica == true || ricalcolando) return;
    if (_ora().difference(_ultimoRicalcolo) < intervalloRicalcolo) return;
    final scarto = (ora.valore - _prevista(p, metri / 1000)).abs();
    final fattoreCambiato = ((consumo?.imparato.fattore ?? 1) - _fattorePiano).abs() > 0.05;
    if (scarto < scartoPerRicalcolo && !fattoreCambiato) return;
    if (viaggio.opzioni.ricalcoloAutomatico) {
      unawaited(_ricalcola(perConsumo: true));
    } else if (proposta == null) {
      // Si chiede una volta; se si dice di no, se ne riparla fra due minuti.
      _ultimoRicalcolo = _ora();
      proposta = ora.valore < _prevista(p, metri / 1000)
          ? 'Consumi più del previsto: ricalcolo le soste?'
          : 'Consumi meno del previsto: ricalcolo le soste?';
      notifyListeners();
    }
  }

  /// «Ricalcola», dal bottone o dalla scheda: da dove si è, con la batteria
  /// di adesso.
  Future<void> ricalcolaOra() async {
    proposta = null;
    if (!muto) unawaited(voce.parla('Ricalcolo il viaggio.'));
    await _ricalcola(perConsumo: true, detto: true);
  }

  /// Auto termica: si passa da [l] (un distributore) e poi si prosegue
  /// verso la meta di prima.
  Future<void> passaDa(Luogo l) async {
    final d = viaggio.destinazione;
    if (d == null) return;
    final vecchio = pronto, tappaDiPrima = viaggio.tappa;
    viaggio.tappa = l;
    _giroStrade++;
    risparmio?.lascia();
    ricalcolando = true;
    _ultimoRicalcolo = _ora();
    notifyListeners();
    try {
      if (!muto) unawaited(voce.parla('Passo da ${l.nome}, poi proseguo.'));
      // In guida: il viaggio di adesso resta finché non arriva quello nuovo.
      await viaggio.pianifica(d, partenza: _ultimaPosizione, inGuida: attiva);
      if (pronto case final p? when !identical(p, vecchio)) {
        _cambiaGuida(p.viaggio.percorso);
        _nuovoPiano(p);
      } else if (identical(pronto, vecchio)) {
        // Non è arrivato: si resta sulla strada di prima, senza la tappa.
        viaggio.tappa = tappaDiPrima;
      }
    } catch (e) {
      debugPrint('passa da ${l.nome}: $e');
    } finally {
      _finitoIlRicalcolo();
    }
  }

  /// Comunque sia andato il ricalcolo. Rimasto acceso dopo un errore,
  /// «ricalcolando» spegneva i ricalcoli dopo per tutto il viaggio: fuori
  /// strada, la guida non ne faceva più nessuno.
  void _finitoIlRicalcolo() {
    ricalcolando = false;
    notifyListeners();
  }

  /// Il traffico di adesso sulla strada che si sta facendo: l'arrivo si
  /// aggiorna, le code sulla mappa pure; se il ritardo cambia di parecchio
  /// lo si dice.
  Future<void> aggiornaTraffico() async {
    final vecchio = pronto, prima = vecchio?.viaggio.percorso;
    final nuovo = await viaggio.aggiornaTraffico();
    final g = _guida;
    if (nuovo == null || g == null || !attiva) return;
    _guida = g.conTempi(nuovo.viaggio.percorso);
    // Stessa strada e stesso piano: il consumo continua a contare sul viaggio
    // nuovo. Senza, dopo il primo traffico riletto la batteria stimata
    // restava ferma per il resto del viaggio.
    if (identical(_pianoConsumo, vecchio)) _pianoConsumo = nuovo;
    final ritardo = nuovo.viaggio.percorso.ritardoTraffico;
    final differenza = ritardo - (prima?.ritardoTraffico ?? Duration.zero);
    if (differenza.inMinutes.abs() >= 5 && !muto) {
      unawaited(
        voce.parla(
          differenza.isNegative
              ? 'Il traffico si è alleggerito: ${differenza.inMinutes.abs()} minuti in meno.'
              : 'Traffico più avanti: ${differenza.inMinutes} minuti in più.',
        ),
      );
    }
    notifyListeners();
  }

  /// «No» alla proposta.
  void lasciaCosi() {
    proposta = null;
    notifyListeners();
  }

  /// Le strade a risparmio: la strada da qui alla meta si confronta con le
  /// altre, col traffico di adesso; se una vale la proposta, la si dice.
  /// Non con le tappe (le strade migliori vanno dritte alla meta), né quando
  /// manca poco.
  Future<void> controllaStrade() async {
    final r = risparmio, p = pronto, a = avanzamento;
    if (r == null || p == null || a == null || !attiva || ricalcolando) return;
    if (viaggio.tappe.isNotEmpty || viaggio.tappa != null) return;
    if (a.restantiM < 5000 || a.restante < const Duration(minutes: 8)) return;
    final giro = _giroStrade;
    final percorso = p.viaggio.percorso;
    final davanti = restoDelPercorso(percorso, a.percorsiM);
    if (davanti.length < 2) return;
    // Le code ancora davanti: se ce ne sono, magari un'altra strada è più rapida.
    final code = percorso.code.where((c) => c.aM > a.percorsiM).fold(Duration.zero, (t, c) => t + c.ritardo);
    final pr = await r.controlla(
      davanti: davanti,
      evita: PercorsiConZtl.rettangoli(percorso.ztl?.evitate ?? const [], [davanti.first, davanti.last]),
      opzioni: viaggio.opzioni,
      condizioni: viaggio.condizioni ?? const Condizioni(),
      conCode: code >= r.soglie.rapidaDi,
    );
    if (pr == null) return;
    // Mentre si chiedeva si è ricalcolato, o si è finito: non vale più.
    if (giro != _giroStrade || !attiva) {
      r.lascia();
      return;
    }
    if (!muto) unawaited(voce.parla(frasePropostaVoce(pr, elettrica: auto.elettrica)));
    notifyListeners();
  }

  /// «Prendila»: il viaggio si rifà sulla strada proposta, da dove si è.
  Future<void> prendiStrada() async {
    final p = pronto;
    final pr = risparmio?.prendi();
    if (pr == null || p == null || !attiva) return;
    _giroStrade++;
    ricalcolando = true;
    _ultimoRicalcolo = _ora();
    notifyListeners();
    try {
      if (!muto) {
        unawaited(
          voce.parla(
            pr.motivo == MotivoProposta.rapida ? 'Prendo la strada più rapida.' : 'Prendo la strada a risparmio.',
          ),
        );
      }
      // Le ZTL restano quelle di prima: la strada nuova le gira al largo uguale.
      final z = p.viaggio.percorso.ztl;
      // Il viaggio di adesso resta sullo schermo (e in auto) finché non
      // arriva quello sulla strada nuova; se non arriva, resta lui.
      await viaggio.seguiStrada(
        z == null ? pr.percorso : pr.percorso.conZtl(z.senzaDomanda()),
        partenza: _ultimaPosizione,
        inGuida: true,
      );
      if (pronto case final nuovo? when !identical(nuovo, p)) {
        _cambiaGuida(nuovo.viaggio.percorso);
        _nuovoPiano(nuovo);
      }
    } catch (e) {
      debugPrint('strada proposta: $e');
    } finally {
      _finitoIlRicalcolo();
    }
  }

  /// «Resto qui»: quella strada non si ripropone.
  void restaQui() => risparmio?.resta();

  /// La batteria all'arrivo prendendo la strada [pr]: quella di adesso più
  /// quello che si risparmia. Solo senza soste davanti: con una sosta si
  /// risparmia ricarica, non batteria all'arrivo.
  double? batteriaArrivoCon(PropostaStrada pr) {
    final arrivo = batteriaArrivo;
    final capacita = auto.veicolo.capacitaUtileKwh;
    if (arrivo == null || !auto.elettrica || prossimaSosta != null || capacita <= 0) return null;
    return (arrivo + pr.risparmio / capacita * 100).clamp(0.0, 100.0);
  }

  Future<void> _ricalcola({bool perConsumo = false, bool detto = false}) async {
    final d = viaggio.destinazione;
    if (d == null) return;
    // La strada proposta partiva dalla strada di prima: non vale più.
    _giroStrade++;
    risparmio?.lascia();
    ricalcolando = true;
    _ultimoRicalcolo = _ora();
    try {
      final prima = pronto?.viaggio.piano?.soste.map((s) => s.colonnina.id).toList();
      // Le soste scelte già passate non valgono più: si riparte da qui.
      final fatti = avanzamento?.percorsiM ?? 0;
      for (final c in pronto?.viaggio.colonnine ?? const <ColonninaSulPercorso>[]) {
        if (c.distanzaM <= fatti) viaggio.obbligate.remove(c.id);
      }
      // Le tappe e il distributore già passati non si ripetono.
      if (_ultimaPosizione case final q?) viaggio.tappeFatte(q, fattiM: fatti);
      notifyListeners();
      if (!perConsumo && !muto) unawaited(voce.parla('Ricalcolo il percorso.'));
      final qui = _ultimaPosizione;
      final vecchio = pronto;
      if (qui != null && vecchio != null) {
        /* Dalla posizione che si ha già e col verso in cui si va
         * (GestoreViaggio.ricalcolaDa). Il viaggio di prima resta sullo
         * schermo finché non arriva il nuovo; se non arriva resta lui, e la
         * prossima posizione fuori strada riprova.
         *
         * Anche per il consumo: prima si rifaceva il viaggio da capo, che
         * toglie il viaggio mentre calcola. «In autostrada all'improvviso
         * ricalcola il percorso, non avevo uscite»: era questo — la batteria
         * scendeva diversa dal previsto, le soste si rifacevano, e intanto
         * in auto spariva la linea e restava «Calcolo il percorso per…». */
        final fatto = await viaggio.ricalcolaDa(
          qui,
          fattiM: fatti,
          batteria: batteriaOra?.valore,
          rifaiLeSoste: perConsumo,
        );
        if (pronto case final p? when fatto && !identical(p, vecchio)) {
          _cambiaGuida(p.viaggio.percorso);
          _nuovoPiano(p);
          final dopo = p.viaggio.piano?.soste.map((s) => s.colonnina.id).toList();
          if (perConsumo && !detto && !listEquals(prima, dopo) && !muto) {
            unawaited(voce.parla('Ho aggiornato le soste in base al consumo reale.'));
          }
        }
        return;
      }
      // Gli errori del calcolo li tiene pianifica; qui arriva quello che le
      // scappa prima (l'archivio). La guida resta sul percorso di prima, e la
      // prossima posizione fuori strada riprova. Le soste da rifare (il
      // consumo) vogliono il calcolo intero, ma dalla posizione che si ha.
      await viaggio.pianifica(d, partenza: qui);
      if (pronto case final p?) {
        _cambiaGuida(p.viaggio.percorso);
        _nuovoPiano(p);
        final dopo = p.viaggio.piano?.soste.map((s) => s.colonnina.id).toList();
        if (perConsumo && !detto && !listEquals(prima, dopo) && !muto) {
          unawaited(voce.parla('Ho aggiornato le soste in base al consumo reale.'));
        }
      }
    } catch (e) {
      debugPrint('ricalcolo: $e');
    } finally {
      _finitoIlRicalcolo();
    }
  }

  /// A Home Assistant, se abbinato: dove si va, quando si arriva, con quanta
  /// batteria. Se il relay non c'è, niente.
  void _racconta({bool inViaggio = true}) {
    final r = auto.relay, p = pronto;
    if (r == null || p == null) return;
    _ultimoRacconto = _ora();
    final sosta = prossimaSosta;
    unawaited(
      r
          .manda(
            Messaggio(
              tipo: TipoMessaggio.viaggio,
              dati: {
                'in_viaggio': inViaggio,
                'destinazione': {
                  'nome': p.destinazione.nome,
                  'lat': p.destinazione.posizione.lat,
                  'lon': p.destinazione.posizione.lon,
                },
                'eta': ?arrivoAlle?.toUtc().toIso8601String(),
                'batteria_arrivo': ?p.viaggio.piano?.batteriaArrivo,
                if (sosta != null)
                  'prossima_sosta': {'nome': sosta.$1.colonnina.nome, 'batteria_arrivo': sosta.$1.batteriaArrivo},
              },
            ),
          )
          .catchError((Object _) {}),
    );
  }

  void _evento(String nome, [Map<String, Object?> dati = const {}]) {
    final r = auto.relay;
    if (r == null) return;
    unawaited(
      r.manda(Messaggio(tipo: TipoMessaggio.evento, dati: {'evento': nome, ...dati})).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _iscrizione?.cancel();
    _svegliaStima?.cancel();
    versioneSullaMappa.dispose();
    super.dispose();
  }
}
