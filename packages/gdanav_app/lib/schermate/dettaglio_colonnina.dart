import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/stato_colonnina.dart';
import '../stato/gestore_viaggio.dart';
import '../tema.dart';

Future<void> mostraColonnina(BuildContext context, GestoreViaggio gestore, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DettaglioColonnina(gestore: gestore, id: id),
  );
}

/// Da dove vengono i dati di una colonnina, detto come lo chiedono le
/// licenze: OpenStreetMap e Open Charge Map coi loro «contributors», la PUN
/// con chi l'ha pubblicata e la licenza. `null` se la fonte non va citata.
String? creditoColonnina(String fonte) {
  final f = fonte.split('+');
  final parti = [
    if (f.contains('osm')) '© OpenStreetMap contributors',
    if (f.contains('ocm')) '© Open Charge Map contributors',
    if (f.contains('pun')) Pun.attribuzione,
  ];
  return parti.isEmpty ? null : 'Dati: ${parti.join(' · ')}';
}

String nomeConnettore(TipoConnettore t) => switch (t) {
  TipoConnettore.ccs2 => 'CCS',
  TipoConnettore.chademo => 'CHAdeMO',
  TipoConnettore.tipo2 => 'Tipo 2',
  TipoConnettore.tesla => 'Tesla',
  TipoConnettore.altro => 'Altra presa',
};

/// Il prezzo di una colonnina in righe da leggere, una per tipo di corrente:
/// «AC: 0,63 €/kWh · sosta 0,08 €/min». Dove i punti costano diverso, da…
/// a…: «0,63–0,69 €/kWh».
List<String> righePrezzi(Prezzi p) {
  return [
    for (final c in Corrente.values)
      if (p.perCorrente[c] case final t?)
        '${switch (c) {
          Corrente.ac => 'AC',
          Corrente.dc => 'DC',
          Corrente.hpc => 'DC ad alta potenza',
        }}: ${[
          if (t.energia case final f?) '${_quanto(f)} €/kWh',
          if (t.tempo case final f?) '${_quanto(f)} €/min di ricarica',
          if (t.avvio case final f?) 'avvio ${_quanto(f)} €',
          if (t.sosta case final f?) 'sosta ${_quanto(f)} €/min',
        ].join(' · ')}',
  ];
}

String _cifra(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
String _quanto(Forchetta f) => f.da == f.a ? _cifra(f.da) : '${_cifra(f.da)}–${_cifra(f.a)}';

/// Il prezzo per la scheda sullo schermo dell'auto, che ha posto per una
/// riga sola: la tariffa della corrente con cui quell'auto caricherebbe lì —
/// ad alta potenza se la colonnina ne ha, poi continua, poi alternata — e
/// sotto quello che si paga oltre l'energia. Se il gestore comunica solo
/// un'altra corrente, quella: meglio un prezzo vero che niente.
///
/// `null` se il prezzo non si è chiesto; «Prezzo non comunicato» se la PUN
/// ha risposto che il gestore non lo manda.
({String titolo, String? testo, bool comunicato})? prezzoInAuto(Colonnina c, Set<TipoConnettore> compatibili) {
  final p = c.prezzi;
  if (p == null) return null;
  if (p.vuoti) return (titolo: 'Prezzo non comunicato', testo: 'il gestore non lo manda alla PUN', comunicato: false);
  final adatte = c.connettori.where((k) => compatibili.contains(k.tipo));
  final continua = [
    for (final k in adatte)
      if (k.tipo != TipoConnettore.tipo2 && k.tipo != TipoConnettore.altro) k.potenzaKw,
  ];
  final ordine = [
    if (continua.isNotEmpty)
      ...(continua.reduce((a, b) => a > b ? a : b) >= 150 ? [Corrente.hpc, Corrente.dc] : [Corrente.dc, Corrente.hpc]),
    if (adatte.any((k) => k.tipo == TipoConnettore.tipo2)) Corrente.ac,
    ...Corrente.values.reversed,
  ];
  bool dice(Tariffa? t) => t != null && (t.energia ?? t.tempo ?? t.sosta ?? t.avvio) != null;
  final corrente = ordine.where((x) => dice(p.perCorrente[x])).firstOrNull;
  if (corrente == null) return null;
  final t = p.perCorrente[corrente]!;
  final quale = switch (corrente) {
    Corrente.ac => 'in alternata',
    Corrente.dc => 'in continua',
    Corrente.hpc => 'ad alta potenza',
  };
  final voci = [
    if (t.energia case final f?) '${_quanto(f)} €/kWh $quale',
    if (t.tempo case final f?) t.energia == null ? '${_quanto(f)} €/min $quale' : '${_quanto(f)} €/min di ricarica',
    if (t.sosta case final f?) 'sosta ${_quanto(f)} €/min',
    if (t.avvio case final f?) 'avvio ${_quanto(f)} €',
  ];
  final prima = voci.first;
  return (
    titolo: prima[0].toUpperCase() + prima.substring(1),
    testo: voci.length > 1 ? voci.skip(1).join(' · ') : null,
    comunicato: true,
  );
}

/// Il prezzo nella scheda di una colonnina: le righe, oppure — se la PUN
/// l'ha detto — che il gestore non lo comunica. Niente se non si è chiesto.
List<Widget> sezionePrezzo(BuildContext context, Prezzi? prezzi) {
  if (prezzi == null) return const [];
  final t = Theme.of(context).textTheme;
  final muto = Theme.of(context).colorScheme.onSurfaceVariant;
  if (prezzi.vuoti) {
    return [
      const SizedBox(height: 12),
      Text(
        'Prezzo: il gestore non lo comunica alla PUN',
        key: const Key('prezzo-assente'),
        style: t.bodyMedium?.copyWith(color: muto),
      ),
    ];
  }
  return [
    const SizedBox(height: 12),
    Text('Prezzo', style: t.titleSmall),
    for (final riga in righePrezzi(prezzi))
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(riga, key: const Key('prezzo'))),
    Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('Come il gestore lo comunica alla PUN', style: t.bodySmall?.copyWith(color: muto)),
    ),
  ];
}

