import '../percorso/pedaggi.dart';

/// Il viaggio appena finito, da dire all'arrivo.
///
/// Dal campo: «quando si arriva a destinazione la navigazione si deve
/// interrompere con scritto arrivo, e fai eventualmente un riepilogo del
/// viaggio: durata, consumo e costi». Qui ci sono i numeri e come si
/// scrivono; li raccoglie la guida, li mostrano il telefono e l'auto.
class RiepilogoViaggio {
  const RiepilogoViaggio({
    required this.destinazione,
    required this.durata,
    required this.metri,
    required this.elettrica,
    this.kwh,
    this.litri,
    this.consumoStimato = true,
    this.euroAlKwh,
    this.euroAlLitro,
    this.pedaggio,
  });

  final String destinazione;
  final Duration durata;

  /// I metri fatti in guida.
  final double metri;
  final bool elettrica;

  /// L'energia (elettrica) o il carburante (termica) usati.
  final double? kwh, litri;

  /// Vero quando il consumo viene dal modello e non dall'auto.
  final bool consumoStimato;

  /// I prezzi per il costo dell'energia, dalle opzioni.
  final double? euroAlKwh, euroAlLitro;

  /// Il pedaggio del viaggio, se se ne paga.
  final CostoPedaggio? pedaggio;

  /// «1 h 12 min», «24 min».
  String get durataTesto {
    final minuti = (durata.inSeconds / 60).round();
    if (minuti < 60) return '$minuti min';
    final h = minuti ~/ 60, m = minuti % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// «98 km», «12,4 km», «850 m».
  String get distanzaTesto {
    if (metri < 1000) return '${(metri / 10).round() * 10} m';
    final km = metri / 1000;
    return km < 20 ? '${_virgola(km, 1)} km' : '${km.round()} km';
  }

  /// «14,2 kWh · 14,5 kWh/100 km», «6,1 l · 6,2 l/100 km»; niente senza consumo.
  String? get consumoTesto {
    final quanto = elettrica ? kwh : litri;
    if (quanto == null || quanto <= 0) return null;
    final unita = elettrica ? 'kWh' : 'l';
    final cento = metri >= 1000 ? ' · ${_virgola(quanto / metri * 100000, 1)} $unita/100 km' : '';
    return '${consumoStimato ? '~' : ''}${_virgola(quanto, 1)} $unita$cento';
  }

  /// Il costo dell'energia (o del carburante), se si sa il prezzo.
  double? get euroEnergia {
    final quanto = elettrica ? kwh : litri;
    final prezzo = elettrica ? euroAlKwh : euroAlLitro;
    if (quanto == null || quanto <= 0 || prezzo == null || prezzo <= 0) return null;
    return quanto * prezzo;
  }

  /// Il pedaggio in euro, se c'è un prezzo.
  double? get euroPedaggio {
    final p = pedaggio;
    if (p == null || p.senzaPedaggi || !p.conPrezzo) return null;
    return p.euro;
  }

  /// «~4,26 € energia + ~12,40 € pedaggio = ~16,66 €»; niente se non si sa.
  String? get costoTesto {
    final energia = euroEnergia, casello = euroPedaggio;
    if (energia == null && casello == null) return null;
    final parti = [
      if (energia != null) '~${euroItaliani(energia)} ${elettrica ? 'energia' : 'carburante'}',
      if (casello != null) '${pedaggio!.prezzo} pedaggio',
    ];
    if (parti.length == 1) return parti.single;
    return '${parti.join(' + ')} = ~${euroItaliani(energia! + casello!)}';
  }

  /// Le righe del riepilogo, per il telefono.
  List<(String, String)> get righe => [
        ('Durata', durataTesto),
        ('Distanza', distanzaTesto),
        if (consumoTesto case final c?) (elettrica ? 'Energia' : 'Carburante', c),
        // Il totale, e sotto di cosa è fatto: su una riga sola andava a capo.
        ...switch ((euroEnergia, euroPedaggio)) {
          (null, null) => const <(String, String)>[],
          (final e?, final p?) => [
              ('Costo', '~${euroItaliani(e + p)}'),
              ('di cui', '~${euroItaliani(e)} ${elettrica ? 'energia' : 'carburante'} · ${pedaggio!.prezzo} pedaggio'),
            ],
          _ => [('Costo', costoTesto!)],
        },
      ];

  /// Una riga sola, per lo schermo dell'auto: «Sei arrivato a Napoli ·
  /// 2 h 41 min · 263 km · ~38,1 kWh · ~11,43 €».
  String get perAuto {
    final energia = euroEnergia, casello = euroPedaggio;
    final costo = energia == null && casello == null ? null : '~${euroItaliani((energia ?? 0) + (casello ?? 0))}';
    final quanto = elettrica ? kwh : litri;
    return [
      'Sei arrivato a $destinazione',
      durataTesto,
      distanzaTesto,
      if (quanto != null && quanto > 0) '${consumoStimato ? '~' : ''}${_virgola(quanto, 1)} ${elettrica ? 'kWh' : 'l'}',
      if (costo != null) costo,
    ].join(' · ');
  }

  static String _virgola(double v, int cifre) => v.toStringAsFixed(cifre).replaceAll('.', ',');
}
