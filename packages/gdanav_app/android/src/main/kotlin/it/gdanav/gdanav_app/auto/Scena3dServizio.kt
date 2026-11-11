package it.gdanav.gdanav_app.auto

import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.ParcelFileDescriptor
import android.util.Log
import android.view.SurfaceControlViewHost
import android.view.WindowManager
import android.webkit.WebView
import androidx.annotation.RequiresApi
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * La scena 3D dell'auto in un processo suo (`:mappa3d`).
 *
 * «La navigazione continua ad avere frame lag, va a scatti soprattutto se
 * apro l'app GdAHome.» Il navigatore sull'auto gira dentro l'app, e una app
 * ha un solo motore web per tutte le sue WebView: la plancia sul telefono e
 * la scena 3D sull'auto si dividevano lo stesso filo di JavaScript, lo stesso
 * filo che disegna e lo stesso filo principale. Aperta la plancia, la mappa
 * dell'auto aspettava lei. Qui la scena ha il suo processo: il suo motore
 * web, il suo filo che disegna, il suo filo principale.
 *
 * L'app ([Scena3dLontana]) si lega a questo servizio e gli dà un posto sullo
 * schermo dell'auto (il gettone di una SurfaceView, da Android 11); il
 * servizio ci mette la WebView di [Scena3dAuto] con un
 * [SurfaceControlViewHost] e ne rimanda il pacchetto da incastrare. I
 * messaggi della regia e quelli della pagina passano per due tubi (i primi
 * sono lunghi: uno stile, un percorso, gli edifici di una tessera — troppo
 * per i messaggi fra processi di Android, che hanno un tetto).
 *
 * Se qualcosa non va (il processo non parte, il telefono è più vecchio, la
 * pagina tace) l'app torna alla scena dentro di sé, quella di sempre.
 */
class Scena3dServizio : Service() {
    private val principale = Handler(Looper.getMainLooper())
    private val messaggero = Messenger(
        Handler(Looper.getMainLooper()) { m ->
            ricevi(m)
            true
        },
    )

    private var ospite: SurfaceControlViewHost? = null
    private var scena: Scena3dAuto? = null
    private var versoLApp: DataOutputStream? = null
    private var dallApp: DataInputStream? = null
    private var scrittura: ExecutorService? = null

    /** A chi rispondere per la scena che si sta aprendo. */
    private var versoChiAprire: Messenger? = null

    /** Ogni apertura ha il suo numero: quello che resta di una chiusa non tocca la nuova. */
    private var giro = 0

    override fun onCreate() {
        super.onCreate()
        // Due processi della stessa app non possono usare la stessa cartella
        // della WebView: questo ha la sua. Va detto prima di ogni WebView.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                WebView.setDataDirectorySuffix(SUFFISSO)
            } catch (e: Exception) {
                Log.w(TAG, "la cartella della WebView era già scelta", e)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) messaggero.binder else null

    override fun onUnbind(intent: Intent?): Boolean {
        chiudi()
        return false
    }

    override fun onDestroy() {
        chiudi()
        super.onDestroy()
    }