/// Tutto di una colonnina: prese, potenza, quante libere, e «fermati qui».
class DettaglioColonnina extends StatelessWidget {
  const DettaglioColonnina({super.key, required this.gestore, required this.id});

  final GestoreViaggio gestore;
  final String id;

  @override
  Widget build(BuildContext context) {
    final stato = gestore.stato;
    if (stato is! ViaggioPronto) return const SizedBox.shrink();
    final c = stato.viaggio.colonnine.where((c) => c.id == id).firstOrNull;
    if (c == null) return const SizedBox.shrink();
    final soste = stato.viaggio.piano?.soste ?? const <Sosta>[];
    final sosta = soste.where((s) => s.colonnina.id == id).firstOrNull;
    final numero = sosta == null ? null : soste.indexOf(sosta) + 1;
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final prese = <(TipoConnettore, double), List<Connettore>>{};
    for (final p in c.dettaglio?.connettori ?? const <Connettore>[]) {
      prese.putIfAbsent((p.tipo, p.potenzaKw), () => []).add(p);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (numero != null)
              Text(
                c.obbligata ? 'SOSTA $numero · SCELTA DA TE' : 'SOSTA $numero DEL VIAGGIO',
                style: t.labelMedium?.copyWith(color: ColoriGdanav.di(context).libera, letterSpacing: 0.8),
              ),
            Text(c.nome, style: t.titleLarge),
            if (c.dettaglio?.operatore case final o?) Text(o, style: t.bodyMedium?.copyWith(color: muto)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [BadgePotenza(c.potenzaKw), BadgeDisponibilita(c.disponibilita)]),
            const SizedBox(height: 12),
            Text(
              'A ${(c.distanzaM / 1000).round()} km dalla partenza'
              '${c.deviazioneM >= 100 ? ' · ${(c.deviazioneM / 1000).toStringAsFixed(1)} km fuori strada' : ''}',
              style: t.bodyMedium,
            ),
            if (sosta != null)
              Text(
                'Ricarichi dal ${sosta.batteriaArrivo.round()}% al ${sosta.batteriaPartenza.round()}% '
                'in ${sosta.ricarica.inMinutes} min',
                style: t.bodyMedium,
              ),
            if (prese.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Prese', style: t.titleSmall),
              const SizedBox(height: 6),
              for (final MapEntry(key: (tipo, kw), value: lista) in prese.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text('${nomeConnettore(tipo)} · ${kw.round()} kW')),
                      for (final p in lista)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: switch (p.stato) {
                              StatoPresa.disponibile => 'Libera',
                              StatoPresa.occupata => 'Occupata',
                              StatoPresa.fuoriServizio => 'Fuori servizio',
                              StatoPresa.sconosciuto => 'Stato non disponibile',
                            },
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(color: _colorePresa(context, p.stato), shape: BoxShape.circle),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            ...sezionePrezzo(context, c.dettaglio?.prezzi),
            const SizedBox(height: 20),
            if (c.obbligata)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Togli questa sosta'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    gestore.togliSosta(id);
                  },
                ),
              )
            else if (sosta == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.ev_station),
                  label: const Text('Fermati qui'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    gestore.fermatiA(id);
                  },
                ),
              )
            else
              Text('Il viaggio si ferma già qui.', style: t.bodyMedium?.copyWith(color: muto)),
            const SizedBox(height: 8),
            Text(
              'Stato delle prese: PUN e operatori, quando lo pubblicano.',
              style: t.bodySmall?.copyWith(color: muto),
            ),
            if (creditoColonnina(c.dettaglio?.fonte ?? '') case final credito?)
              Text(credito, style: t.bodySmall?.copyWith(color: muto)),
          ],
        ),
      ),
    );
  }

  static Color _colorePresa(BuildContext context, StatoPresa s) {
    final c = ColoriGdanav.di(context);
    return switch (s) {
      StatoPresa.disponibile => c.libera,
      StatoPresa.occupata => c.piena,
      StatoPresa.fuoriServizio => c.guasta,
      StatoPresa.sconosciuto => c.ignota,
    };
  }
}
