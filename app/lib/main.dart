import 'package:flutter/material.dart';

import 'auto/ponte_auto.dart';
import 'schermate/schermata_principale.dart';
import 'stato/archivio.dart';
import 'stato/gestore_auto.dart';
import 'stato/gestore_guida.dart';
import 'stato/gestore_posizione.dart';
import 'stato/gestore_viaggio.dart';
import 'stato/posizione.dart';
import 'stato/voce.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final archivio = Archivio();
  final auto = GestoreAuto(archivio: archivio);
  await auto.avvia();
  final viaggio = GestoreViaggio(archivio: archivio, auto: auto, posizione: posizioneAttuale);
  final guida = GestoreGuida(viaggio: viaggio, auto: auto, posizioni: posizioniGuida, voce: VoceTelefono());
  final posizione = GestorePosizione(archivio: archivio, letture: lettureGps);
  await posizione.carica();
  PonteAuto(viaggio: viaggio, guida: guida, posizione: posizione).avvia();
  runApp(
    GdanavApp(
      archivio: archivio,
      auto: auto,
      viaggio: viaggio,
      guida: guida,
      posizione: posizione,
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
  });

  final Archivio archivio;
  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final GestoreGuida guida;
  final GestorePosizione posizione;
  final Future<bool> Function()? chiediPosizione;

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
      ),
    );
  }
}
