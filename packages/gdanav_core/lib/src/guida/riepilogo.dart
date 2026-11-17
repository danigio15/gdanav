import '../percorso/pedaggi.dart';
import 'energia_del_viaggio.dart';

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
    this.kwhPiuOMeno,
    this.euroAlKwh,
    this.euroAlLitro,
    this.pedaggio,
    this.energia,
    this.senzaPrezzoVero,
    this.soste = const [],
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

  /// Quanto è larga la misura dell'energia, in kWh: l'auto dice la batteria
  /// a punti interi, e un punto di una batteria da 70 kWh sono 0,7 kWh. Su un
  /// viaggio lungo non pesa; su 13 km consumati in quattro punti è un quarto
  /// del totale, e «3,5 kWh · 25,8 kWh/100 km» era una precisione che non
  /// c'era. `null`: stimato dal modello, o misurato in kWh veri.
  final double? kwhPiuOMeno;

  /// Vero quando l'energia è misurata ma a grana grossa (più di un decimo
  /// del totale): si scrive «circa», e il perché sta nelle [note].
  bool get consumoCirca {
    final quanto = kwh, largo = kwhPiuOMeno;
    return elettrica && !consumoStimato && quanto != null && quanto > 0 && largo != null && largo >= quanto * 0.1;
  }

  /// I prezzi per il costo dell'energia, dalle opzioni.
  final double? euroAlKwh, euroAlLitro;

  /// Il pedaggio del viaggio, se se ne paga.
  final CostoPedaggio? pedaggio;

  /// Elettrica: il costo vero dell'energia, fra la carica di casa e le soste
  /// ([costoDellEnergia]). Senza, i kWh al prezzo delle opzioni.
  final CostoDellEnergia? energia;

  /// Dentro GdAHome, perché il prezzo non è quello della ricarica di casa:
  /// lo si dice, con dove si rimedia ([note]). `null` se è quello vero, o in
  /// GdANav da sola, che una casa non ce l'ha.
  final SenzaPrezzoVero? senzaPrezzoVero;

  /// Le ricariche fatte per strada.
  final List<RicaricaInViaggio> soste;

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
    // Misurata a grana grossa: «circa», e niente decimi che non ci sono.
    if (consumoCirca) {
      final cento = metri >= 1000 ? ' · circa ${(quanto / metri * 100000).round()} $unita/100 km' : '';
      return 'circa ${_virgola(quanto, 1)} $unita$cento';
    }
    final cento = metri >= 1000 ? ' · ${_virgola(quanto / metri * 100000, 1)} $unita/100 km' : '';
    return '${consumoStimato ? '~' : ''}${_virgola(quanto, 1)} $unita$cento';
  }

  /// Il costo dell'energia (o del carburante), se si sa il prezzo.
  double? get euroEnergia {
    if (elettrica && energia != null) return energia!.totale;
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
        // Da dove veniva l'energia, e quanto è costata.
        // «Da casa» solo se il prezzo è di casa: con quello delle opzioni non
        // si sa da dove venisse, ed è l'energia della batteria e basta.
        if (energia case final e? when e.kwhDaCasa > 0)
          (e.origine == PrezzoDiPartenza.opzioni ? 'Batteria' : 'Da casa', _daCasa(e)),
        for (final s in soste) ('Ricarica', _sosta(s)),
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
      if (quanto != null && quanto > 0)
        '${consumoCirca ? 'circa ' : (consumoStimato ? '~' : '')}${_virgola(quanto, 1)} ${elettrica ? 'kWh' : 'l'}',
      if (costo != null) costo,
    ].join(' · ');
  }

  /// Il riepilogo sullo schermo dell'auto, in righe (titolo, testo).
  ///
  /// «All'arrivo non c'è il report dei costi»: la riga sola di [perAuto]
  /// sull'auto si tagliava dopo il nome della meta, e i costi non si
  /// vedevano. Qui al più quattro righe — quante ne mostra una scheda di
  /// Android Auto —, e il costo c'è sempre, se si sa: tempo e strada insieme,
  /// il consumo, le ricariche, il costo col suo dettaglio.
  List<(String, String)> get righeAuto {
    final energia = euroEnergia, casello = euroPedaggio;
    // «Casa» solo se il prezzo è di casa: con quello delle opzioni è
    // l'energia della batteria, e non si sa da dove venisse.
    final stima = this.energia?.origine == PrezzoDiPartenza.opzioni;
    final ricariche = [
      if (this.energia case final e? when e.kwhDaCasa > 0)
        [
          '${stima ? 'Batteria' : 'Casa'} ${_daCasa(e)}',
          // Cosa manca, sull'auto in due parole; per esteso sul telefono
          // ([note]).
          if (stima)
            if (_cosaManca(breve: true) case final m?) m,
        ].join(' · '),
      for (final s in soste) _sosta(s),
    ];
    return [
      ('Durata e distanza', '$durataTesto · $distanzaTesto'),
      if (consumoTesto case final c?) (elettrica ? 'Energia' : 'Carburante', c),
      if (ricariche.isNotEmpty) (ricariche.length == 1 ? 'Ricarica' : 'Ricariche', ricariche.join(' — ')),
      if (energia != null || casello != null)
        (
          'Costo ~${euroItaliani((energia ?? 0) + (casello ?? 0))}',
          [
            if (energia != null) '~${euroItaliani(energia)} ${elettrica ? 'energia' : 'carburante'}',
            if (casello != null) '${pedaggio!.prezzo} pedaggio',
          ].join(' · '),
        )
      else
        ('Costo', 'Metti i prezzi nelle opzioni per vederlo'),
    ];
  }

  /// Quello che va detto sotto le righe, sul telefono: da dove viene un
  /// numero che non è quello vero, e dove si rimedia.
  ///
  /// «Verifica i costi perché non mi trovo»: il riepilogo diceva «prezzo
  /// delle opzioni» e basta, e a chi ha il fotovoltaico 0,30 €/kWh non
  /// tornava. Adesso dice quanto vale la stima, perché non c'è il prezzo vero
  /// e cosa manca alla casa per averlo.
  List<String> get note {
    final e = energia;
    final manca = _cosaManca();
    return [
      if (consumoStimato && consumoTesto != null)
        'Consumo stimato dal percorso; i prezzi si cambiano nelle opzioni del percorso.',
      if (consumoCirca)
        'Energia misurata dai punti della batteria (±${_virgola(kwhPiuOMeno!, 1)} kWh): su un viaggio corto è una '
            'misura larga.',
      if (e != null && e.kwhDaCasa > 0)
        switch (e.origine) {
          PrezzoDiPartenza.ricarica => null,
          PrezzoDiPartenza.tariffa => [
              'Energia al prezzo della rete di casa${_alKwh(e.euroAlKwhCasa)}',
              if (e.quotaSole == null) ': la parte dal sole non si sa',
              if (manca != null) ', perché $manca',
              '.',
            ].join(),
          PrezzoDiPartenza.opzioni => [
              'Il costo dell\'energia è una stima${_alKwh(e.euroAlKwhCasa)}: il prezzo si cambia nelle opzioni del '
                  'percorso.',
              if (manca != null) ' Non è quello della tua ricarica perché $manca.',
            ].join(),
        },
    ].nonNulls.toList();
  }

  static String _alKwh(double? euro) => euro == null ? '' : ' (${_virgola(euro, 2)} €/kWh)';

  /// Cosa manca per il prezzo vero, in parole; [breve] per lo schermo
  /// dell'auto.
  String? _cosaManca({bool breve = false}) => switch (senzaPrezzoVero) {
        null => null,
        SenzaPrezzoVero.casaMuta =>
          breve ? 'la casa non ha risposto' : 'la casa non ha risposto, né alla partenza né all\'arrivo',
        SenzaPrezzoVero.senzaTariffa => breve
            ? 'in GdAHome manca il prezzo dell\'energia'
            : 'in GdAHome manca il prezzo dell\'energia (si mette nella plancia, sezione Energia: tariffa unica o '
                'fasce orarie; dalla prossima ricarica il costo sarà quello vero, sole compreso)',
        SenzaPrezzoVero.autoNonSeguita => breve
            ? 'la casa non segue la ricarica dell\'auto'
            : 'la casa non segue la ricarica di quest\'auto (nella plancia, sezione Auto, servono il sensore della '
                'batteria e quello dello stato o della potenza di ricarica)',
        SenzaPrezzoVero.senzaRicarica => breve
            ? 'la casa non ha ancora visto una ricarica'
            : 'la casa non ha ancora visto una ricarica di quest\'auto (dalla prossima la ricorda)',
        SenzaPrezzoVero.ricaricaNonVale =>
          breve ? 'l\'ultima ricarica a casa è vecchia' : 'l\'ultima ricarica a casa è di più di due settimane fa',
        SenzaPrezzoVero.ricaricaAltrove => breve
            ? 'l\'ultima ricarica non è stata a casa'
            : 'la batteria alla partenza era più carica di come l\'aveva lasciata l\'ultima ricarica a casa (dopo, '
                'hai caricato altrove)',
      };

  /// «21,3 kWh · ~1,15 € · 40% dal sole»; con la tariffa di casa «prezzo di
  /// casa 0,25 €/kWh»; col prezzo delle opzioni «stima a 0,30 €/kWh».
  static String _daCasa(CostoDellEnergia e) {
    final sole = e.quotaSole;
    final alKwh = e.euroAlKwhCasa;
    return [
      '${_virgola(e.kwhDaCasa, 1)} kWh',
      '~${euroItaliani(e.euroCasa)}',
      if (sole != null && sole > 0 && e.origine != PrezzoDiPartenza.opzioni)
        '${(sole * 100).round()}% dal sole'
      else if (e.origine == PrezzoDiPartenza.tariffa && alKwh != null)
        'prezzo di casa ${_virgola(alKwh, 2)} €/kWh'
      else if (e.origine == PrezzoDiPartenza.opzioni)
        alKwh == null ? 'prezzo stimato' : 'stima a ${_virgola(alKwh, 2)} €/kWh',
    ].join(' · ');
  }

  /// «Ionity Arezzo: 28,4 kWh · 17,04 €», «… · ~16,20 € (stima)».
  static String _sosta(RicaricaInViaggio s) {
    final euro = s.euro;
    final prezzo =
        euro == null ? 'quanto hai speso?' : (s.stimata ? '~${euroItaliani(euro)} (stima)' : euroItaliani(euro));
    return '${s.dove}: ${_virgola(s.kwh, 1)} kWh · $prezzo';
  }

  static String _virgola(double v, int cifre) => v.toStringAsFixed(cifre).replaceAll('.', ',');
}
