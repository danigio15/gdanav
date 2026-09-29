import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../risorse.dart';
import 'archivio.dart';

/// Le ZTL e le aree pedonali d'Italia dentro l'app, da OpenStreetMap: si
/// leggono una volta, su un altro filo, la prima volta che servono (un
/// percorso, la mappa). All'avvio no: l'avvio deve restare svelto.
Future<ArchivioZtl> archivioZtl() => _zone ??= _leggiZone();
Future<ArchivioZtl>? _zone;

Future<ArchivioZtl> _leggiZone() async {
  try {
    final testo = await rootBundle.loadString('$radiceRisorse/ztl.json');
    return await Isolate.run(() => ArchivioZtl.leggi(testo));
  } catch (e) {
    debugPrint('archivio ZTL: $e');
    return ArchivioZtl.vuoto;
  }
}

/// Un permesso risposto: sì o no, col nome per l'elenco delle impostazioni.
class PermessoZtl {
  const PermessoZtl({required this.si, required this.nome});

  final bool si;

  /// «Napoli · Centro storico».
  final String nome;
}

/// Cosa si è scelto per le ZTL: se si vedono sulla mappa, se si avvisa, e i
/// permessi di ogni ZTL a cui si è risposto.
class ScelteZtl {
  const ScelteZtl({this.sullaMappa = true, this.avvisi = true, this.permessi = const {}});

  factory ScelteZtl.daJson(Map<String, Object?> j) => ScelteZtl(
    sullaMappa: j['mappa'] != false,
    avvisi: j['avvisi'] != false,
    permessi: {
      for (final MapEntry(:key, :value) in ((j['permessi'] as Map?) ?? const {}).entries)
        if (value case {'si': final bool si}) '$key': PermessoZtl(si: si, nome: '${value['nome'] ?? key}'),
    },
  );

  /// Le ZTL e le aree pedonali sulla mappa, anche su quella dell'auto.
  final bool sullaMappa;

  /// Avvisare prima di una ZTL attiva, sul percorso o fuori.
  final bool avvisi;

  /// [ZonaLimitata.chiave] → la risposta.
  final Map<String, PermessoZtl> permessi;

  ScelteZtl copia({bool? sullaMappa, bool? avvisi, Map<String, PermessoZtl>? permessi}) => ScelteZtl(
    sullaMappa: sullaMappa ?? this.sullaMappa,
    avvisi: avvisi ?? this.avvisi,
    permessi: permessi ?? this.permessi,
  );

  Map<String, Object?> toJson() => {
    'mappa': sullaMappa,
    'avvisi': avvisi,
    'permessi': {
      for (final MapEntry(:key, :value) in permessi.entries) key: {'si': value.si, 'nome': value.nome},
    },
  };
}

/// Le scelte sulle ZTL, per tutta l'app: il calcolo dei percorsi ne legge i
/// permessi, la mappa e gli avvisi se si vogliono.
class GestoreZtl extends ChangeNotifier {
  GestoreZtl(this.archivio, {Future<ArchivioZtl> Function()? zone}) : zone = zone ?? archivioZtl;

  /// Quello dell'app, per chi calcola i percorsi (`pianificatoreVero`), che
  /// nasce di nuovo a ogni viaggio e non ha altro modo di chiederli.
  static GestoreZtl? attuale;

  final Archivio archivio;

  /// Le zone: quelle dentro l'app, o finte nelle prove.
  final Future<ArchivioZtl> Function() zone;

  ScelteZtl scelte = const ScelteZtl();

  Future<void> carica() async {
    scelte = await archivio.scelteZtl();
    notifyListeners();
  }

  /// Per il calcolo: [ZonaLimitata.chiave] → c'è il permesso o no. Chi manca
  /// non ha ancora risposto.
  Map<String, bool> get permessi => {for (final MapEntry(:key, :value) in scelte.permessi.entries) key: value.si};

  /// La risposta alla domanda del percorso: si ricorda per quella ZTL.
  Future<void> rispondi(ZonaLimitata z, bool si) =>
      _salva(scelte.copia(permessi: {...scelte.permessi, z.chiave: PermessoZtl(si: si, nome: z.etichetta)}));

  /// L'interruttore dell'elenco: cambiata idea.
  Future<void> cambia(String chiave, bool si) async {
    final p = scelte.permessi[chiave];
    if (p == null || p.si == si) return;
    await _salva(scelte.copia(permessi: {...scelte.permessi, chiave: PermessoZtl(si: si, nome: p.nome)}));
  }

  /// Via dall'elenco: la prossima volta si richiede.
  Future<void> dimentica(String chiave) async {
    if (!scelte.permessi.containsKey(chiave)) return;
    await _salva(scelte.copia(permessi: {...scelte.permessi}..remove(chiave)));
  }

  Future<void> mostra(bool si) => _salva(scelte.copia(sullaMappa: si));

  Future<void> avvisa(bool si) => _salva(scelte.copia(avvisi: si));

  Future<void> _salva(ScelteZtl s) async {
    scelte = s;
    notifyListeners();
    await archivio.salvaScelteZtl(s);
  }
}

/// «fino alle 18», «fino alle 19:30»: l'ora com'è sui cartelli.
String oraCorta(DateTime t) => t.minute == 0 ? '${t.hour}' : '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// «18:00», per le frasi più lunghe.
String oraLunga(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Com'è una ZTL adesso, in poche parole: «attiva fino alle 18», «non attiva
/// fino alle 7:30», «attiva». Senza orari scritti è attiva e basta.
String statoBreve(ZonaLimitata z, DateTime ora) {
  final (:attiva, :cambia) = z.statoAlle(ora);
  if (cambia == null) return attiva ? 'attiva' : 'non attiva';
  return attiva ? 'attiva fino alle ${oraCorta(cambia)}' : 'non attiva fino alle ${oraCorta(cambia)}';
}
