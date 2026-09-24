import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';

const _canale = MethodChannel('gdanav/diagnosi');

/// «Android Auto» nel menu: cosa vede il telefono, e cosa fare se gdanav
/// non compare sull'auto.
Future<void> mostraDiagnosiAuto(BuildContext context) async {
  Map<Object?, Object?>? dati;
  try {
    dati = await _canale.invokeMethod<Map<Object?, Object?>>('androidAuto');
  } catch (_) {
    dati = null;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (contesto) => SafeArea(child: DiagnosiAuto(dati: dati)),
  );
}

class DiagnosiAuto extends StatelessWidget {
  const DiagnosiAuto({super.key, required this.dati});

  /// `null` dove il controllo non si può fare (iPhone, prove).
  final Map<Object?, Object?>? dati;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = dati;
    Widget voce(String titolo, bool? ok, String dettaglio) => ListTile(
      dense: true,
      leading: Icon(
        ok == null ? Icons.help_outline : (ok ? Icons.check_circle : Icons.cancel),
        color: ok == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : (ok ? ColoriGdanav.di(context).libera : ColoriGdanav.di(context).guasta),
      ),
      title: Text(titolo),
      subtitle: Text(dettaglio),
    );
    final versione = d?['androidAuto'] as String?;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Android Auto', style: t.titleLarge),
          ),
          if (d == null)
            voce('Controllo non disponibile', null, 'Su questo telefono non si può leggere.')
          else ...[
            voce(
              'Servizio per l\'auto',
              d['servizio'] == true && d['navigazione'] == true && d['descrittore'] == true,
              d['servizio'] == true ? 'Registrato come app di navigazione' : 'Non registrato: reinstalla l\'app',
            ),
            voce(
              'Android Auto sul telefono',
              versione != null,
              versione == null ? 'Non trovato: installalo dal Play Store' : 'Versione $versione',
            ),
            voce('Installata da', null, (d['installatore'] as String?) ?? 'file APK (fuori dal Play Store)'),
            voce('Telefono', null, '${d['telefono']} · Android ${d['android']}'),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Se gdanav non compare sull\'auto', style: t.titleMedium),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '1. Impostazioni di Android Auto → in fondo tocca 10 volte «Versione».\n'
              '2. Menu ⋮ → Impostazioni sviluppatore → attiva «Origini sconosciute».\n'
              '3. Impostazioni del telefono → App → Android Auto → Arresto forzato.\n'
              '4. Scollega e ricollega il telefono all\'auto.\n'
              '5. Impostazioni di Android Auto → «Personalizza avvio app»: gdanav deve esserci.',
            ),
          ),
        ],
      ),
    );
  }
}
