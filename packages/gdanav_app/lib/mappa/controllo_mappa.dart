import 'dart:async';

import 'package:flutter/foundation.dart';

/// Come si guarda la mappa.
///
/// [piatta]: dall'alto, il nord in su. [inclinata] (3D): inclinata, girata
/// come si va, con gli edifici in rilievo. [immersiva]: ancora più bassa e
/// più vicina, le strade larghe quanto sono davvero, il percorso che passa
/// fra le case, e prima di una manovra le corsie disegnate sulla strada.
/// [aumentata] (3D aumentato): in guida la scena 3D della WebView
/// ([Mappa3d]: viadotti in quota coi piloni, alberi, edifici con le
/// finestre, l'auto rossa); fuori dalla guida, o dove la scena non c'è, la
/// mappa di sempre la disegna come il 3D ([nativa]).
enum VistaMappa {
  piatta('2D', 'Dall\'alto', '2D'),
  inclinata('3D', '3D', '3D'),
  immersiva('Immersiva', 'Immersiva', 'immersiva'),
  aumentata('3D+', '3D aumentato', '3D aumentato');

  const VistaMappa(this.sigla, this.nome, this.inFrase);

  /// Quello che c'è scritto sul tasto.
  final String sigla;

  /// Il nome nella scelta.
  final String nome;

  /// Il nome dentro una frase: «torno alla vista 3D», «… alla vista 2D».
  final String inFrase;

  /// Come la disegna la mappa di sempre (MapLibre Native): il 3D aumentato
  /// come il 3D, le altre come sono.
  VistaMappa get nativa => this == aumentata ? inclinata : this;

  /// La vista salvata, da una parola; quella di partenza se non si capisce.
  static VistaMappa daNome(String? nome) =>
      VistaMappa.values.firstWhere((v) => v.name == nome, orElse: () => VistaMappa.inclinata);
}

/// Cosa si dice quando il 3D aumentato si ferma e si torna a [vista]: per
/// sempre su questo telefono ([ricorda]), o solo questa volta.
String avvisoAumentatoNonVa(VistaMappa vista, {required bool ricorda}) => ricorda
    ? '3D aumentato non è disponibile su questo telefono: torno alla vista ${vista.inFrase}'
    : '3D aumentato non è partito: torno alla vista ${vista.inFrase}';

/// Perché il 3D aumentato non va su questo telefono, in una riga (sotto la
/// voce della scelta, e nella spiegazione).
String spiegaAumentatoNonVa(String? motivo) => switch (motivo) {
  'lento' => 'Su questo telefono va a scatti',
  'webview' || 'nessuna-webview' => 'Su questo dispositivo manca la WebView che lo disegna',
  _ => 'Questo telefono non lo può disegnare',
};

/// I comandi della mappa che stanno fuori dalla mappa: la vista (2D, 3D,
/// immersiva), «torna su di me» e la mappa libera.
class ControlloMappa extends ChangeNotifier {
  ControlloMappa({
    this.ritornoAutomatico = const Duration(seconds: 20),
    bool inclinata = true,
    VistaMappa? vista,
    this.salvaVista,
    this.aumentataPossibile = false,
    this.salvaAumentataNonVa,
    this.dimenticaAumentataNonVa,
  }) : vista = vista ?? (inclinata ? VistaMappa.inclinata : VistaMappa.piatta) {
    if (this.vista != VistaMappa.aumentata) vistaPrima = this.vista;
  }

  /// Di partenza 3D, come sullo schermo dell'auto; la scelta si ricorda
  /// ([salvaVista], [carica]).
  VistaMappa vista;

  /// L'ultima vista scelta che non è il 3D aumentato: ci si torna se il
  /// telefono non ce la fa.
  VistaMappa vistaPrima = VistaMappa.inclinata;

  /// Inclinata (3D, immersiva o 3D aumentato): girata come si va, e (fuori
  /// dalla guida come in guida) la mappa segue chi guida. Altrimenti dall'alto.
  bool get inclinata => vista != VistaMappa.piatta;
  set inclinata(bool v) => vista = v ? (vista == VistaMappa.piatta ? VistaMappa.inclinata : vista) : VistaMappa.piatta;

  bool get immersiva => vista == VistaMappa.immersiva;

  /// Dove si ricorda la vista; `null` nelle prove che non la guardano.
  final Future<void> Function(VistaMappa vista)? salvaVista;

