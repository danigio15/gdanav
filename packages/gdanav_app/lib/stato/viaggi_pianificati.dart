import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';
import 'gestore_premium.dart';

/* ─── I viaggi pianificati ──────────────────────────────────────────────
 *
 * Tre modi di pianificare, come nelle fotografie approvate: un viaggio per
 * un giorno («arrivo entro le 9:00 domani»), uno di ogni settimana («Casa –
 * Lavoro, lun – ven») e un giro a tappe. Sono gli stessi viaggi della pagina
 * gdanav della plancia: dentro gdahome stanno nella casa (`ponte/viaggi/…`),
 * che manda l'avviso quando partire e accende il clima dell'auto; in gdanav
 * da sola stanno nel telefono.
 *
 * Il JSON è quello della casa (`ponte/src/viaggi.js`), campo per campo: un
 * viaggio scritto da PC si apre sul telefono e viceversa. */

/// Gli stessi della casa: senza traffico la strada si allunga del 15%, e una
/// stima col traffico vale sei ore.
const margineSenzaTraffico = 1.15;
const stimaColTrafficoVale = Duration(hours: 6);
const tappeAlPiu = 10;

enum TipoViaggioPianificato {
  /// Un giorno solo.
  una,

  /// Ogni settimana, nei giorni scelti.
  settimana,

  /// Un giro a tappe, con le soste.
  tappe,
}

/// Un posto del viaggio, con la sosta (per le tappe in mezzo al giro).
@immutable
class PostoPianificato {
  const PostoPianificato(this.luogo, {this.sostaMin = 0});

  final Luogo luogo;
  final int sostaMin;

  String get nome => luogo.nome;

  Map<String, Object?> toJson() => {
    'nome': luogo.nome,
    'lat': luogo.posizione.lat,
    'lon': luogo.posizione.lon,
    if (sostaMin > 0) 'sostaMin': sostaMin,
  };

  static PostoPianificato? daJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lon = j['lon'];
    if (lat is! num || lon is! num) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    final nome = j['nome'] is String && (j['nome'] as String).isNotEmpty
        ? j['nome'] as String
        : '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
    final sosta = j['sostaMin'];
    return PostoPianificato(
      Luogo(nome: nome, posizione: Punto(lat.toDouble(), lon.toDouble())),
      sostaMin: sosta is num ? sosta.toInt().clamp(0, 12 * 60) : 0,
    );
  }

  PostoPianificato conSosta(int minuti) => PostoPianificato(luogo, sostaMin: minuti);
}

/// Quanto ci vuole: la strada calcolata, col traffico o senza.
@immutable
class StimaViaggio {
  const StimaViaggio({required this.durata, this.km, this.colTraffico = false, this.alle});

  final Duration durata;
  final double? km;
  final bool colTraffico;
  final DateTime? alle;

  Map<String, Object?> toJson() => {
    'durataS': durata.inSeconds,
    'km': ?km,
    'fonte': colTraffico ? 'traffico' : 'strada',
    if (alle case final a?) 'alle': a.millisecondsSinceEpoch,
  };

  static StimaViaggio? daJson(Object? j) {
    if (j is! Map) return null;
    final s = j['durataS'];
    if (s is! num || s <= 0) return null;
    final alle = j['alle'];
    return StimaViaggio(
      durata: Duration(seconds: s.round()),
      km: (j['km'] as num?)?.toDouble(),
      colTraffico: j['fonte'] == 'traffico',
      alle: alle is num ? DateTime.fromMillisecondsSinceEpoch(alle.toInt()) : null,
    );
  }

  /// Ancora buona col traffico: calcolata da meno di sei ore.
  bool frescaAlle(DateTime adesso) => colTraffico && alle != null && adesso.difference(alle!) < stimaColTrafficoVale;
}

/// La prossima volta di un viaggio: quando partire e quando si arriva.
@immutable
class ProssimaVolta {
  const ProssimaVolta({required this.partenza, required this.arrivo, this.stimata = true});

  final DateTime partenza;
  final DateTime arrivo;

  /// Con una stima della strada; senza, la partenza è l'ora scritta.
  final bool stimata;

