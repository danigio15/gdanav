/// La batteria che ci sarà all'arrivo: il conto, senza la sua interfaccia.
///
/// Sta qui, e non dentro il gestore della guida, perché è il pezzo su cui si
/// sbaglia: si prova a mano, con due numeri, e si vede subito se dice una
/// cosa possibile.
library;

/// Quanto la macchina beve davvero, rispetto a quanto il piano credeva.
///
/// 1 vuol dire «come previsto», 2 «il doppio del previsto». Torna `null`
/// finché non si è misurato abbastanza: sotto [kmPerCredere] chilometri un
/// semaforo, una salita e una frenata raccontano qualunque cosa, e una
/// pendenza sbagliata stirata fino all'arrivo è peggio di nessuna correzione.
///
/// Il rapporto si tiene comunque fra [minimo] e [massimo]: una lettura della
/// batteria che salta di cinque punti non deve spostare l'arrivo di venti.
double? fattoreDelConsumo({
  required double kmMisurati,
  required double whMisurati,
  required double kwh100DelPiano,
  double kmPerCredere = 5,
  double minimo = 0.4,
  double massimo = 3,
}) {
  if (kmMisurati < kmPerCredere || whMisurati <= 0 || kwh100DelPiano <= 0) return null;
  final misurato = whMisurati / kmMisurati / 10;
  if (misurato <= 0) return null;
  return (misurato / kwh100DelPiano).clamp(minimo, massimo).toDouble();
}

/// La batteria all'arrivo, corretta con quanto si consuma davvero.
///
/// Il piano prevede un consumo, la macchina ne fa un altro. Spostare la curva
/// del piano in parallelo — «sei quattro punti sopra il piano, quindi arrivi
/// quattro punti sopra» — corregge dove sei adesso e lascia sbagliata la
/// pendenza: da lì «95% adesso, 94% all'arrivo» con davanti dei chilometri
/// che quella macchina paga molto più di un punto.
///
/// Qui si corregge la pendenza: quanto il piano prevede di consumare da qui
/// all'arrivo, moltiplicato per [fattore]. Il punto di partenza è la batteria
/// vera, quindi lo scostamento di adesso è già dentro.
///
/// Con [fattore] a `null` — non si è ancora misurato abbastanza — si torna
/// allo spostamento in parallelo, che è meglio di niente.
///
/// [dopoLUltimaSosta] è la batteria con cui il piano riparte dall'ultima
/// colonnina ancora davanti, se ce n'è una. Da lì in poi quello che hai
/// consumato prima non conta più: a una colonnina si carica **fino a** una
/// percentuale, non **di** una percentuale. Quindi si corregge solo l'ultimo
/// tratto, quello dalla colonnina all'arrivo.
double batteriaAllArrivo({
  required double adesso,
  required double pianoAdesso,
  required double pianoArrivo,
  double? fattore,
  double? dopoLUltimaSosta,
}) {
  if (fattore == null) return (pianoArrivo + adesso - pianoAdesso).clamp(0, 100).toDouble();
  final da = dopoLUltimaSosta ?? adesso;
  final pianoDa = dopoLUltimaSosta ?? pianoAdesso;
  return (da - (pianoDa - pianoArrivo) * fattore).clamp(0, 100).toDouble();
}