  /// Il 3D aumentato si può provare qui (c'è la WebView: Android o iPhone).
  final bool aumentataPossibile;

  /// Cosa si dice quando il 3D aumentato si ferma e si torna a [vista]: per
  /// sempre su questo telefono ([ricorda]), o solo questa volta.
  String avvisoAumentatoNonVa(VistaMappa vista, {required bool ricorda}) => ricorda
      ? '3D aumentato non è disponibile su questo telefono: torno alla vista ${vista.inFrase}'
      : '3D aumentato non è partito: torno alla vista ${vista.inFrase}';

  /// Perché il 3D aumentato non va su questo telefono (`null`: va, o non ci
  /// si è ancora provato). Si ricorda ([salvaAumentataNonVa]) finché non si
  /// riprova a mano ([riprovaAumentata]).
  String? aumentataNonVa;
  final Future<void> Function(String motivo)? salvaAumentataNonVa;
  final Future<void> Function()? dimenticaAumentataNonVa;

  /// Si può scegliere il 3D aumentato, adesso.
  bool get aumentataDisponibile => aumentataPossibile && aumentataNonVa == null;

  /// La scena 3D aumentata è da disegnare (in guida): scelta e disponibile.
  bool get scenaAumentata => vista == VistaMappa.aumentata && aumentataDisponibile;

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
  Future<void> carica(Future<VistaMappa> ricordata, {Future<String?>? nonVa, Future<VistaMappa?>? prima}) async {
    var v = await ricordata;
    if (nonVa != null) aumentataNonVa = await nonVa;
    if (await prima case final p? when p != VistaMappa.aumentata) vistaPrima = p;
    // Ricordato il 3D aumentato, ma il telefono non ce la fa: il 3D.
    if (v == VistaMappa.aumentata && aumentataNonVa != null) v = VistaMappa.inclinata;
    _letta = true;
    if (!_sceltaQui && v != vista) {
      vista = v;
      if (v != VistaMappa.aumentata) vistaPrima = v;
    }
    notifyListeners();
  }

  /// Si rilegge la scelta ricordata anche se qui se n'era fatta una: l'ha
  /// cambiata un'altra schermata (la guida, o il 3D aumentato che si è
  /// fermato).
  Future<void> ricarica(Future<VistaMappa> ricordata, {Future<String?>? nonVa, Future<VistaMappa?>? prima}) {
    _sceltaQui = false;
    return carica(ricordata, nonVa: nonVa, prima: prima);
  }

  /// La scelta ricordata è arrivata ([carica]), o se n'è fatta una qui.
  bool get letta => _letta || _sceltaQui;
  var _letta = false;

  /// La scelta della vista: cambia, si ricorda, e si torna a seguire.
  void scegliVista(VistaMappa v) {
    _sceltaQui = true;
    _ritorno?.cancel();
    libera = false;
    if (v != vista) {
      vista = v;
      if (v != VistaMappa.aumentata) vistaPrima = v;
      unawaited(salvaVista?.call(v));
    }
    notifyListeners();
  }

  /// Il 3D aumentato si è fermato: si torna alla vista di prima. Se il
  /// telefono non ce la fa ([ricorda]: WebGL che manca, solo in software,
  /// troppo lento) lo si ricorda, e anche la vista di prima resta scelta;
  /// altrimenti (un intoppo di questa volta) la prossima volta si riprova.
  void lasciaAumentata(String motivo, {required bool ricorda}) {
    if (ricorda) {
      aumentataNonVa = motivo;
      unawaited(salvaAumentataNonVa?.call(motivo));
    }
    if (vista == VistaMappa.aumentata) {
      vista = vistaPrima;
      if (ricorda) unawaited(salvaVista?.call(vista));
    }
    _sceltaQui = true;
    notifyListeners();
  }

  /// «Riprova»: si dimentica che non andava e si sceglie il 3D aumentato.
  void riprovaAumentata() {
    aumentataNonVa = null;
    unawaited(dimenticaAumentataNonVa?.call());
    scegliVista(VistaMappa.aumentata);
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

  /// Quanto spazio a sinistra copre il cruscotto (di traverso, in punti):
  /// l'auto si mette nel mezzo della parte libera.
  double copertoSinistra = 0;

  void copriSinistra(double punti) {
    if ((punti - copertoSinistra).abs() < 1) return;
    copertoSinistra = punti;
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
