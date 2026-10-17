/// L'archivio delle sole colonnine rapide, per il ponte di Home Assistant: il
/// pianificatore dei viaggi nella plancia lo scarica una volta a settimana
/// dalla release «anteprima» e ci calcola le soste di ricarica in casa.
///
///     dart run tool/colonnine_rapide.dart colonnine.json colonnine-rapide.json.gz
///
/// Stesso formato di `colonnine.json` ([ArchivioColonnine.scrivi]), con gli
/// stessi campi di testa (v, generato, evseInOrdine, q), compresso con gzip.
/// Restano le colonnine con almeno una presa da [sogliaRapide] kW in su, e
/// di quelle si tengono TUTTE le prese e tutti i campi della riga, così come
/// sono: il ponte ne usa il kW massimo, e le prese lente accanto non danno
/// fastidio; toglierle invece sfaserebbe gli EVSE ID, scritti nell'ordine
/// delle prese. I riquadri cercati (q) sono gli stessi: dove non c'è una
/// rapida è vero che non ce ne sono.
library;

import 'dart:convert';
import 'dart:io';

/// La potenza da cui una presa è rapida, in kW.
const sogliaRapide = 50.0;

/// La riga di una colonnina ha almeno una presa da [soglia] kW in su: le
/// prese sono il sesto campo, `[[tipo, kW, quante], …]`.
bool rigaRapida(List riga, {double soglia = sogliaRapide}) =>
    riga.length > 5 &&
    riga[5] is List &&
    (riga[5] as List).any((p) => p is List && p.length > 1 && p[1] is num && (p[1] as num) >= soglia);

/// Dall'archivio intero, in testo, quello delle sole rapide: la testa
/// com'è, le righe rapide com'erano.
String soloRapide(String archivio, {double soglia = sogliaRapide}) {
  final j = jsonDecode(archivio) as Map<String, Object?>;
  if (j['v'] != 1) throw FormatException('Archivio colonnine: versione ${j['v']}');
  return jsonEncode({
    for (final MapEntry(:key, :value) in j.entries)
      key: key == 'c'
          ? [
              for (final r in (value as List).cast<List>())
                if (rigaRapida(r, soglia: soglia)) r
            ]
          : value,
  });
}

Future<void> main(List<String> argomenti) async {
  if (argomenti.length != 2) {
    stderr.writeln('uso: colonnine_rapide.dart colonnine.json colonnine-rapide.json.gz');
    exitCode = 2;
    return;
  }
  final intero = await File(argomenti[0]).readAsString();
  final testo = soloRapide(intero);
  final compresso = GZipCodec(level: 9).encode(utf8.encode(testo));
  await File(argomenti[1]).writeAsBytes(compresso);
  final quante = ((jsonDecode(testo) as Map)['c'] as List).length;
  final tutte = ((jsonDecode(intero) as Map)['c'] as List).length;
  stdout.writeln('::notice title=Archivio rapide::$quante colonnine su $tutte con una presa da '
      '${sogliaRapide.round()} kW in su, ${compresso.length ~/ 1024} kB compresse');
  if (quante < 1000) {
    stdout.writeln('::error title=Archivio rapide::troppo poche, qualcosa non va');
    exitCode = 1;
  }
}
