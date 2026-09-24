package it.gdanav.gdanav.auto

import android.content.Context
import android.content.SharedPreferences
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

    /** Un posto da scegliere in auto: Casa, Lavoro, un preferito, un recente o un risultato. */
    data class Luogo(
        val etichetta: String,
        val nome: String,
        val descrizione: String,
        val lat: Double,
        val lon: Double,
        val tipo: String,
    ) {
        fun comeMappa(): Map<String, Any> =
            mapOf("nome" to nome, "descrizione" to descrizione, "lat" to lat, "lon" to lon)
    }

    @Volatile var luoghi: List<Luogo> = emptyList()

    /** Cosa dire quando non si guida: «Calcolo il percorso…», o cosa non va. */
    @Volatile var messaggio: String? = null

    /** gdanav Premium: l'app lo dice, l'auto lo ricorda anche a telefono spento. */
    private var preferenze: SharedPreferences? = null

    fun premium(context: Context): Boolean =
        context.getSharedPreferences("gdanav", Context.MODE_PRIVATE).getBoolean("premium", false)

    private val principale = Handler(Looper.getMainLooper())
    private val ascoltatori = CopyOnWriteArrayList<() -> Unit>()
    private var canale: MethodChannel? = null
    private var sinkEnergia: EventChannel.EventSink? = null
    private var ultimaEnergia: Map<String, Any?>? = null

    fun ascolta(f: () -> Unit) = ascoltatori.add(f)

    fun smetti(f: () -> Unit) = ascoltatori.remove(f)

    fun collega(messenger: BinaryMessenger, context: Context) {
        preferenze = context.applicationContext.getSharedPreferences("gdanav", Context.MODE_PRIVATE)
        canale = MethodChannel(messenger, "gdanav/schermo_auto").also { c ->
            c.setMethodCallHandler { call, risultato ->
                gestisci(call)
                risultato.success(null)
            }
        }
        EventChannel(messenger, "gdanav/auto").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sinkEnergia = events
                if (ultimaEnergia != null || ultimaVelocita != null) mandaAuto()
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
            "luoghi" -> {
                luoghi = (call.argument<List<Map<String, Any?>>>("elenco") ?: emptyList()).mapNotNull(::luogo)
            }
            "messaggio" -> messaggio = call.argument<String>("testo")
            "premium" -> preferenze?.edit()?.putBoolean("premium", call.argument<Boolean>("sbloccato") == true)?.apply()
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

    private fun luogo(m: Map<String, Any?>): Luogo? {
        val lat = (m["lat"] as? Number)?.toDouble() ?: return null
        val lon = (m["lon"] as? Number)?.toDouble() ?: return null
        val nome = m["nome"] as? String ?: return null
        return Luogo(
            etichetta = m["etichetta"] as? String ?: nome,
            nome = nome,
            descrizione = m["descrizione"] as? String ?: "",
            lat = lat,
            lon = lon,
            tipo = m["tipo"] as? String ?: "risultato",
        )
    }

    /** La ricerca fatta sull'auto, con Photon come sul telefono. */
    fun cerca(testo: String, risultati: (List<Luogo>) -> Unit) {
        val c = canale ?: return risultati(emptyList())
        c.invokeMethod("cerca", mapOf("testo" to testo), object : MethodChannel.Result {
            override fun success(r: Any?) {
                @Suppress("UNCHECKED_CAST")
                risultati(((r as? List<Map<String, Any?>>) ?: emptyList()).mapNotNull(::luogo))
            }

            override fun error(codice: String, messaggio: String?, dettagli: Any?) = risultati(emptyList())

            override fun notImplemented() = risultati(emptyList())
        })
    }

    /** Una meta scelta sull'auto: il telefono calcola e parte la guida. */
    fun vai(l: Luogo) {
        messaggio = "Calcolo il percorso per ${l.etichetta}…"
        avvisa()
        principale.post { canale?.invokeMethod("vai", l.comeMappa()) }
    }

    private fun avvisa() = principale.post { ascoltatori.forEach { it() } }

    private var ultimaVelocita: Double? = null
    private var ultimoOdometro: Double? = null

    /** Dall'auto: batteria in percentuale e autonomia in metri. */
    fun energiaDallAuto(batteria: Float, autonomiaM: Float?) {
        ultimaEnergia = mapOf(
            "batteria" to batteria.toDouble(),
            "autonomia_km" to autonomiaM?.let { it / 1000.0 },
        )
        mandaAuto()
    }

    /** Dall'auto: la velocità del cruscotto, in m/s. */
    fun velocitaDallAuto(ms: Float) {
        ultimaVelocita = ms * 3.6
        mandaAuto()
    }

    /** Dall'auto: il contachilometri, in metri. */
    fun contachilometriDallAuto(metri: Float) {
        ultimoOdometro = metri / 1000.0
        mandaAuto()
    }

    /** Tutto quello che l'auto ha detto finora, in una lettura sola. */
    private fun mandaAuto() {
        val dati = HashMap<String, Any?>(ultimaEnergia ?: emptyMap())
        dati["velocita_kmh"] = ultimaVelocita
        dati["odometro_km"] = ultimoOdometro
        dati["letto_ms"] = System.currentTimeMillis()
        principale.post { sinkEnergia?.success(dati) }
    }

    /** L'auto ha chiesto di finire la guida (tasto sullo schermo o assistente). */
    fun fermaDallAuto() = principale.post { canale?.invokeMethod("ferma", null) }
}
