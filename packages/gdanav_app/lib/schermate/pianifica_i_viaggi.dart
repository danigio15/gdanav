import 'package:flutter/material.dart';

import '../componenti/vetro.dart';
import '../stato/viaggi_pianificati.dart';
import '../tema.dart';

/* ─── «Pianifica i viaggi», sulla mappa ─────────────────────────────────
 *
 * Il pianificatore stava solo nel menu, sotto «Viaggio»: dentro gdahome
 * nessuno lo trovava. Adesso c'è una scheda sulla mappa, sotto il menu: col
 * prossimo viaggio («Casa – Lavoro» / «Domani · parti alle 7:59 · arrivo
 * entro le 8:30») quando ce n'è uno, e più piccola, con la promessa, quando
 * non ce n'è. Toccata apre il pianificatore (o Premium, se è chiuso).
 *
 * La mette la schermata principale solo a mappa libera: non in guida, non
 * con un viaggio aperto, non sopra un avviso. */

/// I viaggi che devono ancora venire, dal più vicino: col prossimo
/// arrivo che la casa ha calcolato o, se manca, quello di adesso.
List<(ViaggioPianificato, ProssimaVolta)> viaggiInArrivo(List<ViaggioPianificato> viaggi, DateTime adesso) {
  final fila = [
    for (final v in viaggi)
      if (v.prossima ?? prossimaVolta(v, adesso) case final p? when p.arrivo.isAfter(adesso)) (v, p),
  ]..sort((a, b) => a.$2.partenza.compareTo(b.$2.partenza));
  return fila;
}

/// La riga sotto il nome: «Domani · parti alle 7:59 · arrivo entro le 8:30».
/// Senza una stima della strada si dice quello che si è scritto.
String quandoParti(ViaggioPianificato v, ProssimaVolta p, DateTime adesso) {
  if (!p.stimata) return quandoDetto(v, adesso);
  final giorno = giornoParlato(p.partenza, adesso);
  final parti = 'parti alle ${oraDetta(p.partenza)}';
  if (v.dicePartenza) return '$giorno · $parti';
  return '$giorno · $parti · arrivo entro le ${oraDetta(p.arrivo)}';
}

class SchedaPianificaIViaggi extends StatelessWidget {
  const SchedaPianificaIViaggi({super.key, required this.gestore, required this.onTap, this.sbloccato = true});

  final GestoreViaggiPianificati gestore;
  final VoidCallback onTap;

  /// Senza Premium la scheda resta, col bollino: toccata apre Premium.
  final bool sbloccato;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = ColoriGdanav.di(context);
    final adesso = gestore.adesso;
    final aperto = sbloccato && gestore.sbloccato;
    final fila = aperto ? viaggiInArrivo(gestore.viaggi, adesso) : const <(ViaggioPianificato, ProssimaVolta)>[];
    final prossimo = fila.firstOrNull;
    final piccola = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: t.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      button: true,
      label: 'Pianifica i viaggi',
      child: Vetro(
        key: const Key('scheda-pianifica'),
        raggio: 20,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, prossimo == null ? 10 : 12, 10, prossimo == null ? 10 : 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.percorso.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(Icons.event_rounded, color: c.percorso, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (prossimo case (final v, final p)) ...[
                      Text('PIANIFICA I VIAGGI · ${fila.length}', style: piccola),
                      const SizedBox(height: 2),
                      Text(
                        v.titolo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        quandoParti(v, p, adesso),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ] else ...[
                      // Senza Premium, il bollino dove l'altra dice quanti
                      // viaggi: il titolo resta intero anche sui telefoni stretti.
                      if (!aperto) ...[
                        Container(
                          key: const Key('scheda-pianifica-premium'),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'PREMIUM',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: t.brightness == Brightness.dark
                                  ? const Color(0xFFFCD34D)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                      ],
                      const Text(
                        'Pianifica i viaggi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Ti dico io quando partire, col traffico',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
