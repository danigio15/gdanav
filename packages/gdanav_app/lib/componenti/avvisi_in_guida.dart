import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'icone_segnalazioni.dart';
import 'tachimetro.dart';
import 'vetro.dart';

/// La segnalazione che si avvicina: in guida, e sulla mappa senza percorso.
class AvvisoSegnalazione extends StatelessWidget {
  const AvvisoSegnalazione({super.key, required this.segnalazione, required this.metri});

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
              BollinoSegnalazione.di(segnalazione, lato: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controlloDi(segnalazione)?.nome ?? segnalazione.tipo.avviso,
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

/// Il Tutor: quando arriva, e dentro la media fin qui, rossa se è sopra il
/// limite.
class AvvisoTutor extends StatelessWidget {
  const AvvisoTutor({super.key, required this.stato});

  final StatoTutor stato;

  /// Il colore del Tutor, uguale nella pagina degli avvisi.
  static const colore = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context), t = tema.textTheme;
    final limite = stato.tratto.limiteKmh;
    final (titolo, sotto, sopra) = switch (stato) {
      TutorDavanti(:final metri) => ('Tutor', 'tra ${distanzaBreve(metri)}', false),
      final DentroTutor d => (
        d.mediaKmh == null ? 'Tutor · media…' : 'Tutor · media ${d.mediaKmh!.round()} km/h',
        'mancano ${distanzaBreve(d.restantiM)}',
        d.sopra(),
      ),
      FineTutor() => ('Fine Tutor', '', false),
    };
    return Padding(
      key: const Key('avviso-tutor'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Vetro(
        raggio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: colore, shape: BoxShape.circle),
                child: const Icon(Icons.av_timer_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titolo,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: sopra ? const Color(0xFFDC2626) : null,
                      ),
                    ),
                    Text(sopra ? '$sotto · rallenta' : sotto, style: t.bodyMedium),
                  ],
                ),
              ),
              if (limite != null) CartelloLimite(limiteKmh: limite, lato: 44),
            ],
          ),
        ),
      ),
    );
  }
}
