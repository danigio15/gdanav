/// Di quanto gira davvero una manovra, guardando la strada invece del
/// numero che Valhalla le ha messo addosso.
///
/// Il tipo della manovra dice «uscita a sinistra», non dice se è un raccordo
/// che si stacca di quindici gradi o una rampa che torna indietro. Per
/// disegnare lo svincolo com'è servono i gradi, e i gradi stanno nei punti.
library;

import '../geo/geo.dart';
import 'valhalla.dart';

/// I gradi di cui gira la manovra [m], con segno: negativi a sinistra.
///
/// Si confronta la direzione della strada nei [guardaM] metri prima con
/// quella nei metri dopo. Una rampa non gira tutta insieme — si stacca piano
/// e poi si chiude — quindi si guarda a più distanze e si tiene la più larga:
/// è quella che dice se è una deviazione o un tornante.
///
/// `null` quando non c'è abbastanza strada intorno per dirlo.
double? quantoGiraLaManovra(
  PercorsoCalcolato percorso,
  Manovra m, {
  double guardaM = 60,
  List<double> dopoM = const [40, 80, 150],
}) {
  final punti = percorso.punti;
  if (punti.length < 3) return null;
  final i = m.inizio.clamp(1, punti.length - 2);
  final prima = _lontano(punti, i, guardaM, indietro: true);
  if (prima == null) return null;
  final daDove = rottaGradi(prima, punti[i]);
  double? piuLargo;
  for (final quantoRichiesto in dopoM) {
    // Non guardare oltre la fine di questa manovra: il campione a 150 m
    // poteva finire dentro la svolta successiva e far sembrare questo
    // svincolo piu' stretto/largo di quello reale.
    final massimoDopo = m.lunghezzaM > 20 ? m.lunghezzaM * 0.8 : m.lunghezzaM;
    final quanto = massimoDopo > 10 ? quantoRichiesto.clamp(10.0, massimoDopo).toDouble() : quantoRichiesto;
    final dopo = _lontano(punti, i, quanto, indietro: false);
    if (dopo == null) continue;
    final gira = diQuantoSiGira(daDove, rottaGradi(punti[i], dopo));
    if (piuLargo == null || gira.abs() > piuLargo.abs()) piuLargo = gira;
  }
  return piuLargo;
}

/// Il punto a [metri] da [i], avanti o indietro lungo la linea. `null` se la
/// strada finisce prima di dieci metri: meno di così è rumore.
Punto? _lontano(List<Punto> punti, int i, double metri, {required bool indietro}) {
  var fatti = 0.0;
  var j = i;
  while (fatti < metri) {
    final k = indietro ? j - 1 : j + 1;
    if (k < 0 || k >= punti.length) break;
    fatti += distanzaM(punti[j], punti[k]);
    j = k;
  }
  return fatti < 10 ? null : punti[j];
}

/// Da che parte va la manovra [m]: 1 a destra, -1 a sinistra, 0 dritto.
///
/// E' l'unica fonte per il lato dello svincolo: la usano l'icona, il
/// cartello (anche quello di Android Auto, `PannelloAuto.lato`, che ha la
/// stessa tabella) e la scena in 3D. Decide il tipo della manovra, cioè quello
/// che dice il motore del percorso («tieni la sinistra», «esci a destra»).
///
/// Prima la scena guardava i gradi della strada, e i gradi battevano il tipo:
/// a Napoli, sulla SS162dir, «tieni la sinistra» con la strada che poi piega
/// a destra disegnava il ramo a destra, mentre icona, cartello e corsie
/// dicevano sinistra. I gradi dicono dove va la strada dopo, non da che parte
/// si stacca il ramo: servono solo quando il tipo non lo dice (rampa dritta,
/// resta dritto), e prima di loro le corsie giuste.
int latoDellaManovra(Manovra m, {double? gradi}) {
  switch (m.tipo) {
    case 9 || 10 || 11 || 18 || 20 || 23 || 37:
      return 1;
    case 14 || 15 || 16 || 19 || 21 || 24 || 38:
      return -1;
  }
  // Il tipo non lo dice: le corsie giuste, se stanno tutte da una parte.
  if (m.corsieUtili) {
    final giuste = [
      for (final (i, c) in m.corsie.indexed)
        if (c.giusta) i,
    ];
    final n = m.corsie.length;
    if (giuste.first == 0 && giuste.last < n - 1) return -1;
    if (giuste.last == n - 1 && giuste.first > 0) return 1;
  }
  if (gradi != null && gradi.abs() >= 8) return gradi > 0 ? 1 : -1;
  return 0;
}
