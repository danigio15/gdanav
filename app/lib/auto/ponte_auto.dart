import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../componenti/stato_colonnina.dart' show testoDisponibilita;
import '../componenti/scena_svincolo.dart';
import '../componenti/vista_svincolo.dart';
import '../mappa/dati_viaggio.dart';
import '../mappa/segnaposto.dart';
import '../mappa/stile.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/avvisi_strada.dart';
import '../stato/distributori.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_luoghi.dart';
import '../stato/gestore_meteo.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_premium.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';

/// Tiene aggiornato lo schermo di Android Auto: stile, percorso, colonnine,
/// segnalazioni, segnaposto e prossima manovra, e il cruscotto (batteria,
/// velocità e limite, arrivo, prossima sosta, meteo, avvisi). Dall'auto
/// arrivano la ricerca, la meta scelta (che parte subito in guida), Casa e
/// Lavoro da salvare, le opzioni del percorso, le segnalazioni e «Fine». Il
/// lato nativo è in `android/app/src/main/kotlin/it/gdanav/gdanav/auto`. Su
/// iPhone e nelle prove il canale non c'è, e si tace.
class PonteAuto {
  PonteAuto({
    required this.viaggio,
    required this.guida,
    required this.posizione,
    this.luoghi,
    this.auto,
    this.segnalazioni,
    this.meteo,
    this.vicini,
    MethodChannel? canale,
    DateTime Function()? orologio,
  }) : _canale = canale ?? const MethodChannel('gdanav/schermo_auto'),
       _ora = orologio ?? DateTime.now;

  final GestoreViaggio viaggio;
  final GestoreGuida guida;
  final GestorePosizione posizione;

  /// Casa, Lavoro e recenti, da scegliere sullo schermo dell'auto.
  final GestoreLuoghi? luoghi;
  final GestoreAuto? auto;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreMeteo? meteo;

  /// Distributori o colonnine intorno, anche sulla mappa dell'auto.
  final GestoreVicini? vicini;
  final MethodChannel _canale;
  final DateTime Function() _ora;
  var _attivo = true;
  DateTime _ultimaPosizione = DateTime(0);
  AvvisiStrada? _avvisi;

  void avvia() {
    _canale.setMethodCallHandler(_dallAuto);
    _manda('stili', {
      'chiaro': jsonEncode(stileMappa(scuro: false, chiaveTraffico: Servizi.chiaveTomTom)),
      'scuro': jsonEncode(stileMappa(scuro: true, chiaveTraffico: Servizi.chiaveTomTom)),
    });
    _immagini();
    viaggio.addListener(_viaggio);
    viaggio.addListener(_opzioni);
    guida.addListener(_guida);
    posizione.addListener(_posizione);
    luoghi?.addListener(_luoghi);
    auto?.addListener(_cruscotto);
    meteo?.addListener(_cruscotto);
    vicini?.addListener(_vicini);
    if (segnalazioni case final s?) {
      s.addListener(_segnalazioni);
      _avvisi = AvvisiStrada.di(guida, s)..addListener(_avviso);
    }
    _viaggio();
    _luoghi();
    _opzioni();
    _segnalazioni();
    _vicini();
  }

  /// Le icone delle segnalazioni, disegnate come sul telefono.
  Future<void> _immagini() async {
    if (!_attivo) return;
    try {
      _manda('immagini', {
        'png': {
          for (final t in TipoSegnalazione.values) nomeIcona(t): await iconaSegnalazionePng(t),
          // Le icone dei punti: categorie, distributori, colonnine.
          ...await iconePunti(),
        },
      });
    } catch (_) {
      // Senza icone le segnalazioni restano nel cruscotto.
    }
  }

