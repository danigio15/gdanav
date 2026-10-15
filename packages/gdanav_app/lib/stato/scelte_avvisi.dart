import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Gli avvisi della guida, uno per uno: le segnalazioni della strada, le ZTL
/// e il limite di velocità.
enum Avviso {
  autovelox('Autovelox', 'Fissi e segnalati'),
  tutor('Tutor', 'La tua media sul tratto controllato'),
  polizia('Polizia', 'Segnalata da chi passa'),
  incidente('Incidenti', 'Segnalati da chi passa'),
  pericolo('Pericoli', 'Oggetti, animali, auto ferme'),
  lavori('Lavori in corso', 'Segnalati da chi passa'),
  chiusura('Strade chiuse', 'Segnalate da chi passa'),
  traffico('Traffico', 'Code segnalate da chi passa'),
  ztl('ZTL e aree pedonali', 'Attive, sul percorso o davanti'),
  limite('Limite di velocità', 'Quando lo si supera');

  const Avviso(this.nome, this.sotto);

  final String nome;
  final String sotto;

  /// Il limite non ha un riquadro suo: a schermo c'è il tachimetro, che
  /// diventa rosso comunque. Si sceglie solo se dirlo a voce.
  bool get soloVoce => this == limite;

  static Avviso diSegnalazione(TipoSegnalazione t) => values.byName(t.name);

  /// Le segnalazioni hanno un avviso ciascuna; il Tutor, la ZTL e il limite
  /// no.
  TipoSegnalazione? get segnalazione => TipoSegnalazione.values.where((t) => t.name == name).firstOrNull;
}

/// Come avvisare.
enum ComeAvvisare {
  /// Detto a voce e mostrato nel riquadro in guida.
  voce('A voce'),

  /// Il riquadro in guida, senza voce.
  schermo('Schermo'),

  /// Niente: né voce né riquadro, e le segnalazioni spariscono dalla mappa.
  spento('Spento');

  const ComeAvvisare(this.etichetta);

  final String etichetta;
}

/// Come si vuole essere avvisati, avviso per avviso. Di partenza tutti a
/// voce, come prima. Vale sul telefono e sullo schermo dell'auto, e si
/// somma al tasto dell'audio: col silenzio tace tutto lo stesso.
class ScelteAvvisi extends ChangeNotifier {
  ScelteAvvisi([Map<Avviso, ComeAvvisare> iniziali = const {}, this.onCambia]) : _scelte = {...iniziali};

  final Map<Avviso, ComeAvvisare> _scelte;

  /// Chi le salva.
  final void Function(ScelteAvvisi)? onCambia;

  ComeAvvisare di(Avviso a) {
    final c = _scelte[a] ?? ComeAvvisare.voce;
    // Il limite non ha un riquadro: «solo schermo» è il tachimetro, e basta.
    return a.soloVoce && c == ComeAvvisare.spento ? ComeAvvisare.schermo : c;
  }

  bool aVoce(Avviso a) => di(a) == ComeAvvisare.voce;
  bool spento(Avviso a) => di(a) == ComeAvvisare.spento;

  void scegli(Avviso a, ComeAvvisare c) {
    if (a.soloVoce && c == ComeAvvisare.spento) c = ComeAvvisare.schermo;
    if (di(a) == c) return;
    if (c == ComeAvvisare.voce) {
      _scelte.remove(a);
    } else {
      _scelte[a] = c;
    }
    notifyListeners();
    onCambia?.call(this);
  }

  /// Per il menu: «Tutti a voce», «2 spenti · 1 solo schermo».
  String get riassunto {
    final spenti = Avviso.values.where(spento).length;
    final schermo = Avviso.values.where((a) => di(a) == ComeAvvisare.schermo).length;
    if (spenti == 0 && schermo == 0) return 'Tutti a voce';
    return [
      if (spenti > 0) spenti == 1 ? '1 spento' : '$spenti spenti',
      if (schermo > 0) '$schermo solo a schermo',
    ].join(' · ');
  }

  String aJson() => jsonEncode({for (final e in _scelte.entries) e.key.name: e.value.name});

  static Map<Avviso, ComeAvvisare> daJson(String? testo) {
    if (testo == null || testo.isEmpty) return const {};
    try {
      final j = jsonDecode(testo);
      if (j is! Map) return const {};
      final scelte = <Avviso, ComeAvvisare>{};
      for (final e in j.entries) {
        final a = Avviso.values.where((a) => a.name == e.key).firstOrNull;
        final c = ComeAvvisare.values.where((c) => c.name == e.value).firstOrNull;
        if (a != null && c != null) scelte[a] = c;
      }
      return scelte;
    } on FormatException {
      return const {};
    }
  }
}
