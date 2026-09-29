import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';

const _canale = MethodChannel('gdanav/diagnosi');

/// «Android Auto» nel menu: cosa vede il telefono, e cosa fare se gdanav
/// non compare sull'auto. Su iPhone, «CarPlay»: cosa controllare.
Future<void> mostraDiagnosiAuto(BuildContext context) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (contesto) => const SafeArea(child: AiutoCarPlay()),
    );
    return;
  }
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Il traffico sull\'auto', style: t.titleMedium),
            ),
            for (final (titolo, ok, dettaglio) in vociTraffico(d['traffico'])) voce(titolo, ok, dettaglio),
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

/// Cosa ha visto del traffico la mappa dell'auto nell'ultimo viaggio
/// (`DiagnosiTraffico.kt`): se lo strato c'è, quanti riquadri di TomTom sono
/// arrivati e quanti no, quante code c'erano sullo schermo. «Sul telefono il
/// traffico si vede, su Android Auto no»: qui si capisce se i riquadri non
/// arrivano o se sullo schermo non c'era niente da disegnare.
List<(String, bool?, String)> vociTraffico(Object? dati) {
  if (dati is! Map || dati.isEmpty) {
    return [('Non ancora visto', null, 'Apri gdanav sull\'auto e guida qualche minuto, poi torna qui.')];
  }
  int n(String k) => (dati[k] as num?)?.toInt() ?? 0;
  final arrivati = n('arrivati'), errori = n('errori'), massimo = n('massimo'), inizio = n('inizio');
  final ultimo = dati['ultimo_errore'] as String?;
  return [
    if (inizio > 0) ('Ultimo viaggio', null, 'Dalle ${_ora(DateTime.fromMillisecondsSinceEpoch(inizio))}'),
    switch (dati['strato']) {
      true => ('Strato del traffico', true, 'C\'è nella mappa dell\'auto'),
      false => ('Strato del traffico', false, 'Non c\'è: l\'app è senza la chiave TomTom'),
      _ => ('Strato del traffico', null, 'La mappa dell\'auto non si è ancora caricata'),
    },
    (
      'Riquadri da TomTom',
      errori > 0 ? false : (arrivati > 0 ? true : null),
      [
            '$arrivati arrivati',
            if (errori > 0) '$errori con errore',
            if (arrivati == 0 && errori == 0) 'nessuno chiesto ancora',
          ].join(', ') +
          (ultimo != null && errori > 0 ? '\nUltimo errore: $ultimo' : ''),
    ),
    if (massimo > 0)
      (
        'Code sullo schermo',
        true,
        'Fino a $massimo tratti insieme; all\'ultimo controllo ${n('tratti')}, '
            'zoom ${((dati['zoom'] as num?) ?? 0).toStringAsFixed(1)}',
      )
    else if (arrivati > 0)
      (
        'Code sullo schermo',
        null,
        'I riquadri sono arrivati, ma dove sei passato non c\'era traffico da disegnare. '
            'Col tasto «−» sull\'auto si vedono più strade.',
      ),
  ];
}

String _ora(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} del ${d.day}/${d.month}';

/// Su iPhone non c'è niente da leggere: CarPlay mostra gdanav da sé, se il
/// telefono è collegato e l'app è consentita.
class AiutoCarPlay extends StatelessWidget {
  const AiutoCarPlay({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CarPlay', style: t.titleLarge),
          const SizedBox(height: 12),
          Text('Se gdanav non compare sull\'auto', style: t.titleMedium),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '1. Impostazioni dell\'iPhone → Generali → CarPlay: l\'auto deve esserci.\n'
              '2. Tocca l\'auto → Personalizza: gdanav deve essere fra le app mostrate.\n'
              '3. Impostazioni → Tempo di utilizzo → Restrizioni: CarPlay non deve essere bloccato.\n'
              '4. Impostazioni → gdanav → Posizione: «Sempre», così la guida continua con lo schermo del telefono spento.\n'
              '5. Scollega e ricollega l\'iPhone all\'auto.',
            ),
          ),
        ],
      ),
    );
  }
}
