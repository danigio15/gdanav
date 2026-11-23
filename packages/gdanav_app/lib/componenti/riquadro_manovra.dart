import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'icona_manovra.dart';

/// Quanto è grande il riquadro della manovra in guida, sul telefono.
///
/// «Il riquadro con la freccia occupa troppo schermo e copre la mappa»: a due
/// chilometri dalla svolta non serve una freccia da 54 punti col cartello e
/// il «Poi» sotto. Con [automatica] lontano diventa una riga sola, e torna
/// grande quando la svolta si avvicina; con [normale] resta sempre grande,
/// com'era.
enum DimensioneIndicazioni {
  automatica('Automatica', 'Una riga sola lontano dalla svolta, grande quando si avvicina'),
  normale('Normale', 'Sempre grande, con la freccia, il cartello e il «Poi»');

  const DimensioneIndicazioni(this.nome, this.spiegazione);

  final String nome;
  final String spiegazione;
}

/// La dimensione scelta («Dimensione indicazioni» nel menu). La carica l'app
/// all'avvio, come la voce di guida.
final dimensioneIndicazioni = ValueNotifier(DimensioneIndicazioni.automatica);

/// Oltre questi metri dalla manovra il riquadro si fa piccolo...
const compattoSopraM = 500.0;

/// ...e sotto questi torna grande. In mezzo resta com'era: avvicinandosi a
/// 480 m e poi (il GPS che balla, una curva) a 510, non deve sfarfallare.
const grandeSottoM = 300.0;

/// Se il riquadro della manovra va piccolo, a [metri] dalla manovra, se
/// [prima] lo era.
///
/// Con due manovre ravvicinate ([poiVicino], la seconda entro
/// [poiEntroM] dalla prima, come la scheda dell'auto) resta grande: il «Poi»
/// sotto è proprio quello che serve sapere, e nella riga sola non ci sta.
bool riquadroCompatto({
  required double metri,
  required bool prima,
  bool poiVicino = false,
  DimensioneIndicazioni dimensione = DimensioneIndicazioni.automatica,
}) {
  if (dimensione == DimensioneIndicazioni.normale || poiVicino) return false;
  if (metri > compattoSopraM) return true;
  if (metri < grandeSottoM) return false;
  return prima;
}

/// Il riquadro della manovra in guida: freccia, distanza e via, su un vetro
/// scuro che lascia intravedere la mappa sotto.
///
/// Lontano dalla manovra è una riga sola (freccia piccola, distanza, via);
/// vicino è quello grande di sempre, col cartello dello svincolo e sotto il
/// «Poi». Il passaggio fra i due è morbido, e immediato con «riduci
/// animazioni». Le corsie, quando servono, restano sotto in tutti e due.
class RiquadroManovra extends StatefulWidget {
  const RiquadroManovra({
    super.key,
    required this.manovra,
    required this.metri,
    this.dopo,
    this.ricalcolando = false,
    this.dimensione = DimensioneIndicazioni.automatica,
  });

  /// La prossima manovra; `null` prima di sapere il percorso.
  final Manovra? manovra;

  /// Quanto manca a [manovra].
  final double metri;

  /// La manovra dopo, per il «Poi».
  final Manovra? dopo;

  /// Si ricalcola: al posto della distanza «Ricalcolo…», e la misura resta
  /// quella che era (i metri sono quelli del percorso di prima).
  final bool ricalcolando;
  final DimensioneIndicazioni dimensione;

  /// Il fondo del vetro: il blu-grigio scuro del riquadro di sempre, un po'
  /// trasparente. Scuro anche col tema chiaro: la freccia e la distanza
  /// bianche si leggono su qualsiasi mappa.
  static const fondo = Color(0xFF2A3140);

  /// Col tema scuro (e di notte) più cupo: la mappa scura ha lo stesso
  /// blu-grigio, e il riquadro ci si perdeva dentro.
  static const fondoScuro = Color(0xFF141925);

  @override
  State<RiquadroManovra> createState() => _RiquadroManovraState();
}

class _RiquadroManovraState extends State<RiquadroManovra> {
  late bool _compatto = _misura(prima: false);

  bool _misura({required bool prima}) {
    final m = widget.manovra;
    return riquadroCompatto(
      metri: widget.metri,
      prima: prima,
      poiVicino: m != null && poiVicino(m, widget.dopo),
      dimensione: widget.dimensione,
    );
  }

