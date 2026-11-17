import 'package:flutter/material.dart';

import '../componenti/avviso_di_casa.dart';
import '../componenti/mini_lettore.dart';
import '../stato/gestore_casa_in_guida.dart';

/// «Casa e musica in guida»: gli avvisi di casa sopra la mappa (dentro
/// GdAHome) e il lettore musicale, con i loro interruttori.
///
/// - «Avvisi di casa durante la guida», acceso di serie; sotto, categoria per
///   categoria. Gli urgenti (fumo, acqua, gas, l'allarme) passano sempre, se
///   l'interruttore è acceso.
/// - «Musica nel navigatore», acceso di serie; senza il permesso del
///   telefono, la spiegazione e «Consenti». Su Android, col permesso, «App
///   della musica»: quale app fa partire ▶ quando niente suona (Spotify di
///   serie, se c'è).
///
/// Quello che non arriva al telefono non arriva nemmeno qui: le notifiche si
/// scelgono, casa per casa, nella pagina «Notifiche» di GdAHome.
class NotificheNelNavigatoreSchermata extends StatelessWidget {
  const NotificheNelNavigatoreSchermata({super.key, required this.gestore});

  final GestoreCasaInGuida gestore;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tenue = tema.colorScheme.onSurfaceVariant;
    Widget titolo(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(s, style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.primary)),
    );
    Widget nota(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Text(s, style: tema.textTheme.bodySmall?.copyWith(color: tenue)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(gestore.coda == null ? 'Musica in guida' : 'Casa e musica in guida')),
      body: ListenableBuilder(
        listenable: Listenable.merge([gestore, ?gestore.lettore]),
        builder: (context, _) {
          final scelta = gestore.scelta;
          final accesi = gestore.avvisiAccesi;
          final lettore = gestore.lettore;
          final iPhone = lettore?.fonte == FonteMusica.sistema;
          // Far partire la musica da zero: solo dove si può (Android).
          final avvio = switch (lettore) {
            final AvvioDellaMusica a when a.puoAvviare && lettore!.permesso && gestore.musica => a,
            _ => null,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              if (gestore.coda != null) ...[
                titolo('Avvisi di casa'),
                Card(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    key: const Key('avvisi-di-casa'),
                    secondary: const Icon(Icons.home_rounded),
                    title: const Text('Avvisi di casa durante la guida'),
                    subtitle: const Text('Le notifiche di GdAHome sopra la mappa'),
                    value: accesi,
                    onChanged: gestore.accendiAvvisi,
                  ),
                ),
                nota(
                  'Compaiono sotto la freccia, una alla volta, e spariscono da sole. In movimento: una riga, '
                  'al più due tasti, niente tastiera; se ne arrivano tante diventano «3 notifiche di casa», '
                  'da aprire da fermi. Restano comunque tutte sul telefono.',
                ),
                if (accesi) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final c in CategoriaAvvisoDiCasa.values)
                          SwitchListTile(
                            key: Key('categoria-${c.name}'),
                            secondary: _IconaCategoria(categoria: c),
                            title: Text(c.nome),
                            subtitle: Text(
                              c == CategoriaAvvisoDiCasa.sicurezza ? 'Sempre, con gli avvisi accesi' : c.descrizione,
                            ),
                            value: scelta.accesa(c),
                            onChanged: c == CategoriaAvvisoDiCasa.sicurezza
                                ? null
                                : (v) => gestore.cambiaScelta(scelta.conCategoria(c, v)),
                          ),
                      ],
                    ),
                  ),
                  nota(
                    'Gli urgenti (fumo, acqua, gas, l\'allarme che suona) passano sempre davanti e restano finché '
                    'non li tocchi. Aprire il cancello o disinserire l\'antifurto chiede prima «Sì / No», e poi '
                    'passa dalle stesse regole dei tasti delle notifiche (il lucchetto di GdAHome, se acceso); '
                    'quello che apre l\'app si fa da fermi.',
                  ),
                ],
              ],
              titolo('Musica'),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  key: const Key('musica-nel-navigatore'),
                  secondary: const Icon(Icons.headphones_rounded),
                  title: const Text('Musica nel navigatore'),
                  subtitle: Text(
                    iPhone
                        ? 'Il brano e i comandi della Musica di Apple'
                        : 'Il brano e i comandi dell\'app che suona: Spotify, YouTube Music…',
                  ),
                  value: gestore.musica,
                  onChanged: lettore == null ? null : gestore.cambiaMusica,
                ),
              ),
              if (gestore.musica && lettore != null && !lettore.permesso)
                _Spiegazione(
                  key: const Key('spiegazione-musica'),
                  icona: iPhone ? Icons.library_music_rounded : Icons.notifications_rounded,
                  testo: iPhone
                      ? 'Per vedere il brano e cambiarlo, l\'iPhone chiede l\'accesso a Musica. GdANav lo usa solo '
                            'per il lettore in guida: non legge né cambia la tua libreria.'
                      : 'Per vedere il brano e cambiarlo, Android chiede «Accesso alle notifiche». GdANav lo usa '
                            'solo per il lettore musicale: non legge né conserva i tuoi messaggi.',
                  tasto: 'Consenti',
                  onTap: lettore.chiediPermesso,
                ),
              if (avvio != null) ...[
                titolo('App della musica'),
                Card(
                  key: const Key('app-della-musica'),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SceltaAppDellaMusica(avvio: avvio, conDettagli: true),
                  ),
                ),
                nota(
                  'Quando niente suona, il tasto play del navigatore (sul telefono e in Android Auto) fa partire '
                  'questa app, anche se è chiusa, e di solito riprende da dove eri. Se non parte, sul telefono da '
                  'fermo si apre l\'app; in auto mai.',
                ),
              ],
              nota(
                iPhone
                    ? 'Sull\'iPhone un\'app non può comandare le altre né farle partire: qui si vede la Musica '
                          'di Apple. Spotify arriverà più avanti. In CarPlay «Play/pausa» e «Avanti» stanno nella '
                          'barra del navigatore; il brano lo mostra la scheda «In riproduzione» di CarPlay.'
                    : 'In Android Auto il brano e i tasti stanno nel lettore in alto sulla mappa (o fra i tasti del '
                          'navigatore, sulle auto che non si toccano); i comandi completi restano quelli dell\'auto.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IconaCategoria extends StatelessWidget {
  const _IconaCategoria({required this.categoria});

  final CategoriaAvvisoDiCasa categoria;

  @override
  Widget build(BuildContext context) {
    final (:icona, :colore) = aspettoPer(categoria);
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colore.withValues(alpha: scuro ? 0.28 : 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icona, color: scuro ? Colors.white : colore),
    );
  }
}

class _Spiegazione extends StatelessWidget {
  const _Spiegazione({super.key, required this.icona, required this.testo, required this.tasto, this.onTap});

  final IconData icona;
  final String testo;
  final String tasto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: tema.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icona, size: 20, color: tema.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(testo, style: tema.textTheme.bodyMedium)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(onPressed: onTap, child: Text(tasto)),
          ),
        ],
      ),
    );
  }
}
