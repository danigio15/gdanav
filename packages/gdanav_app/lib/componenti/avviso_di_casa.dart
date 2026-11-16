/// Gli avvisi di casa sopra la mappa in guida: **tutte** le notifiche che
/// arrivano a GdAHome — la lavatrice finita, l'antifurto inserito, l'auto
/// carica, chi arriva a casa, il campanello, il fumo. Li manda chi ospita
/// GdANav (GdAHome), quando gli arriva una notifica della casa; GdANav li
/// riconosce, li riduce per la guida e li mostra.
///
/// Qui il modello, la coda, la scheda e le regole. Chi la riempie è GdAHome:
/// passa a `preparaGdanav` le notifiche aperte dal suo postino, e
/// `GestoreCasaInGuida` le trasforma con [AvvisoDiCasa.daNotifica]. Lo schermo
/// dell'auto le riceve da `PonteAuto` (Android Auto con `Alert`, CarPlay con
/// `CPNavigationAlert`): al più due tasti, niente tasti «da fermo».
///
/// ## Il modello
///
/// Ogni notifica ha una [CategoriaAvvisoDiCasa] (decide l'icona, il colore e
/// l'interruttore nelle impostazioni) e un'[UrgenzaAvvisoDiCasa]:
///
/// - **info** (la lavatrice, l'antifurto inserito, Marta arrivata): una scheda
///   chiara che sparisce da sola dopo [CodaAvvisiDiCasa.durata], in silenzio;
/// - **importante** (il campanello, una finestra aperta con la casa vuota):
///   resta il doppio, con il bordo colorato e la frase a voce;
/// - **urgente** (fumo, acqua, gas, l'allarme che suona): rossa, passa davanti
///   a tutto e resta finché non la si tocca.
///
/// ## Le regole in guida
///
/// - una scheda alla volta, sotto la manovra e il «Poi»: la freccia e la
///   prossima svolta restano sempre in vista;
/// - un titolo e una riga di testo, al più due tasti grandi; niente tastiera;
/// - un tasto che apre qualcosa da lontano (il cancello, l'antifurto) chiede
///   prima «Sì / No», sempre con un tocco solo; uno che vuole il codice o apre
///   l'app (`apre` / `pin` nella notifica) si vede solo da fermi;
/// - se ne arrivano tante ([CodaAvvisiDiCasa.raggruppaDa]) diventano una
///   scheda sola, «3 notifiche di casa», che si apre solo da fermi.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'vetro.dart';

/// Di cosa parla l'avviso: decide l'icona, il colore e l'interruttore.
enum CategoriaAvvisoDiCasa {
  elettrodomestici('Elettrodomestici', 'Lavatrice, asciugatrice, lavastoviglie, forno finiti'),
  antifurto('Antifurto', 'Inserito, disinserito, movimento con la casa vuota'),
  aperture('Porte e finestre', 'Porte, finestre, cancello e garage rimasti aperti'),
  persone('Persone', 'Chi arriva a casa e chi esce'),
  energia('Energia', 'Fotovoltaico, corrente di rete, auto in carica'),
  clima('Clima', 'Riscaldamento, condizionatore, temperatura'),
  meteo('Meteo e allerte', 'Pioggia, vento, allerta meteo'),
  sicurezza('Fumo, acqua, gas', 'Gli allarmi di sicurezza'),
  campanello('Campanello e citofono', 'Chi suona alla porta o al cancello'),
  aggiornamenti('Aggiornamenti', 'L\'app o la casa da aggiornare'),
  altre('Altre notifiche', 'Le automazioni di Home Assistant e il resto');

  const CategoriaAvvisoDiCasa(this.nome, this.descrizione);

  final String nome;
  final String descrizione;
}

/// Quanto conta: decide il colore, il tempo in vista, la voce e la coda.
enum UrgenzaAvvisoDiCasa { info, importante, urgente }

/// «Notifiche nel navigatore»: tutte (di serie), quelle scelte, nessuna.
enum NotificheNelNavigatore { tutte, scelte, nessuna }

/// Quali avvisi passano: il modo e, con «scelte», le categorie spente.
///
/// Con «scelte» gli urgenti passano sempre (fumo, acqua, gas, l'allarme che
/// suona): li ferma solo «nessuna».
@immutable
class SceltaAvvisiDiCasa {
  const SceltaAvvisiDiCasa({this.modo = NotificheNelNavigatore.tutte, this.spente = const {}});

  static const nessuna = SceltaAvvisiDiCasa(modo: NotificheNelNavigatore.nessuna);

  final NotificheNelNavigatore modo;
  final Set<CategoriaAvvisoDiCasa> spente;

  /// Se la categoria è accesa (nella pagina delle impostazioni).
  bool accesa(CategoriaAvvisoDiCasa c) => switch (modo) {
    NotificheNelNavigatore.tutte => true,
    NotificheNelNavigatore.nessuna => false,
    NotificheNelNavigatore.scelte => c == CategoriaAvvisoDiCasa.sicurezza || !spente.contains(c),
  };

  bool mostra(AvvisoDiCasa a) => switch (modo) {
    NotificheNelNavigatore.nessuna => false,
    NotificheNelNavigatore.tutte => true,
    NotificheNelNavigatore.scelte => a.urgente || accesa(a.categoria),
  };

  SceltaAvvisiDiCasa conModo(NotificheNelNavigatore modo) => SceltaAvvisiDiCasa(modo: modo, spente: spente);