  static ProssimaVolta? daJson(Object? j) {
    if (j is! Map) return null;
    final p = j['partenza'], a = j['arrivo'];
    if (p is! num || a is! num) return null;
    return ProssimaVolta(
      partenza: DateTime.fromMillisecondsSinceEpoch(p.toInt()),
      arrivo: DateTime.fromMillisecondsSinceEpoch(a.toInt()),
      stimata: j['stimata'] != false,
    );
  }
}

@immutable
class ViaggioPianificato {
  const ViaggioPianificato({
    this.id,
    required this.tipo,
    this.nome = '',
    this.da,
    required this.tappe,
    this.arrivoEntro = true,
    required this.ora,
    this.giorno,
    this.giorni = const [],
    this.avviso = true,
    this.avvisoMin = 10,
    this.clima,
    this.climaMin = 10,
    this.garage,
    this.stima,
    this.prossima,
    this.creatoIl,
  });

  /// `null` finché non è salvato.
  final String? id;
  final TipoViaggioPianificato tipo;
  final String nome;

  /// Da dove si parte; `null` è «da dove sono».
  final PostoPianificato? da;

  /// La meta (una sola, se non è a tappe) o le tappe, l'ultima è la meta.
  final List<PostoPianificato> tappe;

  /// «Arrivo entro» o «Parto alle». Un giro a tappe dice sempre la partenza.
  final bool arrivoEntro;

  /// «HH:MM».
  final String ora;

  /// «YYYY-MM-DD», per i viaggi di un giorno e i giri.
  final String? giorno;

  /// Lunedì 1 … domenica 7, per quelli di ogni settimana.
  final List<int> giorni;

  final bool avviso;
  final int avvisoMin;

  /// Con gdahome: il clima dell'auto da accendere prima (`climate.*` o un
  /// interruttore) e il garage da proporre nell'avviso (`cover.*`).
  final String? clima;
  final int climaMin;
  final String? garage;

  final StimaViaggio? stima;

  /// La calcola la casa (o [prossimaVolta] qui).
  final ProssimaVolta? prossima;
  final DateTime? creatoIl;

  PostoPianificato? get meta => tappe.isEmpty ? null : tappe.last;

  bool get dicePartenza => tipo == TipoViaggioPianificato.tappe || !arrivoEntro;

  /// Il nome da far vedere: quello dato, se no «Casa – Caserta».
  String get titolo {
    if (nome.isNotEmpty) return nome;
    String corto(String s) => s.split(' · ').first.split(',').first.trim();
    final a = meta == null ? '' : corto(meta!.nome);
    final d = da == null ? '' : corto(da!.nome);
    if (d.isEmpty) return a.isEmpty ? 'Viaggio' : a;
    return a.isEmpty ? d : '$d – $a';
  }

  ViaggioPianificato copia({
    String? id,
    TipoViaggioPianificato? tipo,
    String? nome,
    PostoPianificato? Function()? da,
    List<PostoPianificato>? tappe,
    bool? arrivoEntro,
    String? ora,
    String? Function()? giorno,
    List<int>? giorni,
    bool? avviso,
    int? avvisoMin,
    String? Function()? clima,
    int? climaMin,
    String? Function()? garage,
    StimaViaggio? Function()? stima,
    ProssimaVolta? Function()? prossima,
  }) => ViaggioPianificato(
    id: id ?? this.id,
    tipo: tipo ?? this.tipo,
    nome: nome ?? this.nome,
    da: da == null ? this.da : da(),
    tappe: tappe ?? this.tappe,
    arrivoEntro: arrivoEntro ?? this.arrivoEntro,
    ora: ora ?? this.ora,
    giorno: giorno == null ? this.giorno : giorno(),
    giorni: giorni ?? this.giorni,
    avviso: avviso ?? this.avviso,
    avvisoMin: avvisoMin ?? this.avvisoMin,
    clima: clima == null ? this.clima : clima(),
    climaMin: climaMin ?? this.climaMin,
    garage: garage == null ? this.garage : garage(),
    stima: stima == null ? this.stima : stima(),
    prossima: prossima == null ? this.prossima : prossima(),
    creatoIl: creatoIl,
  );

