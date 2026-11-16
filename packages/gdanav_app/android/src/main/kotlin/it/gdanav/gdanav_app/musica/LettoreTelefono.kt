package it.gdanav.gdanav_app.musica

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import it.gdanav.gdanav_app.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Il lettore musicale del telefono, qualunque app suoni (Spotify, YouTube
 * Music, Amazon Music…): il brano, la copertina, play/pausa, e i comandi
 * precedente / play-pausa / successivo.
 *
 * Android lo lascia fare con `MediaSessionManager.getActiveSessions`, a
 * patto che l'utente abbia dato «Accesso alle notifiche» a GdANav
 * ([AscoltoNotifiche]): senza, [permesso] è falso e non si chiede niente al
 * sistema. Niente SDK, niente account.
 *
 * Uno per il processo: lo usano il telefono (dal canale `gdanav/musica`,
 * `lib/componenti/mini_lettore.dart`) e lo schermo di Android Auto
 * (`auto/SchermoNavigazione.kt`, `auto/PannelloAuto.kt`), che lo leggono
 * direttamente. È lo stesso processo: il servizio dell'auto, il motore
 * Flutter, [AscoltoNotifiche] e Firebase non hanno un `android:process`
 * (solo la scena 3D, `Scena3dServizio`, ne ha uno suo), e lo controlla
 * `test/processi_test.dart`. Si accende solo con «Musica nel navigatore»
 * accesa ([acceso], lo dice il telefono con `avvia`/`ferma`), con o senza
 * un percorso: come in Waze, la musica c'è anche a mappa libera.
 */
object LettoreTelefono {
    /** Il brano come lo vede l'auto. */
    data class Brano(
        val app: String?,
        val titolo: String,
        val artista: String,
        val suona: Boolean,
        val copertina: Bitmap?,
    )

    @Volatile var acceso = false
        private set

    @Volatile var permesso = false
        private set

    /** Quello che suona adesso; `null` se nessuna app ha un lettore aperto. */
    @Volatile var brano: Brano? = null
        private set

    /** Se l'auto deve mostrare il brano: accesa, col permesso, e qualcosa da dire. */
    val daMostrare: Boolean get() = acceso && permesso && brano != null

    /**
     * Se l'auto mette ⏯ in alto: accesa e col permesso, anche se nessuna app
     * ha un lettore aperto. Allora ⏯ fa come il tasto play del volante
     * ([comando]): il sistema riprende l'ultima app che suonava, e appena
     * suona arrivano il brano e ⏭.
     */
    val conTasti: Boolean get() = acceso && permesso

    /** Manca solo il permesso: la musica è accesa, l'«Accesso alle notifiche» no. */
    val senzaPermesso: Boolean get() = acceso && !permesso

    private val principale = Handler(Looper.getMainLooper())
    private val ascoltatori = CopyOnWriteArrayList<() -> Unit>()
    private var contesto: Context? = null
    private var gestore: MediaSessionManager? = null
    private var controllore: MediaController? = null
    private var copertinaPng: ByteArray? = null
    private var copertinaDi: Bitmap? = null

    /** I canali dei motori Flutter che hanno chiesto la musica (`avvia`). */
    private val canali = mutableMapOf<BinaryMessenger, MethodChannel>()
    private val vogliono = mutableSetOf<BinaryMessenger>()

    fun ascolta(f: () -> Unit) = ascoltatori.add(f)

    fun smetti(f: () -> Unit) = ascoltatori.remove(f)

