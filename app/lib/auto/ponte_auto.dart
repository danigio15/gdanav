import 'dart:convert';

import 'package:flutter/services.dart';

import '../servizi.dart';
import '../mappa/dati_viaggio.dart';
import '../mappa/segnaposto.dart';
import '../mappa/stile.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_luoghi.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_viaggio.dart';

/// Tiene aggiornato lo schermo di Android Auto: stile, percorso, colonnine,
/// segnaposto e prossima manovra; dall'auto arrivano la ricerca, la meta
/// scelta (che parte subito in guida) e «Fine». Il lato nativo è in
/// `android/app/src/main/kotlin/it/gdanav/gdanav/auto`. Su iPhone e nelle
/// prove il canale non c'è, e si tace.
class PonteAuto {
  PonteAuto({
    required this.viaggio,
    required this.guida,
    required this.posizione,
    this.luoghi,
    MethodChannel? canale,
    DateTime Function()? orologio,
  }) : _canale = canale ?? const MethodChannel('gdanav/schermo_auto'),
       _ora = orologio ?? DateTime.now;

  final GestoreViaggio viaggio;
  final GestoreGuida guida;
  final GestorePosizione posizione;

  /// Casa, Lavoro e recenti, da scegliere sullo schermo dell'auto.
  final GestoreLuoghi? luoghi;
  final MethodChannel _canale;
  final DateTime Function() _ora;
  var _attivo = true;
  DateTime _ultimaPosizione = DateTime(0);

  void avvia() {
    _canale.setMethodCallHandler(_dallAuto);
    _manda('stili', {
      'chiaro': jsonEncode(stileMappa(scuro: false, chiaveTraffico: Servizi.chiaveTomTom)),
      'scuro': jsonEncode(stileMappa(scuro: true, chiaveTraffico: Servizi.chiaveTomTom)),
    });
    viaggio.addListener(_viaggio);
    guida.addListener(_guida);
    posizione.addListener(_posizione);
    luoghi?.addListener(_luoghi);
    _viaggio();
    _luoghi();
  }

  Future<Object?> _dallAuto(MethodCall call) async {
    switch (call.method) {
      // «Fine» premuto sullo schermo dell'auto.
      case 'ferma':
        if (guida.attiva) await guida.ferma();
        viaggio.annulla();
      case 'cerca':
        final testo = (call.arguments as Map?)?['testo'] as String? ?? '';
        final trovati = await viaggio.luoghi.cerca(testo, vicinoA: posizione.qui ?? viaggio.ultimaPosizione);
        return [for (final l in trovati) luogoJson(l)];
      // Una meta scelta in auto: si calcola e si parte, senza toccare il telefono.
      case 'vai':
        final l = luogoDaJson(call.arguments);
        if (l == null) return null;
        if (guida.attiva) await guida.ferma();
        await luoghi?.usato(l);
        await viaggio.vaiA(l);
        if (viaggio.stato is ViaggioPronto) guida.avvia();
    }
    return null;
  }

  void _luoghi() {
    final g = luoghi;
    if (g == null) return;
    _manda('luoghi', {
      'elenco': [
        for (final p in g.preferiti) {...luogoJson(p.luogo), 'tipo': p.tipo.name, 'etichetta': p.etichetta},
        for (final l in g.recenti) {...luogoJson(l), 'tipo': 'recente', 'etichetta': l.nome},
      ],
    });
  }

  void ferma() {
    viaggio.removeListener(_viaggio);
    guida.removeListener(_guida);
    posizione.removeListener(_posizione);
    luoghi?.removeListener(_luoghi);
  }

  void _viaggio() {
    final stato = viaggio.stato;
    // Cosa dire sull'auto quando non si guida.
    _manda('messaggio', {
      'testo': switch (stato) {
        Calcolo(:final destinazione) => 'Calcolo il percorso per ${destinazione.nome}…',
        ErroreViaggio(:final messaggio) => messaggio,
        _ => null,
      },
    });
    final dati = datiViaggio(stato is ViaggioPronto ? stato.viaggio : null);
    _manda('sorgenti', {
      'dati': {for (final MapEntry(:key, :value) in dati.entries) key: jsonEncode(value)},
    });
  }

  void _guida() {
    final a = guida.avanzamento;
    final p = guida.pronto;
    if (!guida.attiva || p == null) {
      _manda('guida', {'attiva': false});
      return;
    }
    final m = a?.prossima ?? p.viaggio.percorso.manovre.firstOrNull;
    _manda('guida', {
      'attiva': true,
      'tipo': m?.tipo ?? 8,
      'distanza': a?.allaProssimaM ?? m?.lunghezzaM ?? 0.0,
      'strada': m?.strada ?? '',
      'istruzione': m?.istruzione ?? '',
      'restanti': a?.restantiM ?? p.viaggio.percorso.lunghezzaM,
      'secondi': (a?.restante ?? p.viaggio.percorso.durata).inSeconds,
      'arrivo': (guida.arrivoAlle ?? _ora()).millisecondsSinceEpoch,
      'destinazione': p.destinazione.nome,
    });
    _posizione();
  }

  /// Al massimo due volte al secondo: l'auto non ha bisogno di più.
  void _posizione() {
    final a = guida.attiva ? guida.avanzamento : null;
    final qui = a?.posizioneSulPercorso ?? posizione.qui;
    // Senza posizione non c'è niente da mostrare: non si consuma il turno.
    if (qui == null) return;
    final ora = _ora();
    if (ora.difference(_ultimaPosizione) < const Duration(milliseconds: 500)) return;
    _ultimaPosizione = ora;
    final rotta = a?.rotta ?? posizione.rotta;
    _manda('posizione', {'lat': qui.lat, 'lon': qui.lon, 'rotta': rotta});
    _manda('sorgenti', {
      'dati': {sorgenteIo: jsonEncode(datiIo(qui, rotta, posizione.segnaposto))},
    });
  }

  void _manda(String metodo, Map<String, Object?> dati) {
    if (!_attivo) return;
    _canale.invokeMethod<void>(metodo, dati).catchError((Object e) {
      // Nessun Android Auto (iPhone, prove): si smette di provarci.
      if (e is MissingPluginException) _attivo = false;
    });
  }
}
