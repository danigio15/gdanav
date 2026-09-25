import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_luoghi.dart';

/// Un file scelto: nome e contenuto.
typedef FileScelto = ({String nome, List<int> byte});

/// I posti salvati dentro i file di Google Takeout: lo zip intero, o i
/// singoli JSON e CSV.
List<LuogoGoogle> postiDaiFile(List<FileScelto> file) {
  final posti = <LuogoGoogle>[];
  void leggi(String nome, List<int> byte) {
    final basso = nome.toLowerCase();
    if (!basso.endsWith('.json') && !basso.endsWith('.csv') && !basso.endsWith('.geojson')) return;
    try {
      posti.addAll(ImportaGoogle.leggi(utf8.decode(byte, allowMalformed: true), nomeFile: nome));
    } catch (_) {
      // Un file che non è dei posti salvati: si salta.
    }
  }

  for (final f in file) {
    if (f.nome.toLowerCase().endsWith('.zip')) {
      final zip = ZipDecoder().decodeBytes(f.byte);
      for (final dentro in zip.files) {
        if (dentro.isFile) leggi(dentro.name, dentro.content);
      }
    } else {
      leggi(f.nome, f.byte);
    }
  }
  return posti;
}

/// «Importa da Google Maps»: come esportare da Google Takeout, la scelta
/// del file, e i posti che entrano nei preferiti (quelli senza coordinate si
/// cercano per nome).
class ImportaGoogleMaps extends StatefulWidget {
  const ImportaGoogleMaps({super.key, required this.luoghi, required this.fonte, this.scegliFile, this.vicinoA});

  final GestoreLuoghi luoghi;
  final FonteLuoghi fonte;
  final Punto? vicinoA;

  /// Chi fa scegliere i file (nelle prove, finto).
  final Future<List<FileScelto>> Function()? scegliFile;

  @override
  State<ImportaGoogleMaps> createState() => _ImportaGoogleMapsState();
}

class _ImportaGoogleMapsState extends State<ImportaGoogleMaps> {
  List<LuogoGoogle>? _posti;
  String? _errore;
  (int, int)? _avanzamento;
  ({int entrati, List<LuogoGoogle> mancanti})? _fatto;

  static const _indirizzo = 'takeout.google.com';

  Future<List<FileScelto>> _scegli() async {
    final scelti = await FilePicker.pickFiles(dialogTitle: 'Il file di Google Takeout');
    return [for (final f in scelti) (nome: f.name, byte: await f.readAsBytes())];
  }

  Future<void> _file() async {
    setState(() {
      _errore = null;
      _fatto = null;
    });
    try {
      final file = await (widget.scegliFile ?? _scegli)();
      if (file.isEmpty) return;
      final posti = postiDaiFile(file);
      setState(() {
        _posti = posti;
        if (posti.isEmpty) {
          _errore =
              'In questo file non ci sono posti salvati. Scegli lo zip di Google Takeout, o il file '
              '«Luoghi salvati.json» o uno degli elenchi .csv che ci sono dentro.';
        }
      });
    } catch (e) {
      setState(() => _errore = 'Il file non si è potuto leggere: $e');
    }
  }

  Future<void> _importa() async {
    final posti = _posti;
    if (posti == null || posti.isEmpty) return;
    setState(() => _avanzamento = (0, posti.length));
    final r = await ImportaGoogle.risolvi(
      posti,
      widget.fonte,
      vicinoA: widget.vicinoA,
      avanzamento: (fatti, totale) {
        if (mounted) setState(() => _avanzamento = (fatti, totale));
      },
    );
    final entrati = await widget.luoghi.aggiungiTanti([
      for (final (g, l) in r.trovati) Preferito(TipoPreferito.altro, l, nome: g.nome, lista: g.lista),
    ]);
    if (!mounted) return;
    setState(() {
      _avanzamento = null;
      _posti = null;
      _fatto = (entrati: entrati, mancanti: r.mancanti);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final muto = tema.colorScheme.onSurfaceVariant;
    final posti = _posti;
    final av = _avanzamento;
    final fatto = _fatto;

    Widget passo(int n, String testo, {Widget? sotto}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: tema.colorScheme.primary,
            child: Text(
              '$n',
              style: t.labelMedium?.copyWith(color: tema.colorScheme.onPrimary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(testo, style: t.bodyLarge),
                ?sotto,
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Importa da Google Maps')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Porta qui i posti che hai salvato in Google Maps: finiscono fra i preferiti, pronti come mete e tappe.',
            style: t.bodyLarge?.copyWith(color: muto),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: tema.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Column(
                children: [
                  passo(
                    1,
                    'Apri Google Takeout dal browser',
                    sotto: InkWell(
                      onTap: () async {
                        await Clipboard.setData(const ClipboardData(text: 'https://$_indirizzo'));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Indirizzo copiato')));
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _indirizzo,
                              style: t.bodyLarge?.copyWith(
                                color: tema.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.copy_rounded, size: 16, color: tema.colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  passo(2, 'Deseleziona tutto e scegli solo «Salvati» e «Maps (i tuoi luoghi)»'),
                  passo(3, 'Crea l\'esportazione e scarica lo zip sul telefono'),
                  passo(4, 'Qui sotto, scegli lo zip (o i file .json e .csv che ci sono dentro)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (av == null)
            FilledButton.icon(
              key: const Key('scegli-file-google'),
              onPressed: _file,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Scegli il file'),
            ),
          if (_errore case final e?) ...[
            const SizedBox(height: 16),
            Text(e, style: t.bodyMedium?.copyWith(color: tema.colorScheme.error)),
          ],
          if (posti != null && posti.isNotEmpty && av == null) ...[
            const SizedBox(height: 20),
            Text('${posti.length} posti trovati', key: const Key('posti-trovati'), style: t.titleMedium),
            Text(
              [for (final e in _perLista(posti).entries) '${e.key}: ${e.value}'].join(' · '),
              style: t.bodyMedium?.copyWith(color: muto),
            ),
            if (posti.where((p) => p.posizione == null).length case final n when n > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('$n senza coordinate: li cerco per nome.', style: t.bodySmall?.copyWith(color: muto)),
              ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              key: const Key('importa-google'),
              onPressed: _importa,
              icon: const Icon(Icons.bookmark_add_rounded),
              label: Text('Importa ${posti.length} posti'),
            ),
          ],
          if (av != null) ...[
            const SizedBox(height: 20),
            Text('Importo… ${av.$1} di ${av.$2}', style: t.titleMedium),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: av.$2 == 0 ? null : av.$1 / av.$2,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
          if (fatto != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: tema.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fatto.entrati == 1 ? '1 posto nuovo nei preferiti' : '${fatto.entrati} posti nuovi nei preferiti',
                    key: const Key('importati'),
                    style: t.titleMedium,
                  ),
                ),
              ],
            ),
            if (fatto.mancanti.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Non trovati (${fatto.mancanti.length}):', style: t.bodyMedium?.copyWith(color: muto)),
              for (final m in fatto.mancanti.take(30)) Text('· ${m.nome}', style: t.bodyMedium?.copyWith(color: muto)),
            ],
          ],
        ],
      ),
    );
  }

  static Map<String, int> _perLista(List<LuogoGoogle> posti) {
    final m = <String, int>{};
    for (final p in posti) {
      final l = p.lista.isEmpty ? 'Salvati' : p.lista;
      m[l] = (m[l] ?? 0) + 1;
    }
    return m;
  }
}
