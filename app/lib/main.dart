import 'package:flutter/material.dart';

import 'schermate/schermata_principale.dart';
import 'stato/archivio.dart';
import 'stato/gestore_auto.dart';
import 'stato/gestore_viaggio.dart';
import 'stato/posizione.dart';

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

  /// Nelle prove si passa un segnaposto: la mappa vera vuole il codice
  /// nativo.
  final WidgetBuilder? mappa;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gdanav',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1D5BA8), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF1D5BA8), brightness: Brightness.dark, useMaterial3: true),
      home: SchermataPrincipale(auto: auto, viaggio: viaggio, archivio: archivio, mappa: mappa),
    );
  }
}