  /// Un interruttore toccato: si passa a «scelte».
  SceltaAvvisiDiCasa conCategoria(CategoriaAvvisoDiCasa c, bool accesa) =>
      SceltaAvvisiDiCasa(modo: NotificheNelNavigatore.scelte, spente: {...spente.where((x) => x != c), if (!accesa) c});

  Map<String, Object> inJson() => {
    'modo': modo.name,
    'spente': [for (final c in spente) c.name],
  };

  static SceltaAvvisiDiCasa leggi(Object? grezzo) {
    if (grezzo is! Map) return const SceltaAvvisiDiCasa();
    final spente = grezzo['spente'];
    return SceltaAvvisiDiCasa(
      modo: NotificheNelNavigatore.values.asNameMap()[grezzo['modo']] ?? NotificheNelNavigatore.tutte,
      spente: {
        if (spente is List)
          for (final s in spente) ?CategoriaAvvisoDiCasa.values.asNameMap()[s],
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceltaAvvisiDiCasa &&
      other.modo == modo &&
      other.spente.length == spente.length &&
      other.spente.containsAll(spente);

  @override
  int get hashCode => Object.hash(modo, Object.hashAllUnordered(spente));
}

/// Un tasto sotto l'avviso. [domanda]: se c'è, prima di farlo si chiede
/// («Aprire il cancello?» Sì / No). [daFermo]: vuole il codice o apre l'app,
/// e in movimento non si mostra.
class AzioneAvvisoDiCasa {
  const AzioneAvvisoDiCasa(this.id, this.etichetta, {this.principale = false, this.domanda, this.daFermo = false});

  final String id;
  final String etichetta;
  final bool principale;
  final String? domanda;
  final bool daFermo;
}

/// Un avviso di casa, già ridotto per la guida.
class AvvisoDiCasa {
  AvvisoDiCasa({
    required this.id,
    required this.categoria,
    required this.titolo,
    this.urgenza = UrgenzaAvvisoDiCasa.info,
    this.sotto,
    this.testo = '',
    this.casa,
    List<AzioneAvvisoDiCasa> azioni = const [],
    this.voce,
  }) : azioni = List.unmodifiable(azioni.take(3));

  /// Da una notifica di GdAHome, come la manda il ponte
  /// (`ponte/src/notifiche.js`, `_contenuto`): `id`, `tipo`, `cat`, `urg`,
  /// `titolo`, `testo`, `entita`, `azioni` (`id`, `etichetta`, `apre`).
  /// Facoltativi, se il ponte li manda: `sotto` (la cosa precisa:
  /// `lavatrice`, `fumo`, `auto`…) e `pin` su un tasto.
  ///
  /// `null` se non è da mostrare in guida: senza titolo, o un promemoria dei
  /// viaggi (lo dice già il navigatore).
  static AvvisoDiCasa? daNotifica(Map<String, Object?> busta, {String? casa}) {
    final titolo = _pulito(busta['titolo']);
    final tipo = '${busta['tipo'] ?? ''}';
    if (titolo.isEmpty || tipo == 'viaggi') return null;
    final testo = _pulito(busta['testo']);
    final entita = busta['entita'] is String ? busta['entita'] as String : '';
    final parole = '$titolo $testo ${entita.replaceAll('_', ' ').replaceAll('.', ' ')}'.toLowerCase();
    final detto = busta['sotto'] is String ? busta['sotto'] as String : null;
    final (categoria, sotto) = _riconosci(tipo, '${busta['cat'] ?? ''}', parole);
    final urgenza = _urgenza(tipo, '${busta['urg'] ?? ''}', categoria, detto ?? sotto);
    final grezze = busta['azioni'];
    var principale = false;
    final azioni = <AzioneAvvisoDiCasa>[
      if (grezze is List)
        for (final g in grezze)
          if (g is Map && g['id'] is String)
            () {
              final id = g['id'] as String;
              final etichetta = '${g['etichetta'] ?? id}';
              final innocuo = _innocui.contains(id);
              final primo = !innocuo && !principale;
              if (primo) principale = true;
              return AzioneAvvisoDiCasa(
                id,
                etichetta,
                principale: primo,
                domanda: _domanda(id, categoria, parole),
                daFermo: g['apre'] == true || g['pin'] == true,
              );
            }(),
    ];
    return AvvisoDiCasa(
      id: '${busta['id'] ?? '$tipo:$titolo'}',
      categoria: categoria,
      urgenza: urgenza,
      sotto: detto ?? sotto,
      titolo: titolo,
      testo: testo,
      casa: casa,
      azioni: azioni,
      voce: urgenza == UrgenzaAvvisoDiCasa.info ? null : titolo,
    );
  }

  final String id;
  final CategoriaAvvisoDiCasa categoria;
  final UrgenzaAvvisoDiCasa urgenza;

  /// La cosa precisa, per l'icona: `lavatrice`, `forno`, `inserito`,
  /// `allarme`, `cancello`, `arrivo`, `auto`, `fumo`… `null`: quella della
  /// categoria.
  final String? sotto;

  /// Breve: «Lavatrice finita», «Fumo in cucina».
  final String titolo;

  /// Una riga sola: quello che non ci sta si taglia.
  final String testo;

  /// Il nome della casa, per chi ne ha più d'una.
  final String? casa;

  /// Quelli della notifica (al più tre); in guida se ne vedono due
  /// ([tasti]).
  final List<AzioneAvvisoDiCasa> azioni;

  /// La frase breve da dire, se la voce è accesa: «Campanello di casa».
  final String? voce;

  bool get urgente => urgenza == UrgenzaAvvisoDiCasa.urgente;
  bool get importante => urgenza == UrgenzaAvvisoDiCasa.importante;

  /// I tasti da mostrare: al più due; in movimento senza quelli da fermo.
  List<AzioneAvvisoDiCasa> tasti({required bool inMovimento}) => [
    for (final a in azioni)
      if (!inMovimento || !a.daFermo) a,
  ].take(2).toList();
}

/// I tasti che non fanno niente alla casa: toccati, la scheda si chiude.
const _innocui = {'ok', 'ignora', 'piu-tardi', 'va-bene', 'resta', 'chiudi-avviso'};

/// Il titolo senza l'emoji davanti («🚪 Cucina: …») e senza spazi in più.
String _pulito(Object? s) =>
    '${s ?? ''}'.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();

bool _c(String parole, String re) => RegExp(re, unicode: true).hasMatch(parole);

/// Dal tipo del ponte, e se non basta dalle parole (le automazioni di Home
/// Assistant, le personalizzate, l'assistente): la categoria e la cosa.
(CategoriaAvvisoDiCasa, String?) _riconosci(String tipo, String cat, String p) {
  String? elettrodomestico() => _c(p, r'lavatric|washer|washing')
      ? 'lavatrice'
      : _c(p, r'asciugatric|dryer')
      ? 'asciugatrice'
      : _c(p, r'lavastovigli|dishwasher')
      ? 'lavastoviglie'
      : _c(p, r'\bforn[oi]\b|\boven\b')
      ? 'forno'
      : _c(p, r'frig|freezer|congelator')
      ? 'frigo'
      : null;
  String antifurto() => _c(p, r'disinser|spento|disarm')
      ? 'disinserito'
      : _c(p, r'scattat|suona|sirena|intrus|triggered')
      ? 'allarme'
      : 'inserito';
  String? sicurezza() => _c(p, r'\bfum|smoke')
      ? 'fumo'
      : _c(p, r'allag|perdit|\bacqua\b|leak|moisture|water')
      ? 'acqua'
      : _c(p, r'\bgas\b|monossid|carbon')
      ? 'gas'
      : null;
  String? apertura() => _c(p, r'cancell|\bgate\b')
      ? 'cancello'
      : _c(p, r'garage|basculant')
      ? 'garage'
      : _c(p, r'finestr|window')
      ? 'finestra'
      : 'porta';
  String energia() => _c(p, r'\bauto\b|wallbox|ricaric|charg|\bev\b|colonnin')
      ? 'auto'
      : _c(p, r'fotovolt|solar|pannell|\bsole\b')
      ? 'sole'
      : 'rete';
  switch (tipo) {
    case 'allarmi':
      return (CategoriaAvvisoDiCasa.sicurezza, sicurezza());
    case 'antifurto':
      return (CategoriaAvvisoDiCasa.antifurto, 'allarme');
    case 'inserimenti' || 'uscito':
      return (CategoriaAvvisoDiCasa.antifurto, antifurto());
    case 'movimento':
      return (CategoriaAvvisoDiCasa.antifurto, 'movimento');
    case 'campanello':
      return (CategoriaAvvisoDiCasa.campanello, null);
    case 'aperture':
      return (CategoriaAvvisoDiCasa.aperture, apertura());
    case 'elettrodomestici':
      return (CategoriaAvvisoDiCasa.elettrodomestici, elettrodomestico());
    case 'frigo':
      return (CategoriaAvvisoDiCasa.elettrodomestici, 'frigo');
    case 'arrivi':
      return (CategoriaAvvisoDiCasa.persone, _c(p, r'uscit|andat|\bleft\b') ? 'uscita' : 'arrivo');
    case 'blackout':
      return (CategoriaAvvisoDiCasa.energia, 'rete');
    case 'pioggia':
      return (CategoriaAvvisoDiCasa.meteo, 'pioggia');
    case 'aggiorna_app':
      return (CategoriaAvvisoDiCasa.aggiornamenti, null);
  }
  // Le parole: prima quello che conta di più.
  if (sicurezza() case final s? when _c(p, r'allarm|rilevat|sensor|alarm|perdit|allag|fumo|smoke|gas')) {
    return (CategoriaAvvisoDiCasa.sicurezza, s);
  }
  if (_c(p, r'campanell|citofon|doorbell|suonano')) return (CategoriaAvvisoDiCasa.campanello, null);
  if (_c(p, r'antifurt|allarm|alarm|sirena')) return (CategoriaAvvisoDiCasa.antifurto, antifurto());
  if (elettrodomestico() case final e?) return (CategoriaAvvisoDiCasa.elettrodomestici, e);
  if (_c(
    p,
    r'fotovolt|solar|pannell|ricaric|wallbox|charg|\bauto\b.*\bcaric|caricat|blackout|corrente|rete elettric',
  )) {
    return (CategoriaAvvisoDiCasa.energia, energia());
  }
  if (_c(p, r'\bport[ae]\b|finestr|cancell|garage|\bdoor|window|\bgate\b')) {
    return (CategoriaAvvisoDiCasa.aperture, apertura());
  }
  if (_c(p, r'arrivat|è a casa|uscit|arrived|left home|\bperson ')) {
    return (CategoriaAvvisoDiCasa.persone, _c(p, r'uscit|\bleft\b') ? 'uscita' : 'arrivo');
  }
  if (_c(p, r'termostat|riscald|caldai|condizionat|\bclima|climate|temperatur|umidit')) {
    return (CategoriaAvvisoDiCasa.clima, _c(p, r'condizionat|fresc|\bcool') ? 'fresco' : null);
  }
  if (_c(p, r'pioggi|piove|vento|grandin|\bneve|temporal|allerta|meteo|weather|\brain')) {
    return (CategoriaAvvisoDiCasa.meteo, _c(p, r'allerta|temporal|grandin') ? 'allerta' : 'pioggia');
  }
  if (_c(p, r'aggiorn|update|versione')) return (CategoriaAvvisoDiCasa.aggiornamenti, null);
  return (CategoriaAvvisoDiCasa.altre, null);
}

UrgenzaAvvisoDiCasa _urgenza(String tipo, String urg, CategoriaAvvisoDiCasa c, String? sotto) {
  // Il campanello sul telefono suona come una chiamata (`urg: urgente`), ma
  // in guida non è un pericolo: importante.
  if (tipo == 'campanello' || c == CategoriaAvvisoDiCasa.campanello) return UrgenzaAvvisoDiCasa.importante;
  if (tipo == 'allarmi' || tipo == 'antifurto') return UrgenzaAvvisoDiCasa.urgente;
  if (urg == 'urgente') return UrgenzaAvvisoDiCasa.urgente;
  if (c == CategoriaAvvisoDiCasa.sicurezza || sotto == 'allarme') return UrgenzaAvvisoDiCasa.importante;
  if (const {'aperture', 'uscito', 'movimento', 'blackout', 'frigo'}.contains(tipo)) {
    return UrgenzaAvvisoDiCasa.importante;
  }
  if (sotto == 'allerta') return UrgenzaAvvisoDiCasa.importante;
  return UrgenzaAvvisoDiCasa.info;
}

/// La domanda prima di un tasto che fa qualcosa da lontano. Le stesse cose
/// che il telefono, dalla tendina, fa solo sbloccato (`postino.dart`).
String? _domanda(String id, CategoriaAvvisoDiCasa c, String p) => switch (id) {
  'apri' when c == CategoriaAvvisoDiCasa.campanello || _c(p, r'cancell') => 'Aprire il cancello?',
  'apri' => 'Aprire?',
  'disinserisci' => 'Disinserire l\'antifurto?',
  'inserisci' => 'Inserire l\'antifurto?',
  'sblocca' || 'unlock' => 'Sbloccare la porta?',
  'apri-garage' => 'Aprire il garage?',
  _ => null,
};

/// L'icona e il colore di un avviso.
({IconData icona, Color colore}) aspettoDi(AvvisoDiCasa a) => aspettoPer(a.categoria, a.sotto);

({IconData icona, Color colore}) aspettoPer(CategoriaAvvisoDiCasa c, [String? sotto]) {
  const verde = Color(0xFF16A34A);
  const rosso = Color(0xFFDC2626);
  const blu = Color(0xFF0284C7);
  const ambra = Color(0xFFD97706);
  return switch ((c, sotto)) {
    (CategoriaAvvisoDiCasa.elettrodomestici, 'lavatrice') => (
      icona: Icons.local_laundry_service_rounded,
      colore: verde,
    ),
    (CategoriaAvvisoDiCasa.elettrodomestici, 'asciugatrice') => (icona: Icons.dry_cleaning_rounded, colore: verde),
    (CategoriaAvvisoDiCasa.elettrodomestici, 'lavastoviglie') => (icona: Icons.flatware_rounded, colore: verde),
    (CategoriaAvvisoDiCasa.elettrodomestici, 'forno') => (icona: Icons.microwave_rounded, colore: ambra),
    (CategoriaAvvisoDiCasa.elettrodomestici, 'frigo') => (icona: Icons.kitchen_rounded, colore: blu),
    (CategoriaAvvisoDiCasa.elettrodomestici, _) => (icona: Icons.local_laundry_service_rounded, colore: verde),
    (CategoriaAvvisoDiCasa.antifurto, 'disinserito') => (
      icona: Icons.remove_moderator_rounded,
      colore: const Color(0xFF64748B),
    ),
    (CategoriaAvvisoDiCasa.antifurto, 'allarme') => (icona: Icons.crisis_alert_rounded, colore: rosso),
    (CategoriaAvvisoDiCasa.antifurto, 'movimento') => (icona: Icons.videocam_rounded, colore: const Color(0xFF7C3AED)),
    (CategoriaAvvisoDiCasa.antifurto, _) => (icona: Icons.gpp_good_rounded, colore: const Color(0xFF2563EB)),
    (CategoriaAvvisoDiCasa.aperture, 'cancello') => (icona: Icons.fence_rounded, colore: const Color(0xFF0D9488)),
    (CategoriaAvvisoDiCasa.aperture, 'garage') => (icona: Icons.garage_rounded, colore: const Color(0xFF0D9488)),
    (CategoriaAvvisoDiCasa.aperture, 'finestra') => (
      icona: Icons.sensor_window_rounded,
      colore: const Color(0xFF0D9488),
    ),
    (CategoriaAvvisoDiCasa.aperture, _) => (icona: Icons.sensor_door_rounded, colore: const Color(0xFF0D9488)),
    (CategoriaAvvisoDiCasa.persone, 'uscita') => (
      icona: Icons.directions_walk_rounded,
      colore: const Color(0xFF9333EA),
    ),
    (CategoriaAvvisoDiCasa.persone, _) => (icona: Icons.person_pin_circle_rounded, colore: const Color(0xFF9333EA)),
    (CategoriaAvvisoDiCasa.energia, 'auto') => (icona: Icons.electric_car_rounded, colore: verde),
    (CategoriaAvvisoDiCasa.energia, 'sole') => (icona: Icons.solar_power_rounded, colore: ambra),
    (CategoriaAvvisoDiCasa.energia, _) => (icona: Icons.bolt_rounded, colore: ambra),
    (CategoriaAvvisoDiCasa.clima, 'fresco') => (icona: Icons.ac_unit_rounded, colore: blu),
    (CategoriaAvvisoDiCasa.clima, _) => (icona: Icons.thermostat_rounded, colore: const Color(0xFFEA580C)),
    (CategoriaAvvisoDiCasa.meteo, 'allerta') => (icona: Icons.thunderstorm_rounded, colore: ambra),
    (CategoriaAvvisoDiCasa.meteo, _) => (icona: Icons.umbrella_rounded, colore: blu),
    (CategoriaAvvisoDiCasa.sicurezza, 'acqua') => (icona: Icons.water_drop_rounded, colore: blu),
    (CategoriaAvvisoDiCasa.sicurezza, 'gas') => (icona: Icons.propane_tank_rounded, colore: ambra),
    (CategoriaAvvisoDiCasa.sicurezza, _) => (icona: Icons.local_fire_department_rounded, colore: rosso),
    (CategoriaAvvisoDiCasa.campanello, _) => (icona: Icons.doorbell_rounded, colore: const Color(0xFF4F46E5)),
    (CategoriaAvvisoDiCasa.aggiornamenti, _) => (icona: Icons.system_update_rounded, colore: const Color(0xFF475569)),
    (CategoriaAvvisoDiCasa.altre, _) => (icona: Icons.home_rounded, colore: const Color(0xFF475569)),
  };
}

/// La coda degli avvisi: uno in vista (o il gruppo), gli altri dietro.
class CodaAvvisiDiCasa extends ChangeNotifier {
  CodaAvvisiDiCasa({
    SceltaAvvisiDiCasa scelta = const SceltaAvvisiDiCasa(),
    this.durata = const Duration(seconds: 8),
    this.raggruppaDa = 3,
    this.onAzione,
    this.onVoce,
  }) : _sceltaOra = scelta;

  SceltaAvvisiDiCasa _sceltaOra;

  /// Quali passano. Cambiandola, quelli in attesa che non passano più se ne
  /// vanno.
  SceltaAvvisiDiCasa get scelta => _sceltaOra;
  set scelta(SceltaAvvisiDiCasa s) {
    _sceltaOra = s;
    final prima = _chiave;
    _urgenti.removeWhere((a) => !s.mostra(a));
    _altre.removeWhere((a) => !s.mostra(a));
    _cambiato(prima);
  }

  /// Quanto resta in vista un avviso «info» (un importante il doppio).
  final Duration durata;

  /// Da quanti avvisi non urgenti insieme si fa il gruppo.
  final int raggruppaDa;

  /// Il tasto premuto (dopo il «Sì», se chiedeva): lo esegue chi ospita,
  /// come un tocco sulla notifica (passa dal lucchetto, `dietro_il_velo`).
  void Function(AvvisoDiCasa avviso, AzioneAvvisoDiCasa azione)? onAzione;

  /// La frase da dire quando un avviso compare.
  void Function(String frase)? onVoce;

  final _urgenti = <AvvisoDiCasa>[];
  final _altre = <AvvisoDiCasa>[];
  AzioneAvvisoDiCasa? _daConfermare;
  bool _aperto = false;
  DateTime? _da;
  Timer? _timer;

  /// L'avviso in vista da solo: il primo urgente, o il primo degli altri se
  /// sono meno di [raggruppaDa].
  AvvisoDiCasa? get attuale => _urgenti.firstOrNull ?? (_altre.length < raggruppaDa ? _altre.firstOrNull : null);

  /// Il gruppo in vista: gli avvisi non urgenti, quando sono tanti.
  List<AvvisoDiCasa>? get gruppo => _urgenti.isEmpty && _altre.length >= raggruppaDa ? List.unmodifiable(_altre) : null;

  /// Il gruppo aperto (solo da fermi: lo decide la scheda).
  bool get aperto => _aperto && gruppo != null;

  /// Il tasto che aspetta il «Sì».
  AzioneAvvisoDiCasa? get daConfermare => _daConfermare;

  /// Quanti aspettano dietro quello in vista.
  int get inCoda {
    if (gruppo != null) return 0;
    return _urgenti.length + _altre.length - 1;
  }

  /// Da quando è in vista quello attuale (per la barra del tempo).
  DateTime? get da => _da;

  /// Quanto resta in vista quello attuale; `null`: finché non lo si tocca.
  Duration? get tempo {
    if (_daConfermare != null || aperto) return null;
    final a = attuale;
    if (a == null) return gruppo == null ? null : durata * 2;
    return switch (a.urgenza) {
      UrgenzaAvvisoDiCasa.urgente => null,
      UrgenzaAvvisoDiCasa.importante => durata * 2,
      UrgenzaAvvisoDiCasa.info => durata,
    };
  }

  /// Cosa si vede adesso: quando cambia, il tempo riparte.
  String? get _chiave => switch ((attuale, gruppo)) {
    (final a?, _) => a.id,
    (_, _?) => 'gruppo',
    _ => null,
  };

  /// Arriva un avviso. Uno con lo stesso id prende il posto del vecchio.
  void aggiungi(AvvisoDiCasa avviso) {
    if (!_sceltaOra.mostra(avviso)) return;
    final prima = _chiave;
    final primoUrgente = _urgenti.firstOrNull?.id;
    _urgenti.removeWhere((a) => a.id == avviso.id);
    _altre.removeWhere((a) => a.id == avviso.id);
    if (avviso.urgente) {
      _urgenti.add(avviso);
      // Un urgente nuovo chiude la domanda di quello che era in vista.
      if (primoUrgente == null) _daConfermare = null;
    } else {
      // Gli importanti davanti agli info, nell'ordine in cui arrivano; ma
      // quello già in vista resta in testa.
      final testa = prima != null && prima != 'gruppo' && _altre.isNotEmpty && _altre.first.id == prima ? 1 : 0;
      var i = _altre.length;
      if (avviso.importante) {
        i = testa;
        while (i < _altre.length && _altre[i].importante) {
          i++;
        }
      }
      _altre.insert(i, avviso);
      // Al più nove: le più vecchie «info» se ne vanno (restano sul telefono).
      while (_altre.length > 9) {
        final vecchia = _altre.lastWhere((a) => !a.importante, orElse: () => _altre.last);
        _altre.remove(vecchia);
      }
    }
    _cambiato(prima);
  }

  /// Toccato un tasto. Se chiede, prima la domanda.
  void premi(AzioneAvvisoDiCasa azione) {
    final a = attuale;
    if (a == null) return;
    if (azione.domanda != null && _daConfermare == null) {
      _daConfermare = azione;
      // Si tiene in vista finché non si risponde, anche se non è urgente.
      _timer?.cancel();
      notifyListeners();
      return;
    }
    onAzione?.call(a, azione);
    chiudi();
  }

  /// «No» alla domanda: si torna all'avviso, col suo tempo da capo.
  void annulla() {
    if (_daConfermare == null) return;
    _daConfermare = null;
    _avvia();
    notifyListeners();
  }

  /// Apre il gruppo (da fermi). Aperto non scade.
  void apri() {
    if (gruppo == null) return;
    _aperto = true;
    _timer?.cancel();
    notifyListeners();
  }

  /// Richiude il gruppo, col suo tempo da capo.
  void richiudi() {
    if (!_aperto) return;
    _aperto = false;
    _avvia();
    notifyListeners();
  }

  /// Chiude quello in vista (o tutto il gruppo) e mostra il prossimo. Quello
  /// che si chiude qui resta fra le notifiche del telefono.
  void chiudi() {
    final prima = _chiave;
    if (_urgenti.isNotEmpty) {
      _urgenti.removeAt(0);
    } else if (gruppo != null) {
      _altre.clear();
    } else if (_altre.isNotEmpty) {
      _altre.removeAt(0);
    }
    _daConfermare = null;
    _cambiato(prima, sempre: true);
  }

  /// Via tutti, in silenzio: la guida è finita. Restano fra le notifiche del
  /// telefono.
  void svuota() {
    if (_urgenti.isEmpty && _altre.isEmpty) return;
    final prima = _chiave;
    _urgenti.clear();
    _altre.clear();
    _cambiato(prima);
  }

  /// Toglie un avviso solo, dal gruppo aperto.
  void togli(String id) {
    final prima = _chiave;
    _altre.removeWhere((a) => a.id == id);
    _cambiato(prima);
  }

  void _cambiato(String? prima, {bool sempre = false}) {
    final dopo = _chiave;
    if (gruppo == null) _aperto = false;
    if (dopo != prima || sempre) {
      _daConfermare = null;
      _da = dopo == null ? null : DateTime.now();
      _avvia();
      final frase = attuale?.voce;
      if (dopo != null && dopo != prima && frase != null) onVoce?.call(frase);
    }
    notifyListeners();
  }

  void _avvia() {
    _timer?.cancel();
    final t = tempo;
    if (t == null || _chiave == null) return;
    _da = DateTime.now();
    _timer = Timer(t, chiudi);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// La scheda in guida, sotto la manovra. Vuota quando non c'è niente.
///
/// [inMovimento]: niente tasti «da fermo», e il gruppo non si apre.
class SchedaAvvisoDiCasa extends StatelessWidget {
  const SchedaAvvisoDiCasa({super.key, required this.coda, this.inMovimento = true});

  final CodaAvvisiDiCasa coda;
  final bool inMovimento;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: coda,
    builder: (context, _) {
      final aperto = coda.aperto && !inMovimento;
      final Widget? figlio = switch ((coda.attuale, coda.gruppo)) {
        (final a?, _) => _Scheda(
          key: ValueKey('${a.id}|${coda.daConfermare?.id}|$inMovimento'),
          avviso: a,
          coda: coda,
          inMovimento: inMovimento,
        ),
        (_, final g?) when aperto => _GruppoAperto(key: const ValueKey('gruppo-aperto'), avvisi: g, coda: coda),
        (_, final g?) => _Gruppo(key: ValueKey('gruppo|$inMovimento'), avvisi: g, coda: coda, inMovimento: inMovimento),
        _ => null,
      };
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (figlio, animazione) => SizeTransition(
          sizeFactor: animazione,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: animazione, child: figlio),
        ),
        child: figlio == null
            ? const SizedBox(key: ValueKey('niente'), width: double.infinity)
            : Padding(
                key: ValueKey('p|${(figlio.key as ValueKey).value}'),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: figlio,
              ),
      );
    },
  );
}

/// L'icona nel quadratino colorato.
class _Icona extends StatelessWidget {
  const _Icona({required this.icona, required this.colore, this.urgente = false, this.lato = 48});

  final IconData icona;
  final Color colore;
  final bool urgente;
  final double lato;

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const Key('avviso-casa-icona'),
      width: lato,
      height: lato,
      decoration: BoxDecoration(
        color: urgente ? Colors.white : colore.withValues(alpha: scuro ? 0.28 : 0.13),
        borderRadius: BorderRadius.circular(lato * 0.29),
      ),
      child: Icon(icona, size: lato * 0.62, color: urgente ? colore : (scuro ? Colors.white : colore)),
    );
  }
}

