import 'dart:convert';

import '../geo/geo.dart';
import 'segnalazioni.dart';

/// Un tratto con la velocità media controllata (il Tutor): si entra da
/// [inizio], si esce da [fine], e conta la media fra i due.
class TrattoTutor {
  const TrattoTutor({required this.id, required this.inizio, required this.fine, this.limiteKmh});

  final String id;
  final Punto inizio;
  final Punto fine;
  final int? limiteKmh;

  /// Da dove si guarda, per trovarli: il mezzo.
  Punto get mezzo => Punto((inizio.lat + fine.lat) / 2, (inizio.lon + fine.lon) / 2);

  /// In linea d'aria, da un capo all'altro.
  double get lunghezzaM => distanzaM(inizio, fine);
}

/// Gli autovelox fissi di OpenStreetMap, dentro l'app: preparati in CI
/// (`tool/autovelox_osm.dart`), divisi in celle di un decimo di grado per
/// trovare in fretta quelli vicini. Con i Tutor, i tratti a velocità media.
///
///     {"v":3,"generato":"…","a":[[lat,lon,limite,direzione],…],
///      "t":[[lat1,lon1,lat2,lon2,limite],…],"s":[[lat,lon,direzione],…]}
///
/// limite 0: non si sa; direzione -1: non si sa. `s` sono i semafori con la
/// foto. La versione 1 non ha `t`, la 2 non ha `s`.
class ArchivioAutovelox {
  ArchivioAutovelox(List<Segnalazione> tutti, {this.generato, List<TrattoTutor> tutor = const []}) {
    for (final a in tutti) {
      (_celle[_cella(a.punto)] ??= []).add(a);
    }
    quanti = tutti.length;
    _tutor = tutor;
  }

  static final vuoto = ArchivioAutovelox(const []);

  final DateTime? generato;
  late final int quanti;
  final _celle = <(int, int), List<Segnalazione>>{};
  late final List<TrattoTutor> _tutor;

  /// Quanti Tutor.
  int get quantiTutor => _tutor.length;

  /// I Tutor che hanno un capo entro [raggioM] da [qui]. Sono pochi (qualche
  /// centinaio): si guardano tutti.
  List<TrattoTutor> tutorVicini(Punto qui, double raggioM) => [
        for (final t in _tutor)
          if (distanzaM(qui, t.inizio) <= raggioM || distanzaM(qui, t.fine) <= raggioM) t,
      ];

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

  static double _cinque(double v) => double.parse(v.toStringAsFixed(5));

  static String scrivi(
    List<(double, double, int?, double?)> autovelox, {
    DateTime? generato,
    List<(double, double, double, double, int?)> tutor = const [],
    List<(double, double, double?)> semafori = const [],
  }) =>
      jsonEncode({
        'v': 3,
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
        't': [
          for (final (lat1, lon1, lat2, lon2, limite) in tutor)
            [_cinque(lat1), _cinque(lon1), _cinque(lat2), _cinque(lon2), limite ?? 0],
        ],
        's': [
          for (final (lat, lon, direzione) in semafori) [_cinque(lat), _cinque(lon), direzione?.round() ?? -1],
        ],
      });

  static ArchivioAutovelox leggi(String testo) {
    final j = jsonDecode(testo) as Map<String, Object?>;
    if (!const [1, 2, 3].contains(j['v'])) throw FormatException('Archivio autovelox: versione ${j['v']}');
    final zero = DateTime.fromMillisecondsSinceEpoch(0);
    final tutti = <Segnalazione>[];
    for (final (i, r) in (j['a'] as List).cast<List>().indexed) {
      final limite = (r[2] as num).toInt(), direzione = (r[3] as num).toDouble();
      tutti.add(Segnalazione(
        id: 'fisso-$i',
        tipo: TipoSegnalazione.autovelox,
        punto: Punto((r[0] as num).toDouble(), (r[1] as num).toDouble()),
        creata: zero,
        fissa: true,
        limiteKmh: limite > 0 ? limite : null,
        direzioneGradi: direzione >= 0 ? direzione : null,
      ));
    }
    for (final (i, r) in ((j['s'] as List?) ?? const []).cast<List>().indexed) {
      final direzione = (r[2] as num).toDouble();
      tutti.add(Segnalazione(
        id: 'semaforo-$i',
        tipo: TipoSegnalazione.autovelox,
        punto: Punto((r[0] as num).toDouble(), (r[1] as num).toDouble()),
        creata: zero,
        fissa: true,
        semaforo: true,
        direzioneGradi: direzione >= 0 ? direzione : null,
      ));
    }
    final tutor = <TrattoTutor>[
      for (final (i, r) in ((j['t'] as List?) ?? const []).cast<List>().indexed)
        TrattoTutor(
          id: 'tutor-$i',
          inizio: Punto((r[0] as num).toDouble(), (r[1] as num).toDouble()),
          fine: Punto((r[2] as num).toDouble(), (r[3] as num).toDouble()),
          limiteKmh: (r[4] as num) > 0 ? (r[4] as num).toInt() : null,
        ),
    ];
    return ArchivioAutovelox(tutti, generato: DateTime.tryParse('${j['generato']}'), tutor: tutor);
  }
}
