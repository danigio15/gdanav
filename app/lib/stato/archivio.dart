import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/segnaposto.dart';
import '../servizi.dart';

/// Quello che l'app ricorda: l'abbinamento con Home Assistant (contiene la
/// chiave, quindi sta nel portachiavi del telefono) e come è messo lo switch.
class Archivio {
  Archivio([FlutterSecureStorage? portachiavi]) : _p = portachiavi ?? const FlutterSecureStorage();

  final FlutterSecureStorage _p;

  static const _abbinamento = 'abbinamento_home_assistant';
  static const _fonte = 'fonte_dati_auto';
  static const _veicolo = 'veicolo';
  static const _preferenze = 'preferenze_ricarica';
  static const _opzioniPercorso = 'opzioni_percorso';
  static const _segnaposto = 'segnaposto';
  static const _luoghi = 'luoghi';

  Future<Abbinamento?> abbinamento() async {
    final uri = await _p.read(key: _abbinamento);
    if (uri == null) return null;
    try {
      return Abbinamento.daUri(uri);
    } on FormatException {
      return null;
    }
  }

  Future<void> salvaAbbinamento(Abbinamento? a) =>
      a == null ? _p.delete(key: _abbinamento) : _p.write(key: _abbinamento, value: a.uri);

  /// `automatica` oppure il nome di una [TipoSorgente].
  Future<ModalitaFonte> fonte() async {
    final nome = await _p.read(key: _fonte);
    final tipo = TipoSorgente.values.where((t) => t.name == nome).firstOrNull;
    return tipo == null ? const Automatica() : Fissa(tipo);
  }

  Future<void> salvaFonte(ModalitaFonte m) => _p.write(
    key: _fonte,
    value: switch (m) {
      Automatica() => 'automatica',
      Fissa(:final sorgente) => sorgente.name,
    },
  );

  /// I servizi sono cablati in [Servizi]: non si scrivono più a mano.
  Future<Impostazioni> impostazioni() async => Impostazioni.predefinite();

  /// L'auto scelta; il profilo d'esempio finché non se ne sceglie una.
  Future<ProfiloVeicolo> veicolo() async => veicoloPerId(await _p.read(key: _veicolo) ?? '') ?? ProfiloVeicolo.esempio;

  Future<void> salvaVeicolo(ProfiloVeicolo v) => _p.write(key: _veicolo, value: v.id);

  Future<PreferenzeRicarica> preferenze() async {
    final testo = await _p.read(key: _preferenze);
    if (testo == null) return const PreferenzeRicarica();
    try {
      return PreferenzeRicarica.daJson(jsonDecode(testo) as Map<String, Object?>);
    } on FormatException {
      return const PreferenzeRicarica();
    }
  }

  Future<void> salvaPreferenze(PreferenzeRicarica p) => _p.write(key: _preferenze, value: jsonEncode(p.toJson()));

  /// Veloce o risparmio, pedaggi, autostrade, traghetti.
  Future<OpzioniPercorso> opzioniPercorso() async {
    final testo = await _p.read(key: _opzioniPercorso);
    if (testo == null) return const OpzioniPercorso();
    try {
      return OpzioniPercorso.daJson(jsonDecode(testo) as Map<String, Object?>);
    } catch (_) {
      return const OpzioniPercorso();
    }
  }

  Future<void> salvaOpzioniPercorso(OpzioniPercorso o) =>
      _p.write(key: _opzioniPercorso, value: jsonEncode(o.toJson()));

  Future<Segnaposto> segnaposto() async => Segnaposto.perNome(await _p.read(key: _segnaposto));

  /// Casa, lavoro, i preferiti e le ultime mete, come JSON.
  Future<Map<String, Object?>> luoghi() async {
    final testo = await _p.read(key: _luoghi);
    if (testo == null) return const {};
    try {
      return jsonDecode(testo) as Map<String, Object?>;
    } on FormatException {
      return const {};
    }
  }

  Future<void> salvaLuoghi(Map<String, Object?> j) => _p.write(key: _luoghi, value: jsonEncode(j));

  /// Il dongle OBD Bluetooth scelto: indirizzo e nome.
  Future<({String id, String nome})?> dongleObd() async {
    final testo = await _p.read(key: 'dongle_obd');
    if (testo == null) return null;
    try {
      final j = jsonDecode(testo) as Map<String, Object?>;
      return (id: j['id']! as String, nome: j['nome'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> salvaDongleObd(({String id, String nome})? d) => d == null
      ? _p.delete(key: 'dongle_obd')
      : _p.write(key: 'dongle_obd', value: jsonEncode({'id': d.id, 'nome': d.nome}));

  /// La foto della propria auto, come percorso di un file dell'app.
  Future<String?> fotoAuto() => _p.read(key: 'foto_auto');

  Future<void> salvaFotoAuto(String? percorso) =>
      percorso == null ? _p.delete(key: 'foto_auto') : _p.write(key: 'foto_auto', value: percorso);

  /// Il consumo imparato di un modello.
  Future<ConsumoImparato> consumo(String veicolo) async {
    final testo = await _p.read(key: 'consumo_$veicolo');
    if (testo == null) return const ConsumoImparato();
    try {
      return ConsumoImparato.daJson(jsonDecode(testo) as Map<String, Object?>);
    } on FormatException {
      return const ConsumoImparato();
    }
  }

  Future<void> salvaConsumo(String veicolo, ConsumoImparato c) =>
      _p.write(key: 'consumo_$veicolo', value: jsonEncode(c.toJson()));

  Future<void> salvaSegnaposto(Segnaposto s) => _p.write(key: _segnaposto, value: s.name);
}

/// Dove stanno i servizi: vedi [Servizi].
class Impostazioni {
  const Impostazioni({this.valhalla = '', this.chiaveValhalla = '', this.chiaveOcm = ''});

  factory Impostazioni.predefinite() => const Impostazioni(
    valhalla: Servizi.valhalla,
    chiaveValhalla: Servizi.chiaveValhalla,
    chiaveOcm: Servizi.chiaveOcm,
  );

  factory Impostazioni.daJson(Map<String, Object?> j) => Impostazioni(
    valhalla: j['valhalla'] as String? ?? '',
    chiaveValhalla: j['chiave_valhalla'] as String? ?? '',
    chiaveOcm: j['chiave_ocm'] as String? ?? '',
  );

  final String valhalla;
  final String chiaveValhalla;
  final String chiaveOcm;

  /// Cosa manca per pianificare un viaggio, in parole. `null` se c'è tutto.
  String? get mancante {
    if (valhalla.isEmpty) return 'Il calcolo dei percorsi non è disponibile in questa versione.';
    // La chiave di Open Charge Map non blocca: senza, le colonnine si provano
    // a chiedere lo stesso.
    return null;
  }

  Map<String, Object?> toJson() => {'valhalla': valhalla, 'chiave_valhalla': chiaveValhalla, 'chiave_ocm': chiaveOcm};
}