/// La riga in alto: «URGENTE · GdAHome · Villa Gialla».
Widget _intestazione(BuildContext context, List<String> pezzi, Color colore) => Text(
  pezzi.join(' · '),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: Theme.of(context).textTheme.labelMedium
      ?.copyWith(color: colore.withValues(alpha: 0.75), fontWeight: FontWeight.w700, letterSpacing: 0.3),
);

class _Scheda extends StatelessWidget {
  const _Scheda({super.key, required this.avviso, required this.coda, required this.inMovimento});

  final AvvisoDiCasa avviso;
  final CodaAvvisiDiCasa coda;
  final bool inMovimento;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (:icona, :colore) = aspettoDi(avviso);
    final urgente = avviso.urgente;
    final testoColore = urgente ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final domanda = coda.daConfermare;
    final tasti = avviso.tasti(inMovimento: inMovimento);
    final corpo = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Icona(icona: icona, colore: colore, urgente: urgente),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _intestazione(context, [if (urgente) 'URGENTE', 'GdAHome', ?avviso.casa], testoColore),
                    Text(
                      domanda?.domanda ?? avviso.titolo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleLarge?.copyWith(color: testoColore, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    if (domanda == null && avviso.testo.isNotEmpty)
                      Text(
                        avviso.testo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(color: testoColore.withValues(alpha: 0.88)),
                      ),
                  ],
                ),
              ),
              if (coda.inCoda > 0)
                Container(
                  key: const Key('avviso-casa-coda'),
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: testoColore.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+${coda.inCoda}',
                    style: t.labelLarge?.copyWith(color: testoColore, fontWeight: FontWeight.w800),
                  ),
                ),
              // Senza tasti: una X grande per toglierla prima del tempo.
              if (tasti.isEmpty && domanda == null)
                IconButton(
                  key: const Key('avviso-casa-chiudi'),
                  onPressed: coda.chiudi,
                  iconSize: 28,
                  color: testoColore,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Chiudi',
                ),
            ],
          ),
          if (domanda != null || tasti.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RigaTasti(
              urgente: urgente,
              colore: urgente ? colore : Theme.of(context).colorScheme.primary,
              tasti: domanda != null
                  ? [
                      ('Sì, ${_minuscola(domanda.etichetta)}', true, () => coda.premi(domanda)),
                      ('No', false, coda.annulla),
                    ]
                  : [
                      for (final az in tasti) (az.etichetta, az.principale, () => coda.premi(az)),
                      // Un tasto solo: accanto, «Chiudi», per non doverla aspettare.
                      if (tasti.length == 1) ('Chiudi', false, coda.chiudi),
                    ],
            ),
          ],
        ],
      ),
    );
    final scheda = urgente
        ? DecoratedBox(
            key: const Key('avviso-casa'),
            decoration: BoxDecoration(
              color: const Color(0xFFC62828),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFFFCDD2), width: 2),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 20, offset: Offset(0, 6))],
            ),
            child: Material(type: MaterialType.transparency, child: corpo),
          )
        : Vetro(
            key: const Key('avviso-casa'),
            raggio: 22,
            child: avviso.importante
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colore.withValues(alpha: 0.7), width: 2),
                    ),
                    child: corpo,
                  )
                : corpo,
          );
    return _ConIlTempo(coda: coda, colore: colore, chiave: avviso.id, child: scheda);
  }

  static String _minuscola(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

/// Tanti avvisi insieme: «3 notifiche di casa», le icone e i titoli in una
/// riga. Da fermi «Mostra» li apre; in movimento solo la X.
class _Gruppo extends StatelessWidget {
  const _Gruppo({super.key, required this.avvisi, required this.coda, required this.inMovimento});

  final List<AvvisoDiCasa> avvisi;
  final CodaAvvisiDiCasa coda;
  final bool inMovimento;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final testoColore = Theme.of(context).colorScheme.onSurface;
    final primi = avvisi.take(3).toList();
    final corpo = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Le icone dei primi tre, una sopra l'altra.
              SizedBox(
                width: 44 + (primi.length - 1) * 8,
                height: 44,
                child: Stack(
                  children: [
                    for (final (i, a) in primi.indexed.toList().reversed)
                      Positioned(
                        left: i * 8.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                            color: Theme.of(context).colorScheme.surface,
                          ),
                          child: _Icona(icona: aspettoDi(a).icona, colore: aspettoDi(a).colore, lato: 40),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _intestazione(context, ['GdAHome', if (inMovimento) 'le vedi da fermo'], testoColore),
                    Text(
                      '${avvisi.length} notifiche di casa',
                      key: const Key('avviso-casa-gruppo'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    Text(
                      avvisi.map((a) => a.titolo).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(color: testoColore.withValues(alpha: 0.88)),
                    ),
                  ],
                ),
              ),
              if (inMovimento)
                IconButton(
                  key: const Key('avviso-casa-chiudi'),
                  onPressed: coda.chiudi,
                  iconSize: 28,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Chiudi tutte',
                ),
            ],
          ),
          if (!inMovimento) ...[
            const SizedBox(height: 12),
            _RigaTasti(
              urgente: false,
              colore: Theme.of(context).colorScheme.primary,
              tasti: [('Mostra', true, coda.apri), ('Chiudi tutte', false, coda.chiudi)],
            ),
          ],
        ],
      ),
    );
    return _ConIlTempo(
      coda: coda,
      colore: Theme.of(context).colorScheme.primary,
      chiave: 'gruppo',
      child: Vetro(key: const Key('avviso-casa'), raggio: 22, child: corpo),
    );
  }
}

