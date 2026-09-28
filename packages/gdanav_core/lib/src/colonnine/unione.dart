import 'dart:math' as math;

import '../geo/geo.dart';
import 'colonnina.dart';

/// Tutte le fonti insieme, non la prima che risponde.
///
/// [FonteColonnineConRiserva] è una catena: prova la prima, e se risponde si
/// ferma lì. Va bene quando le fonti dicono la stessa cosa — ma non è così.
/// Open Charge Map, OpenStreetMap e l'archivio di gdanav hanno ognuno
/// colonnine che gli altri non hanno, e prendendo solo la prima si perde
/// tutto il resto: intorno a Napoli Open Charge Map ne conosce 143, e da
/// sola diventava tutto quello che l'app sapeva.
///
/// Qui si chiedono tutte insieme, si aspetta chi risponde entro [attesa], e
/// quello che torna si fonde: due colonnine a meno di [raggioM] l'una
/// dall'altra sono la stessa, e resta quella che ne sa di più.
///
/// La [riserva] si chiede solo se non ha risposto nessuno: serve per
/// Overpass, che è lento (in CI arriva a scadere dopo cinquanta secondi) e
/// non deve rallentare ogni viaggio.
class FonteColonnineUnite implements FonteColonnine {
  const FonteColonnineUnite(
    this.fonti, {
    this.riserva,
    this.attesa = const Duration(seconds: 20),
    this.raggioM = 60,
  });

  final List<FonteColonnine> fonti;
  final FonteColonnine? riserva;
  final Duration attesa;
  final double raggioM;

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    Object? ultimo;
    final risposte = await Future.wait([
      for (final f in fonti)
        f
            .lungo(percorso, distanzaKm: distanzaKm)
            .timeout(attesa)
            .then<List<Colonnina>>((c) => c)
            .catchError((Object e) {
          ultimo = e;
          return const <Colonnina>[];
        }),
    ]);
    final unite = fondiColonnine(risposte, raggioM: raggioM);
    if (unite.isNotEmpty) return unite;
    if (riserva case final r?) return r.lungo(percorso, distanzaKm: distanzaKm);
    throw Exception('colonnine: ${ultimo ?? 'nessuna fonte ha risposto'}');
  }
}

/// Più elenchi di colonnine in uno solo, senza doppioni.
///
/// Due voci a meno di [raggioM] sono lo stesso posto visto da due fonti: si
/// tiene quella che ha più prese, prendendo dall'altra il nome e l'operatore
/// se lì mancano. Tutto quello che non si accoppia resta, perché il difetto
/// da togliere è la colonnina che manca, non il doppione.
///
/// L'accoppiamento è uno a uno: in un'area di servizio con tre stazioni
/// vicine, se una fonte le vede come una sola e l'altra come tre, restano
/// tre. Meglio una in più che una in meno, per chi deve caricare.
List<Colonnina> fondiColonnine(List<List<Colonnina>> elenchi, {double raggioM = 60}) {
  final risultato = <Colonnina>[];
  // Una griglia grossolana (un centesimo di grado, circa un chilometro) per
  // non confrontare ogni colonnina con tutte le altre: con settecento per
  // fonte sarebbero mezzo milione di distanze a ogni viaggio.
  final griglia = <(int, int), List<int>>{};
  (int, int) cella(Punto p) => ((p.lat * 100).floor(), (p.lon * 100).floor());

  for (final elenco in elenchi) {
    for (final nuova in elenco) {
      final (r, c) = cella(nuova.posizione);
      var vicina = -1;
      var migliore = raggioM;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          for (final i in griglia[(r + dr, c + dc)] ?? const <int>[]) {
            final d = distanzaM(risultato[i].posizione, nuova.posizione);
            if (d <= migliore) {
              migliore = d;
              vicina = i;
            }
          }
        }
      }
      if (vicina < 0) {
        griglia.putIfAbsent((r, c), () => []).add(risultato.length);
        risultato.add(nuova);
        continue;
      }
      risultato[vicina] = _lameglio(risultato[vicina], nuova);
    }
  }
  return risultato;
}

/// Di due voci dello stesso posto, quella che ne sa di più.
Colonnina _lameglio(Colonnina a, Colonnina b) {
  // Chi ha più prese ha visto meglio il posto; a pari prese vince chi c'era
  // già, così l'ordine delle fonti conta e il risultato è sempre lo stesso.
  final ricca = b.connettori.length > a.connettori.length ? b : a;
  final altra = identical(ricca, a) ? b : a;
  return Colonnina(
    id: ricca.id,
    nome: ricca.nome.isNotEmpty ? ricca.nome : altra.nome,
    posizione: ricca.posizione,
    connettori: ricca.connettori,
    operatore: ricca.operatore ?? altra.operatore,
    // «ocm+osm»: da dove viene quello che si vede, per le segnalazioni.
    fonte: _fonti(a.fonte, b.fonte),
  );
}

String _fonti(String a, String b) {
  final tutte = <String>{...a.split('+'), ...b.split('+')}..removeWhere((f) => f.isEmpty);
  return (tutte.toList()..sort()).take(math.min(tutte.length, 3)).join('+');
}
