import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../stato/gestore_auto.dart';
import 'abbina_home_assistant.dart';
import 'fonte_dati_auto.dart';

/// Lo stile di OpenFreeMap: gratis, senza chiave, anche per uso commerciale.
const stileMappa = 'https://tiles.openfreemap.org/styles/liberty';

class SchermataPrincipale extends StatelessWidget {
  const SchermataPrincipale({super.key, required this.gestore, this.mappa});

  final GestoreAuto gestore;
  final WidgetBuilder? mappa;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: (mappa ?? _mappaVera)(context)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: ListenableBuilder(
                  listenable: gestore,
                  builder: (context, _) =>
                      PastigliaBatteria(stato: gestore.stato, onTap: () => mostraFonteDatiAuto(context, gestore)),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AbbinaHomeAssistant(gestore: gestore))),
        icon: const Icon(Icons.home_outlined),
        label: const Text('Home Assistant'),
      ),
    );
  }

  static Widget _mappaVera(BuildContext context) => MapLibreMap(
    styleString: stileMappa,
    initialCameraPosition: CameraPosition(target: LatLng(41.9, 12.5), zoom: 5),
    myLocationEnabled: true,
  );
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
