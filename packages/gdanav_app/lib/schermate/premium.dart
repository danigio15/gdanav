import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../stato/gestore_premium.dart';

/// Cosa comprende Premium, i due piani e il bottone per la prova. Si usa da
/// solo (dal menu) e al posto delle funzioni bloccate.
class PannelloPremium extends StatefulWidget {
  const PannelloPremium({super.key, required this.premium, this.perche});

  final GestorePremium premium;

  /// Cosa si stava cercando di aprire: «Android Auto», «Il traffico».
  final String? perche;

  static const privacy = 'https://gdanav.gdahome.org/privacy';

  /// Le condizioni d'uso: quelle standard di Apple (EULA), valide anche per
  /// Google Play finché gdanav non ne ha di sue.
  static const condizioni = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  /// Lo schermo dell'auto: Android Auto o, su iPhone, CarPlay. Solo quello
  /// della piattaforma: l'App Store non vuole nomi di Android nell'app.
  static String get schermoAuto => defaultTargetPlatform == TargetPlatform.iOS ? 'CarPlay' : 'Android Auto';

  /// Cosa comprende Premium: solo quello che c'è davvero.
  static List<(IconData, String, String)> get funzioni => <(IconData, String, String)>[
    (
      Icons.home_outlined,
      'Home Assistant e batteria letta dall\'auto',
      'Dall\'auto, dal dongle OBD, da gdahome o da Home Assistant: niente da scrivere a mano',
    ),
    (
      Icons.ev_station,
      'Percorso con le soste alle colonnine',
      'Dove fermarti e quanto caricare, con le colonnine libere o occupate in tempo reale',
    ),
    (Icons.directions_car_filled, schermoAuto, 'Mappa, guida e soste sullo schermo dell\'auto'),
  ];

  /// Quello che resta gratis per tutti, detto una volta.
  static const perTutti =
      'Gratis per tutti: l\'auto termica completa, l\'elettrica con la batteria scritta a mano, '
      'traffico, autovelox e meteo.';

  @override
  State<PannelloPremium> createState() => _PannelloPremiumState();
}

class _PannelloPremiumState extends State<PannelloPremium> {
  var _scelto = pianoAnnuale;

