import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// La foto vera di un modello, da Wikimedia Commons: con licenza libera, e
/// l'autore e la licenza vanno scritti accanto.
class FotoCatalogo {
  const FotoCatalogo({
    required this.url,
    required this.fonte,
    required this.autore,
    required this.licenza,
    this.pagina = '',
  });

  final String url;

  /// La pagina del file su Commons.
  final String fonte;
  final String autore;
  final String licenza;
  final String pagina;

  String get credito => '${autore.isEmpty ? 'Wikimedia Commons' : autore} · $licenza';

  static FotoCatalogo? daJson(Object? j) {
    if (j is! Map) return null;
    final url = j['url'], licenza = j['licenza'];
    if (url is! String || licenza is! String) return null;
    return FotoCatalogo(
      url: url,
      fonte: (j['fonte'] as String?) ?? '',
      autore: (j['autore'] as String?) ?? '',
      licenza: licenza,
      pagina: (j['pagina'] as String?) ?? '',
    );
  }
}

/// Le foto dei modelli: l'elenco viaggia con l'app (`assets/foto_auto.json`),
/// la foto si scarica la prima volta e resta sul telefono.
class GestoreFotoAuto extends ChangeNotifier {
  GestoreFotoAuto({http.Client? client, Future<Directory> Function()? cartella, Future<String> Function()? elenco})
    : _http = client ?? http.Client(),
      _cartella = cartella ?? getApplicationSupportDirectory,
      _elenco = elenco ?? (() => rootBundle.loadString('assets/foto_auto.json'));

  final http.Client _http;
  final Future<Directory> Function() _cartella;
  final Future<String> Function() _elenco;

  Map<String, FotoCatalogo> _foto = const {};
  final _file = <String, File>{};
  final _inCorso = <String>{};

  Future<void> carica() async {
    try {
      final j = jsonDecode(await _elenco()) as Map<String, Object?>;
      _foto = {
        for (final MapEntry(:key, :value) in j.entries) key: ?FotoCatalogo.daJson(value),
      };
    } catch (e) {
      debugPrint('foto delle auto: $e');
    }
    notifyListeners();
  }

  FotoCatalogo? info(String idVeicolo) => _foto[idVeicolo];

  /// Il file sul telefono, se c'è già; se no lo si scarica e si avvisa.
  File? file(String idVeicolo) {
    if (_file[idVeicolo] case final f?) return f;
    final foto = _foto[idVeicolo];
    if (foto != null && _inCorso.add(idVeicolo)) _scarica(idVeicolo, foto);
    return null;
  }

  Future<void> _scarica(String id, FotoCatalogo foto) async {
    try {
      final dir = Directory('${(await _cartella()).path}/foto_auto');
      // Lo stesso file per tutte le versioni dello stesso modello.
      final nome = foto.url.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final f = File('${dir.path}/$nome');
      if (!await f.exists()) {
        final r = await _http
            .get(Uri.parse(foto.url), headers: {'user-agent': 'gdanav (https://github.com/danigio15/gdanav)'})
            .timeout(const Duration(seconds: 30));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw Exception('foto: ${r.statusCode}');
        await dir.create(recursive: true);
        await f.writeAsBytes(r.bodyBytes, flush: true);
      }
      _file[id] = f;
      notifyListeners();
    } catch (e) {
      // Resta «in corso»: in questa sessione non si riprova a ogni disegno.
      debugPrint('foto di $id: $e');
    }
  }
}
