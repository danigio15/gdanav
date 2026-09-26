import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Una zona già scaricata (o a metà).
class ZonaScaricata {
  const ZonaScaricata({required this.id, required this.zona, this.megabyte = 0, this.completa = true});
  final int id;
  final Zona zona;
  final double megabyte;
  final bool completa;
}

/// Cosa serve dalla libreria delle mappe: la vera nell'app, una finta nelle
/// prove.
abstract interface class ArchivioMappe {
  Future<List<ZonaScaricata>> elenco();
  Future<void> scarica(Zona zona, void Function(double progresso, double megabyte) avanzamento);
  Future<void> cancella(int id);
}

/// Le mappe offline con MapLibre: i riquadri di OpenFreeMap salvati nel
/// telefono, usati da soli quando manca la rete (anche sullo schermo di
/// Android Auto, che usa lo stesso archivio).
class ArchivioMapLibre implements ArchivioMappe {
  /// Lo stile che MapLibre usa per sapere cosa scaricare: quello di
  /// OpenFreeMap ha la stessa sorgente e gli stessi caratteri del nostro,
  /// quindi i riquadri servono anche alla mappa di gdanav.
  static const stileDiRiferimento = 'https://tiles.openfreemap.org/styles/liberty';

  @override
  Future<List<ZonaScaricata>> elenco() async {
    final regioni = await ml.getListOfRegions();
    final zone = <ZonaScaricata>[];
    for (final r in regioni) {
      final b = r.definition.bounds;
      final m = r.metadata;
      double mb = 0;
      var completa = true;
      try {
        final s = await ml.getOfflineRegionStatus(r.id);
        mb = s.completedResourceSize / 1024 / 1024;
        completa = s.isComplete;
      } catch (_) {}
      zone.add(
        ZonaScaricata(
          id: r.id,
          zona: Zona(
            m['id'] as String? ?? '${r.id}',
            m['nome'] as String? ?? 'Zona',
            b.southwest.latitude,
            b.southwest.longitude,
            b.northeast.latitude,
            b.northeast.longitude,
          ),
          megabyte: mb,
          completa: completa,
        ),
      );
    }
    return zone;
  }

  @override
  Future<void> scarica(Zona zona, void Function(double progresso, double megabyte) avanzamento) async {
    // Il limite di serie (6.000 riquadri) basta appena per una città.
    await ml.setOfflineTileCountLimit(1000000);
    final fatto = Completer();
    await ml.downloadOfflineRegion(
      ml.OfflineRegionDefinition(
        bounds: ml.LatLngBounds(southwest: ml.LatLng(zona.sud, zona.ovest), northeast: ml.LatLng(zona.nord, zona.est)),
        mapStyleUrl: stileDiRiferimento,
        minZoom: 0,
        maxZoom: 14,
      ),
      metadata: {'id': zona.id, 'nome': zona.nome},
      onEvent: (e) {
        switch (e) {
          case ml.InProgress(:final progress, :final completedResourceSize):
            avanzamento(progress / 100, completedResourceSize / 1024 / 1024);
          case ml.Success():
            if (!fatto.isCompleted) fatto.complete();
          case ml.Error(:final cause):
            if (!fatto.isCompleted) fatto.completeError(cause);
        }
      },
    );
    await fatto.future;
  }

  @override
  Future<void> cancella(int id) async {
    await ml.deleteOfflineRegion(id);
  }
}

/// Le zone scaricate e quella che si sta scaricando, per la schermata.
class GestoreMappeOffline extends ChangeNotifier {
  GestoreMappeOffline(this.archivio);

  final ArchivioMappe archivio;
  var zone = <ZonaScaricata>[];
  Zona? inCorso;
  double progresso = 0;
  double megabyte = 0;
  String? errore;

  Future<void> carica() async {
    try {
      zone = await archivio.elenco();
      errore = null;
    } catch (e) {
      errore = 'Non riesco a leggere le mappe salvate: $e';
    }
    notifyListeners();
  }

  bool scaricata(Zona z) => zone.any((s) => s.zona.id == z.id && s.completa);

  Future<void> scarica(Zona z) async {
    if (inCorso != null) return;
    inCorso = z;
    progresso = 0;
    megabyte = 0;
    errore = null;
    notifyListeners();
    try {
      await archivio.scarica(z, (p, mb) {
        progresso = p;
        megabyte = mb;
        notifyListeners();
      });
    } catch (e) {
      errore = 'Lo scaricamento di ${z.nome} si è interrotto. Riprova con la rete.';
    }
    inCorso = null;
    await carica();
  }

  Future<void> cancella(ZonaScaricata z) async {
    await archivio.cancella(z.id);
    await carica();
  }
}