  String _stato(GestorePremium p) {
    if (p.daOspite) {
      return p.sbloccato
          ? 'Premium è attivo con gdahome: tutto sbloccato.'
          : '${widget.perche ?? 'Questo'} fa parte del Premium di gdahome: attivalo dall\'app gdahome.';
    }
    if (p.sbloccato) {
      final l = p.licenza;
      if (l != null && !p.negozioAttivo) {
        return l.scade == null
            ? 'Premium è attivo con un codice regalo, per sempre.'
            : 'Premium è attivo con un codice regalo, fino al ${_data(l.scade!)}.';
      }
      return 'Premium è attivo: grazie!';
    }
    return widget.perche == null
        ? 'Per chi vuole la batteria vera e le soste di ricarica, con 14 giorni di prova gratuita.'
        : '${widget.perche} fa parte di Premium: provalo gratis per 14 giorni.';
  }

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.premium,
      builder: (context, _) {
        final p = widget.premium;
        // Senza il negozio (niente rete, app non scaricata dal negozio) i
        // prezzi si mostrano lo stesso, quelli di listino: comprare no.
        final dalNegozio = p.piani.isNotEmpty;
        final piani = {for (final x in dalNegozio ? p.piani : pianiDiListino) x.id: x};
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
            Text(_stato(p), key: const Key('stato-premium'), style: t.bodyLarge),
            const SizedBox(height: 12),
            for (final (icona, titolo, testo) in PannelloPremium.funzioni)
              _Voce(icona: icona, titolo: titolo, testo: testo),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: s.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(PannelloPremium.perTutti, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!p.sbloccato && !p.daOspite) ...[
              for (final id in [pianoAnnuale, pianoMensile])
                if (piani[id] case final piano?)
                  _Piano(
                    piano: piano,
                    scelto: scelto?.id == id,
                    nota: id == pianoAnnuale ? _risparmio(piani) : null,
                    onTap: () => setState(() => _scelto = id),
                  ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('compra-premium'),
                onPressed: p.inCorso || !dalNegozio || scelto == null ? null : () => p.compra(scelto.id),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: p.inCorso
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        scelto == null || !dalNegozio
                            ? 'Prova gratis'
                            : scelto.giorniProva > 0
                            ? 'Prova gratis per ${scelto.giorniProva} giorni'
                            : 'Abbonati a ${scelto.prezzo}${_periodo(scelto)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
              if (scelto != null && dalNegozio)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${scelto.giorniProva > 0 ? 'Poi ' : ''}${scelto.prezzo}${_periodo(scelto)}, rinnovo automatico. '
                    'Disdici quando vuoi dal$_negozio'
                    '${scelto.giorniProva > 0 ? ': se disdici durante la prova non paghi nulla.' : '.'}',
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
              if (!dalNegozio && !p.inCorso)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$_ilNegozio non risponde: Premium si attiva dall\'app scaricata dal$_negozio.',
                    key: const Key('negozio-assente'),
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
              TextButton(onPressed: p.inCorso ? null : p.ripristina, child: const Text('Ripristina abbonamento')),
            ],
            // Il codice regalo: gdanav da sola, anche con Premium già attivo
            // (per allungarlo), mai dentro gdahome (lì si riscatta per la casa).
            if (p.codiciRegalo)
              OutlinedButton.icon(
                key: const Key('codice-regalo'),
                onPressed: p.riscattoInCorso ? null : () => chiediCodiceRegalo(context, p),
                icon: const Icon(Icons.redeem),
                label: const Text('Ho un codice regalo'),
              ),
            if (!p.sbloccato && !p.daOspite)
              // L'App Store vuole i due link accanto all'abbonamento.
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(onPressed: () => _apri(PannelloPremium.privacy), child: const Text('Privacy')),
                  TextButton(
                    onPressed: () => _apri(PannelloPremium.condizioni),
                    child: const Text('Condizioni d\'uso'),
                  ),
                ],
              ),
            if (p.errore case final e? when !p.daOspite)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  e,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: s.error),
                ),
              ),
          ],
        );
      },
    );
  }

  static Future<void> _apri(String indirizzo) async {
    try {
      await launchUrl(Uri.parse(indirizzo), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// « Play Store» o «l'App Store», dopo «dal».
  static String get _negozio => nomeNegozio == 'App Store' ? 'l\'App Store' : ' $nomeNegozio';

  /// «Il Play Store», «L'App Store»: a inizio frase.
  static String get _ilNegozio => nomeNegozio == 'App Store' ? 'L\'App Store' : 'Il $nomeNegozio';

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

/// «Ho un codice regalo»: si scrive il codice, il quadro lo riscatta per
/// questo telefono. `true` se Premium ora è attivo.
Future<bool> chiediCodiceRegalo(BuildContext context, GestorePremium premium) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _CodiceRegalo(premium: premium),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Codice riscattato: Premium è attivo.')));
  }
  return ok == true;
}

class _CodiceRegalo extends StatefulWidget {
  const _CodiceRegalo({required this.premium});

  final GestorePremium premium;

  @override
  State<_CodiceRegalo> createState() => _CodiceRegaloState();
}

class _CodiceRegaloState extends State<_CodiceRegalo> {
  final _testo = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.premium.erroreCodice = null;
  }

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  Future<void> _riscatta() async {
    final ok = await widget.premium.riscattaCodice(_testo.text);
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.premium,
    builder: (context, _) {
      final p = widget.premium;
      return AlertDialog(
        title: const Text('Codice regalo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Il codice che ti hanno dato, per attivare Premium su questo telefono.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('campo-codice'),
              controller: _testo,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'GDA-XXXX-XXXX-XXXX',
                border: const OutlineInputBorder(),
                errorText: p.erroreCodice,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _riscatta(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const Key('riscatta-codice'),
            onPressed: p.riscattoInCorso ? null : _riscatta,
            child: p.riscattoInCorso
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Riscatta'),
          ),
        ],
      );
    },
  );
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
