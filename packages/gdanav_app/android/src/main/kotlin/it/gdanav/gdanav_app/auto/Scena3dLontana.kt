package it.gdanav.gdanav_app.auto

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
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
import android.view.SurfaceView
import android.view.View
import androidx.annotation.RequiresApi
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * La scena 3D dell'auto che gira nel suo processo ([Scena3dServizio]), vista
 * dall'app: una SurfaceView nella Presentation di [RendererMappa] in cui il
 * servizio incastra la sua WebView. Perché, lo dice [Scena3dServizio].
 *
 * Per [RendererMappa] è una [Scena3d] come quella dentro l'app. La vista
 * resta nascosta finché il servizio non ha mandato il pacchetto (sotto si
 * vede ancora la mappa di sempre, non un buco nero), poi [alVisibile].
 *
 * Tutto quello che può andare storto finisce in [alGuasto], una volta sola:
 * il servizio che non si lega, il processo che muore, un tubo che si rompe,
 * la coda dei messaggi che non scorre, la pagina che non dice niente entro
 * [ATTESA_MS]. Chi la usa allora la chiude e apre la scena dentro l'app.
 */
@RequiresApi(Build.VERSION_CODES.R)
internal class Scena3dLontana(
    context: Context,
    private val notte: Boolean,
    private val allaRegia: (String) -> Unit,
    private val alGuasto: (String) -> Unit,
) : Scena3d {
    private val app = context.applicationContext
    private val principale = Handler(Looper.getMainLooper())

    override val vista: SurfaceView = SurfaceView(context).apply { visibility = View.INVISIBLE }

    @Volatile override var scala: Float? = null
        private set
    override var alMisurato: (() -> Unit)? = null

    @Volatile override var haParlato = false
        private set

    override var visibile = false
        private set
    override var alVisibile: (() -> Unit)? = null

    @Volatile private var finita = false
    private var guasta = false
    private var legata = false
    private var aperta = false
    private var servizio: Messenger? = null
    private var larghezzaDetta = 0
    private var altezzaDetta = 0

    /** Verso il servizio: i messaggi della regia, uno alla volta e in ordine. */
    @Volatile private var versoLei: DataOutputStream? = null
    private var daLei: DataInputStream? = null

    /* Un filo solo che scrive nel tubo, con una coda che ha un fondo: se il
     * servizio smette di leggere la coda si riempie, e invece di crescere
     * senza fine è un guasto. */
    private val scrittura = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS, LinkedBlockingQueue<Runnable>(CODA_MASSIMA))

    private val risposte = Messenger(
        Handler(Looper.getMainLooper()) { m ->
            risposta(m)
            true
        },
    )

    private val legame = object : ServiceConnection {
        override fun onServiceConnected(nome: ComponentName?, binder: IBinder?) {
            if (finita || binder == null) return
            servizio = Messenger(binder)
            apriSePronta()
        }

        override fun onServiceDisconnected(nome: ComponentName?) {
            servizio = null
            guasto("processo")
        }

        override fun onBindingDied(nome: ComponentName?) = guasto("legame morto")

        override fun onNullBinding(nome: ComponentName?) = guasto("nessun legame")
    }

    private val attesa = Runnable { if (!haParlato) guasto("tempo") }

    init {
        vista.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) = apriSePronta()

            override fun onViewDetachedFromWindow(v: View) {}
        })
        vista.addOnLayoutChangeListener { _, sx, su, dx, gi, _, _, _, _ ->
            val w = dx - sx
            val h = gi - su
            if (!aperta) {
                apriSePronta()
            } else if (w > 0 && h > 0 && (w != larghezzaDetta || h != altezzaDetta)) {
                larghezzaDetta = w
                altezzaDetta = h
                manda(Message.obtain(null, Scena3dServizio.MISURA, w, h))
            }
        }
        legata = try {
            app.bindService(Intent(app, Scena3dServizio::class.java), legame, Context.BIND_AUTO_CREATE or Context.BIND_IMPORTANT)
        } catch (e: Exception) {
            Log.w(Scena3dServizio.TAG, "il servizio della scena non si lega", e)
            false
        }
        if (!legata) principale.post { guasto("legame") }
        principale.postDelayed(attesa, ATTESA_MS)
    }

    /** Legato il servizio e messa la vista nella finestra: gli si chiede la scena. */
    private fun apriSePronta() {
        if (finita || guasta || aperta) return
        val s = servizio ?: return
        if (!vista.isAttachedToWindow) return
        val w = vista.width
        val h = vista.height
        if (w <= 0 || h <= 0) return
        val schermo = vista.display ?: return
        // Il gettone della finestra: senza, il servizio non ha dove incastrarsi.
        val gettone = vista.hostToken ?: return
        val giu = tubo()
        val su = tubo()
        if (giu == null || su == null) {
            chiudiTubi(giu, su)
            guasto("tubi")
            return
        }
        try {
            val dati = Bundle().apply {
                putBinder(Scena3dServizio.CHIAVE_GETTONE, gettone)
                putInt(Scena3dServizio.CHIAVE_SCHERMO, schermo.displayId)
                putInt(Scena3dServizio.CHIAVE_LARGHEZZA, w)
                putInt(Scena3dServizio.CHIAVE_ALTEZZA, h)
                putBoolean(Scena3dServizio.CHIAVE_NOTTE, notte)
                putParcelable(Scena3dServizio.CHIAVE_ENTRA, giu[0])
                putParcelable(Scena3dServizio.CHIAVE_ESCE, su[1])
            }
            s.send(Message.obtain(null, Scena3dServizio.APRI).apply {
                data = dati
                replyTo = risposte
            })
        } catch (e: Exception) {
            Log.w(Scena3dServizio.TAG, "la scena lontana non si apre", e)
            chiudiTubi(giu, su)
            guasto("apertura")
            return
        }
        aperta = true
        larghezzaDetta = w
        altezzaDetta = h
        // I capi dati al servizio qui non servono più: lui ne ha una copia.
        try {
            giu[0].close()
            su[1].close()
        } catch (_: IOException) {
        }
        versoLei = DataOutputStream(ParcelFileDescriptor.AutoCloseOutputStream(giu[1]))
        val ingresso = DataInputStream(ParcelFileDescriptor.AutoCloseInputStream(su[0]))
        daLei = ingresso
        Thread({ leggi(ingresso) }, "gdanav-3d-ascolta").start()
    }

    private fun tubo(): Array<ParcelFileDescriptor>? = try {
        ParcelFileDescriptor.createPipe()
    } catch (e: IOException) {
        null
    }

    private fun chiudiTubi(vararg tubi: Array<ParcelFileDescriptor>?) {
        for (coppia in tubi) {
            for (capo in coppia ?: continue) {
                try {
                    capo.close()
                } catch (_: IOException) {
                }
            }
        }
    }

    /** Quello che dice la pagina, dal servizio: alla regia dal filo principale. */
    private fun leggi(ingresso: DataInputStream) {
        try {
            while (true) {
                val tipo = ingresso.readByte().toInt()
                val lungo = ingresso.readInt()
                if (lungo < 0 || lungo > Scena3dServizio.TETTO_MESSAGGIO) throw IOException("messaggio di $lungo byte")
                val corpo = ByteArray(lungo)
                ingresso.readFully(corpo)
                val testo = String(corpo, Charsets.UTF_8)
                when (tipo) {
                    Scena3dServizio.MESSAGGIO -> {
                        haParlato = true
                        principale.post { if (!finita) allaRegia(testo) }
                    }
                    Scena3dServizio.SCALA -> testo.toFloatOrNull()?.let { nuova ->
                        if (nuova > 0f) {
                            principale.post {
                                if (!finita) {
                                    scala = nuova
                                    alMisurato?.invoke()
                                }
                            }
                        }
                    }
                }
            }
        } catch (_: IOException) {
            // Chiuso da qui ([distruggi]) non è un guasto; chiuso da là sì.
            principale.post { guasto("canale") }
        }
    }

    private fun risposta(m: Message) {
        if (finita || guasta) return
        when (m.what) {
            Scena3dServizio.PACCHETTO -> {
                try {
                    @Suppress("DEPRECATION")
                    val pacchetto = m.data.getParcelable<SurfaceControlViewHost.SurfacePackage>(Scena3dServizio.CHIAVE_PACCHETTO)
                        ?: throw IllegalStateException("pacchetto vuoto")
                    vista.setChildSurfacePackage(pacchetto)
                    vista.visibility = View.VISIBLE
                    visibile = true
                    alVisibile?.invoke()
                } catch (e: Exception) {
                    Log.w(Scena3dServizio.TAG, "il pacchetto della scena non si incastra", e)
                    guasto("pacchetto")
                }
            }
            Scena3dServizio.GUASTO -> guasto("servizio: " + (m.data?.getString(Scena3dServizio.CHIAVE_MOTIVO) ?: "?"))
        }
    }

    private fun manda(m: Message) {
        try {
            servizio?.send(m)
        } catch (e: Exception) {
            guasto("messaggio")
        }
    }

    override fun esegui(js: String) {
        if (finita || guasta) return
        val uscita = versoLei ?: return
        try {
            scrittura.execute {
                try {
                    val corpo = js.toByteArray(Charsets.UTF_8)
                    uscita.writeByte(Scena3dServizio.JS)
                    uscita.writeInt(corpo.size)
                    uscita.write(corpo)
                    uscita.flush()
                } catch (_: IOException) {
                    principale.post { guasto("scrittura") }
                }
            }
        } catch (_: RejectedExecutionException) {
            guasto("coda")
        }
    }

    /** Una volta sola, dal filo principale, e mai dopo [distruggi]. */
    private fun guasto(motivo: String) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            principale.post { guasto(motivo) }
            return
        }
        if (finita || guasta) return
        guasta = true
        Log.w(Scena3dServizio.TAG, "la scena lontana non va ($motivo): si torna a quella dentro l'app")
        alGuasto(motivo)
    }

    override fun distruggi() {
        if (finita) return
        finita = true
        principale.removeCallbacks(attesa)
        try {
            servizio?.send(Message.obtain(null, Scena3dServizio.CHIUDI))
        } catch (_: Exception) {
        }
        servizio = null
        if (legata) {
            legata = false
            try {
                app.unbindService(legame)
            } catch (_: Exception) {
            }
        }
        scrittura.shutdownNow()
        val uscita = versoLei
        val ingresso = daLei
        versoLei = null
        daLei = null
        // Chiudere un tubo può aspettare chi ci sta scrivendo: non sul filo principale.
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

    private companion object {
        /** Quanto si aspetta che la pagina, nel suo processo, dica qualcosa. */
        const val ATTESA_MS = 12_000L

        /** Quanti messaggi della regia possono aspettare il tubo. */
        const val CODA_MASSIMA = 400
    }
}
