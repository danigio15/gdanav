/* «Sul NAV potresti mettere i segnalini delle persone direttamente sulla
 * mappa, in modo che quando sei con Android Auto li vedi?» (Andrea)
 *
 * Le persone di casa le mette GdAHome (`GestorePersone`), e sulla mappa del
 * telefono c'erano già. Lo schermo dell'auto ha lo stesso stile, con la
 * stessa sorgente `gdanav-persone` (`stileMappa(perAuto: true)`): mancavano
 * solo i dati. Arrivano come le altre sorgenti, col metodo `sorgenti` del
 * canale `gdanav/schermo_auto`, che Android Auto (`RendererMappa.kt`) e
 * CarPlay (`MappaCarPlay.swift`) scrivono sulla loro mappa così come sono. */
library;

import 'dart:async';
import 'dart:convert';

import '../stato/gestore_persone.dart';

/// Tiene aggiornate le persone di casa sullo schermo dell'auto, senza
/// tempestarlo: GdAHome può mandare una posizione nuova ogni pochi secondi, e
/// rileggere una sorgente costa alla mappa dell'auto.
///
/// - chi arriva, chi se ne va o cambia nome si manda subito (anche la lista
///   vuota: tolte le persone sul telefono, spariscono dall'auto);
/// - le posizioni nuove al più una volta ogni [intervallo]: la prima subito,
///   le altre raccolte e mandate alla fine dell'intervallo, l'ultima vince;
/// - quello che l'auto ha già non si rimanda.
class PersoneInAuto {
  PersoneInAuto(this.persone, this._manda, {this.intervallo = const Duration(seconds: 30)});

  final GestorePersone persone;

  /// Il GeoJSON della sorgente `gdanav-persone`, già scritto.
  final void Function(String geojson) _manda;
  final Duration intervallo;

  Timer? _pausa;
  var _inAttesa = false;
  String? _mandato;
  String? _chi;

  void avvia() {
    persone.addListener(_cambiate);
    _invia();
  }

  void ferma() {
    persone.removeListener(_cambiate);
    _pausa?.cancel();
    _pausa = null;
    _inAttesa = false;
  }

  void _cambiate() {
    if (_pausa == null || firmaPersone(persone.persone) != _chi) {
      _invia();
    } else {
      _inAttesa = true;
    }
  }

  void _invia() {
    _inAttesa = false;
    final p = persone.persone;
    _chi = firmaPersone(p);
    final dati = jsonEncode(datiPersone(p));
    if (dati == _mandato) return;
    _mandato = dati;
    _manda(dati);
    _pausa?.cancel();
    _pausa = Timer(intervallo, () {
      _pausa = null;
      if (_inAttesa) _invia();
    });
  }
}

/// Chi c'è, senza dove: cambia se qualcuno arriva, se ne va o cambia nome,
/// non se si sposta.
String firmaPersone(List<PersonaSullaMappa> persone) =>
    [for (final p in persone) '${p.id}\u0000${p.nome}'].join('\u0001');
