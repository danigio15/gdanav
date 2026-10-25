import 'dart:async';

import 'package:flutter/foundation.dart';

/// Come si guarda la mappa.
///
/// [piatta]: dall'alto, il nord in su. [inclinata] (3D): inclinata, girata
/// come si va, con gli edifici in rilievo. [immersiva]: ancora più bassa e
/// più vicina, le strade larghe quanto sono davvero, il percorso che passa
/// fra le case, e prima di una manovra le corsie disegnate sulla strada.
enum VistaMappa {
  piatta('2D', 'Dall\'alto'),
  inclinata('3D', '3D'),
  immersiva('Immersiva', 'Immersiva');

  const VistaMappa(this.sigla, this.nome);

  /// Quello che c'è scritto sul tasto.
  final String sigla;

  /// Il nome nella scelta.
  final String nome;

  /// La vista salvata, da una parola; quella di partenza se non si capisce.
  static VistaMappa daNome(String? nome) =>
      VistaMappa.values.firstWhere((v) => v.name == nome, orElse: () => VistaMappa.inclinata);
}

/// I comandi della mappa che stanno fuori dalla mappa: la vista (2D, 3D,
/// immersiva), «torna su di me» e la mappa libera.
class ControlloMappa extends ChangeNotifier {
  ControlloMappa({
    this.ritornoAutomatico = const Duration(seconds: 20),
    bool inclinata = true,
    VistaMappa? vista,
    this.salvaVista,
  }) : vista = vista ?? (inclinata ? VistaMappa.inclinata : VistaMappa.piatta);

  /// Di partenza 3D, come sullo schermo dell'auto; la scelta si ricorda
  /// ([salvaVista], [carica]).
  VistaMappa vista;

  /// Inclinata (3D o immersiva): girata come si va, e (fuori dalla guida come
  /// in guida) la mappa segue chi guida. Altrimenti dall'alto.
  bool get inclinata => vista != VistaMappa.piatta;
  set inclinata(bool v) => vista = v ? (vista == VistaMappa.piatta ? VistaMappa.inclinata : vista) : VistaMappa.piatta;

  bool get immersiva => vista == VistaMappa.immersiva;

  /// Dove si ricorda la vista; `null` nelle prove che non la guardano.
  final Future<void> Function(VistaMappa vista)? salvaVista;

  var _sceltaQui = false;
  int _centra = 0;

  /// La mappa non segue più chi guida: l'ha spostata un dito (e dopo
  /// [ritornoAutomatico] senza tocchi torna a seguirlo da sola), o si sta
  /// guardando una persona di casa (finché non si chiede «Dove sono»).
  bool libera = false;
  final Duration ritornoAutomatico;
  Timer? _ritorno;

  /// Cresce a ogni «centra»: la mappa se ne accorge e si muove.
  int get richiesteCentra => _centra;

  /// La scelta ricordata, appena letta. Se nel frattempo se n'è già fatta
  /// una qui, vale quella.
  Future<void> carica(Future<VistaMappa> ricordata) async {
    final v = await ricordata;
    if (_sceltaQui || v == vista) return;
    vista = v;
    notifyListeners();
  }

  /// La scelta della vista: cambia, si ricorda, e si torna a seguire.
  void scegliVista(VistaMappa v) {
    _sceltaQui = true;
    _ritorno?.cancel();
    libera = false;
    if (v != vista) {
      vista = v;
      unawaited(salvaVista?.call(v));
    }
    notifyListeners();
  }

  /// «Dove sono»: la mappa torna su di te, e (in 3D) ti segue di nuovo.
  void centra() {
    _ritorno?.cancel();
    libera = false;
    _centra++;
    notifyListeners();
  }

  /// Un dito sulla mappa: la si lascia dov'è. [torna]: da sola, dopo
  /// [ritornoAutomatico]; altrimenti fino a «Dove sono» (una persona di casa
  /// mostrata, che si vuole guardare quanto serve).
  void toccata({bool torna = true}) {
    _ritorno?.cancel();
    _ritorno = torna ? Timer(ritornoAutomatico, segui) : null;
    if (libera) return;
    libera = true;
    notifyListeners();
  }

  /// Quanto spazio in alto copre un popup (in punti): la mappa sposta giù
  /// l'auto, così quello che arriva resta in vista sotto il popup.
  double coperto = 0;

  void copriAlto(double punti) {
    if ((punti - coperto).abs() < 1) return;
    coperto = punti;
    notifyListeners();
  }

  /// Si torna a seguire l'auto.
  void segui() {
    _ritorno?.cancel();
    if (!libera) return;
    libera = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _ritorno?.cancel();
    super.dispose();
  }
}
