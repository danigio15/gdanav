import 'package:flutter/material.dart';

import '../stato/gestore_ztl.dart';

/// «ZTL e aree pedonali», dal menu: sulla mappa o no, gli avvisi, e una riga
/// per ogni ZTL a cui si è risposto, con l'interruttore per cambiare idea.
class ZoneZtlSchermata extends StatelessWidget {
  const ZoneZtlSchermata({super.key, required this.ztl});

  final GestoreZtl ztl;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final muto = tema.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('ZTL e aree pedonali')),
      body: ListenableBuilder(
        listenable: ztl,
        builder: (context, _) {
          final s = ztl.scelte;
          final permessi = s.permessi.entries.toList()..sort((a, b) => a.value.nome.compareTo(b.value.nome));
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              _Gruppo(
                children: [
                  SwitchListTile(
                    key: const Key('ztl-mappa'),
                    title: const Text('Mostrale sulla mappa'),
                    subtitle: const Text('Anche sullo schermo dell\'auto'),
                    value: s.sullaMappa,
                    onChanged: ztl.mostra,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    key: const Key('ztl-avvisi'),
                    title: const Text('Avvisami prima di una ZTL attiva'),
                    subtitle: const Text('Se il percorso ci entra, o se esci dal percorso'),
                    value: s.avvisi,
                    onChanged: ztl.avvisa,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Text(
                  'I TUOI PERMESSI',
                  style: t.labelMedium?.copyWith(color: muto, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
              ),
              _Gruppo(
                children: [
                  if (permessi.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Ancora nessuna. Te lo chiedo la prima volta che il percorso passerebbe da una ZTL attiva, '
                        'e me lo ricordo.',
                        style: t.bodyMedium?.copyWith(color: muto),
                      ),
                    ),
                  for (final (i, MapEntry(key: chiave, value: p)) in permessi.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    Dismissible(
                      key: ValueKey('permesso-$chiave'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: tema.colorScheme.errorContainer,
                        child: Text('Dimentica', style: TextStyle(color: tema.colorScheme.onErrorContainer)),
                      ),
                      onDismissed: (_) => ztl.dimentica(chiave),
                      child: SwitchListTile(
                        secondary: const _SegnoZtl(),
                        title: Text(p.nome),
                        subtitle: Text(
                          p.si
                              ? 'Hai il permesso: il percorso ci passa'
                              : 'Niente permesso: il percorso la evita quando è attiva',
                        ),
                        value: p.si,
                        onChanged: (v) => ztl.cambia(chiave, v),
                      ),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'Le aree pedonali in auto non si attraversano mai: il percorso le evita sempre. '
                  'Per togliere una ZTL dall\'elenco, falla scorrere verso sinistra: la prossima volta te lo richiedo.\n'
                  'ZTL e orari da © OpenStreetMap contributors: dove i cartelli dicono altro, valgono i cartelli.',
                  style: t.bodySmall?.copyWith(color: muto, height: 1.45),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Gruppo extends StatelessWidget {
  const _Gruppo({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// Il quadretto rosa con «ZTL», accanto a ogni permesso.
class _SegnoZtl extends StatelessWidget {
  const _SegnoZtl();

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scuro ? const Color(0xFF4C1D1D) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'ZTL',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: scuro ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
        ),
      ),
    );
  }
}
