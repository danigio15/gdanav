import 'package:flutter/material.dart';
import 'package:gdanav_app/gdanav_app.dart';

/// L'app gdanav: il pacchetto `gdanav_app`, a tutto schermo e con Android
/// Auto. Lo stesso pacchetto sta anche dentro gdahome, come sezione.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await preparaGdanav());
}
