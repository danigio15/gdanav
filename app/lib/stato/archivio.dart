import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Quello che l'app ricorda: l'abbinamento con Home Assistant (contiene la
/// chiave, quindi sta nel portachiavi del telefono) e come è messo lo switch.
class Archivio {
  Archivio([FlutterSecureStorage? portachiavi]) : _p = portachiavi ?? const FlutterSecureStorage();

  final FlutterSecureStorage _p;

  static const _abbinamento = 'abbinamento_home_assistant';
  static const _fonte = 'fonte_dati_auto';
  static const _impostazioni = 'impostazioni';
  static const _veicolo = 'veicolo';
  static const _preferenze = 'preferenze_ricarica';

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

  Future<Impostazioni> impostazioni() async {
    final testo = await _p.read(key: _impostazioni);
    if (testo == null) return Impostazioni.predefinite();
    try {
      return Impostazioni.daJson(jsonDecode(testo) as Map<String, Object?>);
    } on FormatException {
      return Impostazioni.predefinite();
    }
  }

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

  Future<void> salvaImpostazioni(Impostazioni i) => _p.write(key: _impostazioni, value: jsonEncode(i.toJson()));
}

/// Dove stanno i servizi. Si scrivono nelle impostazioni dell'app, oppure si
/// danno alla compilazione:
///
///     flutter run --dart-define=GDANAV_VALHALLA=https://1-2-3-4.sslip.io/ \
///                 --dart-define=GDANAV_VALHALLA_CHIAVE=... \
///                 --dart-define=GDANAV_OCM_CHIAVE=...
class Impostazioni {
  const Impostazioni({this.valhalla = '', this.chiaveValhalla = '', this.chiaveOcm = ''});

  factory Impostazioni.predefinite() => const Impostazioni(
    valhalla: String.fromEnvironment('GDANAV_VALHALLA', defaultValue: valhallaDiProva),
    chiaveValhalla: String.fromEnvironment('GDANAV_VALHALLA_CHIAVE'),
    chiaveOcm: String.fromEnvironment('GDANAV_OCM_CHIAVE'),
  );

  factory Impostazioni.daJson(Map<String, Object?> j) => Impostazioni(
    valhalla: j['valhalla'] as String? ?? '',
    chiaveValhalla: j['chiave_valhalla'] as String? ?? '',
    chiaveOcm: j['chiave_ocm'] as String? ?? '',
  );

  /// Il server pubblico di FOSSGIS: va bene per provare l'app, non per
  /// distribuirla a tanti (chiede un uso moderato). Poi si mette il proprio.
  static const valhallaDiProva = 'https://valhalla1.openstreetmap.de/';

  final String valhalla;
  final String chiaveValhalla;
  final String chiaveOcm;

  /// Cosa manca per pianificare un viaggio, in parole. `null` se c'è tutto.
  String? get mancante {
    if (valhalla.isEmpty) return "Manca l'indirizzo del server dei percorsi: scrivilo nelle impostazioni.";
    // La chiave di Open Charge Map non blocca: senza, le colonnine si provano
    // a chiedere lo stesso.
    return null;
  }

  Map<String, Object?> toJson() => {'valhalla': valhalla, 'chiave_valhalla': chiaveValhalla, 'chiave_ocm': chiaveOcm};
}
