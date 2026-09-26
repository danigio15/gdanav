import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_auto.dart';
import '../stato/gestore_consumo.dart';
import '../componenti/indicatore_batteria.dart';
import 'esplora_auto.dart';
import 'scegli_dongle.dart';

/// Lo switch «Fonte dati auto»: Automatica, oppure una sorgente fissa.
Future<void> mostraFonteDatiAuto(BuildContext context, GestoreAuto gestore, {GestoreConsumo? consumo}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: FonteDatiAuto(gestore: gestore, consumo: consumo),
    ),
  );
}

class FonteDatiAuto extends StatelessWidget {
  const FonteDatiAuto({super.key, required this.gestore, this.consumo});

  final GestoreAuto gestore;

  /// Il consumo imparato: per dire quanto è preciso il calcolo.
  final GestoreConsumo? consumo;

  static const _scelte = [
    TipoSorgente.androidAuto,
    TipoSorgente.obd,
    TipoSorgente.gdahome,
    TipoSorgente.homeAssistant,
    TipoSorgente.manuale,
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gestore,
      builder: (context, _) {
        final m = gestore.modalita;
        final scelta = switch (m) {
          Automatica() => null,
          Fissa(:final sorgente) => sorgente,
        };
        return SafeArea(
          child: RadioGroup<TipoSorgente?>(
            groupValue: scelta,
            onChanged: (t) => gestore.cambiaModalita(t == null ? const Automatica() : Fissa(t)),
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Fonte dati auto', style: Theme.of(context).textTheme.titleLarge),
                ),
                RadioListTile<TipoSorgente?>(
                  value: null,
                  title: const Text('Automatica'),
                  subtitle: Text(
                    gestore.gdahome == null
                        ? 'Auto, poi OBD, poi Home Assistant se recente, poi stima'
                        : 'Auto, poi OBD, poi gdahome e Home Assistant se recenti, poi stima',
                  ),
                ),
                for (final t in _scelte)
                  // gdahome c'è solo dentro l'app gdahome.
                  if (t != TipoSorgente.gdahome || gestore.gdahome != null)
                    RadioListTile<TipoSorgente?>(
                      value: t,
                      title: Text(nomeSorgente(t)),
                      subtitle: gestore.disponibili.contains(t) ? null : const Text('Non collegata'),
                    ),
                const Divider(),
                _Dongle(gestore: gestore),
                const Divider(),
                _BatteriaManuale(gestore: gestore),
                const Divider(),
                DatiUsati(stato: gestore.stato),
                if (consumo case final c?) ...[
                  const Divider(),
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => PrecisioneConsumo(imparato: c.imparato),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BatteriaManuale extends StatefulWidget {
  const _BatteriaManuale({required this.gestore});

  final GestoreAuto gestore;

  @override
  State<_BatteriaManuale> createState() => _BatteriaManualeState();
}

class _BatteriaManualeState extends State<_BatteriaManuale> {
  late double _valore = widget.gestore.stato?.batteria.roundToDouble() ?? 80;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: _valore,
              max: 100,
              divisions: 100,
              label: '${_valore.round()}%',
              onChanged: (v) => setState(() => _valore = v),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => widget.gestore.manuale.imposta(_valore),
            child: Text('Batteria ${_valore.round()}%'),
          ),
        ],
      ),
    );
  }
}

/// Il dongle OBD: quale, se dà dati, e come cambiarlo.
class _Dongle extends StatelessWidget {
  const _Dongle({required this.gestore});

  final GestoreAuto gestore;

  @override
  Widget build(BuildContext context) {
    final d = gestore.dongle;
    void scegli() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScegliDongle(auto: gestore)));
    if (d == null) {
      return ListTile(
        leading: const Icon(Icons.cable),
        title: const Text('Dongle OBD Bluetooth'),
        subtitle: const Text('Batteria, velocità e temperatura dalla presa OBD, come ABRP'),
        trailing: const Icon(Icons.chevron_right),
        onTap: scegli,
      );
    }
    final dati = gestore.stato?.sorgente == TipoSorgente.obd;
    return ListTile(
      leading: const Icon(Icons.cable),
      title: Text(d.nome.isEmpty ? 'Dongle OBD' : d.nome),
      subtitle: Text(dati ? 'Dà i dati dell\'auto' : (gestore.erroreObd ?? 'In attesa dell\'auto accesa')),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => switch (v) {
          'esplora' => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EsploraAuto(auto: gestore))),
          'cambia' => scegli(),
          _ => gestore.togliDongle(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'esplora', child: Text("Esplora l'auto")),
          PopupMenuItem(value: 'cambia', child: Text('Cambia dongle')),
          PopupMenuItem(value: 'togli', child: Text('Togli')),
        ],
      ),
    );
  }
}

/// Quali dati dell'auto arrivano adesso, e a cosa servono.
class DatiUsati extends StatelessWidget {
  const DatiUsati({super.key, required this.stato});

  final StatoAuto? stato;

