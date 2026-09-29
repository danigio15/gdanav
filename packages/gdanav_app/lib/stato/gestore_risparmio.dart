import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';
import 'gestore_auto.dart';
import 'gestore_ztl.dart';

/// Chiede le strade migliori di quella che si fa: [davanti] è il pezzo che
/// resta. Il primo è la strada di adesso rifatta col traffico, gli altri le
/// migliori (vedi [ClienteTomTom.migliori]).
typedef CercaStrade = Future<List<PercorsoCalcolato>> Function(
  List<Punto> davanti, {
  required bool eco,
  ModelloConsumoTomTom? consumo,
  List<Rettangolo> evita,
  OpzioniPercorso opzioni,
});

/// Le strade migliori chieste a TomTom, se c'è la chiave; senza, nessuna.
CercaStrade cercaConTomTom(Archivio archivio) =>
    (davanti, {required eco, consumo, evita = const [], opzioni = const OpzioniPercorso()}) async {
      final i = await archivio.impostazioni();
      if (!i.percorsiDaTomTom) return const <PercorsoCalcolato>[];
      // La deviazione almeno a un chilometro: a 130 all'ora sono ventotto
      // secondi, abbastanza per leggere la proposta e decidere.
      return ClienteTomTom(i.chiaveTomTom)
          .migliori(davanti, eco: eco, consumo: consumo, evita: evita, opzioni: opzioni, staccoM: 1000);
    };

/// Le soglie come si salvano.
Map<String, Object?> soglieJson(SoglieRisparmio s) => {
  'proponi': s.proponi,
  'minimo_percento': s.minimoPercento,
  'massimo_in_piu_min': s.massimoInPiu.inMinutes,
  'anche_rapide': s.ancheRapide,
};

SoglieRisparmio soglieDaJson(Map<String, Object?> j) {
  const d = SoglieRisparmio();
  return SoglieRisparmio(
    proponi: j['proponi'] as bool? ?? d.proponi,
    minimoPercento: (j['minimo_percento'] as num?)?.toDouble() ?? d.minimoPercento,
    massimoInPiu: switch (j['massimo_in_piu_min']) {
      final num m => Duration(minutes: m.toInt()),
      _ => d.massimoInPiu,
    },
    ancheRapide: j['anche_rapide'] as bool? ?? d.ancheRapide,
  );
}

SoglieRisparmio copiaSoglie(
  SoglieRisparmio s, {
  bool? proponi,
  double? minimoPercento,
  Duration? massimoInPiu,
  bool? ancheRapide,
}) => SoglieRisparmio(
  proponi: proponi ?? s.proponi,
  minimoPercento: minimoPercento ?? s.minimoPercento,
  massimoInPiu: massimoInPiu ?? s.massimoInPiu,
  ancheRapide: ancheRapide ?? s.ancheRapide,
  rapidaDi: s.rapidaDi,
);

/// Le strade a risparmio, come in ABRP: le soglie scelte nelle impostazioni
/// e, in guida, la strada proposta se ce n'è una che vale il disturbo.
///
/// Il confronto lo fa TomTom col modello di consumo dell'auto: la strada di
/// adesso rifatta da dove si è, e le sole alternative che la battono — che
/// consumano meno, o (con [SoglieRisparmio.ancheRapide]) che arrivano prima.
/// Una strada rifiutata, o lasciata scadere, non si ripropone.
class GestoreRisparmio extends ChangeNotifier {
  GestoreRisparmio({
    required this.archivio,
    required this.auto,
    this.cerca,
    this.ztl,
    this.durataProposta = const Duration(seconds: 20),
    DateTime Function()? orologio,
  }) : _ora = orologio ?? DateTime.now;

  /// Quello dell'app, per chi calcola i percorsi (`pianificatoreVero`).
  static GestoreRisparmio? attuale;

  final Archivio archivio;
  final GestoreAuto auto;

  /// Come si chiedono le strade migliori. `null`: non si propone niente.
  final CercaStrade? cerca;

  /// Le ZTL: una strada proposta non deve entrare in una ZTL attiva senza
  /// permesso.
  final GestoreZtl? ztl;

  /// Dopo quanto la proposta si chiude da sola, e si resta dove si è.
  final Duration durataProposta;
  final DateTime Function() _ora;

  SoglieRisparmio soglie = const SoglieRisparmio();

  Future<void> carica() async {
    soglie = await archivio.soglieRisparmio();
    notifyListeners();
  }