  /// Un viaggio nuovo, come la pagina della plancia (`bozzaNuova`).
  static ViaggioPianificato nuovo(TipoViaggioPianificato tipo, DateTime adesso) {
    final domani = adesso.add(const Duration(days: 1));
    return ViaggioPianificato(
      tipo: tipo,
      tappe: const [],
      arrivoEntro: tipo != TipoViaggioPianificato.tappe,
      ora: tipo == TipoViaggioPianificato.settimana ? '08:30' : '09:00',
      giorno: tipo == TipoViaggioPianificato.settimana ? null : giornoDetto(domani),
      giorni: tipo == TipoViaggioPianificato.settimana ? const [1, 2, 3, 4, 5] : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'id': ?id,
    'tipo': tipo.name,
    'nome': nome,
    'da': da?.toJson(),
    'tappe': [for (final t in tappe) t.toJson()],
    'quando': {
      'modo': dicePartenza ? 'partenza' : 'arrivo',
      'ora': ora,
      'giorno': tipo == TipoViaggioPianificato.settimana ? null : giorno,
      'giorni': tipo == TipoViaggioPianificato.settimana ? giorni : const <int>[],
    },
    'avviso': {'acceso': avviso, 'minuti': avvisoMin},
    'prepara': {
      'clima': clima == null ? null : {'entity': clima, 'minuti': climaMin},
      'garage': garage == null ? null : {'entity': garage},
    },
    'stima': stima?.toJson(),
    if (creatoIl case final c?) 'creatoIl': c.millisecondsSinceEpoch,
  };

  /// `null` se non sta in piedi: senza meta, senza ora, senza giorno.
  static ViaggioPianificato? daJson(Object? j) {
    if (j is! Map) return null;
    final tipo = TipoViaggioPianificato.values.where((t) => t.name == j['tipo']).firstOrNull;
    if (tipo == null) return null;
    final tappe = [for (final t in (j['tappe'] as List?) ?? const []) ?PostoPianificato.daJson(t)]
        .take(tappeAlPiu)
        .toList();
    if (tappe.isEmpty) return null;
    final quando = j['quando'] is Map ? j['quando'] as Map : const {};
    final ora = quando['ora'];
    if (ora is! String || !oraBuona.hasMatch(ora)) return null;
    final giorni = [
      for (final g in (quando['giorni'] as List?) ?? const [])
        if (g is num && g >= 1 && g <= 7) g.toInt(),
    ]..sort();
    final giorno = quando['giorno'] is String ? quando['giorno'] as String : null;
    if (tipo == TipoViaggioPianificato.settimana ? giorni.isEmpty : giorno == null) return null;
    final avviso = j['avviso'] is Map ? j['avviso'] as Map : const {};
    final prepara = j['prepara'] is Map ? j['prepara'] as Map : const {};
    final clima = prepara['clima'] is Map ? prepara['clima'] as Map : null;
    final garage = prepara['garage'] is Map ? prepara['garage'] as Map : null;
    final creato = j['creatoIl'];
    return ViaggioPianificato(
      id: j['id'] as String?,
      tipo: tipo,
      nome: j['nome'] as String? ?? '',
      da: PostoPianificato.daJson(j['da']),
      tappe: tipo == TipoViaggioPianificato.tappe ? tappe : tappe.take(1).toList(),
      arrivoEntro: tipo != TipoViaggioPianificato.tappe && quando['modo'] != 'partenza',
      ora: ora,
      giorno: tipo == TipoViaggioPianificato.settimana ? null : giorno,
      giorni: tipo == TipoViaggioPianificato.settimana ? {...giorni}.toList() : const [],
      avviso: avviso['acceso'] != false,
      avvisoMin: (avviso['minuti'] as num?)?.toInt() ?? 10,
      clima: clima?['entity'] as String?,
      climaMin: (clima?['minuti'] as num?)?.toInt() ?? 10,
      garage: garage?['entity'] as String?,
      stima: StimaViaggio.daJson(j['stima']),
      prossima: ProssimaVolta.daJson(j['prossima']),
      creatoIl: creato is num ? DateTime.fromMillisecondsSinceEpoch(creato.toInt()) : null,
    );
  }
}

final oraBuona = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

String _due(int n) => n.toString().padLeft(2, '0');

/// «2026-10-16».
String giornoDetto(DateTime d) => '${d.year}-${_due(d.month)}-${_due(d.day)}';

/// «8:12».
String oraDetta(DateTime d) => '${d.hour}:${_due(d.minute)}';

/// Quanto si guida, con le soste delle tappe in mezzo: col traffico se la
/// stima è fresca, se no col margine. `null` senza stima. Come
/// `durataDelViaggio` della casa.
Duration? durataDelViaggio(ViaggioPianificato v, DateTime adesso) {
  final s = v.stima;
  if (s == null || s.durata <= Duration.zero) return null;
  final guida = s.durata.inMilliseconds * (s.frescaAlle(adesso) ? 1 : margineSenzaTraffico);
  final soste = v.tappe.isEmpty ? 0 : v.tappe.sublist(0, v.tappe.length - 1).fold<int>(0, (t, p) => t + p.sostaMin);
  return Duration(milliseconds: guida.round() + soste * 60000);
}

/// La prossima volta da [adesso]: come `prossimaVolta` della casa. Un viaggio
/// di un giorno finito da più di un'ora torna `null`.
ProssimaVolta? prossimaVolta(ViaggioPianificato v, DateTime adesso) {
  final durata = durataDelViaggio(v, adesso) ?? Duration.zero;
  final m = oraBuona.firstMatch(v.ora);
  if (m == null) return null;
  ProssimaVolta per(DateTime giorno) {
    final scritta = DateTime(giorno.year, giorno.month, giorno.day, int.parse(m[1]!), int.parse(m[2]!));
    return v.dicePartenza
        ? ProssimaVolta(partenza: scritta, arrivo: scritta.add(durata), stimata: durata > Duration.zero)
        : ProssimaVolta(partenza: scritta.subtract(durata), arrivo: scritta, stimata: durata > Duration.zero);
  }

  if (v.tipo != TipoViaggioPianificato.settimana) {
    final g = DateTime.tryParse(v.giorno ?? '');
    if (g == null) return null;
    final volta = per(g);
    return volta.arrivo.isBefore(adesso.subtract(const Duration(hours: 1))) ? null : volta;
  }
  final oggi = DateTime(adesso.year, adesso.month, adesso.day);
  for (var i = 0; i < 8; i++) {
    final g = DateTime(oggi.year, oggi.month, oggi.day + i);
    if (!v.giorni.contains(g.weekday)) continue;
    final volta = per(g);
    if (!volta.arrivo.isBefore(adesso.subtract(const Duration(minutes: 5)))) return volta;
  }
  return null;
}

const _nomiGiorni = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
const _giorniLunghi = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];
const _mesi = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];

