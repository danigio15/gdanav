import 'package:flutter/material.dart';

import 'auto/ponte_auto.dart';
import 'schermate/schermata_principale.dart';
import 'stato/archivio.dart';
import 'stato/gestore_auto.dart';
import 'stato/gestore_consumo.dart';
import 'stato/gestore_guida.dart';
import 'stato/gestore_luoghi.dart';
import 'stato/gestore_posizione.dart';
import 'stato/gestore_segnalazioni.dart';
import 'stato/gestore_viaggio.dart';
import 'stato/posizione.dart';
import 'stato/voce.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final archivio = Archivio();
  final auto = GestoreAuto(archivio: archivio);
  await auto.avvia();
  // Il consumo imparato del modello scelto; cambiando auto si cambia storia.
  final consumo = GestoreConsumo(archivio);
  await consumo.carica(auto.veicolo.id);
  auto.addListener(() => consumo.carica(auto.veicolo.id));
  final viaggio = GestoreViaggio(archivio: archivio, auto: auto, posizione: posizioneAttuale, consumo: consumo);
  final guida = GestoreGuida(
    viaggio: viaggio,
    auto: auto,
    posizioni: posizioniGuida,
    voce: VoceTelefono(),
    consumo: consumo,
  );
  final posizione = GestorePosizione(archivio: archivio, letture: lettureGps);
  await posizione.carica();
  final segnalazioni = GestoreSegnalazioni(posizione: posizione);
  final luoghi = GestoreLuoghi(archivio);
  await luoghi.carica();
  // Aperta da Android Auto la schermata del telefono non c'è: la posizione
  // parte subito, se il permesso è già stato dato.
  if (await haPosizione()) posizione.avvia();
  PonteAuto(viaggio: viaggio, guida: guida, posizione: posizione, luoghi: luoghi).avvia();
  runApp(
    GdanavApp(
      archivio: archivio,
      auto: auto,
      viaggio: viaggio,
      guida: guida,
      posizione: posizione,
      segnalazioni: segnalazioni,
      luoghi: luoghi,
      consumo: consumo,
      chiediPosizione: chiediPosizione,
    ),
  );
}

class GdanavApp extends StatelessWidget {
  const GdanavApp({
    super.key,
    required this.archivio,
    required this.auto,
    required this.viaggio,
    required this.guida,
    required this.posizione,
    this.mappa,
    this.chiediPosizione,
    this.segnalazioni,
    this.luoghi,
    this.consumo,
  });

  final Archivio archivio;
  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final GestoreGuida guida;
  final GestorePosizione posizione;
  final Future<bool> Function()? chiediPosizione;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreLuoghi? luoghi;
  final GestoreConsumo? consumo;

  /// Nelle prove e nelle anteprime si passa un'altra mappa: quella vera vuole
  /// il codice nativo.
  final CostruisciMappa? mappa;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gdanav',
      debugShowCheckedModeBanner: false,
      theme: temaGdanav(Brightness.light),
      darkTheme: temaGdanav(Brightness.dark),
      home: SchermataPrincipale(
        auto: auto,
        viaggio: viaggio,
        archivio: archivio,
        guida: guida,
        posizione: posizione,
        mappa: mappa,
        chiediPosizione: chiediPosizione,
        segnalazioni: segnalazioni,
        luoghi: luoghi,
        consumo: consumo,
      ),
    );
  }
}