  Future<Object?> _dallAuto(MethodCall call) async {
    final a = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      // «Fine» premuto sullo schermo dell'auto.
      case 'ferma':
        if (guida.attiva) await guida.ferma();
        viaggio.annulla();
      case 'cerca':
        final testo = a['testo'] as String? ?? '';
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
      // «Imposta Casa» (o Lavoro) scelto dalla ricerca sull'auto.
      case 'imposta':
        final l = luogoDaJson(a['luogo']);
        final tipo = TipoPreferito.values.where((t) => t.name == a['tipo']).firstOrNull;
        final g = luoghi;
        if (l == null || tipo == null || g == null) return false;
        await g.salva(Preferito(tipo, l));
        return true;
      case 'opzioni':
        var o = viaggio.opzioni;
        if (a['modo'] case final String m) {
          o = o.copia(modo: ModoGuida.values.where((x) => x.name == m).firstOrNull ?? o.modo);
        }
        if (a['pedaggi'] case final bool v) o = o.copia(evitaPedaggi: v);
        if (a['autostrade'] case final bool v) o = o.copia(evitaAutostrade: v);
        if (a['traghetti'] case final bool v) o = o.copia(evitaTraghetti: v);
        if (a['ricalcolo'] case final bool v) o = o.copia(ricalcoloAutomatico: v);
        await viaggio.cambiaOpzioni(o);
      case 'voce':
        guida.alternaVoce();
        _opzioni();
      case 'segnala':
        final tipo = TipoSegnalazione.values.where((t) => t.name == a['tipo']).firstOrNull;
        final s = segnalazioni;
        if (tipo == null || s == null) return 'Le segnalazioni non sono disponibili.';
        return s.segnala(tipo);
      case 'ancora':
        final s = _avvisi?.passata;
        if (s != null && s.id == a['id']) _avvisi!.rispondi(s, a['si'] == true);
      // Auto termica: i distributori intorno; in guida si passa da lì.
      case 'distributori':
        final qui = guida.avanzamento?.posizioneSulPercorso ?? posizione.qui ?? viaggio.ultimaPosizione;
        if (qui == null) return const <Object>[];
        try {
          return [
            for (final d in (await distributoriVicini(qui)).take(12))
              {
                'nome': d.nome,
                'descrizione': descriviDistributore(d, qui, carburante: auto?.carburante ?? Carburante.benzina),
                'lat': d.posizione.lat,
                'lon': d.posizione.lon,
              },
          ];
        } catch (_) {
          return const <Object>[];
        }
      case 'passa':
        final l = luogoDaJson(call.arguments);
        if (l == null) return null;
        // Con la termica ci si passa e si prosegue; con l'elettrica il
        // punto diventa la meta (le soste le fa il piano).
        if (guida.attiva && (guida.pronto?.termica ?? false)) {
          await guida.passaDa(l);
        } else {
          if (guida.attiva) await guida.ferma();
          await viaggio.vaiA(l);
          if (viaggio.stato is ViaggioPronto) guida.avvia();
        }
      // Un punto toccato sulla mappa dell'auto: cosa dirne.
      case 'punto':
        final p = PuntoToccato.daElemento({
          'properties': a['proprieta'],
          'geometry': {
            'type': 'Point',
            'coordinates': [a['lon'], a['lat']],
          },
        });
        if (p == null) return null;
        final qui = guida.avanzamento?.posizioneSulPercorso ?? posizione.qui;
        final (:sopra, :righe) = righePunto(
          p,
          vicini: vicini,
          qui: qui,
          carburante: auto?.carburante ?? Carburante.benzina,
        );
        return {
          'titolo': p.nome,
          'sopra': sopra,
          'righe': righe,
          'vai': guida.attiva && (guida.pronto?.termica ?? false) ? 'Passa di qui' : 'Vai',
          'luogo': {
            'nome': p.nome,
            'descrizione': righe.firstOrNull ?? sopra,
            'lat': p.posizione.lat,
            'lon': p.posizione.lon,
          },
        };
      case 'colonnine':
        final qui = posizione.qui ?? viaggio.ultimaPosizione;
        final v = auto?.veicolo;
        if (qui == null || v == null) return const <Object>[];
        final trovate = await colonnineVicine(qui, v);
        return [
          for (final c in trovate)
            {
              'nome': c.nome,
              'descrizione': [
                '${(distanzaM(qui, c.posizione) / 1000).toStringAsFixed(1)} km',
                '${c.potenzaNominalePer(v.connettori).round()} kW',
                if (GestorePremium.attivo.value) testoDisponibilita(c.disponibilitaPer(v.connettori)),
                if (c.operatore case final o? when o.isNotEmpty) o,
              ].join(' · '),
              'lat': c.posizione.lat,
              'lon': c.posizione.lon,
            },
        ];
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

  /// Le opzioni del percorso e la voce, per il menu dell'auto.
  void _opzioni() {
    final o = viaggio.opzioni;
    _manda('opzioni', {
      'modo': o.modo.name,
      'modo_nome': o.modo.nome,
      'pedaggi': o.evitaPedaggi,
      'autostrade': o.evitaAutostrade,
      'traghetti': o.evitaTraghetti,
      'ricalcolo': o.ricalcoloAutomatico,
      'muto': guida.muto,
    });
  }

  void ferma() {
    viaggio.removeListener(_viaggio);
    viaggio.removeListener(_opzioni);
    guida.removeListener(_guida);
    posizione.removeListener(_posizione);
    luoghi?.removeListener(_luoghi);
    auto?.removeListener(_cruscotto);
    meteo?.removeListener(_cruscotto);
    vicini?.removeListener(_vicini);
    segnalazioni?.removeListener(_segnalazioni);
    _avvisi?.removeListener(_avviso);
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
    _cruscotto();
  }

  void _vicini() {
    final v = vicini;
    if (v == null) return;
    _manda('sorgenti', {
      'dati': {for (final MapEntry(:key, :value) in v.dati().entries) key: jsonEncode(value)},
    });
  }

  void _segnalazioni() {
    final s = segnalazioni;
    if (s == null) return;
    _manda('sorgenti', {
      'dati': {sorgenteSegnalazioni: jsonEncode(datiSegnalazioni(s.vicine))},
    });
  }

  /// La segnalazione che si avvicina, o quella appena passata.
  void _avviso() {
    final a = _avvisi;
    if (a == null) return;
    final passata = a.passata;
    _manda('avviso', {
      if (a.davanti case (final s, final m)) ...{
        'titolo': s.fissa ? 'Autovelox fisso' : s.tipo.avviso,
        'tipo': s.tipo.name,
        'metri': m,
        'limite': s.limiteKmh,
      },
      if (passata != null) ...{'ancora_id': passata.id, 'ancora_testo': '${passata.tipo.nome}: c\'è ancora?'},
    });
  }

  void _guida() {
    final a = guida.avanzamento;
    final p = guida.pronto;
    if (!guida.attiva || p == null) {
      _manda('guida', {'attiva': false});
      if (_freccia != null) {
        _freccia = null;
        _manda('sorgenti', {
          'dati': {sorgenteManovra: jsonEncode(datiManovra(null, null))},
        });
      }
      _cruscotto();
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
      'uscita': m?.uscita ?? '',
      'verso': m?.verso ?? '',
      'rotonda': m?.uscitaRotonda,
      // Le corsie solo avvicinandosi allo svincolo, e se non vanno bene tutte.
      if (m != null && m.corsieUtili && (a?.allaProssimaM ?? m.lunghezzaM) <= 2000)
        'corsie': [for (final c in m.corsie) c.toJson()],
      if (a?.dopo case final d?) ...{'dopo_tipo': d.tipo, 'dopo_strada': d.strada.isNotEmpty ? d.strada : d.istruzione},
      if (m != null && _svincoloPronto == m.inizio && (a?.allaProssimaM ?? m.lunghezzaM) <= PopupSvincolo.daMetri)
        'svincolo': m.inizio,
    });
    // La freccia della manovra sul percorso, avvicinandosi.
    final chiave = chiaveFreccia(p.viaggio, a?.prossima, a?.allaProssimaM, ricalcolo: guida.ricalcolando);
    if (chiave != _freccia) {
      _freccia = chiave;
      _manda('sorgenti', {
        'dati': {sorgenteManovra: jsonEncode(datiManovra(chiave == null ? null : p.viaggio, a?.prossima))},
      });
    }
    // La vista dello svincolo si disegna una volta, poco prima.
    if (m != null &&
        haSvincolo(m) &&
        (a?.allaProssimaM ?? m.lunghezzaM) <= PopupSvincolo.daMetri + 400 &&
        _svincoloChiesto != m.inizio) {
      _svincoloChiesto = m.inizio;
      unawaited(_disegnaSvincolo(m));
    }
    _posizione();
  }