/// «Lun – Ven», «Sab, Dom», «Tutti i giorni».
String giorniDetti(List<int> giorni) {
  final s = {...giorni.where((g) => g >= 1 && g <= 7)}.toList()..sort();
  if (s.length == 7) return 'Tutti i giorni';
  var fila = s.length > 2;
  for (var i = 1; i < s.length && fila; i++) {
    fila = s[i] == s[i - 1] + 1;
  }
  if (fila) return '${_nomiGiorni[s.first - 1]} – ${_nomiGiorni[s.last - 1]}';
  return [for (final g in s) _nomiGiorni[g - 1]].join(', ');
}

/// «Oggi», «Domani», «sab 18 ott».
String giornoParlato(DateTime giorno, DateTime adesso) {
  final oggi = DateTime(adesso.year, adesso.month, adesso.day);
  final g = DateTime(giorno.year, giorno.month, giorno.day);
  final fra = g.difference(oggi).inHours ~/ 24;
  if (fra == 0) return 'Oggi';
  if (fra == 1) return 'Domani';
  return '${_nomiGiorni[g.weekday - 1].toLowerCase()} ${g.day} ${_mesi[g.month - 1]}';
}

/// «giovedì 16».
String giornoLungo(DateTime g) => '${_giorniLunghi[g.weekday - 1]} ${g.day}';

/// La riga sotto il nome: «Domani · arrivo entro le 9:00», «Lun – Ven ·
/// parto alle 18:00», «4 tappe · sab 18 ott alle 8:30».
String quandoDetto(ViaggioPianificato v, DateTime adesso) {
  final ora = _senzaZero(v.ora);
  final azione = v.dicePartenza ? 'parto alle $ora' : 'arrivo entro le $ora';
  if (v.tipo == TipoViaggioPianificato.settimana) return '${giorniDetti(v.giorni)} · $azione';
  final g = DateTime.tryParse(v.giorno ?? '');
  final quando = g == null ? '' : giornoParlato(g, adesso);
  if (v.tipo == TipoViaggioPianificato.tappe) return '${v.tappe.length} tappe · $quando alle $ora';
  return '$quando · $azione';
}

