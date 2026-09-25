import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../sorgenti/canale_ble.dart';
import '../sorgenti/sorgente_android_auto.dart';
import '../sorgenti/sorgente_manuale.dart';
import 'archivio.dart';

/// Tiene accese le sorgenti dei dati dell'auto e dice all'interfaccia
/// quale stato vale adesso, secondo lo switch «Fonte dati auto».
class GestoreAuto extends ChangeNotifier {
  GestoreAuto({required this.archivio, Future<CanaleObd> Function(String id)? apriObd})
    : arbitro = ArbitroSorgenti(capacitaUtileKwh: ProfiloVeicolo.esempio.capacitaUtileKwh),
      _apriObd = apriObd ?? CanaleBle.apri;

  final Future<CanaleObd> Function(String id) _apriObd;

  /// La foto della propria auto, se l'utente l'ha messa.
  String? foto;

  Future<void> impostaFoto(String? percorso) async {
    foto = percorso;
    await archivio.salvaFotoAuto(percorso);
    notifyListeners();
  }

  /// Il dongle OBD scelto, se c'è.
  ({String id, String nome})? dongle;

  /// Perché il dongle non dà dati, in parole; `null` se va.
  String? get erroreObd => switch (_sorgenti[TipoSorgente.obd]) {
    final SorgenteObd s => s.ultimoErrore,
    _ => null,
  };

  final Archivio archivio;
  final ArbitroSorgenti arbitro;
  final manuale = SorgenteManuale();

  final _sorgenti = <TipoSorgente, SorgenteDatiAuto>{};
  final _iscrizioni = <StreamSubscription<StatoAuto>>[];
  Timer? _orologio;

  Abbinamento? abbinamento;

  /// L'auto dell'utente: da lei dipendono consumi, soste e prese.
  ProfiloVeicolo veicolo = ProfiloVeicolo.esempio;
  StatoAuto? stato;

  ModalitaFonte get modalita => arbitro.modalita;

  /// Il filo con Home Assistant, se l'auto è abbinata: la guida ci manda
  /// viaggio ed eventi.
  ClienteRelay? get relay => switch (_sorgenti[TipoSorgente.homeAssistant]) {
    final SorgenteHomeAssistant s => s.relay,
    _ => null,
  };

  /// Le sorgenti che questo telefono può usare adesso, per lo switch.
  Iterable<TipoSorgente> get disponibili => _sorgenti.keys;

  /// Home Assistant fa parte di Premium: senza, l'abbinamento resta salvato
  /// ma il collegamento non parte.
  var homeAssistantConsentito = true;

  Future<void> consentiHomeAssistant(bool si) async {
    if (si == homeAssistantConsentito) return;
    homeAssistantConsentito = si;
    if (!si) {
      await _spegni(TipoSorgente.homeAssistant);
    } else if (abbinamento case final a?) {
      await _accendi(SorgenteHomeAssistant(ClienteRelay(a)));
    }
    notifyListeners();
  }

  /// In viaggio: che Home Assistant rilegga l'auto e mandi i dati freschi.
  Future<void> chiediAggiornamento() async {
    if (_sorgenti[TipoSorgente.homeAssistant] case final SorgenteHomeAssistant h) await h.chiediAggiornamento();
  }

  Future<void> avvia() async {
    veicolo = await archivio.veicolo();
    arbitro.capacitaUtileKwh = veicolo.capacitaUtileKwh;
    arbitro.modalita = await archivio.fonte();
    abbinamento = await archivio.abbinamento();
    await _accendi(manuale);
    await _accendi(SorgenteAndroidAuto(onVelocita: _velocita));
    if (abbinamento != null && homeAssistantConsentito) {
      await _accendi(SorgenteHomeAssistant(ClienteRelay(abbinamento!)));
    }
    foto = await archivio.fotoAuto();
    dongle = await archivio.dongleObd();
    if (dongle != null) unawaited(_accendiObd());
    // Anche senza letture nuove l'età del dato cambia: si ricalcola ogni tanto.
    _orologio = Timer.periodic(const Duration(seconds: 5), (_) => _aggiorna());
  }

  Future<void> scegliVeicolo(ProfiloVeicolo v) async {
    veicolo = v;
    arbitro.capacitaUtileKwh = v.capacitaUtileKwh;
    await archivio.salvaVeicolo(v);
    notifyListeners();
  }

