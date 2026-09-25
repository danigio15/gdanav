package it.gdanav.gdanav_app.auto

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
        val uscita: String = "",
        val verso: String = "",
        val rotonda: Int? = null,
        val corsie: List<CorsiaAuto> = emptyList(),
        val dopoTipo: Int? = null,
        val dopoStrada: String = "",
        /** La vista dello svincolo da mostrare, se pronta (vedi [svincoli]). */
        val svincolo: Int? = null,
    )

    /** Una corsia prima dello svincolo: le frecce, se è giusta, quale seguire. */
    data class CorsiaAuto(val direzioni: List<String>, val giusta: Boolean, val consigliata: String?)

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

    fun casa(): Luogo? = luoghi.firstOrNull { it.tipo == "casa" }
    fun lavoro(): Luogo? = luoghi.firstOrNull { it.tipo == "lavoro" }

    /** Sopra la mappa: batteria, velocità e limite, arrivo, sosta, meteo. */
    data class Cruscotto(
        val batteria: Double? = null,
        val autonomiaKm: Double? = null,
        /** L'autonomia la dice l'auto (non una stima). */
        val autonomiaAuto: Boolean = false,
        val velocita: Double? = null,
        val limite: Int? = null,
        val arrivoBatteria: Double? = null,
        val sostaNome: String? = null,
        val sostaKm: Double? = null,
        val sostaBatteria: Double? = null,
        val meteoTemperatura: Double? = null,
        val meteoEmoji: String? = null,
        val meteoDove: String? = null,
    )

    @Volatile var cruscotto = Cruscotto()

    /** La segnalazione che si avvicina, e quella appena passata. */
    data class Avviso(
        val titolo: String? = null,
        val tipo: String? = null,
        val metri: Double? = null,
        val limite: Int? = null,
        val ancoraId: String? = null,
        val ancoraTesto: String? = null,
    )

    @Volatile var avviso = Avviso()

    /** Le opzioni del percorso e la voce, per il menu. */
    @Volatile var opzioni: Map<String, Any?> = emptyMap()

    /** Le viste degli svincoli, disegnate dall'app: le ultime, per manovra. */
    @Volatile var svincoli: Map<Int, Bitmap> = emptyMap()

    /** Le icone delle segnalazioni, disegnate dall'app. */
    @Volatile var immagini: Map<String, Bitmap> = emptyMap()

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

    /**
     * Cresce quando cambia qualcosa dei modelli di Android Auto (manovra,
     * messaggi, luoghi, opzioni): il resto (posizione, cruscotto) ridisegna
     * solo la mappa, senza consumare gli aggiornamenti concessi dall'auto.
     */
    @Volatile var versioneModello = 0
        private set

    private val soloMappa = setOf("posizione", "sorgenti", "cruscotto", "immagini", "stili")

    private fun gestisci(call: MethodCall) {
        val prima = avviso.ancoraId
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
            "cruscotto" -> cruscotto = Cruscotto(
                batteria = numero(call, "batteria"),
                autonomiaKm = numero(call, "autonomia_km"),
                autonomiaAuto = call.argument<Boolean>("autonomia_auto") == true,
                velocita = numero(call, "velocita"),
                limite = numero(call, "limite")?.toInt(),
                arrivoBatteria = numero(call, "arrivo_batteria"),
                sostaNome = call.argument<String>("sosta_nome"),
                sostaKm = numero(call, "sosta_km"),
                sostaBatteria = numero(call, "sosta_batteria"),
                meteoTemperatura = numero(call, "meteo_temperatura"),
                meteoEmoji = call.argument<String>("meteo_emoji"),
                meteoDove = call.argument<String>("meteo_dove"),
            )
            "avviso" -> avviso = Avviso(
                titolo = call.argument<String>("titolo"),
                tipo = call.argument<String>("tipo"),
                metri = numero(call, "metri"),
                limite = numero(call, "limite")?.toInt(),
                ancoraId = call.argument<String>("ancora_id"),
                ancoraTesto = call.argument<String>("ancora_testo"),
            )
            "opzioni" -> opzioni = (call.arguments as? Map<*, *>)?.entries?.associate { "${it.key}" to it.value } ?: emptyMap()
            "svincolo" -> {
                val id = numero(call, "id")?.toInt()
                val png = call.argument<ByteArray>("png")
                val bitmap = png?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                if (id != null && bitmap != null) {
                    svincoli = svincoli.entries.toList().takeLast(2).associate { it.key to it.value } + (id to bitmap)
                }
            }
            "immagini" -> {
                val nuove = HashMap(immagini)
                (call.argument<Map<String, ByteArray>>("png") ?: emptyMap()).forEach { (nome, byte) ->
                    BitmapFactory.decodeByteArray(byte, 0, byte.size)?.let { nuove[nome] = it }
                }
                immagini = nuove
            }
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
                        uscita = call.argument<String>("uscita") ?: "",
                        verso = call.argument<String>("verso") ?: "",
                        rotonda = numero(call, "rotonda")?.toInt(),
                        corsie = (call.argument<List<Map<String, Any?>>>("corsie") ?: emptyList()).map { c ->
                            CorsiaAuto(
                                direzioni = (c["direzioni"] as? List<*>)?.map { "$it" } ?: emptyList(),
                                giusta = c["giusta"] == true,
                                consigliata = c["consigliata"] as? String,
                            )
                        },
                        dopoTipo = numero(call, "dopo_tipo")?.toInt(),
                        dopoStrada = call.argument<String>("dopo_strada") ?: "",
                        svincolo = numero(call, "svincolo")?.toInt(),
                    )
                } else {
                    null
                }
            }
        }
        if (call.method !in soloMappa && (call.method != "avviso" || avviso.ancoraId != prima)) versioneModello++
        avvisa()
    }

    private fun numero(call: MethodCall, chiave: String): Double? = (call.argument<Any?>(chiave) as? Number)?.toDouble()

    /** Una domanda all'app, con la risposta sul filo principale. */
    fun chiedi(metodo: String, argomenti: Any?, risposta: (Any?) -> Unit = {}) {
        val c = canale ?: return risposta(null)
        principale.post {
            c.invokeMethod(metodo, argomenti, object : MethodChannel.Result {
                override fun success(r: Any?) = risposta(r)

                override fun error(codice: String, messaggio: String?, dettagli: Any?) = risposta(null)

                override fun notImplemented() = risposta(null)
            })
        }
    }

    /** Casa o Lavoro scelti dalla ricerca sull'auto. */
    fun imposta(tipo: String, l: Luogo, fatto: (Boolean) -> Unit) =
        chiedi("imposta", mapOf("tipo" to tipo, "luogo" to l.comeMappa())) { fatto(it == true) }

    fun cambiaOpzione(chiave: String, valore: Any) = chiedi("opzioni", mapOf(chiave to valore))

    fun alternaVoce() = chiedi("voce", null)

    /** Segnala dove sei; la risposta è la frase da mostrare. */
    fun segnala(tipo: String, risposta: (String) -> Unit) =
        chiedi("segnala", mapOf("tipo" to tipo)) { risposta(it as? String ?: "Non è partita.") }

    fun ancora(id: String, si: Boolean) = chiedi("ancora", mapOf("id" to id, "si" to si))

    /** Le colonnine rapide vicine, come luoghi da raggiungere. */
    fun colonnine(risultati: (List<Luogo>) -> Unit) = chiedi("colonnine", null) { r ->
        @Suppress("UNCHECKED_CAST")
        risultati(((r as? List<Map<String, Any?>>) ?: emptyList()).mapNotNull { luogo(it + ("tipo" to "colonnina")) })
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
        versioneModello++
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