String _senzaZero(String ora) => ora.startsWith('0') ? ora.substring(1) : ora;

/// «1 h 20 min», «48 min».
String durataDetta(Duration d) {
  final minuti = (d.inSeconds / 60).round();
  if (minuti < 60) return '$minuti min';
  final resto = minuti % 60;
  return resto == 0 ? '${minuti ~/ 60} h' : '${minuti ~/ 60} h $resto min';
}

/* ─── Dove stanno ──────────────────────────────────────────────────────── */

/// Un errore della fonte detto in parole.
class ErroreViaggi implements Exception {
  const ErroreViaggi(this.codice);
  final String codice;

  String get messaggio => switch (codice) {
    'premium-richiesto' => 'Il pianificatore è con Premium.',
    'viaggio-non-valido' => 'Manca qualcosa: la meta, l\'ora o il giorno.',
    'troppi-viaggi' => 'Hai già 50 viaggi: togline qualcuno.',
    'non-trovato' => 'Questo viaggio non c\'è più.',
    _ => 'Non sono riuscito a salvare. Riprova.',
  };

  @override
  String toString() => 'ErroreViaggi($codice)';
}

/// Dove stanno i viaggi: nella casa (gdahome) o nel telefono.
abstract class FonteViaggi {
  /// I viaggi, e se il pianificatore è sbloccato.
  Future<({bool sbloccato, List<ViaggioPianificato> viaggi})> elenco();
  Future<ViaggioPianificato> salva(ViaggioPianificato v);
  Future<void> togli(String id);

  /// La stima col traffico calcolata dal navigatore, portata a chi la tiene.
  Future<ViaggioPianificato?> stima(String id, StimaViaggio s);

  /// Nella casa: c'è chi manda l'avviso e accende il clima.
  bool get dellaCasa;
}

/// I viaggi della casa, attraverso gdahome: `ponte/viaggi/*`. [chiedi] lo
/// mette chi ospita gdanav (vedi `SorgenteGdahome.chiedi`): manda il comando
/// alla casa e torna il risultato, o lancia l'errore.
///
/// La casa li tiene per chi li ha scritti: ognuno vede solo i suoi.
class FonteViaggiDellaCasa implements FonteViaggi {
  FonteViaggiDellaCasa(this.chiedi);

  final Future<Object?> Function(Map<String, Object?> comando) chiedi;

  @override
  bool get dellaCasa => true;

  Future<Map> _chiedi(Map<String, Object?> comando) async {
    final Object? r;
    try {
      r = await chiedi(comando);
    } catch (e) {
      final testo = '$e';
      for (final c in const ['premium-richiesto', 'viaggio-non-valido', 'troppi-viaggi', 'non-trovato']) {
        if (testo.contains(c)) throw ErroreViaggi(c);
      }
      throw const ErroreViaggi('casa');
    }
    if (r is! Map) throw const ErroreViaggi('casa');
    return r;
  }

  @override
  Future<({bool sbloccato, List<ViaggioPianificato> viaggi})> elenco() async {
    final r = await _chiedi({'type': 'ponte/viaggi/elenco'});
    return (
      sbloccato: r['sbloccato'] == true,
      viaggi: [for (final v in (r['viaggi'] as List?) ?? const []) ?ViaggioPianificato.daJson(v)],
    );
  }

  @override
  Future<ViaggioPianificato> salva(ViaggioPianificato v) async {
    final r = await _chiedi({'type': 'ponte/viaggi/salva', 'viaggio': v.toJson()});
    return ViaggioPianificato.daJson(r['viaggio']) ?? (throw const ErroreViaggi('casa'));
  }

  @override
  Future<void> togli(String id) => _chiedi({'type': 'ponte/viaggi/togli', 'viaggio': id});

  @override
  Future<ViaggioPianificato?> stima(String id, StimaViaggio s) async {
    final r = await _chiedi({'type': 'ponte/viaggi/stima', 'viaggio': id, 'stima': s.toJson()});
    return ViaggioPianificato.daJson(r['viaggio']);
  }
}

