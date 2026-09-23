import 'package:geolocator/geolocator.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Dove si è adesso, chiedendo il permesso la prima volta. `null` se la
/// posizione è spenta o negata: chi chiama lo dice all'utente.
Future<Punto?> posizioneAttuale() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permesso = await Geolocator.checkPermission();
  if (permesso == LocationPermission.denied) permesso = await Geolocator.requestPermission();
  if (permesso == LocationPermission.denied || permesso == LocationPermission.deniedForever) return null;
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    return Punto(p.latitude, p.longitude);
  } catch (_) {
    final ultima = await Geolocator.getLastKnownPosition();
    return ultima == null ? null : Punto(ultima.latitude, ultima.longitude);
  }
}