  static String _n(double v, [int cifre = 0]) => v.toStringAsFixed(cifre).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final s = stato;
    final righe = <(IconData, String, String?, String)>[
      (Icons.battery_std, 'Batteria', s == null ? null : '${s.batteria.round()}%', 'partenza, soste, arrivo'),
      (
        Icons.route,
        'Autonomia',
        s?.autonomiaKm == null ? null : '${s!.autonomiaKm!.round()} km',
        'confronto col calcolo',
      ),
      (
        Icons.ev_station,
        'In carica',
        s?.inCarica == null ? null : (s!.inCarica! ? 'sì' : 'no'),
        'non si misura il consumo mentre carica',
      ),
      (
        Icons.bolt,
        'Potenza di carica',
        s?.potenzaCaricaKw == null ? null : '${_n(s!.potenzaCaricaKw!, 1)} kW',
        'tempi di ricarica',
      ),
      (
        Icons.thermostat,
        'Temperatura esterna',
        s?.temperaturaEsternaC == null ? null : '${_n(s!.temperaturaEsternaC!)} °C',
        'consumo del clima e aria più densa',
      ),
      (
        Icons.device_thermostat,
        'Temperatura batteria',
        s?.temperaturaBatteriaC == null ? null : '${_n(s!.temperaturaBatteriaC!)} °C',
        'ricarica più lenta a freddo',
      ),
      (Icons.speed, 'Velocità', s?.velocitaKmh == null ? null : '${s!.velocitaKmh!.round()} km/h', 'tachimetro'),
      (
        Icons.electric_bolt,
        'Potenza in uso',
        s?.potenzaKw == null ? null : '${_n(s!.potenzaKw!, 1)} kW',
        'consumo istantaneo',
      ),
      (Icons.pin, 'Contachilometri', s?.odometroKm == null ? null : '${s!.odometroKm!.round()} km', 'km misurati'),
      (Icons.place, 'Posizione dell\'auto', s?.latitudine == null ? null : 'sì', 'partenza quando non sei in auto'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dati che arrivano dall\'auto', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            s == null
                ? 'Nessun dato: gdanav stima la batteria.'
                : 'Da ${nomeSorgente(s.sorgente)} · ${eta(DateTime.now().difference(s.letto))}',
            style: t.bodySmall?.copyWith(color: muto),
          ),
          const SizedBox(height: 6),
          for (final (icona, nome, valore, uso) in righe)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(icona, size: 20, color: valore == null ? muto.withValues(alpha: 0.5) : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nome, style: t.bodyMedium?.copyWith(color: valore == null ? muto : null)),
                        Text(uso, style: t.bodySmall?.copyWith(color: muto)),
                      ],
                    ),
                  ),
                  Text(
                    valore ?? 'non arriva',
                    style: valore == null
                        ? t.bodySmall?.copyWith(color: muto)
                        : t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Quanto il calcolo del consumo ci prende, per tipo di strada: previsto
/// contro misurato dalla batteria vera.
class PrecisioneConsumo extends StatelessWidget {
  const PrecisioneConsumo({super.key, required this.imparato});

  final ConsumoImparato imparato;

  static String _n(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Precisione del consumo', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            'Il consumo previsto per ogni tratto confrontato con quello vero della batteria, '
            'ogni 2 punti di batteria. Dopo ${ConsumoStrada.kmPerFidarsi.round()} km un tipo di strada '
            'ha il suo correttivo.',
            style: t.bodySmall?.copyWith(color: muto),
          ),
          const SizedBox(height: 8),
          for (final tipo in TipoStrada.values)
            _Strada(tipo: tipo, s: imparato.strade[tipo], generale: imparato.fattore, n: _n, muto: muto),
          const SizedBox(height: 4),
          Text(
            imparato.kmOsservati == 0
                ? 'Ancora nessun km misurato: si usa la scheda tecnica dell\'auto.'
                : 'In tutto ${imparato.kmOsservati.round()} km misurati · correttivo generale '
                      '${imparato.scartoPercento >= 0 ? '+' : ''}${imparato.scartoPercento}%',
            style: t.bodySmall?.copyWith(color: muto),
          ),
        ],
      ),
    );
  }
}

class _Strada extends StatelessWidget {
  const _Strada({required this.tipo, required this.s, required this.generale, required this.n, required this.muto});

  final TipoStrada tipo;
  final ConsumoStrada? s;
  final double generale;
  final String Function(double) n;
  final Color muto;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = this.s;
    final precisione = s?.precisionePercento;
    final String dettaglio;
    if (s == null || s.km == 0) {
      dettaglio = 'Ancora nessuna misura';
    } else {
      final correttivo = ((s.fattore - 1) * 100).round();
      dettaglio =
          '${s.km.round()} km · previsto ${n(s.previstoKwh100!)} · vero ${n(s.realeKwh100!)} kWh/100 km\n'
          '${s.affidabile ? 'Correttivo ${correttivo >= 0 ? '+' : ''}$correttivo%' : 'Correttivo suo tra ${(ConsumoStrada.kmPerFidarsi - s.km).ceil()} km'}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(switch (tipo) {
            TipoStrada.urbana => Icons.location_city,
            TipoStrada.extraurbana => Icons.landscape_outlined,
            TipoStrada.autostrada => Icons.add_road,
          }, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tipo.nome} (${tipo.velocita})', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(dettaglio, style: t.bodySmall?.copyWith(color: muto)),
              ],
            ),
          ),
          Text(
            precisione == null ? '–' : '${precisione.round()}%',
            key: Key('precisione-${tipo.name}'),
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
