import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../sorgenti/sorgente_android_auto.dart';
import '../sorgenti/sorgente_manuale.dart';
import 'archivio.dart';

/// Tiene accese le sorgenti dei dati dell'auto e dice all'interfaccia
/// quale stato vale adesso, secondo lo switch «Fonte dati auto».
class GestoreAuto extends ChangeNotifier {
  GestoreAuto({required this.archivio})
    : arbitro = ArbitroSorgenti(capacitaUtileKwh: ProfiloVeicolo.esempio.capacitaUtileKwh);

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

  /// Le sorgenti che questo telefono può usare adesso, per lo switch.
  Iterable<TipoSorgente> get disponibili => _sorgenti.keys;

  Future<void> avvia() async {
    veicolo = await archivio.veicolo();
    arbitro.capacitaUtileKwh = veicolo.capacitaUtileKwh;
    arbitro.modalita = await archivio.fonte();
    abbinamento = await archivio.abbinamento();
    await _accendi(manuale);
    await _accendi(SorgenteAndroidAuto());
    if (abbinamento != null) await _accendi(SorgenteHomeAssistant(ClienteRelay(abbinamento!)));
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
    await _accendi(SorgenteHomeAssistant(ClienteRelay(a)));
    notifyListeners();
  }

  Future<void> scollega() async {
    await _spegni(TipoSorgente.homeAssistant);
    abbinamento = null;
    await archivio.salvaAbbinamento(null);
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
    notifyListeners();
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
