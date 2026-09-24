import 'package:gdanav_core/gdanav_core.dart';

/// Come ti vedi sulla mappa: la freccia di navigazione o un'auto vista
/// dall'alto. Il nome è anche quello dell'immagine nello stile.
enum Segnaposto {
  freccia('Freccia'),
  autoBlu('Auto blu'),
  autoBianca('Auto bianca'),
  autoRossa('Auto rossa'),
  autoNera('Auto nera'),
  autoGrigia('Auto grigia');

  const Segnaposto(this.etichetta);
  final String etichetta;

  /// `auto_blu`: come il file in `assets/segnaposto`.
  String get immagine => switch (this) {
    freccia => 'freccia',
    autoBlu => 'auto_blu',
    autoBianca => 'auto_bianca',
    autoRossa => 'auto_rossa',
    autoNera => 'auto_nera',
    autoGrigia => 'auto_grigia',
  };

  String get asset => 'assets/segnaposto/$immagine.png';

  static Segnaposto perNome(String? nome) => values.where((s) => s.name == nome).firstOrNull ?? autoBlu;
}

/// I dati della sorgente `gdanav-io`: vuota se non si sa dove sei.
Map<String, Object?> datiIo(Punto? qui, double rotta, Segnaposto segnaposto) => {
  'type': 'FeatureCollection',
  'features': [
    if (qui != null)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [qui.lon, qui.lat],
        },
        'properties': {'icona': segnaposto.immagine, 'rotta': rotta},
      },
  ],
};

/// Le segnalazioni per la sorgente `gdanav-segnalazioni`.
Map<String, Object?> datiSegnalazioni(List<Segnalazione> tutte) => {
  'type': 'FeatureCollection',
  'features': [
    for (final s in tutte)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [s.punto.lon, s.punto.lat],
        },
        'properties': {'id': s.id, 'tipo': s.tipo.name},
      },
  ],
};
