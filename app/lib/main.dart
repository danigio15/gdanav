import 'package:flutter/material.dart';

import 'schermate/schermata_principale.dart';
import 'stato/archivio.dart';
import 'stato/gestore_auto.dart';
import 'stato/gestore_viaggio.dart';
import 'stato/posizione.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final archivio = Archivio();
  final auto = GestoreAuto(archivio: archivio);
  await auto.avvia();
  final viaggio = GestoreViaggio(archivio: archivio, auto: auto, posizione: posizioneAttuale);
  runApp(GdanavApp(archivio: archivio, auto: auto, viaggio: viaggio));
}

class GdanavApp extends StatelessWidget {
  const GdanavApp({super.key, required this.archivio, required this.auto, required this.viaggio, this.mappa});

  final Archivio archivio;
  final GestoreAuto auto;
  final GestoreViaggio viaggio;

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
      home: SchermataPrincipale(auto: auto, viaggio: viaggio, archivio: archivio, mappa: mappa),
    );
  }
}
