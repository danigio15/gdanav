package it.gdanav.gdanav_app.auto

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * Quanto può pesare la scena 3D sullo schermo dell'auto, detto alla pagina
 * (`carico` in `web3d/src/messaggi.js`).
 *
 * «Quando è attiva la modalità 3D aumentata si rallenta anche lo
 * smartphone: se lo utilizzo va lento il telefono e il navigatore.» La scena
 * dell'auto e l'app aperta sul telefono si dividono la stessa scheda grafica,
 * e il telefono in auto è già caldo (il sole, la ricarica, il video verso
 * Android Auto). Qui si guarda:
 *
 *  - il calore: lo stato termico di Android (da Android 10) e il margine
 *    prima della frenata (da Android 11, `getThermalHeadroom`);
 *  - se il telefono si sta usando: lo schermo acceso e sbloccato.
 *
 * Ne esce un livello da 0 (tutto) a 3 (il minimo che si guida ancora bene):
 * la pagina abbassa i fotogrammi al secondo e la risoluzione interna. Il
 * livello si dice solo quando cambia; [ridici] lo rimanda (pagina ricaricata).
 */
internal class CaricoScena3d(context: Context, private val dici: (String) -> Unit) {
    private val app = context.applicationContext
    private val principale = Handler(Looper.getMainLooper())
    private val energia: PowerManager? = app.getSystemService(PowerManager::class.java)
    private val blocco: KeyguardManager? = app.getSystemService(KeyguardManager::class.java)
    private var detto: String? = null
    private var finito = false

    private val ricevitore = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) = aggiorna()
    }

    private val termico: Any? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        PowerManager.OnThermalStatusChangedListener { aggiorna() }
    } else {
        null
    }

    /** Il margine termico non ha un avviso: lo si guarda ogni tanto. */
    private val giro = object : Runnable {
        override fun run() {
            if (finito) return
            aggiorna()
            principale.postDelayed(this, OGNI_MS)
        }
    }

    init {
        try {
            val filtro = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            // Avvisi di sistema: niente da esportare.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                app.registerReceiver(ricevitore, filtro, Context.RECEIVER_NOT_EXPORTED)
            } else {
                app.registerReceiver(ricevitore, filtro)
            }
        } catch (e: Exception) {
            Log.w(Scena3dServizio.TAG, "lo schermo del telefono non si ascolta", e)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                energia?.addThermalStatusListener(app.mainExecutor, termico as PowerManager.OnThermalStatusChangedListener)
            } catch (e: Exception) {
                Log.w(Scena3dServizio.TAG, "lo stato termico non si ascolta", e)
            }
        }
        principale.post(giro)
    }

    /** Il livello dato dal margine termico l'ultima volta: per non andare su e giù. */
    private var livelloDelMargine = 0

    /** Il livello da 0 a 3, dal calore. */
    private fun livelloTermico(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
        val p = energia ?: return 0
        val stato = when (p.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT -> 0
            PowerManager.THERMAL_STATUS_MODERATE -> 1
            PowerManager.THERMAL_STATUS_SEVERE -> 2
            else -> 3
        }
        // Prima che Android freni: come andrà fra dieci secondi (1 = la frenata forte).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val h = p.getThermalHeadroom(10)
                if (!h.isNaN()) livelloDelMargine = livelloDalMargine(h, livelloDelMargine)
            } catch (_: Exception) {
            }
        }
        return maxOf(stato, livelloDelMargine)
    }

    /** Lo schermo del telefono acceso e sbloccato: qualcuno lo sta usando. */
    private fun telefonoInUso(): Boolean {
        val acceso = energia?.isInteractive ?: false
        val bloccato = blocco?.isKeyguardLocked ?: false
        return acceso && !bloccato
    }

    private fun aggiorna() {
        if (finito) return
        val livello = livelloTermico()
        val inUso = telefonoInUso()
        val js = "window.gdanav3d&&window.gdanav3d.ricevi({v:1,tipo:'carico',livello:$livello,telefono:$inUso})"
        if (js == detto) return
        detto = js
        Log.i(Scena3dServizio.TAG, "carico della scena: livello $livello, telefono in uso $inUso")
        dici(js)
    }

    /** La pagina è (ri)caricata: le si ridice il livello. */
    fun ridici() {
        detto = null
        aggiorna()
    }

    fun ferma() {
        if (finito) return
        finito = true
        principale.removeCallbacks(giro)
        try {
            app.unregisterReceiver(ricevitore)
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                energia?.removeThermalStatusListener(termico as PowerManager.OnThermalStatusChangedListener)
            } catch (_: Exception) {
            }
        }
    }

    internal companion object {
        /** Ogni quanto si guarda il margine termico (Android ne vuole al più uno al secondo). */
        private const val OGNI_MS = 10_000L

        /** Il margine termico da cui la scena si alleggerisce di uno, e di due. */
        private const val MARGINE_UNO = 0.85f
        private const val MARGINE_DUE = 0.95f

        /** Per tornare giù il margine deve scendere di tanto sotto la soglia. */
        private const val MARGINE_RITORNO = 0.07f

        /**
         * Il livello (0–2) dal margine termico [h] di Android (`getThermalHeadroom`:
         * 1 è la frenata forte), sapendo quello di [prima]: si sale appena
         * passata la soglia, si scende solo un po' sotto. Sul filo della
         * soglia la scena cambiava risoluzione ogni dieci secondi.
         */
        fun livelloDalMargine(h: Float, prima: Int): Int {
            val su = when {
                h >= MARGINE_DUE -> 2
                h >= MARGINE_UNO -> 1
                else -> 0
            }
            if (su >= prima) return su
            val giu = when {
                h >= MARGINE_DUE - MARGINE_RITORNO -> 2
                h >= MARGINE_UNO - MARGINE_RITORNO -> 1
                else -> 0
            }
            return minOf(prima, giu)
        }
    }
}
