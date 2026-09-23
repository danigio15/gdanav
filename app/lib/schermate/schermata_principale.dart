import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/archivio.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_viaggio.dart';
import 'abbina_home_assistant.dart';
import 'cerca_destinazione.dart';
import 'fonte_dati_auto.dart';
import 'impostazioni.dart';
import 'mappa.dart';
import 'scheda_viaggio.dart';

class SchermataPrincipale extends StatelessWidget {
  const SchermataPrincipale({
    super.key,
    required this.auto,
    required this.viaggio,
    required this.archivio,
    this.mappa,
  });

  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final Archivio archivio;

  /// Nelle prove si passa un segnaposto: la mappa vera vuole il codice
  /// nativo.
  final WidgetBuilder? mappa;

  Future<void> _cerca(BuildContext context) async {
    final luogo = await Navigator.of(context).push<Luogo>(
      MaterialPageRoute(
        builder: (_) => CercaDestinazione(luoghi: viaggio.luoghi, vicinoA: viaggio.ultimaPosizione),
      ),
    );
    if (luogo != null) await viaggio.pianifica(luogo);
  }

  void _impostazioni(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => SchermataImpostazioni(archivio: archivio)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: (mappa ??
                    (_) => MappaViaggio(
                      gestore: viaggio,
                      onPuntoScelto: (p) => viaggio.pianifica(
                        Luogo(nome: 'Punto sulla mappa', posizione: p, descrizione: '${p.lat}, ${p.lon}'),
                      ),
                    ))(context),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _cerca(context),
                            child: const Padding(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(Icons.search),
                                  SizedBox(width: 12),
                                  Text('Dove vuoi andare?'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Home Assistant',
                          icon: const Icon(Icons.home_outlined),
                          onPressed: () => Navigator.of(
                            context,
                          ).push(MaterialPageRoute<void>(builder: (_) => AbbinaHomeAssistant(gestore: auto))),
                        ),
                        IconButton(
                          tooltip: 'Impostazioni',
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => _impostazioni(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: auto,
                    builder: (context, _) =>
                        PastigliaBatteria(stato: auto.stato, onTap: () => mostraFonteDatiAuto(context, auto)),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: SchedaViaggio(gestore: viaggio, apriImpostazioni: () => _impostazioni(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// «82% · Home Assistant · 12 min fa»: la batteria, da dove arriva e quanto
/// è vecchia. Toccandola si apre lo switch della fonte.
class PastigliaBatteria extends StatelessWidget {
  const PastigliaBatteria({super.key, required this.stato, required this.onTap});

  final StatoAuto? stato;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = stato;
    final testo = s == null
        ? 'Batteria sconosciuta'
        : '${s.batteria.round()}% · ${nomeSorgente(s.sorgente)} · ${eta(DateTime.now().difference(s.letto))}';
    return ActionChip(
      avatar: Icon(s?.inCarica == true ? Icons.battery_charging_full : Icons.battery_std),
      label: Text(testo),
      onPressed: onTap,
    );
  }
}

String nomeSorgente(TipoSorgente t) => switch (t) {
  TipoSorgente.automotive => 'Auto',
  TipoSorgente.androidAuto => 'Android Auto',
  TipoSorgente.obd => 'OBD',
  TipoSorgente.homeAssistant => 'Home Assistant',
  TipoSorgente.manuale => 'Manuale',
  TipoSorgente.stima => 'Stima',
};

String eta(Duration d) {
  if (d.inSeconds < 60) return 'adesso';
  if (d.inMinutes < 60) return '${d.inMinutes} min fa';
  return '${d.inHours} h fa';
}
