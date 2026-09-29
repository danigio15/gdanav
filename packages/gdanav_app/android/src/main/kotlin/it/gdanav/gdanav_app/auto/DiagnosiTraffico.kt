package it.gdanav.gdanav_app.auto

import android.content.Context
import android.content.SharedPreferences
import android.graphics.RectF
import android.util.Log
import org.json.JSONObject
import org.maplibre.android.log.Logger
import org.maplibre.android.log.LoggerDefinition
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.tile.TileOperation
import java.util.concurrent.atomic.AtomicInteger

/**
 * Cosa ha visto del traffico la mappa dell'auto: se lo strato c'è, quanti
 * riquadri di TomTom sono arrivati e quanti no — con l'errore —, quanti
 * tratti di coda c'erano sullo schermo.
 *
 * «Sul telefono il traffico si vede, su Android Auto no.» Il codice dà
 * all'auto lo stesso strato del telefono, con la stessa chiave e la stessa
 * MapLibre: quindi o i riquadri sull'auto non arrivano, e qui si legge
 * l'errore, o arrivano e sullo schermo non c'era niente da disegnare. Lo si
 * legge dal telefono, nella scheda «Android Auto», anche a viaggio finito.
 *
 * Della chiave non si scrive mai niente: dagli errori si toglie.
 */
object DiagnosiTraffico {
    /** La sorgente e gli strati del traffico nello stile (`stile.dart`). */
    const val SORGENTE = "traffico"
    private val STRATI = arrayOf("traffico", "traffico-locale")
    private const val CHIAVE = "diagnosi_traffico"

    @Volatile var strato: Boolean? = null
    private val daRete = AtomicInteger()
    private val arrivati = AtomicInteger()
    private val errori = AtomicInteger()
    @Volatile private var ultimoErrore: String? = null
    @Volatile private var tratti = 0
    @Volatile private var massimo = 0
    @Volatile private var zoom = 0.0
    @Volatile private var quando = 0L
    @Volatile private var inizio = 0L
    private var preferenze: SharedPreferences? = null
    private var ascoltaLog = false

    /** Una sessione nuova sull'auto: i conti ripartono da zero. */
    fun inizia(context: Context) {
        preferenze = context.applicationContext.getSharedPreferences("gdanav", Context.MODE_PRIVATE)
        strato = null
        daRete.set(0)
        arrivati.set(0)
        errori.set(0)
        ultimoErrore = null
        tratti = 0
        massimo = 0
        zoom = 0.0
        quando = 0L
        inizio = System.currentTimeMillis()
        ascoltaErrori()
    }

    /** Ogni riquadro chiesto, arrivato o sbagliato, di qualunque sorgente: si contano quelli del traffico. */
    fun riquadro(operazione: TileOperation, sorgente: String?) {
        if (sorgente != SORGENTE) return
        when (operazione) {
            TileOperation.RequestedFromNetwork -> daRete.incrementAndGet()
            TileOperation.LoadFromNetwork, TileOperation.LoadFromCache -> arrivati.incrementAndGet()
            TileOperation.Error -> errori.incrementAndGet()
            else -> Unit
        }
    }

    /** Quanti tratti di coda ci sono adesso sullo schermo dell'auto. */
    fun contaTratti(mappa: MapLibreMap, larghezza: Int, altezza: Int) {
        if (larghezza <= 0 || altezza <= 0) return
        val n = try {
            mappa.queryRenderedFeatures(RectF(0f, 0f, larghezza.toFloat(), altezza.toFloat()), *STRATI).size
        } catch (e: Exception) {
            return
        }
        tratti = n
        zoom = mappa.cameraPosition.zoom
        quando = System.currentTimeMillis()
        if (n > massimo) massimo = n
        salva()
    }

    /*
     * Gli errori dei riquadri MapLibre li scrive nel suo registro («Failed to
     * load tile … for source traffico: HTTP status code 403»). Si ascolta il
     * registro, e tutto continua ad andare in logcat come prima.
     */
    private fun ascoltaErrori() {
        if (ascoltaLog) return
        ascoltaLog = true
        Logger.setLoggerDefinition(object : LoggerDefinition {
            override fun v(tag: String?, msg: String?) { Log.v(tag, msg ?: "") }
            override fun v(tag: String?, msg: String?, tr: Throwable?) { Log.v(tag, msg ?: "", tr) }
            override fun d(tag: String?, msg: String?) { Log.d(tag, msg ?: "") }
            override fun d(tag: String?, msg: String?, tr: Throwable?) { Log.d(tag, msg ?: "", tr) }
            override fun i(tag: String?, msg: String?) { Log.i(tag, msg ?: "") }
            override fun i(tag: String?, msg: String?, tr: Throwable?) { Log.i(tag, msg ?: "", tr) }
            override fun w(tag: String?, msg: String?) {
                Log.w(tag, msg ?: "")
                guarda(msg)
            }
            override fun w(tag: String?, msg: String?, tr: Throwable?) {
                Log.w(tag, msg ?: "", tr)
                guarda(msg)
            }
            override fun e(tag: String?, msg: String?) {
                Log.e(tag, msg ?: "")
                guarda(msg)
            }
            override fun e(tag: String?, msg: String?, tr: Throwable?) {
                Log.e(tag, msg ?: "", tr)
                guarda(msg)
            }
        })
    }

    private fun guarda(messaggio: String?) {
        val m = messaggio ?: return
        if (!m.contains("source $SORGENTE") && !m.contains("tomtom", ignoreCase = true)) return
        ultimoErrore = senzaChiave(m).take(240)
        salva()
    }

    /** Un indirizzo con la chiave dentro diventa un indirizzo senza. */
    fun senzaChiave(testo: String): String = testo.replace(Regex("""key=[^&\s"']+"""), "key=…")

    fun comeMappa(): Map<String, Any?> {
        val o = if (inizio > 0L) adesso() else letto() ?: return emptyMap()
        val mappa = HashMap<String, Any?>()
        for (k in o.keys()) mappa[k] = o.get(k).takeUnless { it == JSONObject.NULL }
        return mappa
    }

    private fun adesso() = JSONObject().apply {
        put("inizio", inizio)
        put("strato", strato ?: JSONObject.NULL)
        put("richiesti", daRete.get())
        put("arrivati", arrivati.get())
        put("errori", errori.get())
        put("ultimo_errore", ultimoErrore ?: JSONObject.NULL)
        put("tratti", tratti)
        put("massimo", massimo)
        put("zoom", zoom)
        put("quando", quando)
    }

    private fun letto(): JSONObject? = try {
        preferenze?.getString(CHIAVE, null)?.let { JSONObject(it) }
    } catch (e: Exception) {
        null
    }

    /** Anche a processo chiuso, la scheda sul telefono ritrova l'ultimo viaggio. */
    fun salva() {
        if (inizio == 0L) return
        preferenze?.edit()?.putString(CHIAVE, adesso().toString())?.apply()
    }

    /** Per la scheda sul telefono, dopo che il processo è ripartito. */
    fun leggi(context: Context) {
        if (preferenze == null) {
            preferenze = context.applicationContext.getSharedPreferences("gdanav", Context.MODE_PRIVATE)
        }
    }
}