  Future<void> cambia(SoglieRisparmio s) async {
    soglie = s;
    if (!s.proponi) _chiudi();
    notifyListeners();
    await archivio.salvaSoglieRisparmio(s);
  }

  /// Il modello di consumo dell'auto, come lo vuole TomTom.
  ModelloConsumoTomTom modello([Condizioni c = const Condizioni()]) =>
      auto.elettrica ? ModelloConsumoTomTom.elettrica(auto.veicolo, c) : ModelloConsumoTomTom.termica(auto.carburante);

  /// Quanto consuma [p] se TomTom non l'ha detto: col profilo dell'auto.
  double stima(PercorsoCalcolato p, [Condizioni c = const Condizioni()]) => auto.elettrica
      ? energiaPercorsoKwh(p.tratti, auto.veicolo, c)
      : p.tratti.fold(
          0.0,
          (s, t) => s + ModelloConsumoTomTom.litriTratto(t.lunghezzaM, t.velocitaKmh, auto.carburante),
        );

  /// Di cosa sono i consumi: «kWh», «l» o «kg».
  String get unita => auto.elettrica
      ? 'kWh'
      : auto.carburante == Carburante.metano
      ? 'kg'
      : 'l';

  /// La strada proposta adesso, e da quando: la barra che si svuota.
  PropostaStrada? proposta;
  DateTime? propostaAlle;
  Timer? _scade;
  final _rifiutate = <Set<String>>[];
  var _cercando = false;

  /// Si confronta la strada che si fa ([davanti], da dove si è alla meta)
  /// con le altre: se ce n'è una che vale, diventa la [proposta]. Le ZTL già
  /// evitate restano evitate ([evita]); [conCode] vuol dire che davanti c'è
  /// traffico, e allora si cercano anche le strade più rapide.
  Future<PropostaStrada?> controlla({
    required List<Punto> davanti,
    List<Rettangolo> evita = const [],
    OpzioniPercorso opzioni = const OpzioniPercorso(),
    Condizioni condizioni = const Condizioni(),
    bool conCode = false,
  }) async {
    final c = cerca;
    if (c == null || !soglie.proponi || _cercando || proposta != null || davanti.length < 2) return null;
    _cercando = true;
    try {
      final m = modello(condizioni);
      Future<List<PercorsoCalcolato>> chiedi({required bool eco}) => c(
        davanti,
        eco: eco,
        consumo: m,
        evita: evita,
        opzioni: opzioni,
      ).timeout(const Duration(seconds: 40)).catchError((Object _) => const <PercorsoCalcolato>[]);
      final rapide = soglie.ancheRapide && conCode;
      final risposte = await Future.wait([chiedi(eco: true), if (rapide) chiedi(eco: false)]);
      final eco = risposte.first, veloci = risposte.length > 1 ? risposte[1] : const <PercorsoCalcolato>[];
      final adesso = eco.firstOrNull ?? veloci.firstOrNull;
      if (adesso == null) return null;
      final ora = _ora();
      final zone = await ztl?.zone().catchError((Object _) => ArchivioZtl.vuoto);
      final permessi = ztl?.permessi ?? const <String, bool>{};
      bool ammessa(PercorsoCalcolato p) => zone == null || PercorsiConZtl.vietate(zone, p, ora, permessi).isEmpty;
      final pr = scegliProposta(
        adesso: adesso,
        eco: [...eco.skip(1).where(ammessa)],
        rapide: [...veloci.skip(1).where(ammessa)],
        soglie: soglie,
        consumo: (p) => consumoStrada(p, (q) => stima(q, condizioni)),
        rifiutate: _rifiutate,
      );
      // Nel frattempo si è spento, o è finito il viaggio.
      if (pr == null || !soglie.proponi || proposta != null) return null;
      _proponi(pr);
      return pr;
    } finally {
      _cercando = false;
    }
  }

  void _proponi(PropostaStrada p) {
    proposta = p;
    propostaAlle = _ora();
    _scade?.cancel();
    _scade = Timer(durataProposta, () {
      if (identical(proposta, p)) resta();
    });
    notifyListeners();
  }

  /// «Resto qui», o nessuna risposta: quella strada non si ripropone.
  void resta() {
    final p = proposta;
    if (p == null) return;
    _rifiutate.add(p.firma);
    _chiudi();
  }

