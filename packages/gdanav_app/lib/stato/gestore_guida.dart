import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';
import 'gestore_auto.dart';
import 'gestore_consumo.dart';
import 'gestore_risparmio.dart';
import 'gestore_viaggio.dart';
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
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now {
    audio = audioIniziale;
  }

  /// Il consumo imparato: in guida lo si misura e lo si corregge.
  final GestoreConsumo? consumo;

  /// Le strade a risparmio: ogni tanto la strada che si fa si confronta con
  /// le altre, e se una vale la pena la si propone.
  final GestoreRisparmio? risparmio;

  /// Archivio delle preferenze persistenti del navigatore.
  final Archivio? archivio;

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

  DateTime? _partitoAlle;

  /// La batteria quando si è partiti (anche dopo un ricalcolo).
  double? get batteriaPartenza => _batteriaInizio ?? pronto?.batteriaPartenza;

  /// La batteria adesso: quella vera se l'auto l'ha mandata dopo la
  /// partenza (Home Assistant, Android Auto), altrimenti la stima del piano
  /// al punto in cui si è.
  ({double valore, bool misurata})? get batteriaOra {
    final p = pronto;
    if (p == null || p.soloPercorso) return null;
    final s = auto.stato, partito = _partitoAlle;
    if (s != null &&
        partito != null &&
        !s.letto.isBefore(partito) &&
        s.sorgente != TipoSorgente.manuale &&
        s.sorgente != TipoSorgente.stima) {
      return (valore: s.batteria, misurata: true);
    }
    return (valore: _prevista(p, (avanzamento?.percorsiM ?? 0) / 1000), misurata: false);
  }

  /// La batteria all'arrivo: il piano, con la pendenza corretta da quanto la
  /// macchina beve davvero. Il conto è in [batteriaAllArrivo].
  double? get batteriaArrivo {
    final p = pronto, ora = batteriaOra, piano = p?.viaggio.piano;
    if (p == null || piano == null || ora == null) return null;
    if (!ora.misurata) return piano.batteriaArrivo;
    final km = (avanzamento?.percorsiM ?? 0) / 1000;
    return batteriaAllArrivo(
      adesso: ora.valore,
      pianoAdesso: _prevista(p, km),
      pianoArrivo: piano.batteriaArrivo,
      fattore: _fattoreDelConsumo,
      dopoLUltimaSosta: _dopoLUltimaSosta(piano, km),
    );
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
  /// gdahome, Android Auto, OBD), com'è se è recente e altrimenti portata
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

  void avvia() {
    final p = pronto;
    if (p == null || attiva) return;
    attiva = true;
    _partitoAlle = _ora();
    _vicinoDetto = false;
    _guida = Guida(p.viaggio.percorso);
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
    _nuovoPiano(p);
    auto.addListener(_datiAuto);
    // Un errore del GPS non deve finire nel vuoto né chiudere la guida: la
    // posizione dopo arriva lo stesso.
    _iscrizione = posizioni().listen(_posizione, onError: (Object e) => debugPrint('posizioni in guida: $e'));
    _ultimaRichiestaDati = DateTime(0);
    _forseChiediDati();
    _evento('partenza');
    _racconta();
    notifyListeners();
  }

  Future<void> ferma() async {
    attiva = false;
    _giroStrade++;
    risparmio?.lascia();
    auto.removeListener(_datiAuto);
    _misuratore = null;
    await _iscrizione?.cancel();
    _iscrizione = null;
    await voce.zitta();
    _racconta(inViaggio: false);
    notifyListeners();
  }

  /// Un messaggio del viaggio fuori dalle manovre: tace con la voce di guida.
  void annuncia(String frase) {
    if (!muto) unawaited(voce.parla(frase));
  }

  /// Un avviso: autovelox, segnalazioni, ZTL, limite. Si sente anche con la
  /// voce di guida spenta («Solo avvisi»); tace solo col silenzio.
  void annunciaAvviso(String frase) {
    if (!audio.senzaAvvisi) unawaited(voce.parla(frase));
  }

  /// Il tasto dell'audio: Tutto → Solo avvisi → Silenzio → Tutto.
  void alternaVoce() {
    audio = audio.dopo;
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
    annunciaAvviso('Attenzione, il limite è $limite.');
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
  /// mappa ci mette a disegnare.
  static const anticipo = Duration(milliseconds: 300);

  /// Mai più avanti di così: un GPS che tace non deve far correre l'auto da
  /// sola lungo la strada.
  static const avantiAlPiuM = 60.0;

  /// Cresce a ogni posizione: chi segue l'auto (la telecamera) si muove una
  /// volta per posizione, non a ogni novità della guida.
  int get letture => _letture;
  var _letture = 0;
  DateTime? _lettaAlle;
  double? _velocitaMs;

  /// Dove disegnare l'auto adesso e la direzione della strada lì; `null`
  /// se non si è agganciati alla strada (si disegna il punto del GPS).
  ({Punto punto, double rotta})? posizioneStimata() {
    final a = avanzamento, g = _guida, sulla = a?.posizioneSulPercorso, rotta = a?.rotta;
    if (a == null || g == null || sulla == null || rotta == null) return null;
    final v = _velocitaMs, alle = _lettaAlle;
    if (v == null || alle == null || v < 1.5) return (punto: sulla, rotta: rotta);
    var eta = _ora().difference(alle);
    if (eta.isNegative) eta = Duration.zero;
    if (eta > const Duration(seconds: 2)) eta = const Duration(seconds: 2);
    final metri = v * (eta + anticipo).inMilliseconds / 1000;
    return g.avanti(a.percorsiM, metri > avantiAlPiuM ? avantiAlPiuM : metri);
  }

  Future<void> _posizione(Punto qui) async {
    _ultimaPosizione = qui;
    _letture++;
    final ora = _ora();
    // L'ora della lettura del GPS, se è credibile; altrimenti adesso.
    final letta = qui is PuntoInMoto ? qui.alle : null;
    _lettaAlle = letta != null && !letta.isAfter(ora) && ora.difference(letta) < const Duration(seconds: 5)
        ? letta
        : ora;
    final kmh = auto.velocitaAuto();
    _velocitaMs = kmh != null ? kmh / 3.6 : (qui is PuntoInMoto ? qui.velocitaMs : null);
    _forseChiediDati();
    final g = _guida;
    if (g == null || !attiva) return;
    final a = g.aggiorna(qui);
    avanzamento = a;
    _controllaLimite(a.limiteKmh, _velocitaKmh(qui));
    // Arrivati al distributore: da qui si prosegue verso la meta.
    // Arrivati a una tappa (o al distributore): da qui si prosegue.
    viaggio.tappeFatte(qui);
    if (a.daDire case final frase? when !muto) unawaited(voce.parla(frase));
    if (a.arrivato) {
      _evento('arrivo');
      notifyListeners();
      await ferma();
      return;
    }
    if (!_vicinoDetto && a.restante.inMinutes < 10) {
      _vicinoDetto = true;
      _evento('arrivo_vicino', {'minuti': a.restante.inMinutes});
    }
    if (a.fuoriPercorso && !ricalcolando) unawaited(_ricalcola());
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

  /// Si comincia a misurare sul piano nuovo, col modello senza correttivo.
  void _nuovoPiano(ViaggioPronto p) {
    // Auto termica, o elettrica senza soste: niente piano da misurare.
    if (p.soloPercorso) {
      _misuratore = null;
      return;
    }
    final senza = consumo?.condizioni(auto.stato, conFattore: false) ?? const Condizioni();
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
    final misura = _misuratore?.registra(batteria: s.batteria, metri: metri, inCarica: s.inCarica == true);
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
    viaggio.tappa = l;
    _giroStrade++;
    risparmio?.lascia();
    ricalcolando = true;
    _ultimoRicalcolo = _ora();
    notifyListeners();
    try {
      if (!muto) unawaited(voce.parla('Passo da ${l.nome}, poi proseguo.'));
      await viaggio.pianifica(d, partenza: _ultimaPosizione);
      if (pronto case final p?) {
        _guida = Guida(p.viaggio.percorso);
        _nuovoPiano(p);
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
    final prima = pronto?.viaggio.percorso;
    final nuovo = await viaggio.aggiornaTraffico();
    final g = _guida;
    if (nuovo == null || g == null || !attiva) return;
    _guida = g.conTempi(nuovo.viaggio.percorso);
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
      await viaggio.seguiStrada(
        z == null ? pr.percorso : pr.percorso.conZtl(z.senzaDomanda()),
        partenza: _ultimaPosizione,
      );
      if (pronto case final nuovo?) {
        _guida = Guida(nuovo.viaggio.percorso);
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
      if (!perConsumo && qui != null && vecchio != null) {
        /* Fuori strada: solo il percorso, dalla posizione che si ha già e col
         * verso in cui si va (GestoreViaggio.ricalcolaDa). Il viaggio di prima
         * resta sullo schermo finché non arriva il nuovo; se non arriva resta
         * lui, e la prossima posizione fuori strada riprova. */
        final fatto = await viaggio.ricalcolaDa(qui, fattiM: fatti, batteria: batteriaOra?.valore);
        if (pronto case final p? when fatto && !identical(p, vecchio)) {
          _guida = Guida(p.viaggio.percorso);
          _nuovoPiano(p);
        }
        return;
      }
      // Gli errori del calcolo li tiene pianifica; qui arriva quello che le
      // scappa prima (l'archivio). La guida resta sul percorso di prima, e la
      // prossima posizione fuori strada riprova. Le soste da rifare (il
      // consumo) vogliono il calcolo intero, ma dalla posizione che si ha.
      await viaggio.pianifica(d, partenza: qui);
      if (pronto case final p?) {
        _guida = Guida(p.viaggio.percorso);
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
    super.dispose();
  }
}
