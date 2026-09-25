import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/icona_manovra.dart';
import '../componenti/indicatore_batteria.dart' show eta;
import '../componenti/icone_segnalazioni.dart';
import '../componenti/tachimetro.dart';
import '../componenti/vista_svincolo.dart';
import '../componenti/vetro.dart';
import '../mappa/controllo_mappa.dart';
import '../mappa/mappa_viaggio.dart';
import '../stato/avvisi_strada.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_segnalazioni.dart';
import '../tema.dart';
import 'scheda_viaggio.dart' show durata, orario;
import 'schermata_principale.dart' show CostruisciMappa;
import 'segnala.dart';

/// La guida: la mappa ti segue inclinata, in alto la prossima manovra, in
/// basso arrivo, chilometri e la prossima sosta.
class SchermataGuida extends StatefulWidget {
  const SchermataGuida({super.key, required this.guida, required this.posizione, this.segnalazioni, this.mappa});

  final GestoreGuida guida;
  final GestorePosizione posizione;
  final GestoreSegnalazioni? segnalazioni;
  final CostruisciMappa? mappa;

  @override
  State<SchermataGuida> createState() => _SchermataGuidaState();
}

class _SchermataGuidaState extends State<SchermataGuida> {
  final controllo = ControlloMappa()..inclinata = true;