  /// I chilometri che restano: quelli dell'auto se li dice, altrimenti una
  /// stima a 90 km/h in piano con il modello di consumo.
  double? autonomiaKm() {
    final s = stato;
    if (s == null) return null;
    if (s.autonomiaKm != null && s.sorgente != TipoSorgente.stima) return s.autonomiaKm;
    final whKm = consumoMedioWhKm(const [Tratto(lunghezzaM: 1000, velocitaKmh: 90)], veicolo);
    return s.batteria / 100 * veicolo.capacitaUtileKwh * 1000 / whKm;
  }

  Future<void> cambiaModalita(ModalitaFonte m) async {
    arbitro.modalita = m;
    await archivio.salvaFonte(m);
    _aggiorna();
  }

  Future<void> abbina(Abbinamento a) async {
    await _spegni(TipoSorgente.homeAssistant);
    abbinamento = a;
    await archivio.salvaAbbinamento(a);
    if (homeAssistantConsentito) await _accendi(SorgenteHomeAssistant(ClienteRelay(a)));
    notifyListeners();
  }

  Future<void> scollega() async {
    await _spegni(TipoSorgente.homeAssistant);
    abbinamento = null;
    await archivio.salvaAbbinamento(null);
    notifyListeners();
  }

  /// Il dongle col profilo della marca dell'auto (quello standard se non
  /// c'è ancora uno specifico).
  Future<void> _accendiObd() async {
    final d = dongle;
    if (d == null) return;
    await _accendi(SorgenteObd(apri: () => _apriObd(d.id), profilo: profiloPerMarca(veicolo.marca)));
    notifyListeners();
  }

  Future<void> usaDongle(String id, String nome) async {
    await _spegni(TipoSorgente.obd);
    dongle = (id: id, nome: nome);
    await archivio.salvaDongleObd(dongle);
    notifyListeners();
    await _accendiObd();
  }

  /// Il giro di sola lettura per conoscere l'auto: si ferma la lettura
  /// normale, si esplora, si riaccende.
  Future<String> esploraObd({void Function(String riga)? onRiga}) async {
    final d = dongle;
    if (d == null) throw const ErroreObd('nessun dongle scelto');
    await _spegni(TipoSorgente.obd);
    Elm327? elm;
    try {
      elm = Elm327(await _apriObd(d.id));
      final auto = '# ${veicolo.nome} · dongle ${d.nome}';
      onRiga?.call(auto);
      return '$auto\n${await EsploraObd(elm, onRiga: onRiga).esegui()}';
    } finally {
      await elm?.chiudi().catchError((Object _) {});
      await _accendiObd();
    }
  }

  Future<void> togliDongle() async {
    await _spegni(TipoSorgente.obd);
    dongle = null;
    await archivio.salvaDongleObd(null);
    notifyListeners();
  }

  Future<void> _accendi(SorgenteDatiAuto s) async {
    _sorgenti[s.tipo] = s;
    _iscrizioni.add(
      s.letture.listen((l) {
        arbitro.registra(l);
        _aggiorna();
      }),
    );
    try {
      await s.avvia();
    } catch (e) {
      debugPrint('Sorgente ${s.tipo.name} non disponibile: $e');
    }
  }

  Future<void> _spegni(TipoSorgente tipo) async {
    await _sorgenti.remove(tipo)?.ferma();
  }

  void _aggiorna() {
    stato = arbitro.statoAttuale(DateTime.now());
    if (stato?.velocitaKmh case final v?) _velocita(v, notifica: false);
    notifyListeners();
  }

  /// La velocità del cruscotto (Android Auto, Home Assistant), per il
  /// tachimetro: più precisa del GPS.
  double? _velocitaAuto;
  DateTime? _velocitaLetta;

  void _velocita(double kmh, {bool notifica = true}) {
    _velocitaAuto = kmh;
    _velocitaLetta = DateTime.now();
    if (notifica) notifyListeners();
  }

  /// `null` se l'auto non la dice o tace da più di tre secondi.
  double? velocitaAuto() {
    final t = _velocitaLetta;
    if (t == null || DateTime.now().difference(t) > const Duration(seconds: 3)) return null;
    return _velocitaAuto;
  }

  @override
  void dispose() {
    _orologio?.cancel();
    for (final i in _iscrizioni) {
      i.cancel();
    }
    for (final s in _sorgenti.values) {
      s.ferma();
    }
    super.dispose();
  }
}
