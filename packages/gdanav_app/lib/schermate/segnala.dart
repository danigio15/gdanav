import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/icone_segnalazioni.dart';
import '../stato/gestore_segnalazioni.dart';

/// Il bottone giallo di Waze: triangolo col più.
class BottoneSegnala extends StatelessWidget {
  const BottoneSegnala({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Segnala',
    child: Material(
      color: const Color(0xFFFFD84A),
      elevation: 6,
      shadowColor: const Color(0x55000000),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: const SizedBox.square(
          dimension: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 50, color: Color(0xFF1F2328)),
              Padding(
                padding: EdgeInsets.only(top: 9),
                child: Icon(Icons.add, size: 18, color: Color(0xFF1F2328), weight: 900),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// «Cosa vedi?»: si tocca il tipo e la segnalazione parte da dove sei.
Future<void> mostraSegnala(BuildContext context, GestoreSegnalazioni segnalazioni) async {
  final tipo = await showModalBottomSheet<TipoSegnalazione>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (contesto) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cosa vedi?', style: Theme.of(contesto).textTheme.titleLarge),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              childAspectRatio: 0.66,
              children: [
                for (final t in TipoSegnalazione.values)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(contesto).pop(t),
                    child: Column(
                      children: [
                        BollinoSegnalazione(t, lato: 62),
                        const SizedBox(height: 8),
                        Flexible(
                          child: Text(
                            t.nome,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(contesto).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (tipo == null || !context.mounted) return;
  final esito = await segnalazioni.segnala(tipo);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(esito)));
}