  int? _svincoloChiesto;

  (int, int)? _freccia;

  int? _svincoloPronto;

  /// Lo svincolo in 3D per l'auto: la stessa scena del telefono, in PNG.
  Future<void> _disegnaSvincolo(Manovra m) async {
    if (!_attivo) return;
    try {
      _manda('svincolo', {'id': m.inizio, 'png': await scenaSvincoloPng(m)});
      _svincoloPronto = m.inizio;
      _guida();
    } catch (_) {
      // Senza immagine restano freccia e corsie.
    }
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
    // La mappa guarda un po' avanti; la freccia dell'auto segue la strada.
    _manda('posizione', {'lat': qui.lat, 'lon': qui.lon, 'rotta': a?.rottaMappa ?? rotta});
    _manda('sorgenti', {
      'dati': {sorgenteIo: jsonEncode(datiIo(qui, rotta, posizione.segnaposto))},
    });
    _cruscotto();
  }

  /// Quello che sta sopra la mappa dell'auto.
  void _cruscotto() {
    final s = auto?.stato;
    final p = guida.attiva ? guida.pronto : null;
    final a = guida.avanzamento;
    final ora = p == null ? null : guida.batteriaOra;
    // La prossima sosta davanti.
    final sosta = p == null
        ? null
        : (p.viaggio.piano?.soste ?? const <Sosta>[])
              .where((x) => x.colonnina.distanzaM > (a?.percorsiM ?? 0))
              .firstOrNull;
    final m = meteo;
    final arrivoMeteo = p == null ? null : m?.delViaggio?.arrivo;
    final previsione = arrivoMeteo?.previsione ?? m?.qui;
    // Auto termica: niente batteria, autonomia né colonnine sull'auto.
    final elettrica = auto?.elettrica ?? true;
    final batteria = elettrica ? ora?.valore ?? s?.batteria : null;
    final autonomia = auto == null || !elettrica ? null : guida.autonomiaOra;
    _manda('cruscotto', {
      'elettrica': elettrica,
      'batteria': batteria,
      'autonomia_km': autonomia?.km,
      'autonomia_auto': autonomia?.dallAuto ?? false,
      'velocita': posizione.velocitaKmh,
      'limite': guida.attiva ? a?.limiteKmh : null,
      'arrivo_batteria': p == null || !elettrica ? null : guida.batteriaArrivo,
      if (sosta != null) ...{
        'sosta_nome': sosta.colonnina.nome,
        'sosta_km': (sosta.colonnina.distanzaM - (a?.percorsiM ?? 0)) / 1000,
        'sosta_batteria': sosta.batteriaArrivo,
      },
      if (previsione != null) ...{
        'meteo_temperatura': previsione.temperaturaC,
        'meteo_emoji': previsione.cielo.emoji,
        'meteo_dove': arrivoMeteo != null ? 'all\'arrivo' : 'qui',
      },
    });
  }

  /// Premium sbloccato o no: l'auto lo ricorda anche a telefono spento.
  void premium(bool sbloccato) => _manda('premium', {'sbloccato': sbloccato});

  void _manda(String metodo, Map<String, Object?> dati) {
    if (!_attivo) return;
    _canale.invokeMethod<void>(metodo, dati).catchError((Object e) {
      // Nessun Android Auto (iPhone, prove): si smette di provarci.
      if (e is MissingPluginException) _attivo = false;
    });
  }
}