  /// «Prendila»: la proposta passa a chi guida, che rifà il viaggio lì.
  PropostaStrada? prendi() {
    final p = proposta;
    _chiudi();
    return p;
  }

  /// Si ricalcola, o il viaggio è finito: la proposta non vale più.
  void lascia() => _chiudi();

  /// Un viaggio nuovo: anche le strade rifiutate si dimenticano.
  void dimentica() {
    _rifiutate.clear();
    _chiudi();
  }

  void _chiudi() {
    _scade?.cancel();
    _scade = null;
    if (proposta == null) return;
    proposta = null;
    propostaAlle = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _scade?.cancel();
    super.dispose();
  }
}

/// Il nome di ognuna delle [scelte], come in ABRP, col consumo che dice
/// TomTom (o, se non l'ha detto, il profilo dell'auto).
List<EtichettaStrada> etichetteDi(List<PercorsoCalcolato> scelte, GestoreRisparmio r) =>
    etichetteStrade(scelte, (p) => consumoStrada(p, r.stima), minimoPercento: r.soglie.minimoPercento);

/// Quale delle [scelte] risparmia energia, per disegnarla verde; `null` se
/// nessuna.
int? stradaCheRisparmia(List<PercorsoCalcolato> scelte, GestoreRisparmio? r) {
  if (r == null || scelte.length < 2) return null;
  final i = etichetteDi(scelte, r).indexOf(EtichettaStrada.risparmia);
  return i < 0 ? null : i;
}

/// «1,8 kWh», «0,6 l»: con la virgola, come si scrive in Italia.
String quantita(double v, String unita) => '${v.abs().toStringAsFixed(1).replaceAll('.', ',')} $unita';

/// «−1,8 kWh», «+0,4 kWh». Sulla mappa [meno] è il trattino: il segno meno
/// non c'è in tutti i caratteri.
String quantitaConSegno(double v, String unita, {String meno = '−'}) => '${v < 0 ? meno : '+'}${quantita(v, unita)}';

/// «+4 min», «−6 min», «+1 h 05», o «stesso tempo».
String minutiConSegno(Duration d, {String meno = '−'}) {
  final m = (d.inSeconds / 60).round();
  if (m == 0) return 'stesso tempo';
  final segno = m > 0 ? '+' : meno;
  final a = m.abs();
  return a < 60 ? '$segno$a min' : '$segno${a ~/ 60} h ${(a % 60).toString().padLeft(2, '0')}';
}

/// La proposta in poche parole, per il fumetto sulla mappa e per l'auto:
/// «−1,8 kWh · +4 min», o per quella più rapida «−6 min · +0,4 kWh».
String sintesiProposta(PropostaStrada p, String unita, {String meno = '−'}) {
  final energia = quantitaConSegno(-p.risparmio, unita, meno: meno);
  final tempo = minutiConSegno(p.differenza, meno: meno);
  return switch (p.motivo) {
    MotivoProposta.risparmio => '$energia · $tempo',
    MotivoProposta.rapida => p.risparmio.abs() < 0.05 ? tempo : '$tempo · $energia',
  };
}

/// Il titolo della proposta.
String titoloProposta(PropostaStrada p, {required bool elettrica}) => switch (p.motivo) {
  MotivoProposta.risparmio =>
    elettrica ? 'C\'è una strada che risparmia energia' : 'C\'è una strada che risparmia carburante',
  MotivoProposta.rapida => 'C\'è una strada più rapida',
};

/// «per la SS 18, senza autostrada».
String? doveProposta(PropostaStrada p) {
  final parti = [if (p.via.isNotEmpty) 'per la ${p.via}', if (p.senzaAutostrada) 'senza autostrada'];
  return parti.isEmpty ? null : parti.join(', ');
}

/// Quello che dice la voce quando arriva una proposta.
String frasePropostaVoce(PropostaStrada p, {required bool elettrica}) {
  final m = (p.differenza.inSeconds / 60).round();
  final tempo = m == 0
      ? 'nello stesso tempo'
      : m > 0
      ? '${m == 1 ? 'un minuto' : '$m minuti'} in più'
      : '${m == -1 ? 'un minuto' : '${-m} minuti'} in meno';
  return switch (p.motivo) {
    MotivoProposta.risparmio => '${titoloProposta(p, elettrica: elettrica)}, $tempo.',
    MotivoProposta.rapida => 'C\'è una strada più rapida: $tempo.',
  };
}
