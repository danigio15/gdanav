import 'dart:convert';

import '../geo/geo.dart';
import 'segnalazioni.dart';

/// Gli autovelox fissi di OpenStreetMap (`highway=speed_camera`), dentro
/// l'app: preparati in CI (`tool/autovelox_osm.dart`), divisi in celle di un
/// decimo di grado per trovare in fretta quelli vicini.
///
///     {"v":1,"generato":"…","a":[[lat,lon,limite,direzione],…]}
///
/// limite 0: non si sa; direzione -1: non si sa.
class ArchivioAutovelox {
  ArchivioAutovelox(List<Segnalazione> tutti, {this.generato}) {
    for (final a in tutti) {
      (_celle[_cella(a.punto)] ??= []).add(a);
    }
    quanti = tutti.length;
  }

  static final vuoto = ArchivioAutovelox(const []);

  final DateTime? generato;
  late final int quanti;
  final _celle = <(int, int), List<Segnalazione>>{};

  static (int, int) _cella(Punto p) => ((p.lat * 10).floor(), (p.lon * 10).floor());

  /// Quelli entro [raggioM] da [qui].
  List<Segnalazione> vicini(Punto qui, double raggioM) {
    final passi = (raggioM / 11000).ceil();
    final (r, c) = _cella(qui);
    return [
      for (var dr = -passi; dr <= passi; dr++)
        for (var dc = -passi * 2; dc <= passi * 2; dc++)
          for (final a in _celle[(r + dr, c + dc)] ?? const <Segnalazione>[])
            if (distanzaM(qui, a.punto) <= raggioM) a,
    ];
  }

  static String scrivi(List<(double, double, int?, double?)> autovelox, {DateTime? generato}) => jsonEncode({
    'v': 1,
    'generato': (generato ?? DateTime.now().toUtc()).toIso8601String(),
    'a': [
      for (final (lat, lon, limite, direzione) in autovelox)
        [
          double.parse(lat.toStringAsFixed(5)),
          double.parse(lon.toStringAsFixed(5)),
          limite ?? 0,
          direzione?.round() ?? -1,
        ],
    ],
  });

  static ArchivioAutovelox leggi(String testo) {
    final j = jsonDecode(testo) as Map<String, Object?>;
    if (j['v'] != 1) throw FormatException('Archivio autovelox: versione ${j['v']}');
    final zero = DateTime.fromMillisecondsSinceEpoch(0);
    final tutti = <Segnalazione>[];
    for (final (i, r) in (j['a'] as List).cast<List>().indexed) {
      final limite = (r[2] as num).toInt(), direzione = (r[3] as num).toDouble();
      tutti.add(
        Segnalazione(
          id: 'fisso-$i',
          tipo: TipoSegnalazione.autovelox,
          punto: Punto((r[0] as num).toDouble(), (r[1] as num).toDouble()),
          creata: zero,
          fissa: true,
          limiteKmh: limite > 0 ? limite : null,
          direzioneGradi: direzione >= 0 ? direzione : null,
        ),
      );
    }
    return ArchivioAutovelox(tutti, generato: DateTime.tryParse('${j['generato']}'));
  }
}
