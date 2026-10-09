import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Una persona di casa sulla mappa: chi la mette (gdahome) sa dov'è.
@immutable
class PersonaSullaMappa {
  const PersonaSullaMappa({required this.id, required this.nome, required this.posizione, this.dove = ''});

  /// Stabile finché la persona è la stessa: `person.anna` in gdahome.
  final String id;
  final String nome;
  final Punto posizione;

  /// Dove sta, scritto: l'indirizzo o la zona. Vuoto se non si sa.
  final String dove;

  /// Le iniziali per il segnaposto: «Anna Rossi» → «AR».
  String get iniziali {
    final parole = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parole.isEmpty) return '?';
    String prima(String p, int quante) => String.fromCharCodes(p.runes.take(quante));
    final prime = parole.length == 1 ? prima(parole.first, 1) : prima(parole.first, 1) + prima(parole.last, 1);
    return prime.toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      other is PersonaSullaMappa &&
      other.id == id &&
      other.nome == nome &&
      other.posizione.lat == posizione.lat &&
      other.posizione.lon == posizione.lon &&
      other.dove == dove;

  @override
  int get hashCode => Object.hash(id, nome, posizione.lat, posizione.lon, dove);
}

/// Le persone della casa sulla mappa, e quale far vedere.
///
/// Le mette l'app che ospita gdanav: gdahome sa dove sta chi abita in casa.
/// gdanav da sola non ne ha, e la mappa resta com'era.
///
/// «Mostra» non è «portami»: la mappa va sulla persona e basta. Il viaggio
/// fin lì lo si chiede dalla sua scheda, toccandola.
class GestorePersone extends ChangeNotifier {
  List<PersonaSullaMappa> _persone = const [];
  List<PersonaSullaMappa> get persone => _persone;

  int _richieste = 0;
  PersonaSullaMappa? _daMostrare;

  /// Cresce a ogni «mostra»: la mappa se ne accorge e si muove.
  int get richiesteMostra => _richieste;

  /// La persona da far vedere all'ultima richiesta; `null`: tutte.
  PersonaSullaMappa? get daMostrare => _daMostrare;

  /// Le persone di adesso. Coordinate fuori scala non si mettono.
  void aggiorna(Iterable<PersonaSullaMappa> persone) {
    final buone = [
      for (final p in persone)
        if (_valida(p.posizione)) p,
    ];
    if (listEquals(buone, _persone)) return;
    _persone = List.unmodifiable(buone);
    notifyListeners();
  }

  /// La persona per [id], se c'è.
  PersonaSullaMappa? persona(String id) => _persone.where((p) => p.id == id).firstOrNull;

  /// Porta la mappa su [persona]: se non era fra quelle note la si aggiunge
  /// (o la si rinfresca, se c'era con un'altra posizione).
  void mostra(PersonaSullaMappa persona) {
    if (!_valida(persona.posizione)) return;
    final i = _persone.indexWhere((p) => p.id == persona.id);
    if (i < 0) {
      _persone = List.unmodifiable([..._persone, persona]);
    } else if (_persone[i] != persona) {
      _persone = List.unmodifiable([..._persone]..[i] = persona);
    }
    _daMostrare = persona;
    _richieste++;
    notifyListeners();
  }

  /// Porta la mappa a vederle tutte.
  void mostraTutte() {
    if (_persone.isEmpty) return;
    _daMostrare = null;
    _richieste++;
    notifyListeners();
  }

  static bool _valida(Punto p) => p.lat.isFinite && p.lon.isFinite && p.lat.abs() <= 90 && p.lon.abs() <= 180;
}

/// I dati della sorgente `gdanav-persone`.
Map<String, Object?> datiPersone(List<PersonaSullaMappa> persone) => {
  'type': 'FeatureCollection',
  'features': [
    for (final p in persone)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [p.posizione.lon, p.posizione.lat],
        },
        'properties': {'tipo': 'persona', 'id': p.id, 'nome': p.nome, 'iniziali': p.iniziali, 'dove': p.dove},
      },
  ],
};
