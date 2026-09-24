package it.gdanav.gdanav

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import it.gdanav.gdanav.auto.PonteAuto

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Il filo fra l'app sul telefono e lo schermo dell'auto.
        PonteAuto.collega(flutterEngine.dartExecutor.binaryMessenger)
    }
}
