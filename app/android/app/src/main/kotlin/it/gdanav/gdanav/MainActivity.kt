package it.gdanav.gdanav

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import it.gdanav.gdanav.auto.Diagnosi
import it.gdanav.gdanav.auto.MotoreFlutter
import it.gdanav.gdanav.auto.PonteAuto

class MainActivity : FlutterActivity() {
    private val permessi = Permessi(this)

    // Lo stesso motore dell'auto: se Android Auto l'ha già acceso, si riusa.
    override fun provideFlutterEngine(context: Context): FlutterEngine = MotoreFlutter.assicura(context)

    // Chiudendo l'app sul telefono la guida in auto continua.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Il filo fra l'app sul telefono e lo schermo dell'auto.
        PonteAuto.collega(flutterEngine.dartExecutor.binaryMessenger)
        Diagnosi.collega(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        permessi.collega(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(codice: Int, permessiChiesti: Array<out String>, esiti: IntArray) {
        if (!permessi.risposta(codice, esiti)) super.onRequestPermissionsResult(codice, permessiChiesti, esiti)
    }
}