/// Il gruppo aperto, da fermi: una riga per avviso, ognuna con la sua X.
class _GruppoAperto extends StatelessWidget {
  const _GruppoAperto({super.key, required this.avvisi, required this.coda});

  final List<AvvisoDiCasa> avvisi;
  final CodaAvvisiDiCasa coda;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tenue = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
    return LayoutBuilder(
      builder: (context, vincoli) {
        final altezza = vincoli.maxHeight.isFinite ? (vincoli.maxHeight - 64).clamp(60.0, 5 * 60.0) : 5 * 60.0;
        return Vetro(
          key: const Key('avviso-casa'),
          raggio: 22,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${avvisi.length} notifiche di casa',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    // «Chiudi tutte» in alto: di traverso lascia più righe.
                    TextButton(
                      onPressed: coda.chiudi,
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      child: const Text('Chiudi tutte'),
                    ),
                    IconButton(
                      key: const Key('avviso-casa-richiudi'),
                      onPressed: coda.richiudi,
                      iconSize: 28,
                      icon: const Icon(Icons.expand_less_rounded),
                      tooltip: 'Richiudi',
                    ),
                  ],
                ),
                ConstrainedBox(
                  // Di traverso lo spazio è poco: l'elenco scorre.
                  constraints: BoxConstraints(maxHeight: altezza),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final a in avvisi)
                        SizedBox(
                          height: 60,
                          child: Row(
                            children: [
                              _Icona(icona: aspettoDi(a).icona, colore: aspettoDi(a).colore, lato: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.titolo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    if (a.testo.isNotEmpty)
                                      Text(
                                        a.testo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.bodyMedium?.copyWith(color: tenue),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('avviso-casa-togli-${a.id}'),
                                onPressed: () => coda.togli(a.id),
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Togli',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// La barra del tempo che resta, in fondo: come la barra degli avvisi in auto.
class _ConIlTempo extends StatelessWidget {
  const _ConIlTempo({required this.coda, required this.colore, required this.chiave, required this.child});

  final CodaAvvisiDiCasa coda;
  final Color colore;
  final String chiave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final da = coda.da;
    final tempo = coda.tempo;
    if (tempo == null || da == null) return child;
    final passato = (DateTime.now().difference(da).inMilliseconds / tempo.inMilliseconds).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(chiave),
              tween: Tween(begin: 1 - passato, end: 0),
              duration: tempo * (1 - passato),
              builder: (context, v, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  child: Container(height: 4, color: colore.withValues(alpha: 0.85)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una riga di tasti grandi, ognuno largo uguale.
class _RigaTasti extends StatelessWidget {
  const _RigaTasti({required this.tasti, required this.urgente, required this.colore});

  final List<(String, bool, VoidCallback)> tasti;
  final bool urgente;
  final Color colore;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, (etichetta, principale, premi)) in tasti.indexed) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: _Tasto(
            etichetta: etichetta,
            principale: principale,
            urgente: urgente,
            colore: colore,
            onPressed: premi,
          ),
        ),
      ],
    ],
  );
}

/// Un tasto grande, da premere con un dito senza guardare troppo: alto 56.
class _Tasto extends StatelessWidget {
  const _Tasto({
    required this.etichetta,
    required this.principale,
    required this.urgente,
    required this.colore,
    required this.onPressed,
  });

  final String etichetta;
  final bool principale;
  final bool urgente;
  final Color colore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final stile = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    const forma = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));
    const misura = Size.fromHeight(56);
    final figlio = Text(etichetta, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (principale) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: misura,
          shape: forma,
          textStyle: stile,
          backgroundColor: urgente ? Colors.white : colore,
          foregroundColor: urgente ? colore : Theme.of(context).colorScheme.onPrimary,
        ),
        child: figlio,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: misura,
        shape: forma,
        textStyle: stile,
        foregroundColor: urgente ? Colors.white : null,
        side: BorderSide(
          color: urgente ? Colors.white70 : Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: figlio,
    );
  }
}