/// I viaggi di gdanav da sola, nel telefono: niente casa che avvisa, e la
/// prossima volta si calcola qui.
class FonteViaggiDelTelefono implements FonteViaggi {
  FonteViaggiDelTelefono(this.archivio, {DateTime Function()? orologio, math.Random? caso})
    : _ora = orologio ?? DateTime.now,
      _caso = caso ?? math.Random.secure();

  final Archivio archivio;
  final DateTime Function() _ora;
  final math.Random _caso;
  static const viaggiAlPiu = 50;

  @override
  bool get dellaCasa => false;

  Future<List<ViaggioPianificato>> _tutti() async {
    final testo = await archivio.viaggiPianificati();
    if (testo == null) return [];
    try {
      return [for (final v in (jsonDecode(testo) as List?) ?? const []) ?ViaggioPianificato.daJson(v)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _scrivi(List<ViaggioPianificato> tutti) =>
      archivio.salvaViaggiPianificati(jsonEncode([for (final v in tutti) v.toJson()]));

  ViaggioPianificato _visto(ViaggioPianificato v) => v.copia(prossima: () => prossimaVolta(v, _ora()));

  @override
  Future<({bool sbloccato, List<ViaggioPianificato> viaggi})> elenco() async {
    // Come la casa: un viaggio di un giorno passato da più di un'ora non si
    // mostra più.
    final visti = [
      for (final v in await _tutti())
        if (_visto(v) case final w when w.tipo == TipoViaggioPianificato.settimana || w.prossima != null) w,
    ];
    visti.sort((a, b) {
      final pa = a.prossima?.partenza, pb = b.prossima?.partenza;
      if (pa == null || pb == null) return pa == null ? (pb == null ? 0 : 1) : -1;
      return pa.compareTo(pb);
    });
    return (sbloccato: GestorePremium.attivo.value, viaggi: visti);
  }

  @override
  Future<ViaggioPianificato> salva(ViaggioPianificato v) async {
    if (!GestorePremium.attivo.value) throw const ErroreViaggi('premium-richiesto');
    if (v.tappe.isEmpty || !oraBuona.hasMatch(v.ora)) throw const ErroreViaggi('viaggio-non-valido');
    final tutti = await _tutti();
    final i = v.id == null ? -1 : tutti.indexWhere((w) => w.id == v.id);
    if (i < 0 && tutti.length >= viaggiAlPiu) throw const ErroreViaggi('troppi-viaggi');
    final id = v.id ?? 'v_${List.generate(12, (_) => _caso.nextInt(16).toRadixString(16)).join()}';
    final salvato = ViaggioPianificato.daJson({
      ...v.toJson(),
      'id': id,
      'creatoIl': (i < 0 ? _ora() : tutti[i].creatoIl ?? _ora()).millisecondsSinceEpoch,
    });
    if (salvato == null) throw const ErroreViaggi('viaggio-non-valido');
    if (i < 0) {
      tutti.add(salvato);
    } else {
      tutti[i] = salvato;
    }
    await _scrivi(tutti);
    return _visto(salvato);
  }

  @override
  Future<void> togli(String id) async {
    final tutti = await _tutti();
    tutti.removeWhere((v) => v.id == id);
    await _scrivi(tutti);
  }

  @override
  Future<ViaggioPianificato?> stima(String id, StimaViaggio s) async {
    final tutti = await _tutti();
    final i = tutti.indexWhere((v) => v.id == id);
    if (i < 0) return null;
    tutti[i] = tutti[i].copia(stima: () => s);
    await _scrivi(tutti);
    return _visto(tutti[i]);
  }
}

/// Calcola quanto ci vuole da [da] (o da dove si è) per le [tappe]: lo fa il
/// navigatore, col traffico di adesso quando può (TomTom).
typedef CalcolaStima = Future<StimaViaggio?> Function(Punto? da, List<Punto> tappe);

/// I viaggi pianificati, per le schermate e per l'auto.
class GestoreViaggiPianificati extends ChangeNotifier {
  GestoreViaggiPianificati(this._fonte, {this.calcolaStima, DateTime Function()? orologio})
    : _ora = orologio ?? DateTime.now;

  FonteViaggi _fonte;
  final CalcolaStima? calcolaStima;
  final DateTime Function() _ora;

  FonteViaggi get fonte => _fonte;

  var viaggi = <ViaggioPianificato>[];

  /// Fino alla prima risposta si dice di sì: il lucchetto non lampeggia.
  var sbloccato = true;
  var caricando = false;
  String? errore;

  DateTime get adesso => _ora();

  /// La casa si è collegata (o staccata): i viaggi si leggono dall'altra
  /// parte.
  void cambiaFonte(FonteViaggi f) {
    if (identical(f, _fonte)) return;
    _fonte = f;
    viaggi = [];
    unawaited(carica());
  }

  Future<void> carica() async {
    caricando = true;
    notifyListeners();
    try {
      final r = await _fonte.elenco();
      sbloccato = r.sbloccato;
      viaggi = r.viaggi;
      errore = null;
    } on ErroreViaggi catch (e) {
      errore = e.messaggio;
    } catch (_) {
      errore = 'Non riesco a leggere i viaggi.';
    } finally {
      caricando = false;
      notifyListeners();
    }
    unawaited(_stimeVecchie());
  }

  /// Salva e torna il viaggio salvato; l'errore si lancia ([ErroreViaggi]).
  Future<ViaggioPianificato> salva(ViaggioPianificato v) async {
    final salvato = await _fonte.salva(v);
    await carica();
    return viaggi.where((w) => w.id == salvato.id).firstOrNull ?? salvato;
  }

  Future<void> togli(ViaggioPianificato v) async {
    final id = v.id;
    if (id == null) return;
    viaggi = [
      for (final w in viaggi)
        if (w.id != id) w,
    ];
    notifyListeners();
    await _fonte.togli(id);
    await carica();
  }

  /// La stima per una bozza (prima di salvare): col traffico se si può.
  Future<StimaViaggio?> stimaPer(ViaggioPianificato v) async {
    final c = calcolaStima;
    if (c == null || v.tappe.isEmpty) return null;
    try {
      return await c(v.da?.luogo.posizione, [for (final t in v.tappe) t.luogo.posizione]);
    } catch (_) {
      return null;
    }
  }

  var _stimando = false;

  /// Le stime dei viaggi delle prossime 12 ore senza traffico fresco si
  /// rifanno col traffico di adesso, e si portano a chi le tiene: così la
  /// casa avvisa all'ora giusta.
  Future<void> _stimeVecchie() async {
    if (_stimando || calcolaStima == null) return;
    _stimando = true;
    try {
      final adesso = _ora();
      for (final v in List.of(viaggi)) {
        final id = v.id, p = v.prossima;
        if (id == null || p == null) continue;
        if (p.partenza.difference(adesso) > const Duration(hours: 12)) continue;
        if (v.stima?.frescaAlle(adesso) ?? false) continue;
        final s = await stimaPer(v);
        if (s == null) continue;
        try {
          final nuovo = await _fonte.stima(id, s);
          if (nuovo != null) {
            viaggi = [for (final w in viaggi) w.id == id ? nuovo : w];
            notifyListeners();
          }
        } catch (_) {}
      }
    } finally {
      _stimando = false;
    }
  }

  /// Quelli da mostrare in auto: i prossimi, poi gli altri.
  List<ViaggioPianificato> get perLAuto => viaggi.take(12).toList();
}

/// La riga sotto il nome in auto: «Parti alle 8:12 · arrivo 9:00»,
/// «Domani, parti alle 7:55», «4 tappe · 186 km».
String sottotitoloInAuto(ViaggioPianificato v, DateTime adesso) {
  if (v.tipo == TipoViaggioPianificato.tappe) {
    return ['${v.tappe.length} tappe', if (v.stima?.km case final k?) '${k.round()} km'].join(' · ');
  }
  final p = v.prossima;
  if (p == null) return quandoDetto(v, adesso);
  final giorno = giornoParlato(p.partenza, adesso);
  final parti = 'parti alle ${oraDetta(p.partenza)}';
  final frase = [
    giorno == 'Oggi' ? parti : '$giorno, $parti',
    if (!v.dicePartenza) 'arrivo ${oraDetta(p.arrivo)}',
  ].join(' · ');
  return frase[0].toUpperCase() + frase.substring(1);
}