    /** Il canale `gdanav/musica` di un motore Flutter (dal plugin). */
    fun collega(messenger: BinaryMessenger, context: Context) {
        contesto = context.applicationContext
        val c = MethodChannel(messenger, "gdanav/musica")
        canali[messenger] = c
        c.setMethodCallHandler { call, risultato ->
            val ctx = contesto
            if (ctx == null) {
                risultato.success(null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "avvia" -> {
                    vogliono.add(messenger)
                    accendi(ctx, true)
                    risultato.success(stato())
                }
                "ferma" -> {
                    vogliono.remove(messenger)
                    if (vogliono.isEmpty()) accendi(ctx, false)
                    risultato.success(stato())
                }
                "chiediPermesso" -> {
                    apriPermesso(ctx)
                    risultato.success(stato())
                }
                "comando" -> {
                    comando(call.arguments as? String ?: "")
                    risultato.success(null)
                }
                else -> risultato.notImplemented()
            }
        }
    }

    fun scollega(messenger: BinaryMessenger) {
        canali.remove(messenger)?.setMethodCallHandler(null)
        if (vogliono.remove(messenger) && vogliono.isEmpty()) contesto?.let { accendi(it, false) }
    }

    /** Se GdANav ha l'«Accesso alle notifiche». */
    fun haPermesso(context: Context): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    /**
     * La pagina del sistema dove si dà il permesso: dall'API 30 proprio
     * quella del nostro servizio («GdANav: musica»), prima l'elenco.
     */
    fun intentPermesso(context: Context): Intent {
        val componente = ComponentName(context, AscoltoNotifiche::class.java)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, componente.flattenToString())
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /** La pagina del sistema dove si dà il permesso, su GdANav se si può. */
    fun apriPermesso(context: Context) {
        try {
            context.startActivity(intentPermesso(context))
        } catch (_: Exception) {
            try {
                context.startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (_: Exception) {
                // Un telefono senza quella pagina: resta senza musica.
            }
        }
    }

    /** Il permesso può essere cambiato: si torna a guardare. */
    fun ricontrolla(context: Context) {
        contesto = contesto ?: context.applicationContext
        principale.post { if (acceso) accendi(context.applicationContext, true) else aggiornaPermesso(context) }
    }

    private fun aggiornaPermesso(context: Context) {
        val prima = permesso
        permesso = haPermesso(context)
        // Dato il permesso, l'invito sul telefono non serve più.
        if (permesso && !prima) togliNotificaPermesso(context)
        if (prima != permesso) avvisa()
    }

    private const val CANALE = "gdanav_musica"
    private const val ID_PERMESSO = 4202

    /**
     * Sul telefono, quando in auto manca il permesso: una notifica che apre
     * dritta la pagina del sistema ([intentPermesso]). Chi usa GdANav solo in
     * auto l'invito dell'app non lo vede mai. Senza il permesso delle
     * notifiche (Android 13) non c'è, e resta l'invito nell'app.
     */
    @SuppressLint("MissingPermission")
    fun notificaPermesso(context: Context) {
        val ctx = context.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val gestore = NotificationManagerCompat.from(ctx)
        try {
            gestore.createNotificationChannel(
                NotificationChannelCompat.Builder(CANALE, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                    .setName("Musica nel navigatore")
                    .setDescription("L'invito a consentire la musica nel navigatore")
                    .setSound(null, null)
                    .setVibrationEnabled(false)
                    .build(),
            )
            val apri = PendingIntent.getActivity(
                ctx,
                ID_PERMESSO,
                intentPermesso(ctx),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val n = NotificationCompat.Builder(ctx, CANALE)
                .setSmallIcon(R.drawable.auto_play)
                .setContentTitle("Musica nel navigatore")
                .setContentText("Tocca e consenti l'accesso alle notifiche a «GdANav: musica»")
                .setStyle(
                    NotificationCompat.BigTextStyle().bigText(
                        "Per vedere e comandare la musica sullo schermo dell'auto: tocca qui e consenti " +
                            "l'accesso alle notifiche a «GdANav: musica». GdANav non legge le notifiche.",
                    ),
                )
                .setContentIntent(apri)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
                .build()
            gestore.notify(ID_PERMESSO, n)
        } catch (_: Exception) {
            // Un telefono che non la mostra: resta l'invito nell'app.
        }
    }

    private fun togliNotificaPermesso(context: Context) {
        try {
            NotificationManagerCompat.from(context).cancel(ID_PERMESSO)
        } catch (_: Exception) {}
    }

    private val sessioniCambiate = MediaSessionManager.OnActiveSessionsChangedListener { elenco ->
        scegli(elenco.orEmpty())
    }

    private val richiamo = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = leggi()

        override fun onPlaybackStateChanged(state: PlaybackState?) = leggi()

        override fun onSessionDestroyed() {
            principale.post { gestore?.let { g -> contesto?.let { scegli(sessioni(g, it)) } } }
        }
    }

    private fun accendi(context: Context, si: Boolean) {
        acceso = si
        aggiornaPermesso(context)
        val g = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        if (!si || !permesso || g == null) {
            try {
                gestore?.removeOnActiveSessionsChangedListener(sessioniCambiate)
            } catch (_: Exception) {}
            gestore = null
            cambiaControllore(null)
            avvisa()
            return
        }
        if (gestore == null) {
            try {
                g.addOnActiveSessionsChangedListener(
                    sessioniCambiate,
                    ComponentName(context, AscoltoNotifiche::class.java),
                    principale,
                )
                gestore = g
            } catch (_: SecurityException) {
                // Il permesso è appena stato tolto.
                permesso = false
                avvisa()
                return
            }
        }
        scegli(sessioni(g, context))
    }

    private fun sessioni(g: MediaSessionManager, context: Context): List<MediaController> = try {
        g.getActiveSessions(ComponentName(context, AscoltoNotifiche::class.java))
    } catch (_: SecurityException) {
        emptyList()
    }

    /** Fra i lettori aperti, quello che suona; se nessuno suona, il primo. */
    private fun scegli(elenco: List<MediaController>) {
        val suona = elenco.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
        val scelto = suona ?: elenco.firstOrNull { it.packageName == controllore?.packageName } ?: elenco.firstOrNull()
        cambiaControllore(scelto)
    }

    private fun cambiaControllore(nuovo: MediaController?) {
        if (nuovo?.sessionToken == controllore?.sessionToken && nuovo != null) {
            leggi()
            return
        }
        controllore?.unregisterCallback(richiamo)
        controllore = nuovo
        nuovo?.registerCallback(richiamo, principale)
        leggi()
    }

    private fun leggi() {
        val c = controllore
        val ctx = contesto
        val m = c?.metadata
        val titolo = m?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: ""
        val artista = m?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: m?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: ""
        val copertina = m?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: m?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: m?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        val app = c?.packageName?.let { p ->
            try {
                val pm = ctx?.packageManager
                pm?.getApplicationLabel(pm.getApplicationInfo(p, 0))?.toString()
            } catch (_: Exception) {
                null
            }
        }
        val suona = c?.playbackState?.state.let {
            it == PlaybackState.STATE_PLAYING || it == PlaybackState.STATE_BUFFERING
        }
        brano = if (c == null) null else Brano(app, titolo, artista, suona, copertina?.let(::piccola))
        avvisa()
    }

    /** La copertina al più di 256 punti: l'auto e il telefono la vogliono piccola. */
    private fun piccola(b: Bitmap): Bitmap {
        val lato = maxOf(b.width, b.height)
        if (lato <= 256) return b
        val f = 256f / lato
        return Bitmap.createScaledBitmap(b, (b.width * f).toInt().coerceAtLeast(1), (b.height * f).toInt().coerceAtLeast(1), true)
    }

    fun comando(quale: String) {
        val t = controllore?.transportControls
        if (t == null) {
            // Nessun lettore aperto: ⏯ come il tasto play del volante, il
            // sistema lo dà all'ultima app che suonava (Spotify chiusa da
            // poco, la radio). Se suona, arriva la sua sessione.
            if (quale == "playPausa" && conTasti) tastoPlay()
            return
        }
        try {
            when (quale) {
                "precedente" -> t.skipToPrevious()
                "successivo" -> t.skipToNext()
                "playPausa" -> if (brano?.suona == true) t.pause() else t.play()
            }
        } catch (_: Exception) {
            // L'app che suona non accetta il comando: resta com'è.
        }
    }

    private fun tastoPlay() {
        val audio = contesto?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY))
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY))
        } catch (_: Exception) {
            // Nessuno che lo prenda: resta in silenzio.
        }
    }

    /** Lo stato per il telefono, come lo legge `LettoreDelTelefono.leggi`. */
    private fun stato(): Map<String, Any?> {
        val b = brano
        val img = b?.copertina
        if (img !== copertinaDi) {
            copertinaDi = img
            copertinaPng = img?.let {
                val out = ByteArrayOutputStream()
                it.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.toByteArray()
            }
        }
        val c = controllore
        return mapOf(
            "permesso" to permesso,
            "app" to b?.app,
            "titolo" to b?.titolo,
            "artista" to b?.artista,
            "suona" to (b?.suona == true),
            "copertina" to copertinaPng,
            "durata_ms" to c?.metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION),
            "posizione_ms" to c?.playbackState?.position,
        )
    }

    private fun avvisa() {
        val s = stato()
        for (m in vogliono) canali[m]?.invokeMethod("stato", s)
        for (f in ascoltatori) f()
    }
}