  /// Le segnalazioni lungo la strada, condivise con lo schermo dell'auto.
  AvvisiStrada? _avvisi;

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
  void _copri(BuildContext context, GestoreGuida g) {
    final alto = _svincolo(g) == null
        ? 0.0
        : MediaQuery.paddingOf(context).top + 8 + 72 + (MediaQuery.sizeOf(context).width - 24) * 9 / 16;
    if ((alto - controllo.coperto).abs() < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controllo.copriAlto(alto);
    });
  }

  /// Ridisegna il tachimetro ogni secondo: da fermi il GPS può tacere.
  Timer? _battito;

  @override
  void initState() {
    super.initState();
    _battito = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.guida.avvia();
    if (widget.segnalazioni case final seg?) _avvisi = AvvisiStrada.di(widget.guida, seg);
  }

  @override
  void dispose() {
    _battito?.cancel();
    controllo.dispose();
    super.dispose();
  }

  /// «Fine», come in Waze: si torna alla mappa senza viaggio.
  Future<void> _fine() async {
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
              child:
                  widget.mappa?.call(context, controllo) ??
                  MappaViaggio(
                    gestore: g.viaggio,
                    controllo: controllo,
                    posizione: widget.posizione,
                    guida: g,
                    segnalazioni: widget.segnalazioni,
                    onPuntoScelto: (_) {},
                    onColonnina: (_) {},
                  ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([g, widget.posizione, ?_avvisi]),
              builder: (context, _) {
                _copri(context, g);
                return Column(
                  children: [
                    // In alto la manovra; avvicinandosi a un'uscita o a un
                    // bivio, al suo posto il popup con lo svincolo in 3D.
                    SafeArea(
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
                            // Nelle prove niente scena vera.
                            mappa: widget.mappa == null ? null : (_, _) => const ColoredBox(color: Color(0xFF9DB7A0)),
                            onChiudi: () => setState(() => _svincoliChiusi.add(m.inizio)),
                          ),
                          _ => _Banner(key: const ValueKey('banner'), guida: g),
                        },
                      ),
                    ),
                    if (_avvisi?.davanti case (final s, final m)) _AvvisoSegnalazione(segnalazione: s, metri: m),
                    if (_avvisi?.passata case final s?)
                      _Ancora(
                        segnalazione: s,
                        onSi: () => _avvisi!.rispondi(s, true),
                        onNo: () => _avvisi!.rispondi(s, false),
                      ),
                    if (g.proposta case final testo?) _Proposta(testo: testo, onSi: g.ricalcolaOra, onNo: g.lasciaCosi),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: ListenableBuilder(
                        listenable: controllo,
                        builder: (context, _) => Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Tachimetro(velocitaKmh: widget.posizione.velocitaKmh, limiteKmh: g.avanzamento?.limiteKmh),
                            const Spacer(),
                            // Mappa spostata o allontanata: si torna sull'auto.
                            if (controllo.libera)
                              FilledButton.icon(
                                key: const Key('riprendi'),
                                onPressed: controllo.segui,
                                icon: const Icon(Icons.navigation),
                                label: const Text('Riprendi'),
                              ),
                            const Spacer(),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Vetro(
                                  raggio: 28,
                                  child: SizedBox.square(
                                    dimension: 56,
                                    child: TextButton(
                                      key: const Key('2d-3d'),
                                      onPressed: controllo.alternaInclinazione,
                                      style: TextButton.styleFrom(shape: const CircleBorder()),
                                      child: Text(
                                        controllo.inclinata ? '2D' : '3D',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (widget.segnalazioni case final seg?)
                                  BottoneSegnala(onTap: () => mostraSegnala(context, seg)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    _Fondo(guida: g, onFine: _fine),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// «Polizia segnalata · tra 400 m», sotto la manovra.
class _AvvisoSegnalazione extends StatelessWidget {
  const _AvvisoSegnalazione({required this.segnalazione, required this.metri});

  final Segnalazione segnalazione;
  final double metri;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Vetro(
        raggio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(
            children: [
              BollinoSegnalazione(segnalazione.tipo, lato: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      segnalazione.fissa ? 'Autovelox fisso' : segnalazione.tipo.avviso,
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'tra ${distanzaBreve(metri)}'
                      '${segnalazione.conferme > 0 ? ' · confermata da ${segnalazione.conferme}' : ''}',
                      style: t.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (segnalazione.limiteKmh case final l?) CartelloLimite(limiteKmh: l, lato: 44),
            ],
          ),
        ),
      ),
    );
  }
}

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
              BollinoSegnalazione(segnalazione.tipo, lato: 40),
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
                        Icon(iconaManovra(m?.tipo ?? 8), color: Colors.white, size: 54),
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
                    Icon(iconaManovra(dopo.tipo), color: Colors.white, size: 20),
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
  const _Fondo({required this.guida, required this.onFine});
  final GestoreGuida guida;
  final VoidCallback onFine;

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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Vetro(
          raggio: 24,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            arrivo == null ? '' : orario(arrivo),
                            style: t.headlineSmall?.copyWith(color: ColoriGdanav.di(context).libera),
                          ),
                          Text(
                            '${durata(restante)} · ${distanzaBreve(restantiM)}',
                            style: t.titleSmall?.copyWith(color: muto),
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
                    IconButton.filledTonal(
                      tooltip: guida.muto ? 'Riattiva la voce' : 'Silenzia la voce',
                      onPressed: guida.alternaVoce,
                      icon: Icon(guida.muto ? Icons.volume_off : Icons.volume_up),
                    ),
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
                const Divider(height: 20),
                _Batteria(guida: guida),
                if (sosta != null) ...[
                  const Divider(height: 20),
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

/// Sempre in vista: batteria alla partenza, adesso, all'arrivo, e consumo.
class _Batteria extends StatelessWidget {
  const _Batteria({required this.guida});
  final GestoreGuida guida;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final ora = guida.batteriaOra;
    final consumo = guida.consumoKwh100;
    final autonomia = guida.autonomiaOra;
    String pc(double? v) => v == null ? '–' : '${v.round()}%';
    Color colore(double? v) => switch (v) {
      null => muto,
      < 15 => ColoriGdanav.di(context).guasta,
      < 30 => ColoriGdanav.di(context).piena,
      _ => ColoriGdanav.di(context).libera,
    };
    Widget voce(String etichetta, double? v, {Key? chiave}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pc(v),
            key: chiave,
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: colore(v)),
          ),
          Text(
            etichetta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.labelMedium?.copyWith(color: muto),
          ),
        ],
      ),
    );
    return Row(
      children: [
        voce('partenza', guida.batteriaPartenza, chiave: const Key('batteria-partenza')),
        voce(
          switch ((ora?.misurata, guida.auto.stato)) {
            // Quanto è fresco il dato dell'auto, sotto: «auto» e «adesso» o «4 min fa».
            (true, final s?) => 'auto\n${eta(DateTime.now().difference(s.letto))}',
            _ => 'ora (stima)',
          },
          ora?.valore,
          chiave: const Key('batteria-ora'),
        ),
        voce('all\'arrivo', guida.batteriaArrivo, chiave: const Key('batteria-arrivo')),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // L'autonomia adesso: dall'auto, o stimata sul consumo vero.
              Text(
                autonomia == null ? '– km' : '${autonomia.km.round()} km',
                key: const Key('autonomia'),
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                autonomia?.dallAuto == true ? 'autonomia (auto)' : 'autonomia',
                maxLines: 1,
                style: t.labelMedium?.copyWith(color: muto),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: consumo == null ? '–' : consumo.toStringAsFixed(1).replaceAll('.', ','),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' kWh/100 km'),
                  ],
                ),
                key: const Key('consumo'),
                maxLines: 1,
                style: t.labelMedium?.copyWith(color: muto),
              ),
            ],
          ),
        ),
      ],
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
