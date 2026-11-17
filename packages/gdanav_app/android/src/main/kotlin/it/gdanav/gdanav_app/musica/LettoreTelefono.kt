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
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import it.gdanav.gdanav_app.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * Il lettore musicale del telefono, qualunque app suoni (Spotify, YouTube
 * Music, Amazon Music…): il brano, la copertina, play/pausa, a che punto è, e
 * i comandi precedente / play-pausa / successivo, con quali l'app accetta.
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
 *
 * La copertina è quella che l'app dichiara: l'immagine dell'album, o quella
 * del brano, o l'icona; e se l'app dà solo un indirizzo (o un'immagine
 * minuscola), la si legge da lì, fuori dal filo principale
 * ([caricaCopertina]). Resta in memoria finché non cambia il brano.
 *
 * A che punto è il brano ([posizioneMs]) non fa notizia: chi lo mostra (la
 * barra del lettore sull'auto) lo chiede quando disegna, una volta al secondo.
 */
object LettoreTelefono {
    /** Il brano come lo vede l'auto. */
    data class Brano(
        val app: String?,
        val titolo: String,
        val artista: String,
        val suona: Boolean,
        val copertina: Bitmap?,
        /** Quanto dura, in millisecondi; 0 se l'app non lo dice (una radio). */
        val durataMs: Long = 0L,
        /**
         * I comandi che il lettore dell'app dichiara di accettare adesso
         * (`PlaybackState.actions`): un tasto che non farebbe niente si
         * disegna spento.
         */
        val puoPrecedente: Boolean = true,
        val puoSuccessivo: Boolean = true,
        val puoPlayPausa: Boolean = true,
    )

    @Volatile var acceso = false
        private set

    @Volatile var permesso = false
        private set

    /** Quello che suona adesso; `null` se nessuna app ha un lettore aperto. */
    @Volatile var brano: Brano? = null
        private set

    /**
     * Se l'auto deve mostrare il brano: accesa, col permesso, e qualcosa da
     * dire; o la musica di casa che suona qui ([LettoreDiCasa]), che non
     * chiede né il permesso né l'interruttore: l'ha fatta partire chi guida.
     */
    val daMostrare: Boolean get() = (acceso && permesso || mostraCasa) && brano != null

    /**
     * Il brano è quello della musica di casa ([LettoreDiCasa]): suona, o è in
     * pausa e nessun'altra app suona al suo posto. Allora i tasti vanno a lei.
     */
    @Volatile var mostraCasa = false
        private set

    /**
     * Se l'auto mette i comandi della musica (nel lettore sulla mappa, o ⏯ in
     * alto sulle auto che non mandano i tocchi): accesa e col permesso, anche
     * se nessuna app ha un lettore aperto. Allora ▶ fa partire l'app della
     * musica ([prossima], «▶ Spotify»: vedi [AvvioMusica]), e appena suona
     * arrivano il brano e gli altri tasti.
     */
    val conTasti: Boolean get() = acceso && permesso || mostraCasa

    /**
     * L'app che ▶ fa partire quando niente suona (quella scelta nelle
     * impostazioni, Spotify di serie, l'ultima che ha suonato), col nome e
     * l'icona; `null` se non se ne sa nessuna.
     */
    val prossima: AvvioMusica.App?
        get() {
            val ctx = contesto ?: return null
            return if (conTasti) AvvioMusica.prossima(ctx) else null
        }

    /** Si sta facendo partire la musica: «Avvio Spotify…». */
    val inAvvio: Boolean get() = AvvioMusica.inCorso != null

    /** L'app che si sta facendo partire, se se ne sa quale. */
    val appInAvvio: AvvioMusica.App? get() = AvvioMusica.inCorso?.app

    /** Il nome dell'app che si sta facendo partire. */
    val nomeInAvvio: String? get() = appInAvvio?.nome

    /** Un avvio che non è partito: il messaggio da dire una volta. */
    val esito: AvvioMusica.Esito? get() = AvvioMusica.esito

    /** Manca solo il permesso: la musica è accesa, l'«Accesso alle notifiche» no. */
    val senzaPermesso: Boolean get() = acceso && !permesso

    private val principale = Handler(Looper.getMainLooper())

    init {
        // La musica di casa cambia (parte, brano nuovo, pausa): si rilegge.
        LettoreDiCasa.ascolta { principale.post { programma() } }
    }

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

    /** L'indirizzo da cui si è letta (o si sta leggendo) la copertina di questo brano. */
    private var indirizzoCopertina: String? = null

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
                    comando(call.arguments as? String ?: "", dallAuto = false)
                    risultato.success(null)
                }
                // ▶ con niente che suona, dalla pillola del telefono:
                // `{da_fermi}` (da fermi, all'ultimo si può aprire l'app).
                "parti" -> {
                    val daFermi = (call.arguments as? Map<*, *>)?.get("da_fermi") == true
                    if (conTasti) AvvioMusica.parti(ctx, dallAuto = false, daFermi = daFermi)
                    risultato.success(stato())
                }
                // L'elenco per «App della musica» nelle impostazioni.
                "appDellaMusica" -> risultato.success(elencoApp(ctx))
                "scegliApp" -> {
                    AvvioMusica.scegli(ctx, call.arguments as? String)
                    leggiSubito()
                    risultato.success(elencoApp(ctx))
                }
                "esitoDetto" -> {
                    (call.arguments as? Number)?.let {
                        AvvioMusica.esitoDetto(it.toInt())
                        if (it.toInt() == ID_ERRORE_CASA) LettoreDiCasa.erroreDetto()
                    }
                    risultato.success(null)
                }
                // La musica di casa (`lib/componenti/musica_di_casa.dart`):
                // l'elenco per lo schermo dell'auto, e da suonare qui.
                "casa" -> {
                    MusicaDiCasa.aggiorna(call.arguments)
                    avvisaLAuto()
                    risultato.success(null)
                }
                "suonaFlussi" -> {
                    val a = call.arguments as? Map<*, *>
                    val voci = (a?.get("voci") as? List<*>).orEmpty().mapNotNull { v ->
                        val m = v as? Map<*, *> ?: return@mapNotNull null
                        val url = m["url"] as? String ?: return@mapNotNull null
                        val byte = m["immagine"] as? ByteArray
                        LettoreDiCasa.Flusso(
                            id = m["id"] as? String ?: url,
                            titolo = m["titolo"] as? String ?: "",
                            sotto = m["sotto"] as? String ?: "",
                            url = url,
                            mime = m["mime"] as? String,
                            immagine = LettoreDiCasa.immagine(byte),
                            immagineByte = byte,
                        )
                    }
                    val esito = LettoreDiCasa.suona(
                        ctx,
                        voci,
                        (a?.get("da") as? Number)?.toInt() ?: 0,
                        a?.get("nome") as? String,
                        a?.get("radio") == true,
                    )
                    leggiSubito()
                    risultato.success(mapOf("esito" to esito, "stato" to stato()))
                }
                "suonaNellApp" -> {
                    val a = call.arguments as? Map<*, *>
                    val app = a?.get("app") as? String
                    val esito = if (app == null) {
                        "Non c'è l'app"
                    } else {
                        AvvioMusica.suonaNellApp(
                            ctx,
                            app,
                            a["uri"] as? String,
                            a["cerca"] as? String,
                            a["titolo"] as? String ?: "",
                            dallAuto = false,
                            daFermi = a["da_fermi"] == true,
                        )
                    }
                    leggiSubito()
                    risultato.success(mapOf("esito" to esito, "stato" to stato()))
                }
                "fermaCasa" -> {
                    LettoreDiCasa.ferma()
                    leggiSubito()
                    risultato.success(stato())
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
            AvvioMusica.annulla()
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
        // Le app della musica possono essere cambiate (una installata, la
        // scelta fatta sul telefono): quella di ▶ si riguarda.
        AvvioMusica.rileggi(context)
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
        AvvioMusica.annulla()
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

    /**
     * Fra i lettori aperti, quello che suona; se nessuno suona, il primo.
     * Mentre parte un'app ([AvvioMusica]) si tiene il suo, anche se il
     * sistema non lo mette ancora fra gli attivi.
     */
    private fun scegli(tutte: List<MediaController>) {
        // Mai una nostra: la musica di casa non ha sessione, la si legge da
        // [LettoreDiCasa].
        val elenco = tutte.filter { it.packageName != contesto?.packageName }
        sessioniAttive = elenco
        val suona = elenco.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
        val stessa = elenco.firstOrNull { it.packageName == controllore?.packageName }
        val dellAvvio = controllore?.takeIf { AvvioMusica.eDellAvvio(it) }
        val scelto = suona ?: stessa ?: dellAvvio ?: elenco.firstOrNull()
        cambiaControllore(scelto)
    }

    /**
     * La sessione dell'app che si sta facendo partire, dal suo
     * `MediaBrowserService` ([AvvioMusica]): agganciata subito, così il
     * pannello mostra brano e tasti appena suona. Se un'altra app sta già
     * suonando, resta quella.
     */
    internal fun aggancia(c: MediaController) {
        if (brano?.suona == true && controllore?.packageName != c.packageName) return
        cambiaControllore(c)
    }

    /** L'avvio della musica è cambiato (partito, in corso, non partito): lo si dice a chi guarda. */
    internal fun avvioCambiato() {
        principale.post { avvisa() }
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

    /** L'`esito_id` di un flusso di casa che non si sente (gli avvii hanno id da 1 in su). */
    private const val ID_ERRORE_CASA = -7

    private fun leggi() {
        // La musica di casa, se suona o se nessun'altra app suona al suo posto.
        val altraSuona = controllore != null && statoLettore?.state == PlaybackState.STATE_PLAYING
        mostraCasa = LettoreDiCasa.attivo && (LettoreDiCasa.suona || LettoreDiCasa.carica || !altraSuona)
        if (mostraCasa) {
            // Tornando all'altra app la sua copertina si rifà.
            chiaveBrano = null
            copertinaGrezza = null
            copertina = null
            copertinaPng = null
            pngDi = null
            indirizzoCopertina = null
            brano = LettoreDiCasa.brano()
            avvisa()
            return
        }
        val c = controllore
        if (c == null) {
            chiaveBrano = null
            copertinaGrezza = null
            copertina = null
            copertinaPng = null
            pngDi = null
            indirizzoCopertina = null
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
        // Senza immagine, o con una minuscola (certe app danno solo
        // un'iconcina e l'indirizzo di quella vera): la si legge da lì.
        val indirizzo = if (grezza == null || maxOf(grezza.width, grezza.height) < COPERTINA_MINUSCOLA) {
            INDIRIZZI_COPERTINA.firstNotNullOfOrNull { k -> m?.getString(k)?.takeIf { it.isNotBlank() } }
        } else {
            null
        }
        // La copertina (e il suo PNG) si rifà solo se è cambiato il brano o
        // l'immagine: a ogni «play» e «pausa» resta quella.
        val chiave = "${c.packageName}|$titolo|$artista|${m?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""}"
        if (chiave != chiaveBrano || !stessaImmagine(grezza, copertinaGrezza) || indirizzo != indirizzoCopertina) {
            chiaveBrano = chiave
            copertinaGrezza = grezza
            indirizzoCopertina = indirizzo
            val ridotta = try {
                grezza?.let(::piccola)
            } catch (_: Exception) {
                null
            }
            copertina = ridotta
            comprimi(ridotta)
            if (indirizzo != null) caricaCopertina(indirizzo, chiave)
        }
        val stato = statoLettore
        val quale = stato?.state
        val suona = quale == PlaybackState.STATE_PLAYING || quale == PlaybackState.STATE_BUFFERING
        // Un lettore che non dichiara nessun comando (0) non è che non ne
        // accetti: non lo dice. Allora i tasti restano accesi.
        val azioni = stato?.actions ?: 0L
        fun puo(quali: Long) = azioni == 0L || azioni and quali != 0L
        // Suona: se si stava facendo partire quest'app ci si è riusciti, e
        // la si ricorda come l'ultima che ha suonato.
        if (quale == PlaybackState.STATE_PLAYING) contesto?.let { AvvioMusica.suona(it, c.packageName) }
        brano = Brano(
            app = nomeDi(c.packageName),
            titolo = titolo,
            artista = artista,
            suona = suona,
            copertina = copertina,
            durataMs = (m?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L).coerceAtLeast(0L),
            puoPrecedente = puo(PlaybackState.ACTION_SKIP_TO_PREVIOUS),
            puoSuccessivo = puo(PlaybackState.ACTION_SKIP_TO_NEXT),
            puoPlayPausa = puo(
                PlaybackState.ACTION_PLAY_PAUSE or if (suona) PlaybackState.ACTION_PAUSE else PlaybackState.ACTION_PLAY,
            ),
        )
        avvisa()
    }

    /**
     * A che punto è il brano adesso, in millisecondi: l'ultima posizione detta
     * dal lettore, più il tempo passato da allora se sta suonando. 0 se non
     * si sa. Dal filo principale.
     */
    fun posizioneMs(): Long {
        if (mostraCasa) return LettoreDiCasa.posizioneMs()
        val s = statoLettore ?: return 0L
        var p = s.position
        if (p < 0L) return 0L
        val detta = s.lastPositionUpdateTime
        if (s.state == PlaybackState.STATE_PLAYING && detta > 0L) {
            p += ((SystemClock.elapsedRealtime() - detta) * s.playbackSpeed).toLong()
        }
        val durata = brano?.durataMs ?: 0L
        return if (durata > 0L) p.coerceIn(0L, durata) else p.coerceAtLeast(0L)
    }

    /** Sotto questo lato, in pixel, la copertina dell'app è un'iconcina: si cerca quella vera. */
    private const val COPERTINA_MINUSCOLA = 160

    /** Dove l'app può dire l'indirizzo della copertina, dal più preciso. */
    private val INDIRIZZI_COPERTINA = listOf(
        MediaMetadata.METADATA_KEY_ALBUM_ART_URI,
        MediaMetadata.METADATA_KEY_ART_URI,
        MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI,
    )

    /** Al più tanti byte per una copertina letta da un indirizzo. */
    private const val COPERTINA_AL_PIU = 6 * 1024 * 1024

    /**
     * La copertina da un [indirizzo], su un altro filo: quando arriva prende
     * il posto di quella che c'era (niente, o l'iconcina), se il brano è
     * ancora quello ([chiave]). Se non si riesce a leggere resta com'è, e non
     * si riprova finché il brano non cambia.
     */
    private fun caricaCopertina(indirizzo: String, chiave: String) {
        val ctx = contesto ?: return
        lavoro.execute {
            val letta = try {
                leggiImmagine(ctx, indirizzo)?.let(::piccola)
            } catch (_: Exception) {
                null
            } catch (_: OutOfMemoryError) {
                null
            }
            if (letta != null) {
                principale.post {
                    if (chiaveBrano == chiave && indirizzoCopertina == indirizzo && controllore != null) {
                        copertina = letta
                        comprimi(letta)
                        brano = brano?.copy(copertina = letta)
                        avvisa()
                    }
                }
            }
        }
    }

    /**
     * L'immagine a quell'indirizzo, già ridotta nel leggerla. Solo indirizzi
     * del telefono (`content:`, `android.resource:`) e `https:`: niente file
     * di altre app e niente rete in chiaro.
     */
    private fun leggiImmagine(context: Context, indirizzo: String): Bitmap? {
        val uri = Uri.parse(indirizzo)
        val flusso: InputStream = when (uri.scheme?.lowercase()) {
            "content", "android.resource" -> context.contentResolver.openInputStream(uri)
            "https" -> {
                val rete = URI(indirizzo).toURL().openConnection() as HttpURLConnection
                rete.connectTimeout = 4_000
                rete.readTimeout = 6_000
                rete.instanceFollowRedirects = true
                rete.inputStream
            }
            else -> null
        } ?: return null
        val byte = flusso.use { f ->
            val out = ByteArrayOutputStream()
            val pezzo = ByteArray(16 * 1024)
            while (true) {
                val n = f.read(pezzo)
                if (n < 0) break
                out.write(pezzo, 0, n)
                if (out.size() > COPERTINA_AL_PIU) return null
            }
            out.toByteArray()
        }
        val misura = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(byte, 0, byte.size, misura)
        val lato = maxOf(misura.outWidth, misura.outHeight)
        if (lato <= 0) return null
        var passo = 1
        while (lato / (passo * 2) >= 256) passo *= 2
        return BitmapFactory.decodeByteArray(byte, 0, byte.size, BitmapFactory.Options().apply { inSampleSize = passo })
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

    /** I lettori delle altre app aperti adesso (col permesso). */
    private var sessioniAttive: List<MediaController> = emptyList()

    /**
     * La sessione aperta di [pacchetto], se c'è (col permesso): per far
     * partire una playlist dentro un'app che è già aperta ([AvvioMusica]).
     */
    fun sessioneDi(pacchetto: String): MediaController? =
        controllore?.takeIf { it.packageName == pacchetto } ?: sessioniAttive.firstOrNull { it.packageName == pacchetto }

    /**
     * Una voce della musica di casa toccata sull'auto che serve il telefono
     * (la casa): la si chiede al motore Flutter, e il messaggio torna a
     * [risposta]. Falso se non c'è un motore a cui chiederlo.
     */
    fun chiediAlTelefono(id: String, risposta: (String?) -> Unit): Boolean {
        val m = vogliono.firstOrNull() ?: canali.keys.firstOrNull() ?: return false
        val c = canali[m] ?: return false
        c.invokeMethod(
            "toccaDallAuto",
            id,
            object : MethodChannel.Result {
                override fun success(result: Any?) = risposta(result as? String)

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
                    risposta("Non è partita")

                override fun notImplemented() = risposta("Aggiorna l'app per la musica di casa")
            },
        )
        return true
    }

    /** L'elenco della musica di casa è cambiato: gli schermi dell'auto si rifanno. */
    private fun avvisaLAuto() {
        visto = null
        avvisa()
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

    /**
     * Un tasto del lettore. [dallAuto]: dallo schermo dell'auto (lì, se
     * niente suona, l'app non si apre mai). Senza un lettore aperto ⏯ fa
     * partire l'app della musica ([AvvioMusica]): il modo pulito, poi il
     * tasto ▶ all'app, poi quello di sistema.
     */
    fun comando(quale: String, dallAuto: Boolean = true) {
        if (mostraCasa) {
            LettoreDiCasa.comando(quale)
            return
        }
        val t = controllore?.transportControls
        if (t == null) {
            val ctx = contesto
            if (quale == "playPausa" && conTasti && ctx != null) AvvioMusica.parti(ctx, dallAuto, daFermi = false)
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

    /**
     * Le app della musica per le impostazioni: `{app: [{pacchetto, nome,
     * icona}], scelta, ultima, effettiva, ultimo_avvio}`, come le legge
     * `LettoreDelTelefono.elencoApp`.
     */
    private fun elencoApp(context: Context): Map<String, Any?> {
        val elenco = AvvioMusica.installate(context).map { AvvioMusica.conIcona(context, it) }
        return mapOf(
            "app" to elenco.map { mapOf("pacchetto" to it.pacchetto, "nome" to it.nome, "icona" to it.iconaPng) },
            "scelta" to AvvioMusica.scelta(context),
            "ultima" to AvvioMusica.ultima(context),
            "effettiva" to AvvioMusica.prossima(context)?.pacchetto,
            // Le strade provate l'ultima volta, per chi prova sul telefono vero.
            "ultimo_avvio" to AvvioMusica.ultimoAvvio.ifEmpty { null },
        )
    }

    /** Lo stato per il telefono, come lo legge `LettoreDelTelefono.leggi`. */
    private fun stato(): Map<String, Any?> {
        val b = brano
        // L'app di ▶ serve solo alla pillola, quando niente ha un lettore
        // aperto: l'icona non viaggia a ogni brano.
        val p = if (b == null) prossima else null
        val e = esito
        val casa = mostraCasa
        // Un flusso di casa che non si sente: lo si dice come un avvio non partito.
        val erroreCasa = LettoreDiCasa.errore
        return mapOf(
            // Qui la musica si fa partire anche da zero (l'iPhone no).
            "avviabile" to true,
            "prossima" to p?.let { mapOf("pacchetto" to it.pacchetto, "nome" to it.nome, "icona" to it.iconaPng) },
            "in_avvio" to inAvvio,
            "nome_in_avvio" to nomeInAvvio,
            "esito" to (e?.testo ?: erroreCasa),
            "esito_id" to (e?.id ?: if (erroreCasa != null) ID_ERRORE_CASA else null),
            // La musica di casa si mostra anche senza «Accesso alle notifiche».
            "permesso" to (permesso || casa),
            "casa" to casa,
            "app" to b?.app,
            "titolo" to b?.titolo,
            "artista" to b?.artista,
            "suona" to (b?.suona == true),
            "copertina" to if (casa) LettoreDiCasa.attuale?.immagineByte else copertinaPng,
            "durata_ms" to if (casa) LettoreDiCasa.durataMs else metadati?.getLong(MediaMetadata.METADATA_KEY_DURATION),
            // A che punto è adesso (non quando il lettore l'ha detto l'ultima
            // volta): il telefono ci conta sopra da quando lo riceve.
            "posizione_ms" to if (b != null) posizioneMs() else null,
            "puo_precedente" to (b?.puoPrecedente != false),
            "puo_successivo" to (b?.puoSuccessivo != false),
            "puo_play" to (b?.puoPlayPausa != false),
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
        val ora = listOf(
            acceso, permesso, mostraCasa, MusicaDiCasa.versione, LettoreDiCasa.errore, b?.app, b?.titolo, b?.artista, b?.suona, b?.copertina,
            b?.durataMs, b?.puoPrecedente, b?.puoSuccessivo, b?.puoPlayPausa,
            AvvioMusica.inCorso, AvvioMusica.esito?.id, if (b == null) prossima?.pacchetto else null,
        )
        if (ora == visto) return
        visto = ora
        for (f in ascoltatori) f()
    }
}
