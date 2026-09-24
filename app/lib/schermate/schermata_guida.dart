import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/icona_manovra.dart';
import '../componenti/icone_segnalazioni.dart';
import '../componenti/tachimetro.dart';
import '../componenti/vetro.dart';
import '../mappa/controllo_mappa.dart';
import '../mappa/mappa_viaggio.dart';
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

  /// Le segnalazioni lungo la strada: quella che si avvicina, e quella
  /// appena passata a cui chiedere «c'è ancora?».
  Linea? _linea;
  List<Punto>? _puntiLinea;
  (Segnalazione, double)? _davanti;
  Segnalazione? _passata;
  final _annunciate = <String>{};
  final _chieste = <String>{};

  static const _avvisoM = 800.0;

  @override
  void initState() {
    super.initState();
    widget.guida.avvia();
    widget.guida.addListener(_lungoLaStrada);
  }

  @override
  void dispose() {
    widget.guida.removeListener(_lungoLaStrada);
    controllo.dispose();
    super.dispose();
  }

  void _lungoLaStrada() {
    final g = widget.guida, a = g.avanzamento, punti = g.pronto?.viaggio.percorso.punti;
    final tutte = widget.segnalazioni?.vicine ?? const <Segnalazione>[];
    if (a == null || punti == null || tutte.isEmpty) return;
    if (!identical(punti, _puntiLinea)) {
      _puntiLinea = punti;
      _linea = Linea(punti);
    }
    (Segnalazione, double)? davanti;
    Segnalazione? passata;
    for (final s in tutte) {
      final p = _linea!.proietta(s.punto);
      if (p.lontanoM > 40) continue;
      final avanti = p.lungoM - a.percorsiM;
      if (avanti > 0 && avanti <= _avvisoM && (davanti == null || avanti < davanti.$2)) davanti = (s, avanti);
      if (avanti <= 0 && avanti > -250 && !_chieste.contains(s.id)) passata = s;
    }
    if (davanti case (final s, final m) when _annunciate.add(s.id)) {
      g.annuncia('${s.tipo.avviso} tra ${distanzaParlata(m)}.');
    }
    if (davanti?.$1.id != _davanti?.$1.id || davanti?.$2 != _davanti?.$2 || passata?.id != _passata?.id) {
      setState(() {
        _davanti = davanti;
        _passata = passata;
      });
    }
  }

  void _rispondi(Segnalazione s, bool ancora) {
    _chieste.add(s.id);
    widget.segnalazioni?.vota(s, ancora: ancora);
    setState(() => _passata = null);
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
              listenable: Listenable.merge([g, widget.posizione]),
              builder: (context, _) => Column(
                children: [
                  SafeArea(bottom: false, child: _Banner(guida: g)),
                  if (_davanti case (final s, final m)) _AvvisoSegnalazione(segnalazione: s, metri: m),
                  if (_passata case final s?)
                    _Ancora(segnalazione: s, onSi: () => _rispondi(s, true), onNo: () => _rispondi(s, false)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Tachimetro(velocitaKmh: widget.posizione.velocitaKmh, limiteKmh: g.avanzamento?.limiteKmh),
                        const Spacer(),
                        if (widget.segnalazioni case final seg?)
                          BottoneSegnala(onTap: () => mostraSegnala(context, seg)),
                      ],
                    ),
                  ),
                  _Fondo(guida: g, onFine: _fine),
                ],
              ),
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
                    Text(segnalazione.tipo.avviso, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      'tra ${distanzaBreve(metri)}'
                      '${segnalazione.conferme > 0 ? ' · confermata da ${segnalazione.conferme}' : ''}',
                      style: t.bodyMedium,
                    ),
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
  const _Banner({required this.guida});
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
                  Icon(iconaManovra(m?.tipo ?? 8), color: Colors.white, size: 52),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
