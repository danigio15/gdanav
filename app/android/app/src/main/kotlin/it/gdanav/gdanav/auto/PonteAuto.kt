package it.gdanav.gdanav.auto

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Quello che il telefono sa e lo schermo dell'auto mostra. L'app Flutter lo
 * aggiorna sul canale `gdanav/schermo_auto`; l'auto manda indietro batteria e
 * autonomia sul canale `gdanav/auto`, e «fine» quando si ferma la guida.
 */
object PonteAuto {
    /** La prossima manovra e il viaggio, mentre si guida. */
    data class Guida(
        val tipo: Int,
        val distanzaM: Double,
        val strada: String,
        val istruzione: String,
        val restantiM: Double,
        val restantiS: Long,
        val arrivoMs: Long,
        val destinazione: String,
    )

    @Volatile var stileChiaro: String? = null
    @Volatile var stileScuro: String? = null

    /** I GeoJSON delle sorgenti dello stile, come li usa la mappa del telefono. */
    @Volatile var sorgenti: Map<String, String> = emptyMap()

    /** Dove sei: centro della mappa, e la rotta in gradi. */
    @Volatile var qui: DoubleArray? = null
    @Volatile var rotta: Double = 0.0
    @Volatile var guida: Guida? = null

    private val principale = Handler(Looper.getMainLooper())
    private val ascoltatori = CopyOnWriteArrayList<() -> Unit>()
    private var canale: MethodChannel? = null
    private var sinkEnergia: EventChannel.EventSink? = null
    private var ultimaEnergia: Map<String, Any?>? = null

    fun ascolta(f: () -> Unit) = ascoltatori.add(f)

    fun smetti(f: () -> Unit) = ascoltatori.remove(f)

    fun collega(messenger: BinaryMessenger) {
        canale = MethodChannel(messenger, "gdanav/schermo_auto").also { c ->
            c.setMethodCallHandler { call, risultato ->
                gestisci(call)
                risultato.success(null)
            }
        }
        EventChannel(messenger, "gdanav/auto").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sinkEnergia = events
                ultimaEnergia?.let { events.success(it) }
            }

            override fun onCancel(arguments: Any?) {
                sinkEnergia = null
            }
        })
    }

    private fun gestisci(call: MethodCall) {
        when (call.method) {
            "stili" -> {
                stileChiaro = call.argument("chiaro")
                stileScuro = call.argument("scuro")
            }
            "sorgenti" -> {
                val nuove = HashMap(sorgenti)
                call.argument<Map<String, String>>("dati")?.let { nuove.putAll(it) }
                sorgenti = nuove
            }
            "posizione" -> {
                val lat = call.argument<Double>("lat")
                val lon = call.argument<Double>("lon")
                qui = if (lat != null && lon != null) doubleArrayOf(lat, lon) else null
                rotta = call.argument<Double>("rotta") ?: 0.0
            }
            "guida" -> {
                guida = if (call.argument<Boolean>("attiva") == true) {
                    Guida(
                        tipo = call.argument<Int>("tipo") ?: 8,
                        distanzaM = call.argument<Double>("distanza") ?: 0.0,
                        strada = call.argument<String>("strada") ?: "",
                        istruzione = call.argument<String>("istruzione") ?: "",
                        restantiM = call.argument<Double>("restanti") ?: 0.0,
                        restantiS = (call.argument<Number>("secondi") ?: 0).toLong(),
                        arrivoMs = (call.argument<Number>("arrivo") ?: System.currentTimeMillis()).toLong(),
                        destinazione = call.argument<String>("destinazione") ?: "",
                    )
                } else {
                    null
                }
            }
        }
        avvisa()
    }

    private fun avvisa() = principale.post { ascoltatori.forEach { it() } }

    /** Dall'auto: batteria in percentuale e autonomia in metri. */
    fun energiaDallAuto(batteria: Float, autonomiaM: Float?) {
        val dati = mapOf(
            "batteria" to batteria.toDouble(),
            "autonomia_km" to autonomiaM?.let { it / 1000.0 },
            "letto_ms" to System.currentTimeMillis(),
        )
        ultimaEnergia = dati
        principale.post { sinkEnergia?.success(dati) }
    }

    /** L'auto ha chiesto di finire la guida (tasto sullo schermo o assistente). */
    fun fermaDallAuto() = principale.post { canale?.invokeMethod("ferma", null) }
}
