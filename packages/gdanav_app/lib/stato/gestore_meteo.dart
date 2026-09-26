import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'gestore_posizione.dart';
import 'gestore_premium.dart';
import 'gestore_viaggio.dart';

/// Il meteo (Premium): lungo il viaggio calcolato, ognuno all'ora in cui ci si
/// passa, e dove sei adesso. Serve al consumo (freddo, caldo, vento contro) e
/// si mostra nella scheda del viaggio e sullo schermo dell'auto.
class GestoreMeteo extends ChangeNotifier {
  GestoreMeteo({required this.viaggio, this.posizione, FonteMeteo? fonte, DateTime Function()? orologio})
    : fonte = fonte ?? MeteoMetNorway(),
      _ora = orologio ?? DateTime.now {
    viaggio.addListener(_viaggio);
    posizione?.addListener(_posizione);
    GestorePremium.attivo.addListener(_premium);
  }

  final GestoreViaggio viaggio;
  final GestorePosizione? posizione;
  final FonteMeteo fonte;
  final DateTime Function() _ora;

  /// Il meteo del viaggio pronto; `null` finché non arriva (o senza Premium).
  MeteoViaggio? delViaggio;

  /// Adesso, dove sei.
  Previsione? qui;

  ViaggioPronto? _perViaggio;
  Punto? _ultimoQui;
  DateTime _ultimaVolta = DateTime(0);

  static const _attesa = Duration(seconds: 4);

  /// Prima di calcolare il viaggio, a grandi linee (in linea d'aria, alla
  /// velocità di un'autostrada): la temperatura media e il vento contro.
  /// `null` senza Premium o se il meteo non risponde in fretta.
  Future<({double temperaturaC, double ventoControMs})?> stima(Punto da, Punto a) async {
    if (!GestorePremium.attivo.value) return null;
    try {
      final km = distanzaM(da, a) / 1000 * 1.3;
      final m = await MeteoViaggio.lungo(
        fonte,
        [da, a],
        partenza: _ora(),
        durata: Duration(minutes: (km / 85 * 60).round()),
        quanti: 3,
      ).timeout(_attesa);
      final t = m.temperaturaMediaC;
      if (t == null) return null;
      return (temperaturaC: t, ventoControMs: m.ventoControMedioMs ?? 0);
    } catch (_) {
      return null;
    }
  }

  void _viaggio() {
    final s = viaggio.stato;
    if (s is! ViaggioPronto) {
      if (delViaggio != null || _perViaggio != null) {
        delViaggio = null;
        _perViaggio = null;
        notifyListeners();
      }
      return;
    }
    if (identical(s, _perViaggio)) return;
    _perViaggio = s;
    delViaggio = null;
    notifyListeners();
    if (GestorePremium.attivo.value) unawaited(_lungo(s));
  }

  Future<void> _lungo(ViaggioPronto s) async {
    final arrivo = s.arrivoAlle ?? s.calcolatoAlle.add(s.viaggio.percorso.durata);
    try {
      final m = await MeteoViaggio.lungo(
        fonte,
        s.viaggio.percorso.punti,
        partenza: s.calcolatoAlle,
        durata: arrivo.difference(s.calcolatoAlle),
      );
      if (!identical(s, _perViaggio)) return;
      delViaggio = m;
      notifyListeners();
    } catch (e) {
      debugPrint('meteo: $e');
    }
  }

  /// Dove sei: ogni mezz'ora, o dopo dieci chilometri.
  void _posizione() {
    final p = posizione?.qui;
    if (p == null || !GestorePremium.attivo.value) return;
    final u = _ultimoQui;
    if (u != null && distanzaM(u, p) < 10000 && _ora().difference(_ultimaVolta) < const Duration(minutes: 30)) return;
    _ultimoQui = p;
    _ultimaVolta = _ora();
    unawaited(_adesso(p));
  }

  Future<void> _adesso(Punto p) async {
    try {
      qui = MeteoViaggio.piuVicina(await fonte.previsioni(p), _ora());
      notifyListeners();
    } catch (e) {
      debugPrint('meteo: $e');
    }
  }

  void _premium() {
    if (GestorePremium.attivo.value) {
      _perViaggio = null;
      _viaggio();
      _ultimoQui = null;
      _posizione();
    } else {
      delViaggio = null;
      qui = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    viaggio.removeListener(_viaggio);
    posizione?.removeListener(_posizione);
    GestorePremium.attivo.removeListener(_premium);
    super.dispose();
  }
}
