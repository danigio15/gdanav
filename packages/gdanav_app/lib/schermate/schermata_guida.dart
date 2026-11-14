import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/avvisi_in_guida.dart';
import '../componenti/icona_manovra.dart';
import '../componenti/itinerario.dart' show BadgePedaggio;
import '../componenti/riga_del_viaggio.dart';
import '../componenti/icone_segnalazioni.dart';
import '../componenti/risparmio.dart';
import '../componenti/striscia_traffico.dart';
import '../componenti/tachimetro.dart';
import '../componenti/vista_svincolo.dart';
import '../componenti/vetro.dart';
import '../componenti/ztl.dart';
import '../mappa/controllo_mappa.dart';
import '../mappa/dati_viaggio.dart' show puntoLungo;
import '../mappa/scelta_vista.dart';
import '../mappa/mappa_3d.dart';
import '../mappa/mappa_viaggio.dart';
import '../sorgenti/schermo_acceso.dart';
import '../stato/avvisi_strada.dart';
import '../stato/avvisi_ztl.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_meteo.dart';
import '../stato/gestore_persone.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import '../stato/gestore_ztl.dart';
import '../stato/voce.dart';
import '../tema.dart';
import 'scheda_viaggio.dart' show durata, orario;
import 'schermata_principale.dart' show CostruisciMappa;
import 'distributori.dart';
import 'scheda_punto.dart';
import 'segnala.dart';

/// La guida: la mappa ti segue inclinata, in alto la prossima manovra, in
/// basso arrivo, chilometri e la prossima sosta.
class SchermataGuida extends StatefulWidget {
  const SchermataGuida({
    super.key,
    required this.guida,
    required this.posizione,
    this.segnalazioni,
    this.vicini,
    this.ztl,
    this.persone,
    this.mappa,
    this.meteo,
  });

  final GestoreGuida guida;
  final GestorePosizione posizione;
  final GestoreSegnalazioni? segnalazioni;

  /// Distributori o colonnine intorno, sulla mappa.
  final GestoreVicini? vicini;

  /// Le ZTL sulla mappa, e gli avvisi mentre si guida.
  final GestoreZtl? ztl;

  /// Le persone di casa (da GdAHome), anche in guida: sulla mappa di sempre
  /// e nel 3D aumentato, come sullo schermo dell'auto.
  final GestorePersone? persone;

  /// Il meteo all'arrivo (o qui), nella riga del viaggio come in auto.
  final GestoreMeteo? meteo;
  final CostruisciMappa? mappa;

  @override
  State<SchermataGuida> createState() => _SchermataGuidaState();
}

class _SchermataGuidaState extends State<SchermataGuida> {
  /// La stessa scelta della vista della mappa senza guida, ricordata; col 3D
  /// aumentato, e se questo telefono ce la fa.
  late final controllo = ControlloMappa(
    salvaVista: widget.guida.archivio?.salvaVistaMappa,
    aumentataPossibile: mappa3dPossibile,
    salvaAumentataNonVa: widget.guida.archivio?.salvaAumentataNonVa,
    dimenticaAumentataNonVa: widget.guida.archivio?.dimenticaAumentataNonVa,
  );

  /// Le segnalazioni lungo la strada, condivise con lo schermo dell'auto.
  AvvisiStrada? _avvisi;

  /// Le ZTL attive che si avvicinano, condivise anche loro con l'auto.
  AvvisiZtl? _ztl;

  /// Gli svincoli di cui si è chiuso il popup.
  final _svincoliChiusi = <int>{};

  /// Lo svincolo in arrivo, entro [PopupSvincolo.daMetri], se non chiuso.
  (Manovra, double)? _svincolo(GestoreGuida g) {
    final a = g.avanzamento, m = a?.prossima;
    if (a == null || m == null || !haSvincolo(m) || g.ricalcolando) return null;
    final metri = a.allaProssimaM;
    if (metri <= 0 || metri > PopupSvincolo.daMetri || _svincoliChiusi.contains(m.inizio)) return null;
    return (m, metri);
  }

