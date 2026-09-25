package it.gdanav.gdanav

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import it.gdanav.gdanav.auto.Diagnosi
import it.gdanav.gdanav.auto.MotoreFlutter
import it.gdanav.gdanav.auto.PonteAuto

// I permessi Bluetooth stanno nel pacchetto `gdanav_app`, che Flutter
// registra da solo: qui resta quello che è solo dell'app, cioè Android Auto.
class MainActivity : FlutterActivity() {
    // Lo stesso motore dell'auto: se Android Auto l'ha già acceso, si riusa.
    override fun provideFlutterEngine(context: Context): FlutterEngine = MotoreFlutter.assicura(context)

    // Chiudendo l'app sul telefono la guida in auto continua.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Il filo fra l'app sul telefono e lo schermo dell'auto.
        PonteAuto.collega(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        Diagnosi.collega(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
