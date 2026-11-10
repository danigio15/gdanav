import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../sorgenti/pmtiles.dart';

/// Gli edifici veri per la scena 3D, da Overture Maps.
///
/// «Lungo il percorso voglio vedere le cose reali.» Le tessere di OpenFreeMap
/// hanno gli edifici di OpenStreetMap, e in tanti paesi non li ha disegnati
/// nessuno: a Carinaro, entro 150 m da via Torretta, 5 edifici dove è tutto
/// costruito. Overture unisce quelli di OpenStreetMap a quelli che Microsoft
/// ha ricavato dalle foto dal satellite, con l'altezza: lì sono 43.
///
/// Gli edifici sono in pacchetti, uno per cella z8 (circa 150 km di lato),
/// nella release «edifici» del repository di GdANav (vedi
/// `strumenti/edifici/prepara.py`). Il pacchetto della zona si scarica una
/// volta, su una rete che non si paga a consumo, e poi si legge dal telefono:
/// nessun server da chiamare a ogni tessera, e va anche senza rete. Finché
/// non c'è, la scena usa gli edifici di sempre.
class GestoreEdifici {
  GestoreEdifici({
    http.Client? client,
    Future<Directory> Function()? cartella,
    Future<bool> Function()? aConsumo,
    Uri? base,
    this.indiceValido = const Duration(days: 1),
  }) : _http = client ?? http.Client(),
       _cartellaDi = cartella ?? (() async => Directory('${(await getApplicationSupportDirectory()).path}/edifici')),
       _aConsumo = aConsumo ?? reteAConsumo,
       _base = base ?? Uri.parse('https://github.com/danigio15/gdanav/releases/download/edifici/');

  /// Quello dell'app, per chi apre la scena 3D (anche sull'auto).
  static GestoreEdifici? attuale;

  /// Lo zoom delle celle dei pacchetti.
  static const zoomCelle = 8;

  /// Chi dice gli edifici d'Overture, da scrivere sulla mappa.
  static const attribuzione = '© Overture Maps Foundation, Microsoft';

  final http.Client _http;
  final Future<Directory> Function() _cartellaDi;
  final Future<bool> Function() _aConsumo;
  final Uri _base;

  /// Ogni quanto si rilegge l'indice dei pacchetti.
  final Duration indiceValido;

  final _lettori = <String, Future<LettorePmtiles?>>{};

  /// Gli scaricamenti in corso: chi chiede la stessa cella aspetta quello.
  final _inArrivo = <String, Future<bool>>{};
  Map<String, int>? _indice;
  DateTime? _indiceLetto;

  /// La cella z8 che contiene la tessera [z]/[x]/[y] (z ≥ 8), come «8/x/y».
  static String cellaDi(int z, int x, int y) {
    final s = z - zoomCelle;
    return '$zoomCelle/${x >> s}/${y >> s}';
  }

  static String fileDi(String cella) => 'edifici-${cella.replaceAll('/', '-')}.pmtiles';

  /// La tessera z14 [x]/[y] coi soli edifici, se il pacchetto della sua
  /// zona c'è; altrimenti `null`, e il pacchetto si chiede (non si aspetta:
  /// la scena intanto usa gli edifici di sempre).
  Future<Uint8List?> tessera(int z, int x, int y) async {
    if (z < zoomCelle) return null;
    final cella = cellaDi(z, x, y);
    try {
      final l = await _lettore(cella);
      if (l == null) {
        unawaited(scarica(cella));
        return null;
      }
      return await l.tessera(z, x, y);
    } catch (e) {
      debugPrint('edifici $cella: $e');
      return null;
    }
  }

  Future<LettorePmtiles?> _lettore(String cella) => _lettori[cella] ??= () async {
    final f = File('${(await _cartellaDi()).path}/${fileDi(cella)}');
    if (!await f.exists()) {
      _lettori.remove(cella);
      return null;
    }
    try {
      return await LettorePmtiles.apri(f.path);
    } on FormatException {
      // Un file rovinato: via, e alla prossima si riscarica.
      await f.delete().catchError((Object _) => f);
      _lettori.remove(cella);
      return null;
    }
  }();

  /// Scarica il pacchetto di [cella] se c'è nell'indice, non c'è già, e la
  /// rete non si paga a consumo. Torna `true` se adesso c'è.
  Future<bool> scarica(String cella) => _inArrivo[cella] ??= _scarica(cella).whenComplete(() {
    // Senza graffe tornerebbe il futuro tolto, cioè questo: si aspetterebbe da solo.
    _inArrivo.remove(cella);
  });

  Future<bool> _scarica(String cella) async {
    try {
      final dir = await _cartellaDi();
      final f = File('${dir.path}/${fileDi(cella)}');
      if (await f.exists()) return true;
      final indice = await _leggiIndice();
      final byte = indice?[cella];
      if (byte == null) return false;
      if (await _aConsumo()) return false;
      await dir.create(recursive: true);
      final mezzo = File('${f.path}.mezzo');
      final r = await _http.send(http.Request('GET', _base.resolve(fileDi(cella))));
      if (r.statusCode != 200) return false;
      final s = mezzo.openWrite();
      await r.stream.pipe(s);
      if (await mezzo.length() != byte) {
        await mezzo.delete();
        return false;
      }
      await mezzo.rename(f.path);
      _lettori.remove(cella);
      return true;
    } catch (e) {
      debugPrint('edifici: non scaricato $cella: $e');
      return false;
    }
  }

  /// L'indice dei pacchetti: cella → byte. Si rilegge una volta al giorno.
  Future<Map<String, int>?> _leggiIndice() async {
    final letto = _indiceLetto;
    if (_indice != null && letto != null && DateTime.now().difference(letto) < indiceValido) return _indice;
    try {
      final r = await _http.get(_base.resolve('indice.json')).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return _indice;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final celle = j is Map ? j['celle'] : null;
      if (celle is! Map) return _indice;
      _indice = {
        for (final MapEntry(:key, :value) in celle.entries)
          if (value is Map && value['byte'] is num) '$key': (value['byte'] as num).toInt(),
      };
      _indiceLetto = DateTime.now();
    } catch (_) {}
    return _indice;
  }
}

/// Se la rete di adesso si paga a consumo (i dati del telefono, un hotspot).
/// Nel dubbio sì: un pacchetto può pesare un centinaio di megabyte.
Future<bool> reteAConsumo() async {
  try {
    return await const MethodChannel('gdanav/rete').invokeMethod<bool>('aConsumo') ?? true;
  } catch (_) {
    return true;
  }
}
