import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:geolocator/geolocator.dart' show Position;

import '../componenti/icona_manovra.dart' show bandieraArrivoPng, puntaManovraPng;
import '../componenti/icone_punti.dart';
import '../componenti/icone_segnalazioni.dart';
import '../componenti/itinerario.dart' show nomeStrada, numeroStrada, vociStrade;
import '../componenti/stato_colonnina.dart' show testoDisponibilita;
import '../componenti/scena_svincolo.dart';
import '../componenti/vista_svincolo.dart';
import '../componenti/ztl.dart';
import '../mappa/controllo_mappa.dart' show VistaMappa;
import '../mappa/dati_viaggio.dart';
import '../mappa/ponte_3d.dart' show chiamata3d;
import '../mappa/regia_3d.dart';
import '../mappa/segnaposto.dart';
import '../mappa/stile.dart';
import '../schermate/scheda_punto.dart';
import '../servizi.dart';
import '../stato/archivio.dart' show Archivio;
import '../stato/avvisi_strada.dart';
import '../stato/avvisi_ztl.dart';
import '../stato/distributori.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_luoghi.dart';
import '../stato/gestore_meteo.dart';
import '../stato/gestore_persone.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_risparmio.dart' show sintesiProposta;
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/prova_di_guida.dart';
import '../stato/scelte_avvisi.dart';
import '../stato/viaggi_pianificati.dart';
import '../stato/voce.dart';
import 'persone_in_auto.dart';
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
    this.pianificati,
    this.auto,
    this.segnalazioni,
    this.meteo,
    this.vicini,
    this.prova,
    this.ztl,
    this.persone,
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

  /// I viaggi pianificati (sul telefono o da PC): in cima a «Dove andiamo?».
  final GestoreViaggiPianificati? pianificati;
  final GestoreAuto? auto;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreMeteo? meteo;

  /// Distributori o colonnine intorno, anche sulla mappa dell'auto.
  final GestoreVicini? vicini;

  /// La prova di guida che Android Auto accende (il «test drive»).
  final ProvaDiGuida? prova;

  /// Le ZTL e le aree pedonali sulla mappa dell'auto, e gli avvisi.
  final GestoreZtl? ztl;

  /// Le persone di casa, quando GdANav sta dentro GdAHome: sulla mappa
  /// dell'auto come su quella del telefono (vedi [PersoneInAuto]).
  final GestorePersone? persone;
  PersoneInAuto? _persone;
  final MethodChannel _canale;
  final DateTime Function() _ora;
  var _attivo = true;
  DateTime _ultimaPosizione = DateTime(0);
  AvvisiStrada? _avvisi;
  AvvisiZtl? _avvisiZtl;

  void avvia() {
    _canale.setMethodCallHandler(_dallAuto);
    _stili();
    // Col 3D aumentato scelto sul telefono anche l'auto ne prende l'aspetto
    // (colori, ponti sollevati, corsie, auto rossa); altrimenti com'era.
    Archivio.vistaScelta.addListener(_dallaVista);
    unawaited(guida.archivio?.vistaMappa().then((_) => _dallaVista()));
    _immagini();
    viaggio.addListener(_viaggio);
    viaggio.addListener(_opzioni);
    guida.addListener(_guida);
    // Anche dalla guida: l'avanzamento arriva dopo la posizione, e mandare
    // quello vecchio faceva passi a volte lunghi a volte corti.
    guida.addListener(_posizione);
    posizione.addListener(_posizione);
    luoghi?.addListener(_luoghi);
    pianificati?.addListener(_luoghi);
    auto?.addListener(_cruscotto);
    auto?.addListener(_opzioni);
    meteo?.addListener(_cruscotto);
    vicini?.addListener(_vicini);
    // Le scelte che il menu dell'auto mostra, anche se cambiano sul telefono.
    guida.avvisi.addListener(_opzioni);
    ztl?.addListener(_opzioni);
    if (segnalazioni case final s?) {
      s.addListener(_segnalazioni);
      guida.avvisi.addListener(_segnalazioni);
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
    if (persone case final g?) {
      _persone = PersoneInAuto(
        g,
        (dati) => _manda('sorgenti', {
          'dati': {sorgentePersone: dati},
        }),
      )..avvia();
    }
  }

  /// Le icone delle segnalazioni, disegnate come sul telefono.
  Future<void> _immagini() async {
    if (!_attivo) return;
    try {
      _manda('immagini', {
        'png': {
          // Le segnalazioni; gli autovelox col loro disegno (fisso, mobile,
          // semaforo) e il cartello del limite accanto.
          ...await iconeSegnalazioni(),
          // Il cartello della ZTL, per l'avviso.
          'segnala-ztl': await cartelloZtlPng(),
          // La punta della freccia di manovra sul percorso.
          immaginePuntaManovra: await puntaManovraPng(),
          // La bandiera a scacchi sulla meta.
          immagineBandieraArrivo: await bandieraArrivoPng(),
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
        // E i viaggi pianificati, letti freschi: quello pianificato poco fa
        // sul telefono deve esserci in «Dove andiamo?».
        if (a['si'] == true && pianificati != null) unawaited(pianificati!.carica());
      // Android Auto accende la prova di guida: da qui ogni guida si percorre
      // da sola, e se non c'è ancora una meta se ne sceglie una.
      case 'prova_guida':
        await provaDiGuida();
      // La sessione dell'auto è finita: la prova di guida pure.
      // La scena 3D sullo schermo dell'auto (Scena3dAuto): come la vede
      // l'auto (giorno o notte, la vista, quanto coprono le schede), e quello
      // che la pagina dice.
      case 'stato3d':
        _stato3d = (
          notte: a['notte'] == true,
          vista: a['vista'] == 'immersiva' ? VistaMappa.immersiva : VistaMappa.inclinata,
          sopra: (a['sopra'] as num?)?.toDouble() ?? 0,
          sinistra: (a['sinistra'] as num?)?.toDouble() ?? 0,
        );
        _regia3d?.comandi();
      case 'dalla3d':
        (_regia3d ??= _nuovaRegia3d()).dallaMappa(a['testo'] as String? ?? '');
      case 'chiusa3d':
        _regia3d?.ferma();
        _regia3d = null;
      case 'prova_fine':
        _conProva = false;
        _seguiProva();
      // «Ok Google, naviga verso…» o un'altra app che chiede un percorso.
      case 'naviga':
        await naviga(a['uri'] as String? ?? '');
      // «Fine» premuto sullo schermo dell'auto.
      case 'ferma':
        // Anche dal riepilogo dell'arrivo: si chiude, come «Fine» sul telefono.
        guida.chiudiRiepilogo();
        if (guida.attiva) await guida.ferma();
        viaggio.annulla();
      case 'cerca':
        final testo = a['testo'] as String? ?? '';
        final trovati = await viaggio.luoghi.cerca(testo, vicinoA: posizione.qui ?? viaggio.ultimaPosizione);
        return [for (final l in trovati) luogoJson(l)];
      // Una meta scelta in auto: si calcola e si parte, senza toccare il telefono.
      // La risposta dice se la guida è partita (vedi [vaiDallAuto]).
      // Un viaggio pianificato porta il suo numero: si parte con le sue tappe.
      case 'vai':
        if (_pianificato(a['viaggio']) case final v?) return vaiPianificato(v);
        final l = luogoDaJson(call.arguments);
        if (l == null) return false;
        // «Ehi Siri, portami a casa» parte subito; una meta scelta sullo
        // schermo mostra prima le strade (vedi [_strade]).
        return vaiDallAuto(l, subito: a['subito'] == true);
      // Una delle strade proposte, toccata sull'auto.
      case 'scegli_strada':
        if (a['id'] != _idStrade) return false;
        final i = (a['indice'] as num?)?.toInt() ?? -1;
        await viaggio.scegli(i);
        return true;
      // «Avvia» sulle strade dell'auto: si parte con quella scelta.
      // Con l'indice della strada toccata: se non è ancora quella del
      // viaggio (il tocco e «Avvia» arrivano insieme), prima la si sceglie.
      case 'avvia':
        if (a['id'] != _idStrade || viaggio.stato is! ViaggioPronto || guida.attiva) return guida.attiva;
        if ((a['indice'] as num?)?.toInt() case final i? when i != (viaggio.stato as ViaggioPronto).scelta) {
          await viaggio.scegli(i);
          if (viaggio.stato is! ViaggioPronto || guida.attiva) return guida.attiva;
        }
        guida.avvia();
        return guida.attiva;
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
      case 'scelta':
        await _sceltaDallAuto(a);
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
      // «Usa auto termica» sull'avviso dell'auto: vale solo per l'ultimo
      // «manca la batteria» mandato, e se il viaggio è ancora fermo lì.
      case 'termica':
        if (a['id'] != 'termica-$_numeroTermica' || !identical(viaggio.stato, _senzaBatteriaMandato)) return false;
        await viaggio.passaATermica();
        if (viaggio.stato is! ViaggioPronto) return false;
        guida.avvia();
        return guida.attiva;
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
        if (l == null) return false;
        // Con la termica ci si passa e si prosegue; con l'elettrica il
        // punto diventa la meta (le soste le fa il piano).
        if (guida.attiva && (guida.pronto?.termica ?? false)) {
          await guida.passaDa(l);
          return true;
        }
        return vaiDallAuto(l, ricorda: false, subito: true);
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
          final descrizione = righe.isEmpty ? p.nome : righe.first.titolo;
          return {
            'titolo': p.nome.isEmpty ? 'Punto' : p.nome,
            'voci': [
              for (final r in righe) {'icona': r.icona, 'colore': r.colore, 'titolo': r.titolo, 'testo': r.testo},
            ],
            'stato': stato,
            'vai': guida.attiva && (guida.pronto?.termica ?? false)
                ? 'Passa di qui'
                : p.tipo == 'persona' && p.nome.trim().isNotEmpty
                ? 'Naviga verso ${nomeBreve(p.nome)}'
                : 'Vai',
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

  ViaggioPianificato? _pianificato(Object? id) =>
      id is String ? pianificati?.viaggi.where((v) => v.id == id).firstOrNull : null;

  /// I viaggi pianificati per «Dove andiamo?»: la meta come posto (un'auto
  /// con l'app vecchia ci va e basta), il nome e quando partire.
  List<Map<String, Object?>> _viaggiPerLAuto() {
    final g = pianificati;
    if (g == null || !g.sbloccato) return const [];
    final adesso = _ora();
    return [
      for (final v in g.perLAuto)
        if (v.meta case final m? when v.id != null)
          {
            ...luogoJson(m.luogo),
            'tipo': 'pianificato',
            'viaggio': v.id,
            'etichetta': v.titolo,
            'descrizione': sottotitoloInAuto(v, adesso),
          },
    ];
  }

  void _luoghi() {
    final g = luoghi;
    if (g == null) return;
    _manda('luoghi', {
      // I viaggi pianificati, Casa e Lavoro, gli ultimi posti, poi gli altri
      // salvati (importati da Google possono essere centinaia: l'auto ne
      // mostra pochi).
      'elenco': [
        ..._viaggiPerLAuto(),
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
      // Il muto di prima (la voce di guida) per un'auto con l'app vecchia, e
      // l'audio a tre stati per il menu nuovo.
      'muto': guida.muto,
      'audio': guida.audio.chiave,
      // «Anche il discorso audio deve essere modificabile»: il modo si sceglie
      // diretto, e la voce ha volume e velocità.
      'audio_modi': [
        for (final m in ModoAudio.values) {'id': m.chiave, 'nome': _nomeDelModo(m), 'sotto': _sottoDelModo(m)},
      ],
      'voce_volume': regolazioniVoce.value.$1.name,
      'voce_volume_nome': regolazioniVoce.value.$1.nome,
      'voce_volumi': [
        for (final v in VolumeVoce.values) {'id': v.name, 'nome': v.nome},
      ],
      'voce_velocita': regolazioniVoce.value.$2.name,
      'voce_velocita_nome': regolazioniVoce.value.$2.nome,
      'voce_velocitas': [
        for (final v in VelocitaVoce.values) {'id': v.name, 'nome': v.nome},
      ],
      'elettrica': auto?.elettrica ?? true,
      'arrivo': ?viaggio.minimoArrivo,
      /* «Dall'auto devi dare la possibilità di comandare di più le
       * impostazioni: gli avvisi non si possono modificare, idem il simbolo
       * dell'auto.» Sullo schermo dell'auto, come sul telefono: ogni avviso
       * col suo modo (voce, beep, schermo, spento), il simbolo dell'auto, le
       * ZTL sulla mappa e il 3D aumentato. */
      'avvisi': [
        for (final av in Avviso.values)
          {
            'id': av.name,
            'nome': av.nome,
            'sotto': av.sotto,
            'come': guida.avvisi.di(av).name,
            'come_nome': guida.avvisi.di(av).etichetta,
            if (av.soloVoce) 'solo_voce': true,
            if (av.segnalazione != null) 'segnalazione': true,
          },
      ],
      'segnaposto': posizione.segnaposto.name,
      'segnaposti': [
        for (final sp in Segnaposto.values) {'id': sp.name, 'nome': sp.etichetta},
      ],
      if (ztl case final z?) 'ztl_mappa': z.scelte.sullaMappa,
      if (guida.archivio != null) 'aumentato': Archivio.vistaScelta.value == VistaMappa.aumentata,
    });
    _segnapostoNelMenu = posizione.segnaposto;
  }

  /// Il simbolo che il menu dell'auto ha in pagina.
  Segnaposto? _segnapostoNelMenu;

  static String _nomeDelModo(ModoAudio m) => switch (m) {
    ModoAudio.tutto => 'Tutto',
    ModoAudio.soloAvvisi => 'Solo avvisi',
    ModoAudio.silenzio => 'Silenzio',
  };

  static String _sottoDelModo(ModoAudio m) => switch (m) {
    ModoAudio.tutto => 'Le indicazioni e gli avvisi a voce',
    ModoAudio.soloAvvisi => 'Autovelox, segnalazioni, ZTL e limite; niente indicazioni',
    ModoAudio.silenzio => 'Nessuna voce, nemmeno gli avvisi',
  };

  /// Una scelta fatta sullo schermo dell'auto, nelle impostazioni.
  Future<void> _sceltaDallAuto(Map<Object?, Object?> a) async {
    if (a['audio'] case final String id) {
      final m = ModoAudio.values.where((x) => x.chiave == id).firstOrNull;
      if (m != null) guida.scegliAudio(m);
    }
    final (volume, velocita) = regolazioniVoce.value;
    final nuovoVolume = VolumeVoce.values.where((x) => x.name == a['voce_volume']).firstOrNull ?? volume;
    final nuovaVelocita = VelocitaVoce.values.where((x) => x.name == a['voce_velocita']).firstOrNull ?? velocita;
    if (nuovoVolume != volume || nuovaVelocita != velocita) {
      regolazioniVoce.value = (nuovoVolume, nuovaVelocita);
      unawaited(guida.archivio?.salvaRegolazioniDellaVoce(regolazioniVoce.value));
    }
    // «Prova la voce»: come suona adesso, anche col silenzio scelto.
    if (a['prova_voce'] == true) unawaited(guida.voce.parla('Tra trecento metri, svolta a destra.'));
    if (a['avviso'] case final String id) {
      final av = Avviso.values.where((x) => x.name == id).firstOrNull;
      final come = ComeAvvisare.values.where((x) => x.name == a['come']).firstOrNull;
      if (av != null && come != null) guida.avvisi.scegli(av, come);
    }
    if (a['segnaposto'] case final String n) {
      final sp = Segnaposto.values.where((x) => x.name == n).firstOrNull;
      if (sp != null && sp != posizione.segnaposto) {
        await posizione.scegli(sp);
        _posizione();
      }
    }
    if (a['ztl_mappa'] case final bool si) await ztl?.mostra(si);
    if (a['aumentato'] case final bool si) {
      final archivio = guida.archivio;
      if (archivio != null) {
        await archivio.salvaVistaMappa(
          si ? VistaMappa.aumentata : (await archivio.vistaPrimaDellAumentata() ?? VistaMappa.inclinata),
        );
        // Riaccesa a mano si riprova, come sul telefono.
        if (si) _treDNonVa = false;
      }
    }
    _opzioni();
  }

  void ferma() {
    Archivio.vistaScelta.removeListener(_dallaVista);
    viaggio.removeListener(_viaggio);
    viaggio.removeListener(_opzioni);
    guida.avvisi.removeListener(_opzioni);
    ztl?.removeListener(_opzioni);
    guida.removeListener(_guida);
    guida.removeListener(_posizione);
    posizione.removeListener(_posizione);
    luoghi?.removeListener(_luoghi);
    pianificati?.removeListener(_luoghi);
    auto?.removeListener(_cruscotto);
    auto?.removeListener(_opzioni);
    meteo?.removeListener(_cruscotto);
    vicini?.removeListener(_vicini);
    segnalazioni?.removeListener(_segnalazioni);
    guida.avvisi.removeListener(_segnalazioni);
    _avvisi?.removeListener(_avviso);
    ztl?.removeListener(_zoneDaCapo);
    _avvisiZtl?.removeListener(_avviso);
    guida.risparmio?.removeListener(_strada);
    _persone?.ferma();
    _persone = null;
    _regia3d?.ferma();
    _regia3d = null;
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

  /// La mappa dell'auto con l'aspetto della mappa 3D del telefono (colori,
  /// ponti sollevati, corsie, auto rossa): solo se sul telefono la vista è
  /// il 3D aumentato. L'auto ha le sue viste (2D, 3D, immersiva): l'aspetto
  /// segue il telefono.
  var _aspetto3d = false;

  void _dallaVista() {
    final a = Archivio.vistaScelta.value == VistaMappa.aumentata;
    if (!_attivo || a == _aspetto3d) return;
    _aspetto3d = a;
    _stili();
    _posizione();
    _vuoi3d();
    _opzioni();
  }

  /* ── La scena 3D sull'auto ────────────────────────────────────────────
   *
   * «Certo, voglio la scena reale anche in macchina.» Col 3D aumentato
   * scelto sul telefono, Android Auto nelle viste 3D e immersiva mostra la
   * stessa pagina del telefono (viadotti, alberi, edifici, l'auto 3D) in una
   * WebView sua (Scena3dAuto), al posto della mappa di MapLibre. I dati sono
   * quelli del telefono, dalla stessa regia ([Regia3d]). Se la pagina non ce
   * la fa (WebGL che manca, troppo lenta) l'auto torna alla mappa di sempre,
   * e per questa sessione ci resta. */
  Regia3d? _regia3d;
  var _treDNonVa = false;
  ({bool notte, VistaMappa vista, double sopra, double sinistra}) _stato3d = (
    notte: false,
    vista: VistaMappa.inclinata,
    sopra: 0,
    sinistra: 0,
  );

  void _vuoi3d() => _manda('web3d_vuoi', {'si': _aspetto3d && !_treDNonVa});

  /// Sull'auto la scena 3D quasi alla distanza del telefono (vedi
  /// [Regia3d.piuVicina]): a 0,7 livelli più vicina, «troppo zoomato».
  static const piuVicina3dInAuto = 0.2;

  /// Sull'auto la telecamera più dall'alto che sul telefono (70°).
  static const inclinazione3dInAuto = 55.0;

  Regia3d _nuovaRegia3d() => Regia3d(
    gestore: viaggio,
    posizione: posizione,
    guida: guida,
    manda: (m) => _manda('web3d', {'js': chiamata3d(m)}),
    notte: () => _stato3d.notte,
    vista: () => _stato3d.vista,
    inquadratura: () => (libera: false, sopra: _stato3d.sopra, sinistra: _stato3d.sinistra),
    onNonVa: (motivo, {required ricorda}) {
      _treDNonVa = true;
      _regia3d?.ferma();
      _regia3d = null;
      _manda('web3d_no', {'motivo': motivo});
      _vuoi3d();
    },
    segnalazioni: segnalazioni,
    vicini: vicini,
    persone: persone,
    orologio: _ora,
    piuVicina: piuVicina3dInAuto,
    inclinazione: inclinazione3dInAuto,
  )..avvia();

  void _stili() {
    String stile({required bool scuro, bool immersiva = false}) => jsonEncode(
      stileMappa(
        scuro: scuro,
        chiaveTraffico: Servizi.chiaveTomTom,
        perAuto: true,
        immersiva: immersiva,
        aspetto3d: _aspetto3d,
      ),
    );
    _manda('stili', {
      'chiaro': stile(scuro: false),
      'scuro': stile(scuro: true),
      // La vista immersiva ha uno stile suo: le strade in metri, le corsie
      // sulla strada, gli edifici sopra il percorso.
      'chiaro_immersiva': stile(scuro: false, immersiva: true),
      'scuro_immersiva': stile(scuro: true, immersiva: true),
    });
  }

  String get _icona => iconaSullAuto(posizione.segnaposto, aspetto3d: _aspetto3d);

  void _viaggio() {
    final stato = viaggio.stato;
    final arrivati = guida.attiva ? null : guida.riepilogo;
    // Cosa dire sull'auto quando non si guida.
    _manda('messaggio', {
      'testo': switch (stato) {
        Calcolo(:final destinazione) => 'Calcolo il percorso per ${destinazione.nome}…',
        ErroreViaggio(:final senzaBatteria?) => senzaBatteria.inAuto,
        ErroreViaggio(:final messaggio) => messaggio,
        // Arrivati: «Sei arrivato a …»; il riepilogo intero sta nella sua
        // schermata (`arrivo`, qui sotto).
        _ when arrivati != null => 'Sei arrivato a ${arrivati.destinazione}',
        _ => null,
      },
      ...?_propostaTermica(stato),
    });
    /* «All'arrivo non si blocca il percorso e non c'è il report dei costi.»
     * La guida si fermava, ma il viaggio restava pronto e la sua linea sulla
     * mappa dell'auto; e il riepilogo era una riga sola, tagliata dopo il nome
     * della meta. Adesso, arrivati, la linea va via, e il riepilogo arriva in
     * righe: l'auto lo apre nella sua schermata, col tasto «Fine». */
    _manda('arrivo', {
      if (arrivati != null) ...{
        'titolo': 'Sei arrivato a ${arrivati.destinazione}',
        'righe': [
          for (final (titolo, testo) in arrivati.righeAuto) [titolo, testo],
        ],
      },
    });
    final dati = datiViaggio(stato is ViaggioPronto && arrivati == null ? stato.viaggio : null);
    _manda('sorgenti', {
      'dati': {for (final MapEntry(:key, :value) in dati.entries) key: jsonEncode(value)},
    });
    _cruscotto();
    _strade();
  }

  /* ─── Le strade prima di partire ─────────────────────────────────────────
   *
   * «Quando c'è il calcolo percorso questo non esce su Android Auto e
   * CarPlay»: sul telefono, calcolato il viaggio, la scheda mostra le strade
   * fra cui scegliere (più rapida, risparmia energia, tempo simile, più
   * lenta) con durata, km, batteria all'arrivo, consumo e pedaggio; l'auto
   * vedeva solo la linea. Adesso le stesse voci ([vociStrade]) vanno
   * all'auto: Android Auto le mostra nella sua anteprima dei percorsi,
   * CarPlay nelle sue scelte del viaggio, con «Avvia». Toccandone una si
   * sceglie anche sul telefono, e viceversa. */

  /// Il numero del viaggio di cui l'auto ha le strade: le risposte valgono
  /// solo per quello.
  String? _idStrade;
  var _numeroStrade = 0;
  ViaggioPronto? _prontoStrade;
  Object? _stradeMandate;

  void _strade() {
    final stato = viaggio.stato;
    final pronto = stato is ViaggioPronto && !guida.attiva && guida.riepilogo == null ? stato : null;
    // Un viaggio nuovo (un'altra meta, le tappe), non la stessa con un'altra
    // strada scelta: lo stesso numero, così il tocco sull'auto vale ancora.
    if (pronto == null) {
      _prontoStrade = null;
    } else if (_prontoStrade == null ||
        _prontoStrade!.destinazione != pronto.destinazione ||
        _prontoStrade!.tappe.length != pronto.tappe.length) {
      _idStrade = 'strade-${++_numeroStrade}';
      _prontoStrade = pronto;
    } else {
      _prontoStrade = pronto;
    }
    final dati = pronto == null ? const <String, Object?>{} : datiStrade(pronto, id: _idStrade!);
    final chiave = jsonEncode(dati);
    if (chiave == _stradeMandate) return;
    _stradeMandate = chiave;
    _manda('strade', dati);
  }

  /// Quello che l'auto mostra delle strade del viaggio [p]: le stesse carte
  /// della scheda del telefono (`ScelteStrada`), in testo.
  Map<String, Object?> datiStrade(ViaggioPronto p, {required String id}) {
    final r = guida.risparmio;
    final v = p.viaggio;
    final piano = v.piano;
    final unita = r?.unita ?? 'kWh';
    final tariffa = viaggio.opzioni.tariffaPedaggio;
    final scelte = p.scelte.length > 1 ? p.scelte : [v.percorso];
    final voci = vociStrade(
      scelte,
      scelta: p.scelte.length > 1 ? p.scelta : 0,
      consumo: r == null ? null : (q) => consumoStrada(q, r.stima),
      // Come sul telefono: la batteria all'arrivo solo senza soste.
      arrivo: p.soloPercorso || (piano?.soste.isNotEmpty ?? true) ? null : piano?.batteriaArrivo,
      capacitaKwh: viaggio.auto.veicolo.capacitaUtileKwh,
      minimoPercento: r?.soglie.minimoPercento ?? 5,
      pedaggio: tariffa.stima,
    );
    // Con una strada sola il suo nome non dice niente: «Percorso».
    final sola = voci.length == 1;
    return {
      'id': id,
      'meta': p.destinazione.nome,
      'lat': p.destinazione.posizione.lat,
      'lon': p.destinazione.posizione.lon,
      'scelta': p.scelte.length > 1 ? p.scelta : 0,
      'voci': [
        for (final x in voci)
          {
            'nome': sola ? 'Percorso' : nomeStrada(x.etichetta, unita),
            'eco': x.etichetta == EtichettaStrada.risparmia && !sola,
            'durata_s': x.strada.durata.inSeconds,
            'metri': x.strada.lunghezzaM,
            'via': x.via,
            'km': '${(x.strada.lunghezzaM / 1000).round()} km',
            if (x.arrivo case final a?) 'arrivo': a.round(),
            if (x.consumo case final c?) 'consumo': '${numeroStrada(c)} $unita',
            if (x.risparmio case final c?) 'risparmio': '−${numeroStrada(c)} $unita',
            if (x.pedaggio case final c?) ...{'pedaggio': c.breve, 'paga': !c.senzaPedaggi},
            'traffico': ?x.traffico,
          },
      ],
    };
  }

  /// L'ultimo «manca la batteria» mandato all'auto, e il suo numero: la
  /// risposta dell'auto vale solo per quello.
  ErroreViaggio? _senzaBatteriaMandato;
  var _numeroTermica = 0;

  /// Manca la batteria: l'auto propone di passare alla termica, con un
  /// tasto (Android Auto: un messaggio coi tasti; CarPlay: un avviso). Lì la
  /// batteria non si scrive, e la scheda del telefono è lontana. `titolo` e
  /// `primaria` dicono quale dei due casi è: senza auto elettrica la termica
  /// è la proposta; con l'elettrica, una via d'uscita.
  Map<String, Object?>? _propostaTermica(StatoViaggio stato) {
    if (stato is! ErroreViaggio || stato.senzaBatteria == null) return null;
    if (!identical(stato, _senzaBatteriaMandato)) {
      _senzaBatteriaMandato = stato;
      _numeroTermica++;
    }
    final nessuna = stato.senzaBatteria == SenzaBatteria.nessunaElettrica;
    return {
      'termica': 'termica-$_numeroTermica',
      'termica_titolo': nessuna ? 'Nessuna auto elettrica' : 'Batteria sconosciuta',
      'termica_primaria': nessuna,
    };
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
      'dati': {sorgenteSegnalazioni: jsonEncode(datiSegnalazioni(s.vicine, guida.avvisi))},
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
      if (z != null && z.fuori) ...{
        'titolo': z.titolo,
        'tipo': 'ztl',
        'testo': z.testo,
      } else if (davanti case (final s, final m)) ...{
        'titolo': s.fissa ? 'Autovelox fisso' : s.tipo.avviso,
        'tipo': s.tipo.name,
        'metri': m,
        'limite': s.limiteKmh,
      } else if (a?.tutor case final t?) ...{
        'titolo': switch (t) {
          DentroTutor(:final mediaKmh?) => 'Tutor · media ${mediaKmh.round()} km/h',
          _ => 'Tutor',
        },
        'tipo': 'autovelox',
        if (t case TutorDavanti(:final metri)) 'metri': metri,
        if (t case final DentroTutor d)
          'testo': 'mancano ${distanzaBreve(d.restantiM)}${d.sopra() ? ' · rallenta' : ''}',
        'limite': t.tratto.limiteKmh,
      } else if (z != null) ...{
        'titolo': z.titolo,
        'tipo': 'ztl',
        'testo': z.testo,
      },
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
    if (!subito &&
        prima != null &&
        distanzaM(prima, qui) < 2000 &&
        ora.difference(_zoneAlle) < const Duration(minutes: 5)) {
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
    await vaiDallAuto(meta, subito: true);
  }

  /* ─── Una meta scelta in auto, fino alla guida ───────────────────────────
   *
   * Dal campo, su iPhone con CarPlay dentro GdAHome: «ogni volta che scelgo
   * un indirizzo e lo confermo, lo schermo sfarfalla un attimo e resta sulla
   * pagina iniziale del navigatore dove si sceglie la destinazione».
   *
   * La parte grossa era sul lato nativo (vedi `SchermiCarPlay.swift`, «I
   * passi fra gli schermi»), ma anche qui c'era un buco: tutto quello che
   * succede prima che il viaggio entri in «Calcolo» — chiedere dove si è (che
   * la prima volta chiede il permesso, e con il telefono in tasca può anche
   * lanciare), ricordare la meta fra le recenti nel portachiavi — stava fuori
   * da ogni `try`. Un errore li' saliva fino al canale, l'auto riceveva un
   * errore che nessuno guardava, e sullo schermo restava solo «Calcolo il
   * percorso…» per cinque secondi, poi la mappa ferma: proprio quello che si
   * vedeva. Adesso:
   *
   *  - ricordare la meta non ferma mai il viaggio: se non si scrive, pazienza;
   *  - un errore prima del calcolo diventa un messaggio sull'auto, con il nome
   *    della meta, invece del silenzio;
   *  - la risposta all'auto dice se la guida e' partita davvero (`true`), cosi'
   *    il lato nativo non deve indovinarlo.
   *
   * Gli errori del calcolo vero (niente batteria, server lenti, percorso
   * impossibile) li dice gia' il viaggio stesso (`ErroreViaggio`), e arrivano
   * all'auto da [_viaggio] come sempre: qui non si ripetono. */

  /// Ferma la guida in corso e calcola il viaggio verso [meta]. Se è pronto,
  /// con [subito] (la voce, un distributore dove si passa) si parte; senza,
  /// l'auto mostra le strade fra cui scegliere e parte con «Avvia» (vedi
  /// [_strade]). [ricorda]: la meta va fra le recenti (non per un
  /// distributore). Torna `true` se il viaggio è pronto (e, con [subito], se
  /// la guida è partita).
  Future<bool> vaiDallAuto(Luogo meta, {bool ricorda = true, bool subito = false}) async {
    try {
      if (guida.attiva) await guida.ferma();
      if (ricorda) {
        try {
          await luoghi?.usato(meta);
        } catch (_) {
          // Fra le recenti la si rimette la prossima volta: si parte lo stesso.
        }
      }
      await viaggio.vaiA(meta);
    } catch (_) {
      _manda('messaggio', {'testo': 'Non sono riuscito a calcolare il viaggio per ${meta.nome}. Riprova.'});
      return false;
    }
    if (viaggio.stato is! ViaggioPronto) return false;
    if (!subito) {
      _strade();
      return true;
    }
    guida.avvia();
    return guida.attiva;
  }

  /// Un viaggio pianificato scelto in auto: si parte con tutte le sue tappe,
  /// dall'ultima che si è salvata. Torna `true` se la guida è partita.
  Future<bool> vaiPianificato(ViaggioPianificato v) async {
    final tappe = [for (final t in v.tappe) t.luogo];
    if (tappe.isEmpty) return false;
    try {
      if (guida.attiva) await guida.ferma();
      await viaggio.vaiPerTappe(tappe);
    } catch (_) {
      _manda('messaggio', {'testo': 'Non sono riuscito a calcolare ${v.titolo}. Riprova.'});
      return false;
    }
    if (viaggio.stato is! ViaggioPronto) return false;
    guida.avvia();
    return guida.attiva;
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

  /// Il riepilogo dell'arrivo già mandato all'auto.
  String? _arrivoDetto;

  /// La versione della strada già fatta mandata all'auto, e quando.
  var _tracciaMandata = -1;
  DateTime? _tracciaMandataAlle;

  /// La strada già fatta in guida, all'auto: ogni quattro punti nuovi o tre secondi.
  void _traccia() {
    final v = guida.versioneTraccia;
    if (v == _tracciaMandata) return;
    final ora = _ora();
    final prima = _tracciaMandataAlle;
    // Ogni quattro punti nuovi (una trentina di metri) o tre secondi.
    if (guida.traccia.isNotEmpty &&
        prima != null &&
        v - _tracciaMandata < 4 &&
        ora.difference(prima) < const Duration(seconds: 3)) {
      return;
    }
    _tracciaMandata = v;
    _tracciaMandataAlle = ora;
    _manda('sorgenti', {
      'dati': {sorgenteFatto: jsonEncode(datiTraccia(guida.traccia))},
    });
  }

  void _guida() {
    _seguiProva();
    _traccia();
    // Partita la guida (o arrivati), le strade se ne vanno dall'auto.
    _strade();
    final a = guida.avanzamento;
    final p = guida.pronto;
    /* All'arrivo, al posto della manovra il riepilogo (e via quando si
     * chiude). Si guarda anche a guida partita: «il navigatore
     * improvvisamente perde il percorso». Arrivati senza toccare «Fine» il
     * riepilogo restava, e il viaggio nuovo partiva con la linea vuota
     * sull'auto (`_viaggio`, arrivati); la guida, partita, toglie il
     * riepilogo, ma qui la linea si rimandava solo a guida ferma: scheda
     * della manovra e arrivo c'erano, la linea blu no, fino al traffico
     * dopo o a un ricalcolo. */
    final arrivo = guida.attiva ? null : guida.riepilogo?.perAuto;
    if (arrivo != _arrivoDetto) {
      _arrivoDetto = arrivo;
      _viaggio();
    }
    if (!guida.attiva || p == null) {
      _manda('guida', {'attiva': false});
      if (_freccia != null) {
        _freccia = null;
        _manda('sorgenti', {
          'dati': {
            sorgenteManovra: jsonEncode(datiManovra(null, null)),
            sorgenteCorsie: jsonEncode(datiCorsie(null, null)),
          },
        });
      }
      _cruscotto();
      return;
    }
    final m = a?.prossima ?? p.viaggio.percorso.manovre.firstOrNull;
    final minutiDiTraffico = guida.minutiDiTraffico;
    // La striscia del traffico di lato, come sul telefono: «su Android Auto
    // non esce la linea ai lati del traffico con i minuti in più».
    final striscia = strisciaTraffico(
      p.viaggio.percorso,
      percorsiM: a?.percorsiM ?? 0,
    )?.allineataA(minutiDiTraffico, guida.ritardoDavanti);
    _manda('guida', {
      'attiva': true,
      'tipo': m?.tipo ?? 8,
      'distanza': a?.allaProssimaM ?? m?.lunghezzaM ?? 0.0,
      'strada': m?.strada ?? '',
      'istruzione': m?.istruzione ?? '',
      'restanti': a?.restantiM ?? p.viaggio.percorso.lunghezzaM,
      'secondi': (a?.restante ?? p.viaggio.percorso.durata).inSeconds,
      'arrivo': (guida.arrivoAlle ?? _ora()).millisecondsSinceEpoch,
      // Quanti minuti dell'arrivo sono traffico: l'auto colora il tempo
      // che resta (arancio, rosso da dieci minuti). Zero: niente colore.
      'traffico_minuti': minutiDiTraffico,
      if (striscia != null && striscia.code.isNotEmpty)
        'striscia': datiStriscia(striscia, percorsiM: a?.percorsiM ?? 0, lunghezzaM: p.viaggio.percorso.lunghezzaM),
      'destinazione': p.destinazione.nome,
      // Dove si arriva: CarPlay vuole il viaggio con partenza e arrivo.
      'destinazione_lat': p.destinazione.posizione.lat,
      'destinazione_lon': p.destinazione.posizione.lon,
      // Con quanta batteria si arriva, per il riepilogo del viaggio.
      if (auto?.elettrica ?? true) 'arrivo_batteria': ?guida.batteriaArrivo,
      // Il pedaggio che resta, accanto ai km che restano: nella scheda
      // dell'arrivo di Android Auto («~12,40 € pedaggio»); niente se non se
      // ne paga.
      if (guida.pedaggioDavanti case final c? when !c.senzaPedaggi) 'pedaggio': c.perStima,
      // Che strada si fa (dal percorso), per lo zoom sull'auto: vedi
      // `zoomLontanoInGuida`.
      'strada_kmh': ?a?.velocitaStradaKmh,
      'uscita': m?.uscita ?? '',
      'verso': m?.verso ?? '',
      'rotonda': m?.uscitaRotonda ?? (m != null && m.tipo == 26 ? uscitaDallaFrase(m.istruzione) : null),
      // Le frasi della scheda dalla più lunga alla più corta: sugli schermi
      // piccoli (CarPlay a 400×240) l'auto prende quella che ci sta.
      if (m != null) 'frasi': frasiManovra(m),
      // Le corsie solo avvicinandosi allo svincolo, e se non vanno bene tutte.
      if (m != null && m.corsieUtili && (a?.allaProssimaM ?? m.lunghezzaM) <= 2000)
        'corsie': [for (final c in m.corsie) c.toJson()],
      // Il «poi» solo se la manovra dopo arriva subito (entro 150 m), come
      // Mappe di Apple: più lontano era una riga in più sopra la mappa.
      if (a?.dopo case final d? when m != null && poiVicino(m, d)) ...{
        'dopo_tipo': d.tipo,
        'dopo_strada': d.strada.isNotEmpty ? d.strada : d.istruzione,
        'dopo_rotonda': ?d.uscitaRotonda,
        'dopo_frasi': frasiPoi(d),
      },
      if (m != null && _svincoloPronto == m.inizio && (a?.allaProssimaM ?? m.lunghezzaM) <= PopupSvincolo.daMetri)
        'svincolo': m.inizio,
    });
    // La freccia della manovra sul percorso, avvicinandosi.
    final chiave = chiaveFreccia(p.viaggio, a?.prossima, a?.allaProssimaM, ricalcolo: guida.ricalcolando);
    if (chiave != _freccia) {
      _freccia = chiave;
      _manda('sorgenti', {
        'dati': {
          sorgenteManovra: jsonEncode(datiManovra(chiave == null ? null : p.viaggio, a?.prossima)),
          // Le corsie sulla strada: le disegna solo la vista immersiva, che
          // ha la sorgente; l'auto in 2D e in 3D le lascia cadere.
          sorgenteCorsie: jsonEncode(datiCorsie(chiave == null ? null : p.viaggio, a?.prossima)),
        },
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

  /// Al massimo tre volte al secondo, più ogni posizione nuova della guida:
  /// fra una e l'altra l'auto fa scorrere da sé segnaposto e mappa.
  ///
  /// Prima una posizione nuova arrivata entro 300 ms dall'ultimo invio (il
  /// GPS avvisa la posizione e subito dopo la guida) si buttava: l'auto
  /// riceveva la stima fatta con la lettura di prima, e quella giusta solo un
  /// secondo dopo. Adesso la lettura nuova della guida passa sempre.
  ///
  /// Con la posizione va la velocità lungo la strada (`velocita_ms`): l'auto
  /// la usa per andare avanti da sola fra un invio e l'altro, invece di
  /// fermarsi sull'ultimo punto ad aspettare il prossimo (`MotoFluido` in
  /// gdanav_core, rifatto in `RendererMappa` e `MappaCarPlay`).
  void _posizione() {
    if (posizione.segnaposto != _segnapostoNelMenu) _opzioni();
    final a = guida.attiva ? guida.avanzamento : null;
    // In guida dove l'auto è adesso, portata avanti lungo la strada da
    // quando è arrivata la lettura: come sul telefono, a passi uguali.
    final stimata = a == null ? null : guida.posizioneStimata();
    final qui = stimata?.punto ?? a?.posizioneSulPercorso ?? posizione.qui;
    // Senza posizione non c'è niente da mostrare: non si consuma il turno.
    if (qui == null) return;
    final ora = _ora();
    final nuova = a != null && guida.letture != _lettureMandate;
    if (!nuova && ora.difference(_ultimaPosizione) < const Duration(milliseconds: 300)) return;
    _ultimaPosizione = ora;
    if (a != null) _lettureMandate = guida.letture;
    final rotta = stimata?.rotta ?? a?.rotta ?? posizione.rotta;
    // Agganciati alla strada la velocità della guida; se no quella del GPS
    // (zero col GPS muto: l'auto allora non va avanti da sola).
    final velocita = a != null ? guida.velocitaMs ?? 0.0 : posizione.velocitaAdesso() / 3.6;
    // La mappa guarda un po' avanti; la freccia dell'auto segue la strada.
    // Il segnaposto lo disegna l'auto, che lo fa scorrere fra due posizioni:
    // in guida sopra un pezzo del percorso (`pista`, a coppie lat, lon), dove
    // l'auto è a `pista_qui` metri dal suo inizio. Agli svincoli e nelle
    // rotonde non esce di strada (`MotoSullaStrada` in gdanav_core).
    final strada = stimata == null ? null : guida.strada;
    final metri = stimata == null ? null : guida.metriStimati();
    final da = metri == null ? 0.0 : math.max(0.0, metri - pistaIndietroM);
    final pista = strada == null || metri == null ? null : trattoDiStrada(strada, da, metri + pistaAvantiM);
    _manda('posizione', {
      'lat': qui.lat,
      'lon': qui.lon,
      'rotta': a?.rottaMappa ?? rotta,
      'rotta_io': rotta,
      'velocita_ms': velocita.isFinite ? velocita : 0.0,
      'icona': _icona,
      if (pista != null && metri != null) ...{
        'pista': [
          for (final p in pista) ...[p.lat, p.lon],
        ],
        'pista_qui': metri - da,
      },
    });
    _cruscotto();
    unawaited(_zone());
  }

  /// La lettura della guida già mandata all'auto.
  int _lettureMandate = -1;

  /// Il pezzo di percorso mandato con la posizione: un poco dietro l'auto
  /// (la freccia può essere indietro) e tanto davanti quanto si fa in più
  /// di un secondo e mezzo anche in autostrada.
  static const pistaIndietroM = 40.0, pistaAvantiM = 300.0;

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
      // Fra due letture la batteria è una stima: l'auto la scrive «~21%»,
      // come il pedaggio stimato. Quella detta dall'auto resta senza.
      'batteria_stimata': batteria != null && ora != null && !ora.misurata,
      'autonomia_km': autonomia?.km,
      'autonomia_auto': autonomia?.dallAuto ?? false,
      // Come sul telefono: col GPS muto è zero, non l'ultima letta. Il
      // cruscotto si rimanda anche senza posizioni nuove (i dati dell'auto
      // si rileggono ogni cinque secondi), e lì restava la velocità vecchia.
      'velocita': posizione.velocitaAdesso(),
      // In guida quello del percorso; senza, quello della strada di adesso.
      'limite': guida.attiva ? a?.limiteKmh : posizione.limiteKmh,
      'arrivo_batteria': p == null || !elettrica ? null : guida.batteriaArrivo,
      // Il pedaggio che resta, breve («~12,40 €»), sulla barra dell'auto.
      if (guida.attiva)
        if (guida.pedaggioDavanti case final c? when c.conPrezzo || c.vignetta || c.kmNonStimati > 0)
          'pedaggio': c.breve,
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
  /// [ospite]: Premium si compra nell'app che ospita GdANav (GdAHome).
  /// [aggiorna]: questa versione è troppo vecchia (`GestoreAggiornamento`):
  /// l'auto resta ferma sullo schermo che dice di aggiornare GdANav sul
  /// telefono, come senza Premium.
  ///
  /// [guidaInAuto]: se in auto si guida, che non è per forza Premium: dentro
  /// GdAHome, senza una casa abbinata, si guida base (`preparaGdanav`). Senza
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

/// Il segnaposto sullo schermo dell'auto: quello scelto, sempre.
///
/// Con l'aspetto della mappa 3D la freccia diventava l'auto rossa, come
/// nella scena 3D del telefono (che di frecce non ne ha). Ma sull'auto la
/// freccia c'è, e chi l'ha scelta non la vedeva: «se cambio simbolo e
/// metto freccia non funziona». [aspetto3d] resta per chi chiama.
String iconaSullAuto(Segnaposto s, {required bool aspetto3d}) => s.immagine;

/// La striscia del traffico per l'auto: le code dal basso (l'auto, 0) verso
/// l'alto (la meta, o la cima se il viaggio è più lungo, 1), coi minuti e
/// quanto mancano, già scritti come sul telefono.
///
/// «La linea del traffico laterale non fa vedere dove mi trovo io.» La
/// striscia era la strada che resta, con l'auto sempre in fondo: non si
/// vedeva a che punto del viaggio si è, né dove si è dentro una coda. Adesso,
/// quando il viaggio ci sta tutto ([StrisciaTraffico.tagliata] no), la
/// striscia è il viaggio intero, dalla partenza (0) all'arrivo (1): `qui` è
/// dove si è, e le code stanno al loro posto sul viaggio. Un viaggio più
/// lungo della striscia resta com'era: l'auto in fondo (`qui` 0).
Map<String, Object> datiStriscia(StrisciaTraffico s, {double percorsiM = 0, double lunghezzaM = 0}) {
  final qui = !s.tagliata && lunghezzaM > 0 ? (percorsiM / lunghezzaM).clamp(0.0, 1.0) : 0.0;
  double sulViaggio(double f) => qui + f * (1 - qui);
  return {
    'tagliata': s.tagliata,
    'qui': qui,
    'code': [
      for (final c in s.code)
        {
          'da': sulViaggio(c.da),
          'a': sulViaggio(c.a),
          'livello': c.livello,
          'minuti': c.minuti,
          'sotto': c.dentro ? 'ci sei' : distanzaBreve(c.distanzaM),
        },
    ],
  };
}