    private fun ricevi(m: Message) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        when (m.what) {
            APRI -> {
                val risposta = m.replyTo
                versoChiAprire = risposta
                try {
                    apri(m.data)
                    val pacchetto = ospite?.surfacePackage ?: throw IllegalStateException("nessun pacchetto")
                    risposta?.send(
                        Message.obtain(null, PACCHETTO).apply { data = Bundle().apply { putParcelable(CHIAVE_PACCHETTO, pacchetto) } },
                    )
                } catch (e: Throwable) {
                    Log.w(TAG, "la scena non si apre", e)
                    chiudi()
                    try {
                        risposta?.send(
                            Message.obtain(null, GUASTO).apply { data = Bundle().apply { putString(CHIAVE_MOTIVO, e.javaClass.simpleName) } },
                        )
                    } catch (_: Exception) {
                    }
                }
            }
            MISURA -> {
                val w = m.arg1
                val h = m.arg2
                if (w > 0 && h > 0) {
                    try {
                        ospite?.relayout(w, h)
                    } catch (e: Exception) {
                        Log.w(TAG, "la scena non si ridimensiona", e)
                    }
                }
            }
            CHIUDI -> chiudi()
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun apri(dati: Bundle) {
        chiudi()
        dati.classLoader = javaClass.classLoader
        val mio = ++giro
        val gettone = dati.getBinder(CHIAVE_GETTONE)
        val larghezza = dati.getInt(CHIAVE_LARGHEZZA)
        val altezza = dati.getInt(CHIAVE_ALTEZZA)
        val notte = dati.getBoolean(CHIAVE_NOTTE)
        @Suppress("DEPRECATION")
        val entra = dati.getParcelable<ParcelFileDescriptor>(CHIAVE_ENTRA) ?: throw IllegalStateException("manca il tubo che entra")
        @Suppress("DEPRECATION")
        val esce = dati.getParcelable<ParcelFileDescriptor>(CHIAVE_ESCE) ?: throw IllegalStateException("manca il tubo che esce")
        val uscita = DataOutputStream(ParcelFileDescriptor.AutoCloseOutputStream(esce))
        val ingresso = DataInputStream(ParcelFileDescriptor.AutoCloseInputStream(entra))
        versoLApp = uscita
        dallApp = ingresso
        val fili = Executors.newSingleThreadExecutor()
        scrittura = fili

        val schermo = getSystemService(DisplayManager::class.java).getDisplay(dati.getInt(CHIAVE_SCHERMO))
            ?: throw IllegalStateException("lo schermo dell'auto non si vede da qui")
        val base: Context = createDisplayContext(schermo)
        // Un contesto da finestra, come vuole una WebView; se il telefono non
        // lo dà per questo schermo, quello dello schermo basta.
        val contesto = try {
            base.createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_PANEL, null)
        } catch (e: Exception) {
            base
        }
        val nuovo = SurfaceControlViewHost(contesto, schermo, gettone)
        ospite = nuovo
        val nuova = Scena3dAuto(contesto, notte) { testo -> scrivi(fili, uscita, MESSAGGIO, testo) }
        nuova.alMisurato = { nuova.scala?.let { scrivi(fili, uscita, SCALA, it.toString()) } }
        scena = nuova
        nuovo.setView(nuova.vista, larghezza, altezza)
        // Senza la scheda grafica la scena non si disegna (WebGL): meglio
        // dirlo subito, e l'app torna a quella dentro di sé.
        val risposta = versoChiAprire
        nuova.vista.post {
            if (giro == mio && !nuova.vista.isHardwareAccelerated) {
                try {
                    risposta?.send(
                        Message.obtain(null, GUASTO).apply { data = Bundle().apply { putString(CHIAVE_MOTIVO, "senza scheda grafica") } },
                    )
                } catch (_: Exception) {
                }
            }
        }

        // I messaggi della regia: letti da un filo suo, eseguiti sul principale.
        Thread({
            try {
                while (true) {
                    val tipo = ingresso.readByte().toInt()
                    val lungo = ingresso.readInt()
                    if (lungo < 0 || lungo > TETTO_MESSAGGIO) throw IOException("messaggio di $lungo byte")
                    val corpo = ByteArray(lungo)
                    ingresso.readFully(corpo)
                    if (tipo == JS) {
                        val js = String(corpo, Charsets.UTF_8)
                        principale.post { if (giro == mio) scena?.esegui(js) }
                    }
                }
            } catch (_: IOException) {
                // L'app ha chiuso il tubo (o se n'è andata): si chiude anche qui.
                principale.post { if (giro == mio) chiudi() }
            }
        }, "gdanav-3d-legge").start()
    }

    private fun scrivi(fili: ExecutorService, uscita: DataOutputStream, tipo: Int, testo: String) {
        try {
            fili.execute {
                try {
                    val corpo = testo.toByteArray(Charsets.UTF_8)
                    uscita.writeByte(tipo)
                    uscita.writeInt(corpo.size)
                    uscita.write(corpo)
                    uscita.flush()
                } catch (_: IOException) {
                }
            }
        } catch (_: Exception) {
            // Il filo è già chiuso: la scena sta andando via.
        }
    }

    private fun chiudi() {
        giro++
        scena?.distruggi()
        scena = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ospite?.release()
        } catch (e: Exception) {
            Log.w(TAG, "la scena non si rilascia", e)
        }
        ospite = null
        scrittura?.shutdownNow()
        scrittura = null
        val uscita = versoLApp
        val ingresso = dallApp
        versoLApp = null
        dallApp = null
        // Chiudere un tubo può aspettare chi ci sta scrivendo: non sul filo principale.
        if (uscita != null || ingresso != null) {
            Thread({
                try {
                    uscita?.close()
                } catch (_: IOException) {
                }
                try {
                    ingresso?.close()
                } catch (_: IOException) {
                }
            }, "gdanav-3d-chiude").start()
        }
    }

    internal companion object {
        const val TAG = "gdanav3d"

        /** La cartella della WebView di questo processo. */
        private const val SUFFISSO = "mappa3d"

        // I messaggi fra l'app e il servizio.
        const val APRI = 1
        const val MISURA = 2
        const val CHIUDI = 3
        const val PACCHETTO = 10
        const val GUASTO = 11

        const val CHIAVE_GETTONE = "gettone"
        const val CHIAVE_SCHERMO = "schermo"
        const val CHIAVE_LARGHEZZA = "larghezza"
        const val CHIAVE_ALTEZZA = "altezza"
        const val CHIAVE_NOTTE = "notte"
        const val CHIAVE_ENTRA = "entra"
        const val CHIAVE_ESCE = "esce"
        const val CHIAVE_PACCHETTO = "pacchetto"
        const val CHIAVE_MOTIVO = "motivo"

        // I tipi nei tubi: un byte, quattro di lunghezza, il testo in UTF-8.
        const val JS = 74
        const val MESSAGGIO = 77
        const val SCALA = 83

        /** Più di così non è un messaggio: il tubo si è guastato. */
        const val TETTO_MESSAGGIO = 64 * 1024 * 1024
    }
}