  @override
  void didUpdateWidget(RiquadroManovra vecchio) {
    super.didUpdateWidget(vecchio);
    if (!widget.ricalcolando || widget.dimensione != vecchio.dimensione) _compatto = _misura(prima: _compatto);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manovra;
    final compatto = _compatto;
    final durata = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 280);
    final scuro = Theme.of(context).brightness == Brightness.dark;
    // Lo stesso raggio grande e piccolo: cambiarlo a metà passaggio fa uno scatto.
    final raggio = BorderRadius.circular(20);
    final dopo = widget.dopo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          // Un fondo semitrasparente, senza sfocatura. «La freccia non è
          // allineata in tempo reale, è peggiorata»: una sfocatura sopra la
          // mappa (MapLibre e la scena 3D sono viste della piattaforma) su
          // Android obbliga a ricomporre la mappa a ogni fotogramma per
          // sfocarla, e i fotogrammi persi sono la freccia che resta indietro.
          // La mappa si vede lo stesso attraverso il fondo.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: raggio,
              boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 16, offset: Offset(0, 5))],
            ),
            child: ClipRRect(
              borderRadius: raggio,
              child: DecoratedBox(
                key: const Key('riquadro-manovra'),
                decoration: BoxDecoration(
                  color: scuro
                      ? RiquadroManovra.fondoScuro.withValues(alpha: 0.90)
                      : RiquadroManovra.fondo.withValues(alpha: 0.86),
                  borderRadius: raggio,
                  border: Border.all(color: Colors.white.withValues(alpha: scuro ? 0.12 : 0.18)),
                ),
                child: AnimatedSize(
                  duration: durata,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: durata,
                    // La misura è quella del riquadro nuovo: quello che se ne
                    // va sfuma sopra, senza tenere il posto.
                    layoutBuilder: (adesso, prima) => Stack(
                      alignment: Alignment.topLeft,
                      children: [
                        for (final p in prima) Positioned(left: 0, top: 0, right: 0, child: p),
                        ?adesso,
                      ],
                    ),
                    child: compatto
                        ? _Riga(key: const Key('riquadro-compatto'), manovra: m, distanza: _distanza())
                        : _Grande(key: const Key('riquadro-grande'), manovra: m, distanza: _distanza()),
                  ),
                ),
              ),
            ),
          ),
          // Le corsie, avvicinandosi allo svincolo: quale prendere.
          if (m != null && m.corsieUtili && widget.metri <= 2000)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CorsieSvincolo(corsie: m.corsie),
            ),
          AnimatedSwitcher(
            duration: durata,
            transitionBuilder: (figlio, animazione) => SizeTransition(
              sizeFactor: animazione,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animazione, child: figlio),
            ),
            child: switch (dopo) {
              final d? when !compatto => _Poi(key: const Key('poi'), dopo: d),
              _ => const SizedBox.shrink(key: Key('senza-poi')),
            },
          ),
        ],
      ),
    );
  }

  String _distanza() => widget.ricalcolando ? 'Ricalcolo…' : distanzaBreve(widget.metri);
}

/// Il bianco sul vetro, con un filo d'ombra: sopra una mappa chiara che
/// traspare resta netto.
const _ombra = [Shadow(color: Color(0x73000000), blurRadius: 3, offset: Offset(0, 1))];

/// La via, o l'istruzione se la via non ha nome.
String _via(Manovra? m) => m == null ? '' : (m.strada.isNotEmpty ? m.strada : m.istruzione);

/// La freccia nel suo quadretto, con l'uscita della rotonda in basso a
/// destra.
class _Freccia extends StatelessWidget {
  const _Freccia({required this.manovra, required this.lato, required this.icona, required this.numero});

  final Manovra? manovra;
  final double lato;
  final double icona;
  final TextStyle? numero;

  @override
  Widget build(BuildContext context) {
    final m = manovra;
    return Container(
      width: lato,
      height: lato,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(lato * 0.24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          m == null ? Icon(iconaManovra(8), color: Colors.white, size: icona) : SimboloManovra.di(m, size: icona),
          // Nelle rotonde, quale uscita.
          if (m?.uscitaRotonda case final n?)
            Positioned(
              right: lato * 0.06,
              bottom: 0,
              child: Text(
                '$n',
                style: numero?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lontano dalla manovra: una riga sola, freccia piccola, distanza e via.
class _Riga extends StatelessWidget {
  const _Riga({super.key, required this.manovra, required this.distanza});

  final Manovra? manovra;
  final String distanza;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          _Freccia(manovra: manovra, lato: 40, icona: 30, numero: t.labelSmall),
          const SizedBox(width: 12),
          Text(
            distanza,
            maxLines: 1,
            style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, shadows: _ombra),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _via(manovra),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.94), shadows: _ombra),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vicino alla manovra: la freccia grande, la distanza, la via su due righe
/// e il cartello dello svincolo.
class _Grande extends StatelessWidget {
  const _Grande({super.key, required this.manovra, required this.distanza});

  final Manovra? manovra;
  final String distanza;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = manovra;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 18, 16),
      child: Row(
        children: [
          _Freccia(manovra: m, lato: 68, icona: 54, numero: t.titleSmall),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distanza,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, shadows: _ombra),
                ),
                Text(
                  _via(m),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.94), shadows: _ombra),
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
    );
  }
}

/// «Poi ↰ Via …», piccolo sotto il riquadro grande.
class _Poi extends StatelessWidget {
  const _Poi({super.key, required this.dopo});

  final Manovra dopo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Align(
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
              Flexible(
                child: ConstrainedBox(
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
              ),
          ],
        ),
      ),
    );
  }
}
