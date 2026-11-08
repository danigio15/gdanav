// Lo stile vero dell'app (`stileMappa`), in JSON, per il collaudo nel
// browser: `dart run stile.dart uscita.json chiaro|scuro [auto] [3d] [immersiva]`
// («auto»: quello dello schermo dell'auto; «3d»: con l'aspetto della mappa 3D;
// «immersiva»: quello della vista immersiva).
import 'dart:convert';
import 'dart:io';

import 'package:gdanav_app/mappa/stile.dart';

void main(List<String> argomenti) {
  final scuro = argomenti.length > 1 && argomenti[1] == 'scuro';
  File(argomenti[0]).writeAsStringSync(
    jsonEncode(
      stileMappa(
        scuro: scuro,
        perAuto: argomenti.contains('auto'),
        aspetto3d: argomenti.contains('3d'),
        immersiva: argomenti.contains('immersiva'),
      ),
    ),
  );
}
