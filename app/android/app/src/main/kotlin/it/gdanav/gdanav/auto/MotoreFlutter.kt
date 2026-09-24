package it.gdanav.gdanav.auto

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Un solo motore Flutter per il telefono e per l'auto. Se gdanav si apre da
 * Android Auto prima che dal telefono, il motore parte qui: l'app Dart
 * calcola percorsi e guida anche senza schermata sul telefono. Quando poi
 * si apre l'app, MainActivity usa lo stesso motore.
 */
object MotoreFlutter {
    private const val ID = "gdanav"

    fun assicura(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ID)?.let { return it }
        val motore = FlutterEngine(context.applicationContext)
        PonteAuto.collega(motore.dartExecutor.binaryMessenger)
        motore.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(ID, motore)
        return motore
    }
}
