import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/indicatore_batteria.dart';
import '../sorgenti/sorgente_gdahome.dart';
import '../stato/gestore_auto.dart';
import 'fonte_dati_auto.dart';

/// Cosa dice il menu della fonte gdahome, in una riga.
String riassuntoGdahome(GestoreAuto gestore) {
  final g = gestore.gdahome;
  if (g == null) return 'Automatica dentro l\'app gdahome';
  final auto = g.auto;
  if (auto == null) return 'Nessuna auto nella plancia di gdahome';
  return '${g.collegata ? 'Collegata' : 'In attesa della casa'} · ${auto.etichetta}';
}

/// La fonte gdahome: l'auto della sezione Auto della plancia, senza codice né
/// QR. Qui si vede cosa arriva; da configurare non c'è niente.
Future<void> mostraFonteGdahome(BuildContext context, GestoreAuto gestore) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.8, child: FonteGdahome(gestore: gestore)),
  );
}

class FonteGdahome extends StatelessWidget {
  const FonteGdahome({super.key, required this.gestore});

  final GestoreAuto gestore;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final g = gestore.gdahome;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([gestore, ?g]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('gdahome', style: t.titleLarge),
            const SizedBox(height: 8),
            if (g == null)
              Text(
                'Se usi gdanav dentro l\'app gdahome, l\'auto che hai nella sezione Auto della plancia arriva qui '
                'da sola, coi dati in tempo reale dalla tua casa: nessun codice, nessun QR.',
                style: t.bodyMedium,
              )
            else
              ..._dentro(context, g),
          ],
        ),
      ),
    );
  }

  List<Widget> _dentro(BuildContext context, SorgenteGdahome g) {
    final t = Theme.of(context).textTheme;
    final auto = g.auto;
    final ultima = g.ultima;
    return [
      Text(
        'L\'auto della sezione Auto della plancia di gdahome, coi dati in tempo reale dalla tua casa. '
        'Niente da abbinare: la casa è già collegata.',
        style: t.bodyMedium,
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.electric_car),
        title: Text(auto?.etichetta ?? 'Nessuna auto nella plancia'),
        subtitle: Text(
          auto == null
              ? 'Aggiungila nella sezione Auto della plancia di gdahome.'
              : [
                  if ('${auto.marca} ${auto.modello}'.trim() != auto.etichetta) '${auto.marca} ${auto.modello}'.trim(),
                  if (auto.kwh case final k?) '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)} kWh',
                ].join(' · '),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(g.collegata ? Icons.link : Icons.link_off),
        title: Text(g.collegata ? 'Casa collegata' : 'In attesa della casa'),
        subtitle: Text(
          ultima == null
              ? 'Ancora nessun dato dalla batteria'
              : 'Ultimo dato ${eta(DateTime.now().difference(ultima.letto))}',
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.directions_car_filled_outlined),
        title: const Text('In gdanav'),
        subtitle: Text(
          gestore.veicolo.id == ProfiloVeicolo.esempio.id
              ? 'Modello non riconosciuto: sceglilo in «La tua auto»'
              : gestore.veicolo.nome,
        ),
      ),
      const Divider(),
      DatiUsati(stato: ultima),
    ];
  }
}
