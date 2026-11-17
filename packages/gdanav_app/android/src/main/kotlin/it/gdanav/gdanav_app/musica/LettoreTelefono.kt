package it.gdanav.gdanav_app.musica

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
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
import android.os.SystemClock
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
import java.util.concurrent.Executors

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
 *
 * Poco lavoro, e fuori dai piedi della mappa: all'altra app si chiede solo
 * quando cambia il lettore (poi valgono i dati che arrivano coi richiami);
 * la copertina si rifà solo se cambiano titolo, artista o immagine, e il PNG
 * per il telefono si comprime su un altro filo; i richiami a raffica (certe
 * app ne mandano uno al secondo) si accorpano, uno ogni [OGNI_MS]; e lo
 * schermo dell'auto si avvisa solo se cambia qualcosa che si vede. Tutto il
 * resto si tocca dal filo principale.
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

    /** La compressione della copertina, fuori dal filo principale. */
    private val lavoro = Executors.newSingleThreadExecutor()
    private val ascoltatori = CopyOnWriteArrayList<() -> Unit>()
    private var contesto: Context? = null
    private var gestore: MediaSessionManager? = null
    private var controllore: MediaController? = null

    /** Gli ultimi dati del lettore, come sono arrivati: non si richiedono a ogni giro. */
    private var metadati: MediaMetadata? = null
    private var statoLettore: PlaybackState? = null

    /** Di quale brano è la copertina tenuta: app, titolo, artista, album. */
    private var chiaveBrano: String? = null

    /** La copertina com'è arrivata, quella ridotta, e il suo PNG per il telefono. */
    private var copertinaGrezza: Bitmap? = null
    private var copertina: Bitmap? = null
    private var copertinaPng: ByteArray? = null

    /** La copertina che il PNG (fatto o in arrivo) rappresenta. */
    private var pngDi: Bitmap? = null

    /** Il nome dell'ultima app, per non richiederlo al sistema a ogni giro. */
    private var nomeApp: Pair<String, String?>? = null

    /**
     * [AscoltoNotifiche] è collegato dal sistema: il permesso c'è di sicuro,
     * anche nell'attimo in cui le impostazioni non lo dicono ancora.
     */
    @Volatile private var collegato = false

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
                    leggiSubito()
                    risultato.success(stato())
                }
                "ferma" -> {
                    // «Musica nel navigatore» spenta: l'invito in auto non
                    // torna più, nemmeno riaccendendola.
                    maiPiuInvito(ctx)
                    vogliono.remove(messenger)
                    if (vogliono.isEmpty()) accendi(ctx, false)
                    leggiSubito()
                    risultato.success(stato())
                }
                "chiediPermesso" -> {
                    apriPermesso(ctx)
                    risultato.success(stato())
                }
                // L'invito sul telefono è stato visto o chiuso («Non ora»):
                // in auto non lo si ripete più.
                "invitoVisto" -> {
                    maiPiuInvito(ctx)
                    risultato.success(null)
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

    private fun componente(context: Context) = ComponentName(context, AscoltoNotifiche::class.java)

    /**
     * Se GdANav ha l'«Accesso alle notifiche».
     *
     * Lo si chiede al sistema (dall'API 27), non all'impostazione
     * `enabled_notification_listeners`: quella Android la scrive un quarto di
     * secondo **dopo** aver collegato il servizio, e chi dava il permesso con
     * l'app già viva trovava «no» proprio nell'unico momento in cui si
     * guardava — niente musica fino al viaggio dopo. In più, se il servizio è
     * collegato ([collegato]) il permesso c'è di sicuro.
     */
    fun haPermesso(context: Context): Boolean {
        if (collegato) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            try {
                val sistema = context.getSystemService(NotificationManager::class.java)
                if (sistema != null) return sistema.isNotificationListenerAccessGranted(componente(context))
            } catch (_: Exception) {
                // Un telefono che non risponde: si guarda l'impostazione.
            }
        }
        return NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)
    }

    /**
     * Il sistema ha collegato ([si]) o scollegato [AscoltoNotifiche]: il
     * permesso è appena stato dato o tolto. Si riguarda subito, e ancora
     * qualche volta nei secondi dopo: il sistema ci mette un attimo a
     * lasciar vedere i lettori delle altre app, e la musica deve partire
     * adesso, non al prossimo viaggio.
     */
    fun servizio(context: Context, si: Boolean) {
        val ctx = context.applicationContext
        collegato = si
        ricontrolla(ctx)
        for (tra in RIPROVE_MS) principale.postDelayed({ ricontrolla(ctx) }, tra)
    }

    private val RIPROVE_MS = longArrayOf(300L, 1_000L, 3_000L)

    /**
     * La pagina del sistema dove si dà il permesso: dall'API 30 proprio
     * quella del nostro servizio («GdANav: musica»), prima l'elenco.
     */
    fun intentPermesso(context: Context): Intent {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, componente(context).flattenToString())
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
        val ctx = context.applicationContext
        principale.post {
            contesto = contesto ?: ctx
            if (acceso) accendi(ctx, true) else aggiornaPermesso(ctx)
        }
    }

    private fun aggiornaPermesso(context: Context) {
        val prima = permesso
        permesso = haPermesso(context)
        // Dato il permesso, l'invito sul telefono non serve più.
        if (permesso && !prima) togliNotificaPermesso(context)
        if (prima != permesso) programma()
    }

    private const val CANALE = "gdanav_musica"
    private const val ID_PERMESSO = 4202

    /** Dove si ricorda, oltre la sessione, l'invito al permesso dato in auto. */
    private const val PREFERENZE = "gdanav"
    private const val INVITO_VOLTE = "musica_invito_volte"
    private const val INVITO_MAI = "musica_invito_mai"

    /** Quante volte in tutto l'invito al permesso compare in auto. */
    private const val INVITI_AL_PIU = 2

    /**
     * Se in auto si può ancora invitare a dare il permesso: la musica è
     * accesa e il permesso manca, l'invito è stato dato meno di
     * [INVITI_AL_PIU] volte in tutto, e nessuno ha detto «Non ora» né ha
     * spento «Musica nel navigatore» ([maiPiuInvito]).
     */
    fun invitoPossibile(context: Context): Boolean {
        // Col servizio collegato il permesso c'è: se qui risulta di no è solo
        // l'attimo in cui il sistema non lascia ancora vedere i lettori.
        if (!senzaPermesso || collegato) return false
        val p = context.applicationContext.getSharedPreferences(PREFERENZE, Context.MODE_PRIVATE)
        return !p.getBoolean(INVITO_MAI, false) && p.getInt(INVITO_VOLTE, 0) < INVITI_AL_PIU
    }

    /** L'invito in auto è stato dato: una volta di più, e si ricorda. */
    fun invitoDato(context: Context) {
        val p = context.applicationContext.getSharedPreferences(PREFERENZE, Context.MODE_PRIVATE)
        p.edit().putInt(INVITO_VOLTE, p.getInt(INVITO_VOLTE, 0) + 1).apply()
    }

    private fun maiPiuInvito(context: Context) {
        context.applicationContext.getSharedPreferences(PREFERENZE, Context.MODE_PRIVATE)
            .edit().putBoolean(INVITO_MAI, true).apply()
        togliNotificaPermesso(context)
    }

    /**
     * Sul telefono, quando in auto manca il permesso: una notifica che apre
     * dritta la pagina del sistema ([intentPermesso]). Chi usa GdANav solo in
     * auto l'invito dell'app non lo vede mai. Silenziosa: non suona, non
     * vibra e non salta fuori, la si trova da fermi. Senza il permesso delle
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
                NotificationChannelCompat.Builder(CANALE, NotificationManagerCompat.IMPORTANCE_LOW)
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
                .setSilent(true)
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
        // I dati arrivano col richiamo: si tengono, senza richiederli
        // all'altra app (ogni richiesta si porta dietro tutta la copertina).
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            metadati = metadata
            programma()
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            statoLettore = state
            programma()
        }

        override fun onSessionDestroyed() {
            principale.post {
                val g = gestore
                val ctx = contesto
                if (g != null && ctx != null) sessioni(g, ctx)?.let { scegli(it) }
            }
        }
    }

    private fun accendi(context: Context, si: Boolean) {
        acceso = si
        aggiornaPermesso(context)
        val g = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        if (!si || !permesso || g == null) {
            stacca()
            programma()
            return
        }
        if (gestore == null) {
            try {
                g.addOnActiveSessionsChangedListener(sessioniCambiate, componente(context), principale)
                gestore = g
            } catch (_: SecurityException) {
                // Il permesso è appena stato tolto (o non è ancora arrivato
                // fin qui: ci pensano le riprove di [servizio]).
                permessoTolto()
                return
            }
        }
        sessioni(g, context)?.let { scegli(it) }
    }

    /** Si smette di ascoltare i lettori. */
    private fun stacca() {
        try {
            gestore?.removeOnActiveSessionsChangedListener(sessioniCambiate)
        } catch (_: Exception) {}
        gestore = null
        cambiaControllore(null)
    }

    /** Il sistema dice che il permesso non c'è: come spento, finché non torna. */
    private fun permessoTolto() {
        permesso = false
        stacca()
        programma()
    }

    /** I lettori aperti; `null` se il sistema non li lascia vedere (permesso tolto). */
    private fun sessioni(g: MediaSessionManager, context: Context): List<MediaController>? = try {
        g.getActiveSessions(componente(context))
    } catch (_: SecurityException) {
        permessoTolto()
        null
    }

    /** Fra i lettori aperti, quello che suona; se nessuno suona, il primo. */
    private fun scegli(elenco: List<MediaController>) {
        val suona = elenco.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
        val scelto = suona ?: elenco.firstOrNull { it.packageName == controllore?.packageName } ?: elenco.firstOrNull()
        cambiaControllore(scelto)
    }

    private fun cambiaControllore(nuovo: MediaController?) {
        if (nuovo == null || nuovo.sessionToken != controllore?.sessionToken) {
            controllore?.unregisterCallback(richiamo)
            controllore = nuovo
            nuovo?.registerCallback(richiamo, principale)
        }
        // L'unica lettura chiesta all'altra app: da qui valgono i richiami.
        metadati = try {
            nuovo?.metadata
        } catch (_: Exception) {
            null
        }
        statoLettore = try {
            nuovo?.playbackState
        } catch (_: Exception) {
            null
        }
        programma()
    }

    /** Un giro di [leggi] è già in programma (si tocca solo dal filo principale). */
    private var inProgramma = false
    private var ultimoGiro = 0L
    private val giro = Runnable {
        inProgramma = false
        ultimoGiro = SystemClock.uptimeMillis()
        leggi()
    }

    /**
     * È cambiato qualcosa: si rilegge, ma al più una volta ogni [OGNI_MS]. I
     * richiami arrivano a raffica (a ogni cambio di brano: metadati senza e
     * con copertina, buffering, play), e certe app ne mandano uno al secondo.
     */
    private fun programma() {
        if (inProgramma) return
        inProgramma = true
        val tra = (ultimoGiro + OGNI_MS - SystemClock.uptimeMillis()).coerceIn(0L, OGNI_MS)
        principale.postDelayed(giro, tra)
    }

    /** Si rilegge adesso: la risposta al telefono deve dire com'è. */
    private fun leggiSubito() {
        principale.removeCallbacks(giro)
        inProgramma = false
        ultimoGiro = SystemClock.uptimeMillis()
        leggi()
    }

    private const val OGNI_MS = 250L

    private fun leggi() {
        val c = controllore
        if (c == null) {
            chiaveBrano = null
            copertinaGrezza = null
            copertina = null
            copertinaPng = null
            pngDi = null
            brano = null
            avvisa()
            return
        }
        val m = metadati
        val titolo = m?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: ""
        val artista = m?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: m?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: ""
        val grezza = m?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: m?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: m?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        // La copertina (e il suo PNG) si rifà solo se è cambiato il brano o
        // l'immagine: a ogni «play» e «pausa» resta quella.
        val chiave = "${c.packageName}|$titolo|$artista|${m?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""}"
        if (chiave != chiaveBrano || !stessaImmagine(grezza, copertinaGrezza)) {
            chiaveBrano = chiave
            copertinaGrezza = grezza
            val ridotta = try {
                grezza?.let(::piccola)
            } catch (_: Exception) {
                null
            }
            copertina = ridotta
            comprimi(ridotta)
        }
        val quale = statoLettore?.state
        val suona = quale == PlaybackState.STATE_PLAYING || quale == PlaybackState.STATE_BUFFERING
        brano = Brano(nomeDi(c.packageName), titolo, artista, suona, copertina)
        avvisa()
    }

    /** Se due copertine sono la stessa immagine (l'app la rimanda uguale a ogni richiamo). */
    private fun stessaImmagine(a: Bitmap?, b: Bitmap?): Boolean {
        if (a === b) return true
        if (a == null || b == null || a.width != b.width || a.height != b.height) return false
        return try {
            a.sameAs(b)
        } catch (_: Exception) {
            false
        }
    }

    /** Il nome dell'app che suona («Spotify»), chiesto al sistema una volta per app. */
    private fun nomeDi(pacchetto: String): String? {
        nomeApp?.let { if (it.first == pacchetto) return it.second }
        val nome = try {
            val pm = contesto?.packageManager
            pm?.getApplicationLabel(pm.getApplicationInfo(pacchetto, 0))?.toString()
        } catch (_: Exception) {
            null
        }
        nomeApp = pacchetto to nome
        return nome
    }

    /** Il PNG della copertina per il telefono, su un altro filo: pronto, va al telefono. */
    private fun comprimi(immagine: Bitmap?) {
        pngDi = immagine
        copertinaPng = null
        if (immagine == null) return
        lavoro.execute {
            val byte = try {
                val out = ByteArrayOutputStream()
                immagine.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.toByteArray()
            } catch (_: Exception) {
                null
            }
            principale.post {
                if (pngDi === immagine) {
                    copertinaPng = byte
                    // Se non è riuscito, il telefono resta senza copertina:
                    // non si riprova a ogni giro.
                    if (byte == null) pngDi = null
                    mandaStato()
                }
            }
        }
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
        return mapOf(
            "permesso" to permesso,
            "app" to b?.app,
            "titolo" to b?.titolo,
            "artista" to b?.artista,
            "suona" to (b?.suona == true),
            "copertina" to copertinaPng,
            "durata_ms" to metadati?.getLong(MediaMetadata.METADATA_KEY_DURATION),
            "posizione_ms" to statoLettore?.position,
        )
    }

    private fun mandaStato() {
        val s = stato()
        for (m in vogliono) canali[m]?.invokeMethod("stato", s)
    }

    /** Quello che l'auto mostra del lettore, l'ultima volta che gliel'si è detto. */
    private var visto: List<Any?>? = null

    private fun avvisa() {
        // Col PNG della copertina ancora in arrivo il telefono aspetta lui
        // (qualche millisecondo): se no vedrebbe il brano nuovo senza
        // copertina, e subito dopo con.
        if (pngDi == null || copertinaPng != null) mandaStato()
        // L'auto solo se cambia qualcosa che si vede: la posizione nel brano
        // no, e ogni avviso le fa rifare mappa e pannello.
        val b = brano
        val ora = listOf(acceso, permesso, b?.app, b?.titolo, b?.artista, b?.suona, b?.copertina)
        if (ora == visto) return
        visto = ora
        for (f in ascoltatori) f()
    }
}