  /// Col popup dello svincolo aperto la mappa sposta giù l'auto: la strada
  /// che arriva resta in vista sotto il popup.
  ///
  /// Di traverso il popup sta nel pannello a sinistra, col resto del
  /// cruscotto: la mappa mette l'auto nel mezzo della parte libera a destra.
  void _copri(BuildContext context, GestoreGuida g) {
    final traverso = _traverso(context);
    final alto = _svincolo(g) == null || traverso
        ? 0.0
        : MediaQuery.paddingOf(context).top +
              8 +
              72 +
              PopupSvincolo.larghezzaSu(MediaQuery.sizeOf(context).width) * 9 / 16;
    final sinistra = traverso ? _larghezzaPannello(context) : 0.0;
    if ((alto - controllo.coperto).abs() < 1 && (sinistra - controllo.copertoSinistra).abs() < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controllo.copriAlto(alto);
      controllo.copriSinistra(sinistra);
    });
  }

  /// Il telefono (o il tablet) di traverso: il cruscotto in un pannello a
  /// sinistra, la mappa a destra. In verticale la manovra in alto e la barra
  /// in fondo, come sempre.
  static bool _traverso(BuildContext context) {
    final d = MediaQuery.sizeOf(context);
    return d.width > d.height * 1.15;
  }

  /// Quanto è largo il pannello di sinistra, di traverso (col bordo sicuro).
  static double _larghezzaPannello(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.46).clamp(340.0, 460.0) + MediaQuery.paddingOf(context).left;

  /// Ridisegna ogni secondo il tachimetro e l'avviso del GPS: il GPS può
  /// tacere (da fermi, o perché il flusso si è perso), e quando tace nessuno
  /// lo dice.
  Timer? _battito;

  @override
  void initState() {
    super.initState();
    _battito = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.guida.archivio case final a?) {
      unawaited(controllo.carica(a.vistaMappa(), nonVa: a.aumentataNonVa(), prima: a.vistaPrimaDellAumentata()));
    }
    widget.guida.avvia();
    if (widget.segnalazioni case final seg?) _avvisi = AvvisiStrada.di(widget.guida, seg);
    if (widget.ztl case final z?) _ztl = AvvisiZtl.di(widget.guida, z);
  }

  /* Il telefono sul supporto non si tocca: senza chiederlo, il sistema
   * abbassava lo schermo e poi lo spegneva (`SchermoAcceso`). Ma solo quando
   * la guida si vede: dentro GdAHome, con la guida partita dall'auto e la
   * sezione del navigatore nascosta ([TickerMode] spento), lo schermo restava
   * acceso per sempre sopra la plancia («surriscaldamento atroce»). */
  bool? _schermoTenuto;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final siVede = TickerMode.valuesOf(context).enabled;
    if (siVede == _schermoTenuto) return;
    _schermoTenuto = siVede;
    unawaited(SchermoAcceso.tieni(siVede));
  }

  @override
  void dispose() {
    _battito?.cancel();
    unawaited(SchermoAcceso.tieni(false));
    controllo.dispose();
    super.dispose();
  }

  /// Un punto scelto in guida: con la termica ci si passa e si prosegue;
  /// con l'elettrica (le soste le fa il piano) diventa la nuova meta.
  Future<void> _vaiDurante(Luogo l) async {
    final g = widget.guida;
    if (g.pronto?.termica ?? false) return g.passaDa(l);
    await g.ferma();
    await g.viaggio.vaiA(l);
    if (g.viaggio.stato is ViaggioPronto) g.avvia();
  }

  /// Una sosta di ricarica toccata sulla mappa di sempre: la scheda della
  /// colonnina, come nel 3D aumentato.
  void _colonninaDelViaggio(String id) {
    final v = widget.guida.pronto?.viaggio;
    final c = v?.colonnine.where((x) => x.id == id).firstOrNull;
    if (v == null || c == null) return;
    final dove = c.dettaglio?.posizione ?? puntoLungo(Linea(v.percorso.punti), c.distanzaM);
    if (dove == null) return;
    _punto(PuntoToccato(tipo: 'colonnina', id: c.id, nome: c.nome, posizione: dove));
  }

  void _punto(PuntoToccato p) {
    final g = widget.guida;
    mostraPunto(
      context,
      p,
      vicini: widget.vicini,
      qui: g.avanzamento?.posizioneSulPercorso ?? widget.posizione.qui,
      carburante: g.auto.carburante,
      vai: (g.pronto?.termica ?? false) ? 'Passa di qui e prosegui' : 'Vai qui',
      onVai: _vaiDurante,
    );
  }

  /* La mappa sotto il cruscotto: col 3D aumentato (se il telefono lo regge)
   * la scena 3D della WebView; nelle altre viste, o se il 3D aumentato si
   * ferma, la mappa di sempre. Il cruscotto sopra è lo stesso. */
  Widget _mappa(BuildContext context, GestoreGuida g) {
    // La scelta si legge in un attimo: intanto il colore della mappa, non una
    // mappa che nasce e subito sparisce.
    if (!controllo.letta && widget.guida.archivio != null && mappa3dPossibile) {
      return ColoredBox(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1D2740) : const Color(0xFFE2EAF1),
      );
    }
    if (controllo.scenaAumentata) {
      return Mappa3d(
        key: const Key('mappa-3d'),
        gestore: g.viaggio,
        controllo: controllo,
        posizione: widget.posizione,
        guida: g,
        segnalazioni: widget.segnalazioni,
        vicini: widget.vicini,
        persone: widget.persone,
        onPunto: _punto,
        onNonVa: _nonVa3d,
      );
    }
    return MappaViaggio(
      gestore: g.viaggio,
      controllo: controllo,
      posizione: widget.posizione,
      guida: g,
      segnalazioni: widget.segnalazioni,
      onPuntoScelto: (_) {},
      onColonnina: _colonninaDelViaggio,
      vicini: widget.vicini,
      persone: widget.persone,
      ztl: widget.ztl,
      onPunto: _punto,
    );
  }

  /// Il 3D aumentato non va: si torna alla vista di prima, lo si dice una
  /// volta, e se il telefono non ce la fa lo si ricorda (la voce resta
  /// spenta, col perché e «Riprova»).
  void _nonVa3d(String motivo, {required bool ricorda}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) lasciaAumentataConAvviso(context, controllo, motivo, ricorda: ricorda);
    });
  }

  /// «Fine», come in Waze: si torna alla mappa senza viaggio.
  Future<void> _fine() async {
    widget.guida.chiudiRiepilogo();
    await widget.guida.ferma();
    widget.guida.viaggio.annulla();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guida;
    return PopScope(
      onPopInvokedWithResult: (fatto, _) {
        if (fatto && g.attiva) g.ferma();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: controllo,
                builder: (context, _) => widget.mappa?.call(context, controllo) ?? _mappa(context, g),
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([g, widget.posizione, controllo, ?_avvisi, ?_ztl, ?g.risparmio]),
              builder: (context, _) {
                _copri(context, g);
                final risparmio = g.risparmio;
                final strada = risparmio?.proposta;
                final traverso = _traverso(context);
                // In alto la manovra; avvicinandosi a un'uscita o a un
                // bivio, al suo posto il popup con lo svincolo in 3D.
                final alto = SafeArea(
                  bottom: false,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (figlio, animazione) => SizeTransition(
                      sizeFactor: animazione,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(opacity: animazione, child: figlio),
                    ),
                    child: switch ((_svincolo(g), g.pronto)) {
                      ((final m, final metri), final p?) => PopupSvincolo(
                        key: ValueKey(m.inizio),
                        viaggio: p.viaggio,
                        manovra: m,
                        metri: metri,
                        onChiudi: () => setState(() => _svincoliChiusi.add(m.inizio)),
                      ),
                      _ => _Banner(key: const ValueKey('banner'), guida: g),
                    },
                  ),
                );
                final avvisi = <Widget>[
                  if (widget.posizione.tace()) const _GpsAssente(),
                  if (_ztl?.avviso case final z?) _AvvisoZtl(avviso: z),
                  if (_avvisi?.davanti case (final s, final m)) AvvisoSegnalazione(segnalazione: s, metri: m),
                  if (_avvisi?.tutor case final t?) AvvisoTutor(stato: t),
                  if (_avvisi?.passata case final s?)
                    _Ancora(
                      segnalazione: s,
                      onSi: () => _avvisi!.rispondi(s, true),
                      onNo: () => _avvisi!.rispondi(s, false),
                    ),
                  if (g.proposta case final testo?) _Proposta(testo: testo, onSi: g.ricalcolaOra, onNo: g.lasciaCosi),
                  // Finita una ricarica per strada: quanto si è speso.
                  if (g.daChiedere case final i? when i < g.ricaricheInViaggio.length)
                    QuantoHaiSpeso(
                      ricarica: g.ricaricheInViaggio[i],
                      onSalva: (euro) => g.pagaRicarica(i, euro),
                      onDopo: g.nonOra,
                    ),
                ];
                // Di lato, la striscia del traffico, se davanti c'è qualche coda.
                final Widget striscia = switch (g.pronto?.viaggio.percorso) {
                  // Le etichette tornano col «+N min di traffico» in basso.
                  final p? => switch (strisciaTraffico(
                    p,
                    percorsiM: g.avanzamento?.percorsiM ?? 0,
                  )?.allineataA(g.minutiDiTraffico, g.ritardoDavanti)) {
                    final s? => Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                      child: StrisciaTrafficoLaterale(striscia: s),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                  _ => const SizedBox.shrink(),
                };
                final comandi = Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: ListenableBuilder(
                    listenable: controllo,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Mappa spostata o allontanata: si torna sull'auto.
                        // Sopra la riga: accanto al tachimetro grande non
                        // ci sta su un telefono stretto.
                        if (controllo.libera) ...[
                          FilledButton.icon(
                            key: const Key('riprendi'),
                            onPressed: controllo.segui,
                            icon: const Icon(Icons.navigation),
                            label: const Text('Riprendi'),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Quella di adesso: col GPS muto da qualche
                            // secondo è zero, non l'ultima letta.
                            Tachimetro(
                              velocitaKmh: widget.posizione.velocitaAdesso(),
                              limiteKmh: g.avanzamento?.limiteKmh,
                            ),
                            const Spacer(),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Vetro(
                                  raggio: 28,
                                  child: SceltaVista(key: const Key('2d-3d'), controllo: controllo),
                                ),
                                // Auto termica: un distributore per strada, e poi si prosegue.
                                if (g.pronto?.termica ?? false) ...[
                                  const SizedBox(height: 12),
                                  BottoneDistributori(
                                    onTap: () => mostraDistributori(
                                      context,
                                      qui: g.avanzamento?.posizioneSulPercorso ?? widget.posizione.qui,
                                      inGuida: true,
                                      carburante: g.auto.carburante,
                                      onScegli: g.passaDa,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                if (widget.segnalazioni case final seg?)
                                  BottoneSegnala(onTap: () => mostraSegnala(context, seg)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
                final Widget? proposta = risparmio != null && strada != null
                    ? PropostaRisparmio(
                        proposta: strada,
                        unita: risparmio.unita,
                        elettrica: g.auto.elettrica,
                        arrivo: g.batteriaArrivo,
                        arrivoCon: g.batteriaArrivoCon(strada),
                        arrivoAlle: g.arrivoAlle,
                        rimasto: switch (risparmio.propostaAlle) {
                          final alle? =>
                            1 -
                                DateTime.now().difference(alle).inMilliseconds /
                                    risparmio.durataProposta.inMilliseconds,
                          null => 1.0,
                        },
                        onPrendi: g.prendiStrada,
                        onResta: g.restaQui,
                      )
                    : null;
                if (traverso) {
                  return _DiTraverso(
                    larghezza: _larghezzaPannello(context),
                    alto: alto,
                    avvisi: [...avvisi, ?proposta],
                    striscia: striscia,
                    comandi: comandi,
                    // Basso (un telefono): la barra stretta, e col popup dello
                    // svincolo aperto solo arrivo, strada e tasti.
                    fondo: _Fondo(
                      meteo: widget.meteo,
                      guida: g,
                      onFine: _fine,
                      compatto: MediaQuery.sizeOf(context).height < 560,
                      ridotto: MediaQuery.sizeOf(context).height < 560 && _svincolo(g) != null,
                    ),
                  );
                }
                return Column(
                  children: [
                    alto,
                    ...avvisi,
                    // Lo spazio libero sopra il tachimetro: di lato la
                    // striscia del traffico. Il resto lascia passare i tocchi
                    // alla mappa.
                    Expanded(
                      child: Align(alignment: Alignment.centerRight, child: striscia),
                    ),
                    comandi,
                    // Una strada a risparmio (o più rapida): sopra la barra
                    // in basso, e la strada verde sulla mappa.
                    ?proposta,
                    _Fondo(guida: g, onFine: _fine, meteo: widget.meteo),
                  ],
                );
              },
            ),
            // All'arrivo la guida si ferma e resta questo: dove si è
            // arrivati, quanto ci si è messo, quanto si è consumato e speso.
            ListenableBuilder(
              listenable: g,
              builder: (context, _) => switch (g.riepilogo) {
                final r? when !g.attiva => RiepilogoArrivo(
                  riepilogo: r,
                  onFine: _fine,
                  onRicarica: (i) async {
                    final euro = await chiediLaSpesa(context, g.ricaricheInViaggio[i]);
                    if (euro != null) g.pagaRicarica(i, euro);
                  },
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Il cruscotto della guida di traverso: a sinistra, in un pannello largo
/// [larghezza], la manovra (o il popup dello svincolo) con le corsie, gli
/// avvisi e in fondo la barra dell'arrivo; a destra la mappa libera, con la
/// striscia del traffico e in basso tachimetro, vista e segnalazioni. Quello
/// che non ci sta in altezza nel pannello scorre, non esce dallo schermo.
class _DiTraverso extends StatelessWidget {
  const _DiTraverso({
    required this.larghezza,
    required this.alto,
    required this.avvisi,
    required this.striscia,
    required this.comandi,
    required this.fondo,
  });

  final double larghezza;
  final Widget alto;
  final List<Widget> avvisi;
  final Widget striscia;
  final Widget comandi;
  final Widget fondo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          key: const Key('pannello-traverso'),
          left: 0,
          top: 0,
          bottom: 0,
          width: larghezza,
          child: SafeArea(
            right: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [alto, ...avvisi]),
                  ),
                ),
                fondo,
              ],
            ),
          ),
        ),
        Positioned(
          left: larghezza,
          top: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: striscia),
                ),
                comandi,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Il riepilogo all'arrivo, sopra la mappa: «Sei arrivato», la meta, e
/// durata, distanza, consumo e costo del viaggio. «Fine» chiude la guida.
class RiepilogoArrivo extends StatelessWidget {
  const RiepilogoArrivo({super.key, required this.riepilogo, required this.onFine, this.onRicarica});

  final RiepilogoViaggio riepilogo;
  final VoidCallback onFine;

  /// Tocco su una ricarica per strada: per dire, o correggere, quanto si è
  /// pagato (l'indice in [RiepilogoViaggio.soste]).
  final ValueChanged<int>? onRicarica;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colori = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black38,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: DecoratedBox(
                key: const Key('riepilogo-arrivo'),
                decoration: BoxDecoration(
                  color: colori.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.sports_score, size: 32, color: Color(0xFF16A34A)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Sei arrivato', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  riepilogo.destinazione,
                                  style: t.titleMedium?.copyWith(color: colori.onSurfaceVariant),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...() {
                        // Le ricariche si toccano («quanto hai speso?»): la
                        // n-esima riga «Ricarica» è la n-esima sosta.
                        final righe = <Widget>[];
                        var sosta = 0;
                        for (final (nome, valore) in riepilogo.righe) {
                          final quale = nome == 'Ricarica' ? sosta++ : null;
                          final tocca = onRicarica;
                          righe.add(
                            _rigaDelRiepilogo(
                              context,
                              nome,
                              valore,
                              onTap: quale == null || tocca == null ? null : () => tocca(quale),
                            ),
                          );
                        }
                        return righe;
                      }(),
                      if (riepilogo.consumoStimato && riepilogo.consumoTesto != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Consumo stimato dal percorso; i prezzi si cambiano nelle opzioni del percorso.',
                            style: t.bodySmall?.copyWith(color: colori.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 14),
                      FilledButton(key: const Key('fine-arrivo'), onPressed: onFine, child: const Text('Fine')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _rigaDelRiepilogo(BuildContext context, String nome, String valore, {VoidCallback? onTap}) {
  final t = Theme.of(context).textTheme;
  final colori = Theme.of(context).colorScheme;
  final riga = Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(nome, style: t.bodyLarge?.copyWith(color: colori.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(valore, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (onTap != null) Icon(Icons.edit_outlined, size: 18, color: colori.primary),
      ],
    ),
  );
  return onTap == null ? riga : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: riga);
}

/// Finita una ricarica per strada: «Ricarica a Ionity Arezzo: 28,4 kWh.
/// Quanto hai speso?», con la stima della tariffa se c'è.
class QuantoHaiSpeso extends StatelessWidget {
  const QuantoHaiSpeso({super.key, required this.ricarica, required this.onSalva, required this.onDopo});

  final RicaricaInViaggio ricarica;
  final ValueChanged<double> onSalva;
  final VoidCallback onDopo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stima = ricarica.euroStimati;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Vetro(
        key: const Key('quanto-hai-speso'),
        raggio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.ev_station_rounded, color: Color(0xFF16A34A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${ricarica.dove}: ${ricarica.kwh.toStringAsFixed(1).replaceAll('.', ',')} kWh. '
                      'Quanto hai speso?',
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (stima != null)
                Padding(
                  padding: const EdgeInsets.only(left: 34, top: 2),
                  child: Text('Dalla tariffa della colonnina: ~${euroItaliani(stima)}', style: t.bodySmall),
                ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                children: [
                  TextButton(onPressed: onDopo, child: const Text('Dopo')),
                  if (stima != null) OutlinedButton(onPressed: () => onSalva(stima), child: const Text('Giusto così')),
                  FilledButton(
                    key: const Key('scrivi-la-spesa'),
                    onPressed: () async {
                      final euro = await chiediLaSpesa(context, ricarica);
                      if (euro != null) onSalva(euro);
                    },
                    child: const Text('Scrivi quanto'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quanto si è pagato una ricarica: un numero in euro, con la stima già
/// scritta. `null` se si annulla.
Future<double?> chiediLaSpesa(BuildContext context, RicaricaInViaggio r) {
  final campo = TextEditingController(
    text: switch (r.euro) {
      final e? => e.toStringAsFixed(2).replaceAll('.', ','),
      null => '',
    },
  );
  return showDialog<double>(
    context: context,
    builder: (contesto) {
      void salva() {
        final euro = double.tryParse(campo.text.trim().replaceAll('€', '').replaceAll(',', '.').trim());
        if (euro != null && euro >= 0) Navigator.of(contesto).pop(euro);
      }

      return AlertDialog(
        title: Text('Ricarica a ${r.dove}'),
        content: TextField(
          key: const Key('campo-spesa'),
          controller: campo,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quanto hai speso',
            suffixText: '€',
            helperText: '${r.kwh.toStringAsFixed(1).replaceAll('.', ',')} kWh',
          ),
          onSubmitted: (_) => salva(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(contesto).pop(), child: const Text('Annulla')),
          FilledButton(key: const Key('salva-la-spesa'), onPressed: salva, child: const Text('Salva')),
        ],
      );
    },
  );
}

/// «GPS assente», sotto la manovra, finché la posizione non torna.
///
/// La manovra, l'arrivo e la mappa restano quelli dell'ultima posizione:
/// senza questo sembrano veri. Piccolo, per non coprire la strada, ma col
/// colore degli avvisi: chi guida deve capire al primo sguardo che lo
/// schermo è fermo perché il telefono non sa dov'è.
class _GpsAssente extends StatelessWidget {
  const _GpsAssente();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rosso = ColoriGdanav.di(context).guasta;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Vetro(
          key: const Key('gps-assente'),
          raggio: 16,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gps_off, color: rosso, size: 20),
                const SizedBox(width: 8),
                Text(
                  'GPS assente',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: rosso),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «ZTL Centro storico, attiva · Il percorso la evita», sotto la manovra.
class _AvvisoZtl extends StatelessWidget {
  const _AvvisoZtl({required this.avviso});

  final AvvisoZtl avviso;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Vetro(
        key: const Key('avviso-ztl'),
        raggio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(
            children: [
              const CartelloZtl(lato: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(avviso.titolo, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(avviso.testo, style: t.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Polizia segnalata · tra 400 m», sotto la manovra.
/// Appena passati: «C'è ancora?» Sì / No, come in Waze.
class _Ancora extends StatelessWidget {
  const _Ancora({required this.segnalazione, required this.onSi, required this.onNo});

  final Segnalazione segnalazione;
  final VoidCallback onSi;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Vetro(
        raggio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              BollinoSegnalazione.di(segnalazione, lato: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${segnalazione.tipo.nome}: c\'è ancora?',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton(onPressed: onSi, child: const Text('Sì')),
              const SizedBox(width: 6),
              OutlinedButton(onPressed: onNo, child: const Text('No')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.guida});
  final GestoreGuida guida;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = guida.avanzamento;
    final m = a?.prossima ?? guida.pronto?.viaggio.percorso.manovre.firstOrNull;
    final alla = a?.allaProssimaM ?? m?.lunghezzaM ?? 0;
    // Il riquadro della manovra di Waze: scuro, freccia e distanza grandi.
    const blu = Color(0xFF2A3140);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: blu,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(color: const Color(0xFF3A4458), borderRadius: BorderRadius.circular(16)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        m == null
                            ? Icon(iconaManovra(8), color: Colors.white, size: 54)
                            : SimboloManovra.di(m, size: 54),
                        // Nelle rotonde, quale uscita.
                        if (m?.uscitaRotonda case final n?)
                          Positioned(
                            right: 4,
                            bottom: 2,
                            child: Text(
                              '$n',
                              style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guida.ricalcolando ? 'Ricalcolo…' : distanzaBreve(alla),
                          style: t.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          m == null ? '' : (m.strada.isNotEmpty ? m.strada : m.istruzione),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                        ),
                        if (m != null && (m.verso.isNotEmpty || m.uscita.isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: CartelloSvincolo(manovra: m),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Le corsie, avvicinandosi allo svincolo: quale prendere.
          if (m != null && m.corsieUtili && alla <= 2000)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CorsieSvincolo(corsie: m.corsie),
            ),
          if (a?.dopo case final dopo?)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(top: 6, left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF3A4252), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Poi ', style: t.labelLarge?.copyWith(color: Colors.white70)),
                    SimboloManovra.di(dopo, size: 20),
                    if (dopo.strada.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            dopo.strada,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelLarge?.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Fondo extends StatelessWidget {
  const _Fondo({required this.guida, required this.onFine, this.compatto = false, this.ridotto = false, this.meteo});
  final GestoreGuida guida;
  final GestoreMeteo? meteo;
  final VoidCallback onFine;

  /// Di traverso su un telefono: meno margini.
  final bool compatto;

  /// Solo la prima riga (arrivo, strada, tasti): di traverso col popup dello
  /// svincolo aperto non ci sta altro.
  final bool ridotto;

  /// I pezzi della riga del viaggio, con gli stessi dati che vanno all'auto
  /// (`PonteAuto._cruscotto`).
  List<PezzoViaggio> _pezzi(ViaggioPronto? p) {
    final elettrica = !(p?.soloPercorso ?? false);
    final ora = elettrica ? guida.batteriaOra : null;
    final m = meteo;
    final previsione = m?.delViaggio?.arrivo?.previsione ?? m?.qui;
    return pezziDelViaggio(
      batteria: ora?.valore,
      stimata: ora != null && !ora.misurata,
      // I km che resteranno all'arrivo; senza la batteria all'arrivo, quelli di adesso.
      autonomiaKm: elettrica ? guida.autonomiaArrivoKm ?? guida.autonomiaOra?.km : null,
      arrivo: elettrica ? guida.batteriaArrivo : null,
      meteoEmoji: previsione?.cielo.emoji,
      temperaturaC: previsione?.temperaturaC,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final a = guida.avanzamento;
    final p = guida.pronto;
    final restantiM = a?.restantiM ?? p?.viaggio.percorso.lunghezzaM ?? 0;
    final restante = a?.restante ?? p?.viaggio.percorso.durata ?? Duration.zero;
    final arrivo = guida.arrivoAlle;
    final sosta = guida.prossimaSosta;
    // Il pedaggio che resta da pagare: solo se c'è.
    final pedaggio = guida.pedaggioDavanti;
    final ambra = BadgePedaggio.colori(context, paga: true).$2;
    // Quanto dell'arrivo è traffico: già dentro l'ora e il tempo, qui detto.
    final traffico = guida.minutiDiTraffico;
    final coloreTraffico = gravitaRitardo(traffico) >= 2
        ? ColoriGdanav.di(context).guasta
        : ColoriGdanav.di(context).piena;
    final divisore = compatto ? 12.0 : 20.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(compatto ? 8 : 12),
        child: Vetro(
          raggio: 24,
          child: Padding(
            padding: compatto ? const EdgeInsets.fromLTRB(16, 9, 10, 9) : const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                arrivo == null ? '' : orario(arrivo),
                                style: t.headlineSmall?.copyWith(
                                  color: traffico >= 1 ? coloreTraffico : ColoriGdanav.di(context).libera,
                                ),
                              ),
                              if (traffico >= 1)
                                Row(
                                  key: const Key('traffico-restante'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.traffic_rounded, size: 17, color: coloreTraffico),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        testoRitardoTraffico(traffico),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.titleSmall?.copyWith(
                                          color: coloreTraffico,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          // Il pedaggio che resta, accanto ai km che restano; se
                          // non ci sta (i tasti a destra), subito sotto.
                          Wrap(
                            key: const Key('restanti'),
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${durata(restante)} · ${distanzaBreve(restantiM)}',
                                style: t.titleSmall?.copyWith(color: muto),
                              ),
                              if (pedaggio != null && !pedaggio.senzaPedaggi)
                                Row(
                                  key: const Key('pedaggio-restante'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.toll_rounded, size: 17, color: ambra),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        pedaggio.breve,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.titleSmall?.copyWith(color: ambra, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('ricalcola'),
                      tooltip: 'Ricalcola il viaggio',
                      onPressed: guida.ricalcolando ? null : guida.ricalcolaOra,
                      icon: guida.ricalcolando
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 4),
                    TastoAudio(audio: guida.audio, onPressed: guida.alternaVoce),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ColoriGdanav.di(context).guasta,
                        minimumSize: const Size(72, 48),
                      ),
                      onPressed: onFine,
                      child: const Text('Fine'),
                    ),
                  ],
                ),
                // Con l'auto termica niente batteria: solo arrivo e strada.
                // La batteria, i km, l'arrivo e il meteo come nella scheda
                // dell'arrivo di Android Auto (con l'auto termica solo il meteo).
                if (!ridotto && _pezzi(p).isNotEmpty) ...[
                  Divider(height: divisore),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RigaDelViaggio(
                      pezzi: _pezzi(p),
                      stile: t.titleMedium?.copyWith(color: muto),
                    ),
                  ),
                ],
                if (sosta != null && !ridotto) ...[
                  Divider(height: divisore),
                  Row(
                    children: [
                      Icon(Icons.ev_station, color: ColoriGdanav.di(context).libera),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sosta: ${sosta.$1.colonnina.nome} tra ${distanzaBreve(sosta.$2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Con il ricalcolo automatico spento: la domanda, e la risposta.
class _Proposta extends StatelessWidget {
  const _Proposta({required this.testo, required this.onSi, required this.onNo});

  final String testo;
  final VoidCallback onSi;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Vetro(
        raggio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              const Icon(Icons.battery_alert_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(testo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              FilledButton(onPressed: onSi, child: const Text('Ricalcola')),
              const SizedBox(width: 6),
              OutlinedButton(onPressed: onNo, child: const Text('No')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il tasto dell'audio in guida: Tutto → Solo avvisi → Silenzio. Un'icona
/// e sotto una parola, perché tre stati con la sola icona non si
/// distinguono di sfuggita: l'altoparlante barrato vuol dire «niente voce»
/// o «niente di niente»?
class TastoAudio extends StatelessWidget {
  const TastoAudio({super.key = const Key('audio'), required this.audio, required this.onPressed});

  final ModoAudio audio;
  final VoidCallback onPressed;

  static String suggerimento(ModoAudio a) => switch (a) {
    ModoAudio.tutto => 'Audio: indicazioni e avvisi. Tocca per i soli avvisi',
    ModoAudio.soloAvvisi => 'Audio: solo avvisi (autovelox, segnalazioni, ZTL, limite). Tocca per il silenzio',
    ModoAudio.silenzio => 'Audio: silenzio. Tocca per riattivare tutto',
  };

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (icona, fondo, colore) = switch (audio) {
      ModoAudio.tutto => (Icons.volume_up_rounded, s.secondaryContainer, s.onSecondaryContainer),
      // Gli avvisi: il megafono, arancio come gli avvisi sulla mappa.
      ModoAudio.soloAvvisi => (Icons.campaign_rounded, const Color(0xFFFFE0B2), const Color(0xFF8A4B00)),
      ModoAudio.silenzio => (Icons.volume_off_rounded, s.surfaceContainerHighest, s.onSurfaceVariant),
    };
    return Tooltip(
      message: suggerimento(audio),
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(
            width: 58,
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icona, size: 22, color: colore),
                Text(
                  audio.etichetta,
                  style: TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w700, color: colore),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
