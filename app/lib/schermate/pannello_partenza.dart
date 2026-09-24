import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_luoghi.dart';

/// Il pannello in basso quando non si sta andando da nessuna parte, come in
/// Waze: «Dove andiamo?», Casa, Lavoro, i preferiti e le ultime mete.
class PannelloPartenza extends StatelessWidget {
  const PannelloPartenza({
    super.key,
    required this.luoghi,
    required this.onCerca,
    required this.onVai,
    required this.onPreferito,
    required this.onNuovo,
    required this.onModificaPreferito,
  });

  final GestoreLuoghi luoghi;
  final VoidCallback onCerca;
  final ValueChanged<Luogo> onVai;

  /// Casa o Lavoro toccati: se non ci sono ancora si impostano.
  final ValueChanged<TipoPreferito> onPreferito;
  final VoidCallback onNuovo;
  final ValueChanged<Preferito> onModificaPreferito;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.36,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.36],
      builder: (context, scorri) => Material(
        color: s.surface,
        elevation: 12,
        shadowColor: const Color(0x66000000),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: ListenableBuilder(
          listenable: luoghi,
          builder: (context, _) => ListView(
            controller: scorri,
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: s.outlineVariant, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: s.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(30),
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: onCerca,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 28, color: s.onSurfaceVariant),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Dove andiamo?',
                            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: s.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Chip(
                      icona: Icons.home_rounded,
                      colore: const Color(0xFFE8704A),
                      testo: 'Casa',
                      onTap: () => onPreferito(TipoPreferito.casa),
                      onLungo: luoghi.casa == null ? null : () => onModificaPreferito(luoghi.casa!),
                    ),
                    const SizedBox(width: 10),
                    _Chip(
                      icona: Icons.work_rounded,
                      colore: const Color(0xFFB9642E),
                      testo: 'Lavoro',
                      onTap: () => onPreferito(TipoPreferito.lavoro),
                      onLungo: luoghi.lavoro == null ? null : () => onModificaPreferito(luoghi.lavoro!),
                    ),
                    for (final p in luoghi.altri) ...[
                      const SizedBox(width: 10),
                      _Chip(
                        icona: Icons.star_rounded,
                        colore: const Color(0xFFF2B01E),
                        testo: p.etichetta,
                        onTap: () => onVai(p.luogo),
                        onLungo: () => onModificaPreferito(p),
                      ),
                    ],
                    const SizedBox(width: 10),
                    _Chip(icona: Icons.add, colore: s.primary, testo: 'Nuovo', blu: true, onTap: onNuovo),
                  ],
                ),
              ),
              if (luoghi.recenti.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('Recenti', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                for (final l in luoghi.recenti)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history, color: s.onSurfaceVariant, size: 28),
                    title: Text(l.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                    subtitle: l.descrizione.isEmpty
                        ? null
                        : Text(l.descrizione, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => onVai(l),
                    trailing: IconButton(
                      tooltip: 'Togli dai recenti',
                      icon: Icon(Icons.close, size: 20, color: s.onSurfaceVariant),
                      onPressed: () => luoghi.dimentica(l),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icona,
    required this.colore,
    required this.testo,
    required this.onTap,
    this.onLungo,
    this.blu = false,
  });

  final IconData icona;
  final Color colore;
  final String testo;
  final VoidCallback onTap;
  final VoidCallback? onLungo;
  final bool blu;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: s.outlineVariant, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLungo,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icona, color: colore, size: 26),
              const SizedBox(width: 10),
              Text(
                testo,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: blu ? s.primary : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
