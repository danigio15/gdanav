import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../stato/archivio.dart';
import '../stato/voce.dart';

/// La frase di prova: una manovra vera, così si sente come suonerà in guida.
const fraseDiProva = 'Tra duecento metri, alla rotonda prendi la seconda uscita.';

/// «Voce di guida»: quale voce parla, quanto forte e quanto veloce.
///
/// «Volevo provare a cambiare la voce, quella che c'è è un po' fastidiosa.»
/// Si parlava sempre con la voce italiana predefinita del telefono, e volume
/// e velocità si sceglievano solo dal menu dell'auto. Qui le voci italiane
/// che il telefono ha: toccandone una la si sceglie e la si sente.
class VoceGuidaSchermata extends StatefulWidget {
  const VoceGuidaSchermata({super.key, this.archivio, this.voci, this.prova});

  final Archivio? archivio;

  /// Le voci italiane del telefono; nelle prove un elenco finto.
  final Future<List<VoceDelTelefono>> Function()? voci;

  /// Fa sentire una voce; nelle prove si annota e basta.
  final Future<void> Function(VoceDelTelefono? voce)? prova;

  @override
  State<VoceGuidaSchermata> createState() => _VoceGuidaSchermataState();
}

class _VoceGuidaSchermataState extends State<VoceGuidaSchermata> {
  FlutterTts? _tts;
  late final Future<List<VoceDelTelefono>> _voci = (widget.voci ?? () => vociItalianeDelTelefono(_sintesi))();

  FlutterTts get _sintesi => _tts ??= FlutterTts();

  @override
  void dispose() {
    final tts = _tts;
    if (tts != null) unawaited(tts.stop().catchError((_) => null));
    super.dispose();
  }

  Future<void> _senti(VoceDelTelefono? v) => (widget.prova ?? (v) => VoceTelefono.prova(_sintesi, v, fraseDiProva))(v);

  void _scegli(VoceDelTelefono? v) {
    voceScelta.value = v;
    unawaited(widget.archivio?.salvaVoceDiGuida(v));
    unawaited(_senti(v));
  }

  void _regola((VolumeVoce, VelocitaVoce) r) {
    regolazioniVoce.value = r;
    unawaited(widget.archivio?.salvaRegolazioniDellaVoce(r));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Voce di guida')),
      body: ListenableBuilder(
        listenable: Listenable.merge([voceScelta, regolazioniVoce]),
        builder: (context, _) {
          final (volume, velocita) = regolazioniVoce.value;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Titolo('Volume'),
              SegmentedButton<VolumeVoce>(
                key: const Key('voce-volume'),
                segments: [for (final v in VolumeVoce.values) ButtonSegment(value: v, label: Text(v.nome))],
                selected: {volume},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _regola((s.first, velocita)),
              ),
              const SizedBox(height: 16),
              _Titolo('Velocità'),
              SegmentedButton<VelocitaVoce>(
                key: const Key('voce-velocita'),
                segments: [for (final v in VelocitaVoce.values) ButtonSegment(value: v, label: Text(v.nome))],
                selected: {velocita},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _regola((volume, s.first)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: _Titolo('Voce')),
                  TextButton.icon(
                    key: const Key('voce-ascolta'),
                    onPressed: () => unawaited(_senti(voceScelta.value)),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('Ascolta'),
                  ),
                ],
              ),
              FutureBuilder<List<VoceDelTelefono>>(
                future: _voci,
                builder: (context, s) {
                  if (s.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final voci = s.data ?? const <VoceDelTelefono>[];
                  final scelta = voceScelta.value;
                  return Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: RadioGroup<VoceDelTelefono?>(
                      groupValue: scelta != null && voci.contains(scelta) ? scelta : null,
                      onChanged: _scegli,
                      child: Column(
                        children: [
                          _RigaVoce(
                            key: const Key('voce-predefinita'),
                            voce: null,
                            titolo: 'Predefinita del telefono',
                            sotto: 'Quella scelta nelle impostazioni del telefono',
                            onTap: () => _scegli(null),
                          ),
                          for (final v in voci)
                            _RigaVoce(
                              key: Key('voce-${v.nome}'),
                              voce: v,
                              titolo: v.etichetta,
                              sotto: v.dettaglio,
                              onTap: () => _scegli(v),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                defaultTargetPlatform == TargetPlatform.iOS
                    ? 'Altre voci, più naturali: Impostazioni › Accessibilità › Contenuto letto ad alta voce › '
                          'Voci › Italiano. Scaricate, compaiono qui.'
                    : 'Altre voci: Impostazioni › Accessibilità (o Sistema › Lingue) › Output sintesi vocale › '
                          'Motore preferito › Installa dati vocali › Italiano. Scaricate, compaiono qui.',
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Titolo extends StatelessWidget {
  const _Titolo(this.testo);
  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(testo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
  );
}

class _RigaVoce extends StatelessWidget {
  const _RigaVoce({super.key, required this.voce, required this.titolo, required this.sotto, required this.onTap});

  final VoceDelTelefono? voce;
  final String titolo;
  final String sotto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Radio<VoceDelTelefono?>(value: voce),
    title: Text(titolo),
    subtitle: sotto.isEmpty ? null : Text(sotto),
    onTap: onTap,
  );
}
