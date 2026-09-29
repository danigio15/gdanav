/// La Piattaforma Unica Nazionale dentro l'archivio delle colonnine: a quello
/// fatto da OpenStreetMap (`tool/colonnine_osm.dart`) si aggiungono i posti
/// della PUN, dal CSV che ne pubblica onData con licenza CC BY 4.0:
///
///     curl -sSfL -o pun.csv https://raw.githubusercontent.com/ondata/rete_ricarica_veicoli_elettrici/main/data/pdr_latest_ready.csv
///     dart run tool/colonnine_pun.dart colonnine.json pun.csv colonnine.json
///
/// Le due fonti si fondono con [fondiColonnine]: un posto che c'è in tutte e
/// due resta uno, con le prese di chi ne conta di più; quello che c'è in una
/// sola resta com'è. Al Centro Direzionale di Napoli OpenStreetMap ha quattro
/// stazioni, la PUN quattordici posti e 842 punti di ricarica.
library;

import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';

/// L'Italia con un po' di margine: fuori di qui una riga della PUN ha le
/// coordinate sbagliate (latitudine e longitudine scambiate, un punto in
/// mare aperto) e metterla in archivio vorrebbe dire una colonnina finta.
bool inItalia(Punto p) => p.lat >= 35.2 && p.lat <= 47.2 && p.lon >= 6.5 && p.lon <= 18.6;

Future<void> main(List<String> argomenti) async {
  if (argomenti.length != 3) {
    stderr.writeln('uso: colonnine_pun.dart archivio.json pun.csv uscita.json');
    exitCode = 2;
    return;
  }
  final archivio = ArchivioColonnine.leggi(await File(argomenti[0]).readAsString());
  final osm = archivio.tutte.toList();
  // Si parte sempre dall'archivio di OpenStreetMap soltanto: rifondere la
  // PUN su un archivio che la contiene già accoppierebbe la PUN con sé
  // stessa, e le prese di OpenStreetMap perse nella prima fusione non
  // tornerebbero più.
  if (osm.any((c) => c.fonte.split('+').contains('pun'))) {
    stderr.writeln("L'archivio ha già la PUN: si parte da quello fatto da OpenStreetMap.");
    exitCode = 1;
    return;
  }

  final lette = Pun.leggiCsv(await File(argomenti[1]).readAsString());
  final pun = lette.where((c) => inItalia(c.posizione)).toList();
  final unite = fondiColonnine([osm, pun]);

  // Un riquadro con una colonnina della PUN è cercato anche se OpenStreetMap
  // lì non ne ha: l'estratto copre l'Italia intera, e se non ne ha è perché
  // non ce ne sono. Senza, l'app chiederebbe quel riquadro al relay e le
  // colonnine della PUN lì non le guarderebbe nemmeno.
  final coperti = {
    ...archivio.coperti,
    for (final c in pun)
      ((c.posizione.lat / ClienteColonnineRelay.lato).floor(), (c.posizione.lon / ClienteColonnineRelay.lato).floor()),
  };

  final testo = ArchivioColonnine.scrivi(unite, generato: archivio.generato, coperti: coperti);
  await File(argomenti[2]).writeAsString(testo);

  int prese(Iterable<Colonnina> l) => l.fold(0, (n, c) => n + c.connettori.length);
  final soloPun = unite.where((c) => c.fonte == 'pun').length;
  final insieme = unite.where((c) => c.fonte == 'osm+pun').length;
  final fisse = unite.where((c) => c.evse.isNotEmpty && !c.tempoReale).length;
  stdout
    ..writeln('OpenStreetMap: ${osm.length} stazioni, ${prese(osm)} prese')
    ..writeln('PUN: ${lette.length} posti letti, ${lette.length - pun.length} fuori dall\'Italia e lasciati, '
        '${prese(pun)} punti di ricarica')
    ..writeln('Nella stessa posizione in tutte e due: $insieme; solo nella PUN: $soloPun')
    ..writeln('Con lo stato fisso (il gestore non manda quello di adesso): $fisse')
    ..writeln('Archivio: ${unite.length} stazioni, ${prese(unite)} prese, '
        '${coperti.length} riquadri (${coperti.length - archivio.coperti.length} nuovi), '
        '${testo.length} byte');
}
