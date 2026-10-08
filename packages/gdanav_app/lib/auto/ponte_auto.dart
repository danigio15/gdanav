import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:geolocator/geolocator.dart' show Position;

import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../componenti/stato_colonnina.dart' show testoDisponibilita;
import '../componenti/scena_svincolo.dart';
import '../componenti/vista_svincolo.dart';
import '../componenti/ztl.dart';
import '../mappa/dati_viaggio.dart';
import '../mappa/segnaposto.dart';
import '../mappa/stile.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/avvisi_strada.dart';
import '../stato/avvisi_ztl.dart';
import '../stato/distributori.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_luoghi.dart';
import '../stato/gestore_meteo.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_risparmio.dart' show sintesiProposta;
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/prova_di_guida.dart';
import 'richiesta_navigazione.dart';
import '../stato/gestore_vicini.dart';
import '../stato/gestore_ztl.dart';

/// Tiene aggiornato lo schermo di Android Auto: stile, percorso, colonnine,
/// segnalazioni, segnaposto e prossima manovra, e il cruscotto (batteria,
/// velocità e limite, arrivo, prossima sosta, meteo, avvisi). Dall'auto
/// arrivano la ricerca, la meta scelta (che parte subito in guida), Casa e
/// Lavoro da salvare, le opzioni del percorso, le segnalazioni, «Fine» e, se
/// l'auto lo passa, il suo GPS. Il lato nativo è in
/// `android/src/main/kotlin/it/gdanav/gdanav_app/auto` e, per CarPlay, in
/// `ios/gdanav_app/Sources/gdanav_app`. Nelle prove il canale non c'è, e si
/// tace.
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
    this.prova,
    this.ztl,
    this.gpsDellAuto,
    MethodChannel? canale,
    DateTime Function()? orologio,
  }) : _canale = canale ?? const MethodChannel('gdanav/schermo_auto'),
       _ora = orologio ?? DateTime.now;

  final GestoreViaggio viaggio;
  final GestoreGuida guida;
  final GestorePosizione posizione;

  /// Dove mandare le posizioni del GPS dell'auto, quando l'auto le passa: il
  /// flusso del GPS (`gpsDellAuto` in `stato/posizione.dart`), che le preferisce
  /// a quelle del telefono finché arrivano.
  final void Function(Position)? gpsDellAuto;

  /// Casa, Lavoro e recenti, da scegliere sullo schermo dell'auto.
  final GestoreLuoghi? luoghi;
  final GestoreAuto? auto;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreMeteo? meteo;

  /// Distributori o colonnine intorno, anche sulla mappa dell'auto.
  final GestoreVicini? vicini;

  /// La prova di guida che Android Auto accende (il «test drive»).
  final ProvaDiGuida? prova;

  /// Le ZTL e le aree pedonali sulla mappa dell'auto, e gli avvisi.
  final GestoreZtl? ztl;
  final MethodChannel _canale;
  final DateTime Function() _ora;
  var _attivo = true;
  DateTime _ultimaPosizione = DateTime(0);
  AvvisiStrada? _avvisi;
  AvvisiZtl? _avvisiZtl;

  void avvia() {
    _canale.setMethodCallHandler(_dallAuto);
    _manda('stili', {
      'chiaro': jsonEncode(stileMappa(scuro: false, chiaveTraffico: Servizi.chiaveTomTom, perAuto: true)),
      'scuro': jsonEncode(stileMappa(scuro: true, chiaveTraffico: Servizi.chiaveTomTom, perAuto: true)),
    });
    _immagini();
    viaggio.addListener(_viaggio);
    viaggio.addListener(_opzioni);
    guida.addListener(_guida);
    posizione.addListener(_posizione);
    luoghi?.addListener(_luoghi);
    auto?.addListener(_cruscotto);
    auto?.addListener(_opzioni);
    meteo?.addListener(_cruscotto);
    vicini?.addListener(_vicini);
    if (segnalazioni case final s?) {
      s.addListener(_segnalazioni);
      _avvisi = AvvisiStrada.di(guida, s)..addListener(_avviso);
    }
    if (ztl case final z?) {
      z.addListener(_zoneDaCapo);
      _avvisiZtl = AvvisiZtl.di(guida, z)..addListener(_avviso);
    }
    guida.risparmio?.addListener(_strada);
    _viaggio();
    _luoghi();
    _opzioni();
    // La batteria all'arrivo, per il menu dell'auto.
    if (viaggio.minimoArrivo == null) {
      unawaited(
        viaggio.archivio.preferenze().then((p) {
          viaggio.minimoArrivo ??= p.minimoArrivo;
          _opzioni();
        }, onError: (Object _) {}),
      );
    }
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
          // Il cartello della ZTL, per l'avviso.
          'segnala-ztl': await cartelloZtlPng(),
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
      // Il GPS dell'auto, quando l'auto lo passa: va nel flusso del GPS.
      case 'posizione_auto':
        if (posizioneDellAuto(a) case final p?) gpsDellAuto?.call(p);
      // Lo schermo dell'auto si è acceso o spento: qualcuno sta guardando, e
      // i dati dell'auto si chiedono freschi anche senza un percorso.
      case 'in_auto':
        auto?.schermoDellAuto(a['si'] == true);
      // Android Auto accende la prova di guida: da qui ogni guida si percorre
      // da sola, e se non c'è ancora una meta se ne sceglie una.
      case 'prova_guida':
        await provaDiGuida();
      // La sessione dell'auto è finita: la prova di guida pure.
      case 'prova_fine':
        _conProva = false;
        _seguiProva();
      // «Ok Google, naviga verso…» o un'altra app che chiede un percorso.
      case 'naviga':
        await naviga(a['uri'] as String? ?? '');
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
        if (a['arrivo'] case final num v) {
          await viaggio.cambiaMinimoArrivo(v.toDouble());
          return null;
        }
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
      // «Prendila» o «Resto qui» sulla strada proposta: vale solo per quella
      // che l'auto ha davanti.
      case 'strada':
        if (a['id'] != _idStrada || _stradaMandata == null) return null;
        if (a['si'] == true) {
          await guida.prendiStrada();
        } else {
          guida.restaQui();
        }
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
        try {
          final p = PuntoToccato.daElemento({
            'properties': a['proprieta'],
            'geometry': {
              'type': 'Point',
              'coordinates': [a['lon'], a['lat']],
            },
          });
          if (p == null) return null;
          // Lo stato live della colonnina e' utile, ma non deve mai poter
          // impedire l'apertura della scheda se una fonte non risponde.
          if (p.tipo == 'colonnina' && p.id != null) {
            try {
              await vicini?.statoAdesso(p.id!).timeout(const Duration(seconds: 5));
            } catch (_) {}
          }
          final qui = guida.avanzamento?.posizioneSulPercorso ?? posizione.qui;
          final (:righe, :stato) = schedaInAuto(
            p,
            vicini: vicini,
            qui: qui,
            carburante: auto?.carburante ?? Carburante.benzina,
          );
          final descrizione = righe.isEmpty
              ? p.nome
              : righe.first.titolo;
          return {
            'titolo': p.nome.isEmpty ? 'Punto' : p.nome,
            'voci': [
              for (final r in righe) {'icona': r.icona, 'colore': r.colore, 'titolo': r.titolo, 'testo': r.testo},
            ],
            'stato': stato,
            'vai': guida.attiva && (guida.pronto?.termica ?? false) ? 'Passa di qui' : 'Vai',
            'luogo': {
              'nome': p.nome.isEmpty ? 'Punto' : p.nome,
              'descrizione': descrizione,
              'lat': p.posizione.lat,
              'lon': p.posizione.lon,
            },
          };
        } catch (_) {
          // Un dato POI incompleto o una fonte live guasta non deve far
          // cadere il motore Flutter/Android Auto.
          return null;
        }
      case 'colonnine':
        final qui = posizione.qui ?? viaggio.ultimaPosizione;
        final v = auto?.veicolo;
        if (qui == null || v == null) return const <Object>[];
        final trovate = await colonnineVicineComeSiVuole(qui, v, viaggio.archivio);
        return [
          for (final c in trovate)
            {
              'nome': c.nome,
              'descrizione': [
                '${(distanzaM(qui, c.posizione) / 1000).toStringAsFixed(1)} km',
                '${c.potenzaNominalePer(v.connettori).round()} kW',
                testoDisponibilita(c.disponibilitaPer(v.connettori)),
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
      // Casa e Lavoro, gli ultimi posti, poi gli altri salvati (importati da
      // Google possono essere centinaia: l'auto ne mostra pochi).
      'elenco': [
        for (final p in [?g.casa, ?g.lavoro]) {...luogoJson(p.luogo), 'tipo': p.tipo.name, 'etichetta': p.etichetta},
        for (final l in g.recenti.take(5)) {...luogoJson(l), 'tipo': 'recente', 'etichetta': l.nome},
        for (final p in g.altri.take(60)) {...luogoJson(p.luogo), 'tipo': p.tipo.name, 'etichetta': p.etichetta},
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
      'elettrica': auto?.elettrica ?? true,
      'arrivo': ?viaggio.minimoArrivo,
    });
  }

  void ferma() {
    viaggio.removeListener(_viaggio);
    viaggio.removeListener(_opzioni);
    guida.removeListener(_guida);
    posizione.removeListener(_posizione);
    luoghi?.removeListener(_luoghi);
    auto?.removeListener(_cruscotto);
    auto?.removeListener(_opzioni);
    meteo?.removeListener(_cruscotto);
    vicini?.removeListener(_vicini);
    segnalazioni?.removeListener(_segnalazioni);
    _avvisi?.removeListener(_avviso);
    ztl?.removeListener(_zoneDaCapo);
    _avvisiZtl?.removeListener(_avviso);
    guida.risparmio?.removeListener(_strada);
  }

  /// La strada proposta mandata all'auto, e il suo numero: la risposta
  /// dell'auto vale solo per quella.
  PropostaStrada? _stradaMandata;
  var _numeroStrada = 0;
  String get _idStrada => 'strada-$_numeroStrada';

  /// La strada a risparmio (o più rapida) proposta in guida: all'auto il
  /// titolo e le cifre, coi due tasti; sulla mappa la strada verde col
  /// fumetto. Presa, rifiutata o scaduta: via da tutt'e due.
  void _strada() {
    final r = guida.risparmio;
    final p = r?.proposta;
    if (identical(p, _stradaMandata)) return;
    _stradaMandata = p;
    if (r == null || p == null) {
      _manda('strada', const {});
      _manda('sorgenti', {
        'dati': {sorgenteRisparmio: jsonEncode(datiRisparmio(null, null, ''))},
      });
      return;
    }
    _numeroStrada++;
    final arrivo = guida.batteriaArrivoCon(p);
    _manda('strada', {
      'id': _idStrada,
      'titolo': p.motivo == MotivoProposta.rapida ? 'Strada più rapida' : 'Strada a risparmio',
      'testo': [sintesiProposta(p, r.unita), if (arrivo != null) 'arrivi con il ${arrivo.round()}%'].join(' · '),
    });
    _manda('sorgenti', {
      'dati': {
        sorgenteRisparmio: jsonEncode(
          datiRisparmio(p, guida.pronto?.viaggio.percorso, sintesiProposta(p, r.unita, meno: '-')),
        ),
      },
    });
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

  /// La segnalazione che si avvicina, o quella appena passata; o la ZTL
  /// attiva. Sull'auto ce n'è posto per uno: la ZTL davanti fuori dal
  /// percorso vince su tutto (è una multa), le altre ZTL cedono il posto
  /// alle segnalazioni.
  void _avviso() {
    final a = _avvisi;
    final z = _avvisiZtl?.avviso;
    final passata = a?.passata;
    final davanti = a?.davanti;
    _manda('avviso', {
      if (z != null && (z.fuori || davanti == null))
        ...{'titolo': z.titolo, 'tipo': 'ztl', 'testo': z.testo}
      else if (davanti case (final s, final m))
        ...{'titolo': s.fissa ? 'Autovelox fisso' : s.tipo.avviso, 'tipo': s.tipo.name, 'metri': m, 'limite': s.limiteKmh},
      if (passata != null) ...{'ancora_id': passata.id, 'ancora_testo': '${passata.tipo.nome}: c\'è ancora?'},
    });
  }

  /// Dove erano centrate le ZTL mandate all'auto, e quando.
  Punto? _zoneQui;
  DateTime _zoneAlle = DateTime(0);

  void _zoneDaCapo() => unawaited(_zone(subito: true));

  /// Le ZTL e le aree pedonali intorno all'auto, se si vogliono sulla mappa.
  /// Si rimandano spostandosi di un paio di chilometri, o ogni cinque minuti:
  /// cambiano stato nel corso della giornata («attiva fino alle 18»).
  Future<void> _zone({bool subito = false}) async {
    final g = ztl;
    if (g == null || !_attivo) return;
    final qui = guida.avanzamento?.posizioneSulPercorso ?? posizione.qui ?? viaggio.ultimaPosizione;
    final ora = _ora();
    if (!g.scelte.sullaMappa || qui == null) {
      if (_zoneQui != null || subito) {
        _zoneQui = null;
        _manda('sorgenti', {
          'dati': {sorgenteZtl: jsonEncode(datiZtl(const [], ora))},
        });
      }
      return;
    }
    final prima = _zoneQui;
    if (!subito && prima != null && distanzaM(prima, qui) < 2000 && ora.difference(_zoneAlle) < const Duration(minutes: 5)) {
      return;
    }
    _zoneQui = qui;
    _zoneAlle = ora;
    final archivio = await g.zone();
    // Le ZTL per dieci chilometri; le aree pedonali, che sono tante, per tre.
    final zone = [
      for (final z in archivio.vicine(qui, 10000))
        if (z.tipo == TipoZona.ztl || distanzaM(z.puntoDentro, qui) < 3000) z,
    ];
    _manda('sorgenti', {
      'dati': {sorgenteZtl: jsonEncode(datiZtl(zone.take(1500), ora))},
    });
  }

  /// Una richiesta di navigazione (NF-6, VC-1): con il punto si parte
  /// subito, altrimenti si cerca e si va al primo risultato; una tappa
  /// (`add_a_stop`) in guida si aggiunge al viaggio.
  Future<void> naviga(String uri) async {
    final r = RichiestaNavigazione.leggi(uri);
    if (r == null) {
      _manda('messaggio', {'testo': 'Non ho capito dove andare.'});
      return;
    }
    Luogo? meta;
    if (r.punto case final p?) {
      meta = Luogo(nome: r.testo ?? 'Destinazione', posizione: p);
    } else {
      try {
        final trovati = await viaggio.luoghi.cerca(r.testo!, vicinoA: posizione.qui ?? viaggio.ultimaPosizione);
        meta = trovati.firstOrNull;
      } catch (_) {
        meta = null;
      }
    }
    if (meta == null) {
      _manda('messaggio', {'testo': 'Non trovo «${r.testo}».'});
      return;
    }
    if (r.tappa && guida.attiva) {
      await guida.passaDa(meta);
      return;
    }
    if (guida.attiva) await guida.ferma();
    await luoghi?.usato(meta);
    await viaggio.vaiA(meta);
    if (viaggio.stato is ViaggioPronto) guida.avvia();
  }

  var _conProva = false;

  /// La prova di guida (NF-7): la guida in corso si percorre da sola; senza
  /// guida si parte verso il viaggio pronto o, se non c'è, verso Casa,
  /// Lavoro, l'ultima meta o un punto poco più avanti.
  Future<void> provaDiGuida() async {
    if (prova == null) return;
    _conProva = true;
    if (!guida.attiva) {
      if (viaggio.stato is! ViaggioPronto) {
        final meta = _metaDiProva();
        if (meta == null) {
          _manda('messaggio', {'testo': 'Prova di guida: scegli una meta con Cerca.'});
          return;
        }
        await viaggio.vaiA(meta);
      }
      if (viaggio.stato is ViaggioPronto) guida.avvia();
    }
    _guida();
  }

  Luogo? _metaDiProva() {
    final g = luoghi;
    final salvata = g?.casa?.luogo ?? g?.lavoro?.luogo ?? g?.recenti.firstOrNull;
    final qui = posizione.qui ?? viaggio.ultimaPosizione;
    if (salvata != null && (qui == null || distanzaM(qui, salvata.posizione) > 500)) return salvata;
    if (qui == null) return null;
    // Tre chilometri verso nord-est.
    return Luogo(nome: 'Prova di guida', posizione: Punto(qui.lat + 0.019, qui.lon + 0.026));
  }

  /// Con la prova accesa la posizione finta segue la guida, da dove si è.
  void _seguiProva() {
    final pr = prova, p = guida.pronto;
    if (pr == null) return;
    if (!guida.attiva || p == null || !_conProva) {
      if (pr.attiva) pr.ferma();
      _percorsoProva = null;
      return;
    }
    if (!pr.attiva || !identical(_percorsoProva, p.viaggio.percorso)) {
      // Percorso nuovo (ricalcolo, traffico, tappa fatta): si riparte dal
      // punto in cui si era, portato sul nuovo.
      /* Da fuori percorso l'aggancio non c'e' piu' — e' la regola nuova — ma
       * la prova di guida deve ripartire da dove si e', non dall'inizio. */
      final qui = pr.attiva ? guida.avanzamento?.posizioneSulPercorso ?? posizione.qui : null;
      _percorsoProva = p.viaggio.percorso;
      final daM = qui == null ? 0.0 : Linea(p.viaggio.percorso.punti).proietta(qui).lungoM;
      pr.percorri(p.viaggio.percorso, daM: daM);
    }
  }

  PercorsoCalcolato? _percorsoProva;

  void _guida() {
    _seguiProva();
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
      // Dove si arriva: CarPlay vuole il viaggio con partenza e arrivo.
      'destinazione_lat': p.destinazione.posizione.lat,
      'destinazione_lon': p.destinazione.posizione.lon,
      // Con quanta batteria si arriva, per il riepilogo del viaggio.
      if (auto?.elettrica ?? true) 'arrivo_batteria': ?guida.batteriaArrivo,
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
      unawaited(_disegnaSvincolo(p.viaggio.percorso, m));
    }
    _posizione();
  }

  int? _svincoloChiesto;

  (int, int)? _freccia;

  int? _svincoloPronto;

  /// Lo svincolo in 3D per l'auto: la stessa scena del telefono, in PNG.
  Future<void> _disegnaSvincolo(PercorsoCalcolato percorso, Manovra m) async {
    if (!_attivo) return;
    try {
      _manda('svincolo', {
        'id': m.inizio,
        'png': await scenaSvincoloPng(m, larghezza: 960, altezza: 380, gradi: quantoGiraLaManovra(percorso, m)),
      });
      _svincoloPronto = m.inizio;
      _guida();
    } catch (_) {
      // Senza immagine restano freccia e corsie.
    }
  }

  /// Al massimo tre volte al secondo: fra una e l'altra l'auto fa scorrere
  /// da sé segnaposto e mappa.
  void _posizione() {
    final a = guida.attiva ? guida.avanzamento : null;
    final qui = a?.posizioneSulPercorso ?? posizione.qui;
    // Senza posizione non c'è niente da mostrare: non si consuma il turno.
    if (qui == null) return;
    final ora = _ora();
    if (ora.difference(_ultimaPosizione) < const Duration(milliseconds: 300)) return;
    _ultimaPosizione = ora;
    final rotta = a?.rotta ?? posizione.rotta;
    // La mappa guarda un po' avanti; la freccia dell'auto segue la strada.
    // Il segnaposto lo disegna l'auto, che lo fa scorrere fra due posizioni.
    _manda('posizione', {
      'lat': qui.lat,
      'lon': qui.lon,
      'rotta': a?.rottaMappa ?? rotta,
      'rotta_io': rotta,
      'icona': posizione.segnaposto.immagine,
    });
    _cruscotto();
    unawaited(_zone());
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
      // Come sul telefono: col GPS muto è zero, non l'ultima letta. Il
      // cruscotto si rimanda anche senza posizioni nuove (i dati dell'auto
      // si rileggono ogni cinque secondi), e lì restava la velocità vecchia.
      'velocita': posizione.velocitaAdesso(),
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
  /// [ospite]: Premium si compra nell'app che ospita gdanav (gdahome).
  /// [aggiorna]: questa versione è troppo vecchia (`GestoreAggiornamento`):
  /// l'auto resta ferma sullo schermo che dice di aggiornare gdanav sul
  /// telefono, come senza Premium.
  ///
  /// [guidaInAuto]: se in auto si guida, che non è per forza Premium: dentro
  /// gdahome, senza una casa abbinata, si guida base (`preparaGdanav`). Senza
  /// dirlo vale [sbloccato], come prima.
  void premium(bool sbloccato, {bool ospite = false, bool aggiorna = false, bool? guidaInAuto}) => _manda('premium', {
        'sbloccato': sbloccato && !aggiorna,
        'ospite': ospite,
        'aggiorna': aggiorna,
        'guida_in_auto': (guidaInAuto ?? sbloccato) && !aggiorna,
      });

  void _manda(String metodo, Map<String, Object?> dati) {
    if (!_attivo) return;
    _canale.invokeMethod<void>(metodo, dati).catchError((Object e) {
      // Nessun Android Auto (iPhone, prove): si smette di provarci.
      if (e is MissingPluginException) _attivo = false;
    });
  }
}

/// La posizione che manda il lato Kotlin dal GPS dell'auto
/// (`PonteAuto.posizioneDallAuto`): `lat` e `lon`, e `rotta` in gradi,
/// `velocita_ms`, `precisione_m` e `letto_ms` quando l'auto li dà. `null` se
/// non dice dove.
Position? posizioneDellAuto(Map<Object?, Object?> dati) {
  final lat = (dati['lat'] as num?)?.toDouble(), lon = (dati['lon'] as num?)?.toDouble();
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) return null;
  final rotta = (dati['rotta'] as num?)?.toDouble();
  final ms = (dati['letto_ms'] as num?)?.toInt();
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: ms == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(ms),
    accuracy: (dati['precisione_m'] as num?)?.toDouble() ?? 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: rotta ?? 0,
    // La direzione vale solo se l'auto l'ha data: senza, lo zero vorrebbe
    // dire nord (vedi rottaDaFidarsi).
    headingAccuracy: rotta == null ? 0 : 1,
    speed: (dati['velocita_ms'] as num?)?.toDouble() ?? 0,
    speedAccuracy: 0,
  );
}
