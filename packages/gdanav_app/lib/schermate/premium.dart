import 'package:flutter/material.dart';

import '../stato/gestore_premium.dart';

/// Cosa comprende Premium, i due piani e il bottone per la prova. Si usa da
/// solo (dal menu) e al posto delle funzioni bloccate.
class PannelloPremium extends StatefulWidget {
  const PannelloPremium({super.key, required this.premium, this.perche});

  final GestorePremium premium;

  /// Cosa si stava cercando di aprire: «Android Auto», «Il traffico».
  final String? perche;

  static const funzioni = <(IconData, String, String)>[
    (
      Icons.bolt,
      'Pianificazione EV con dati in tempo reale',
      'Batteria vera dall\'auto, soste ricalcolate sul consumo reale',
    ),
    (Icons.directions_car_filled, 'Android Auto', 'Mappa, guida e soste sullo schermo dell\'auto · CarPlay in arrivo'),
    (Icons.traffic, 'Traffico in tempo reale', 'Code e rallentamenti sulla mappa'),
    (Icons.ev_station, 'Colonnine libere e occupate', 'In tempo reale; le soste evitano quelle piene o guaste'),
    (Icons.speed, 'Autovelox', 'Fissi e segnalati, con l\'avviso e il limite'),
    (Icons.wb_cloudy_outlined, 'Previsioni meteo', 'Temperatura e vento lungo il viaggio, nel consumo'),
    (Icons.history, 'Cronologia viaggi e ricariche', 'Km, consumi, soste e ricariche di ogni viaggio'),
    (Icons.garage_outlined, 'Più veicoli', 'Tutte le tue auto, ognuna col suo consumo imparato'),
    (Icons.home_outlined, 'Home Assistant', 'Batteria dell\'auto, viaggi e ricarica pronta a casa'),
  ];

  @override
  State<PannelloPremium> createState() => _PannelloPremiumState();
}

class _PannelloPremiumState extends State<PannelloPremium> {
  var _scelto = pianoAnnuale;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.premium,
      builder: (context, _) {
        final p = widget.premium;
        final piani = {for (final x in p.piani) x.id: x};
        final scelto = piani[_scelto] ?? piani.values.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium, color: s.primary, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('gdanav Premium', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.daOspite
                  ? p.sbloccato
                        ? 'Premium è attivo con gdahome: tutto sbloccato.'
                        : '${widget.perche ?? 'Tutto gdanav'} fa parte del Premium di gdahome: attivalo dall\'app gdahome.'
                  : p.sbloccato
                  ? 'Premium è attivo: grazie!'
                  : widget.perche == null
                  ? 'Tutto gdanav, con 14 giorni di prova gratuita.'
                  : '${widget.perche} fa parte di Premium: provalo gratis per 14 giorni.',
              style: t.bodyLarge,
            ),
            const SizedBox(height: 12),
            for (final (icona, titolo, testo) in PannelloPremium.funzioni)
              _Voce(icona: icona, titolo: titolo, testo: testo),
            const SizedBox(height: 12),
            if (!p.sbloccato && !p.daOspite) ...[
              if (piani.isNotEmpty) ...[
                for (final id in [pianoAnnuale, pianoMensile])
                  if (piani[id] case final piano?)
                    _Piano(
                      piano: piano,
                      scelto: scelto?.id == id,
                      nota: id == pianoAnnuale ? _risparmio(piani) : null,
                      onTap: () => setState(() => _scelto = id),
                    ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('compra-premium'),
                onPressed: p.inCorso || scelto == null ? null : () => p.compra(scelto.id),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: p.inCorso
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        scelto == null
                            ? 'Prova gratis'
                            : scelto.giorniProva > 0
                            ? 'Prova gratis per ${scelto.giorniProva} giorni'
                            : 'Abbonati a ${scelto.prezzo}${_periodo(scelto)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
              if (scelto != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${scelto.giorniProva > 0 ? 'Poi ' : ''}${scelto.prezzo}${_periodo(scelto)}, rinnovo automatico. '
                    'Disdici quando vuoi dal Play Store'
                    '${scelto.giorniProva > 0 ? ': se disdici durante la prova non paghi nulla.' : '.'}',
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
              TextButton(onPressed: p.inCorso ? null : p.ripristina, child: const Text('Ripristina abbonamento')),
              if (piani.isEmpty && !p.inCorso)
                Text(
                  'Premium si attiva dall\'app scaricata dal Play Store.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                ),
              if (p.errore case final e?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    e,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.error),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  static String _periodo(PianoPremium p) => p.id == pianoAnnuale ? '/anno' : '/mese';

  /// «−44%» rispetto a dodici mesi pagati uno per uno.
  static String? _risparmio(Map<String, PianoPremium> piani) {
    double? euro(String? prezzo) =>
        prezzo == null ? null : double.tryParse(prezzo.replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.'));
    final m = euro(piani[pianoMensile]?.prezzo), a = euro(piani[pianoAnnuale]?.prezzo);
    if (m == null || a == null || m <= 0) return null;
    final r = (100 * (1 - a / (m * 12))).round();
    return r > 0 ? 'Risparmi il $r%' : null;
  }
}

class _Piano extends StatelessWidget {
  const _Piano({required this.piano, required this.scelto, required this.onTap, this.nota});

  final PianoPremium piano;
  final bool scelto;
  final String? nota;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scelto ? s.primary : s.outlineVariant, width: scelto ? 2 : 1),
        ),
        child: InkWell(
          key: Key('piano-${piano.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                Icon(scelto ? Icons.radio_button_checked : Icons.radio_button_off, color: scelto ? s.primary : null),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        piano.id == pianoAnnuale ? 'Annuale' : 'Mensile',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (nota != null) Text(nota!, style: t.bodySmall?.copyWith(color: s.primary)),
                    ],
                  ),
                ),
                Text(
                  '${piano.prezzo}${piano.id == pianoAnnuale ? '/anno' : '/mese'}',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Voce extends StatelessWidget {
  const _Voce({required this.icona, required this.titolo, required this.testo});

  final IconData icona;
  final String titolo;
  final String testo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icona, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titolo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(testo, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dal menu, o toccando una funzione bloccata.
class SchermataPremium extends StatelessWidget {
  const SchermataPremium({super.key, required this.premium, this.perche});

  final GestorePremium premium;
  final String? perche;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Premium')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [PannelloPremium(premium: premium, perche: perche)],
    ),
  );
}
