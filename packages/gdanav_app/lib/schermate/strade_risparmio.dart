import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_risparmio.dart';

/// «Strade a risparmio», dal menu: se proporle durante il viaggio, quanto
/// devono far risparmiare, quanti minuti in più si accettano, e se proporre
/// anche quelle che il traffico rende più rapide.
class StradeRisparmioSchermata extends StatelessWidget {
  const StradeRisparmioSchermata({super.key, required this.risparmio});

  final GestoreRisparmio risparmio;

  /// Le scelte della percentuale minima e dei minuti in più.
  static const percentuali = [3.0, 5.0, 10.0, 15.0, 20.0];
  static const minuti = [0, 5, 10, 15, 20, 30];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final muto = tema.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Strade a risparmio')),
      body: ListenableBuilder(
        listenable: risparmio,
        builder: (context, _) {
          final s = risparmio.soglie;
          String percento(double p) => '${p.round()} %';
          String piu(int m) => m == 0 ? 'Nessuno' : '+$m min';
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      key: const Key('risparmio-proponi'),
                      title: const Text('Proponimele durante il viaggio'),
                      subtitle: const Text('Si confrontano ogni cinque minuti, col traffico'),
                      value: s.proponi,
                      onChanged: (v) => risparmio.cambia(copiaSoglie(s, proponi: v)),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      enabled: s.proponi,
                      title: const Text('Solo se risparmio almeno'),
                      subtitle: const Text('Meno di così, non disturba'),
                      trailing: PopupMenuButton<double>(
                        key: const Key('risparmio-minimo'),
                        enabled: s.proponi,
                        initialValue: s.minimoPercento,
                        onSelected: (v) => risparmio.cambia(copiaSoglie(s, minimoPercento: v)),
                        itemBuilder: (_) => [
                          for (final p in percentuali)
                            PopupMenuItem(value: p, key: Key('minimo-${p.round()}'), child: Text(percento(p))),
                        ],
                        child: _Pastiglia(percento(s.minimoPercento), acceso: s.proponi),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      enabled: s.proponi,
                      title: const Text('E se ci metto al massimo'),
                      subtitle: const Text('Minuti in più rispetto alla strada che fai'),
                      trailing: PopupMenuButton<int>(
                        key: const Key('risparmio-massimo'),
                        enabled: s.proponi,
                        initialValue: s.massimoInPiu.inMinutes,
                        onSelected: (m) => risparmio.cambia(copiaSoglie(s, massimoInPiu: Duration(minutes: m))),
                        itemBuilder: (_) => [
                          for (final m in minuti) PopupMenuItem(value: m, key: Key('massimo-$m'), child: Text(piu(m))),
                        ],
                        child: _Pastiglia(piu(s.massimoInPiu.inMinutes), acceso: s.proponi),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      key: const Key('risparmio-rapide'),
                      title: const Text('Proponimi anche quelle più rapide'),
                      subtitle: const Text('Se il traffico ne apre una che fa arrivare prima'),
                      value: s.ancheRapide,
                      onChanged: s.proponi ? (v) => risparmio.cambia(copiaSoglie(s, ancheRapide: v)) : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Il consumo lo calcola TomTom col profilo della tua auto: velocità, salite, discese e '
                  'temperatura. Con l\'auto termica le strade si confrontano in litri.\n'
                  'Una strada che rifiuti, o che lasci passare, non te la ripropongo in questo viaggio.',
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

/// Il valore scelto, in una pastiglia azzurra da toccare.
class _Pastiglia extends StatelessWidget {
  const _Pastiglia(this.testo, {required this.acceso});

  final String testo;
  final bool acceso;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: acceso ? c.primaryContainer : c.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        testo,
        style: TextStyle(fontWeight: FontWeight.w800, color: acceso ? c.onPrimaryContainer : c.onSurfaceVariant),
      ),
    );
  }
}

/// Com'è impostato, in poche parole, per il menu.
String riassuntoRisparmio(SoglieRisparmio s) => !s.proponi
    ? 'Spente'
    : 'Da ${s.minimoPercento.round()} % in su, ${s.massimoInPiu.inMinutes == 0 ? 'senza minuti in più' : 'fino a +${s.massimoInPiu.inMinutes} min'}';
