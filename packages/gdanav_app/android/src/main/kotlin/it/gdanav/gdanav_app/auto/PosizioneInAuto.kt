package it.gdanav.gdanav_app.auto

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import it.gdanav.gdanav_app.R

/**
 * La posizione in auto, col telefono in tasca.
 *
 * Dal campo: «se non si apre l'app non lega il GPS». Per il telefono
 * un'app che sta sullo schermo dell'auto **non è davanti**: lo scrive la
 * libreria stessa dell'auto (`CarAppService`, «Accessing Location»), e alle
 * app che stanno dietro Android dà la posizione poche volte l'ora — il
 * permesso «mentre usi l'app» lì non vale. Aprendo l'app sul telefono l'app
 * tornava davanti e il GPS ripartiva: era quello, non un caso.
 *
 * Il rimedio è quello che la libreria consiglia, e che fanno i navigatori
 * veri: finché gdanav è sullo schermo dell'auto, un servizio **in primo
 * piano**, di tipo posizione, tiene l'app «in uso» per il GPS. Non legge
 * niente lui — la posizione la legge il Dart come sempre — ma con lui acceso
 * l'app intera conta come davanti, e il GPS arriva una volta al secondo
 * anche a schermo spento. Sul telefono resta una notifica quieta, finché si
 * è in macchina.
 *
 * Si **lega** e non si avvia (`bindService`, non `startForegroundService`):
 * un servizio avviato per stare davanti che poi non ci riesce fa cadere
 * l'app intera; uno legato resta un servizio qualunque. E Android può dire
 * di no — quando in quel momento l'app non la considera in uso — e allora si
 * riprova appena si può: a ogni ritorno sullo schermo dell'auto, e quando
 * l'app sul telefono torna davanti (`GdanavAppPlugin`).
 */
class PosizioneInAuto : Service() {
    private var davanti = false

    override fun onBind(intent: Intent?): IBinder {
        acceso = this
        mettiDavanti()
        return Binder()
    }

    override fun onDestroy() {
        if (acceso === this) acceso = null
        if (davanti) ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        davanti = false
        super.onDestroy()
    }

    /**
     * In primo piano, se il permesso della posizione c'è e Android lo lascia
     * fare. [ancora] lo richiede anche se ci è già: Android, a ogni richiesta,
     * riguarda se l'app è in uso, e chiesto con l'app sul telefono davanti la
     * posizione vale di sicuro fino a fine viaggio — anche dove all'inizio, con
     * l'app dietro, era partito senza (fino ad Android 13 succede in silenzio).
     */
    private fun mettiDavanti(ancora: Boolean = false) {
        if ((davanti && !ancora) || !haLaPosizione(this)) return
        try {
            ServiceCompat.startForeground(
                this,
                ID,
                notifica(),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0,
            )
            davanti = true
        } catch (e: Exception) {
            // Da Android 12 `ForegroundServiceStartNotAllowedException` con
            // l'app dietro, dal 14 una `SecurityException` se la posizione
            // «mentre usi l'app» adesso non vale: si riprova dopo.
        }
    }

    private fun notifica(): Notification {
        val gestore = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && gestore?.getNotificationChannel(CANALE) == null) {
            gestore?.createNotificationChannel(
                NotificationChannel(CANALE, "In auto", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "La posizione accesa mentre il navigatore è sullo schermo dell'auto"
                    setShowBadge(false)
                },
            )
        }
        val apri = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val n = NotificationCompat.Builder(this, CANALE)
            .setSmallIcon(R.drawable.icona_percorso)
            .setContentTitle("${applicationInfo.loadLabel(packageManager)} è in auto")
            .setContentText("La posizione resta accesa anche col telefono in tasca")
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        apri?.let { n.setContentIntent(it) }
        return n.build()
    }

    companion object {
        private const val ID = 4202
        private const val CANALE = "gdanav_in_auto"

        @Volatile private var acceso: PosizioneInAuto? = null
        private var legame: ServiceConnection? = null
        private var sessioni = 0

        private fun haLaPosizione(context: Context): Boolean =
            listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION).any {
                ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
            }

        /**
         * Una sessione dell'auto comincia: il servizio si lega e prova subito
         * a mettersi davanti. Una seconda sessione non ne lega un altro.
         */
        fun accendi(context: Context) {
            sessioni++
            if (legame != null) return riprova()
            val app = context.applicationContext
            val c = object : ServiceConnection {
                override fun onServiceConnected(nome: ComponentName?, servizio: IBinder?) {}

                override fun onServiceDisconnected(nome: ComponentName?) {}
            }
            val legato = try {
                app.bindService(Intent(app, PosizioneInAuto::class.java), c, Context.BIND_AUTO_CREATE)
            } catch (e: Exception) {
                false
            }
            if (legato) legame = c
        }

        /** La sessione dell'auto è finita: con l'ultima se ne va il servizio, e la notifica con lui. */
        fun spegni(context: Context) {
            if (sessioni > 0) sessioni--
            if (sessioni > 0) return
            val c = legame ?: return
            legame = null
            try {
                context.applicationContext.unbindService(c)
            } catch (e: Exception) {
            }
        }

        /** Lo schermo dell'auto è tornato su gdanav: se prima non era riuscito a mettersi davanti, ci riprova. */
        fun riprova() {
            acceso?.mettiDavanti()
        }

        /**
         * L'app sul telefono è davanti, in macchina: è il momento in cui
         * Android dice sempre di sì, e la posizione da lì resta accesa anche
         * col telefono di nuovo in tasca.
         */
        fun dalTelefono() {
            acceso?.mettiDavanti(ancora = true)
        }
    }
}
