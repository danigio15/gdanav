import 'package:flutter/material.dart';

import 'schermate/schermata_principale.dart';
import 'stato/archivio.dart';
import 'stato/gestore_auto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final archivio = Archivio();
  final gestore = GestoreAuto(archivio: archivio);
  await gestore.avvia();
  runApp(GdanavApp(gestore: gestore));
}

class GdanavApp extends StatelessWidget {
  const GdanavApp({super.key, required this.gestore, this.mappa});

  final GestoreAuto gestore;

  /// Nelle prove si passa un segnaposto: la mappa vera vuole il codice
  /// nativo.
  final WidgetBuilder? mappa;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gdanav',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1D5BA8), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF1D5BA8), brightness: Brightness.dark, useMaterial3: true),
      home: SchermataPrincipale(gestore: gestore, mappa: mappa),
    );
  }
}
