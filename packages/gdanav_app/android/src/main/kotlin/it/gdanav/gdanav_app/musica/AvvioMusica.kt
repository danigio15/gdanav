package it.gdanav.gdanav_app.musica

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.AudioManager
import android.media.browse.MediaBrowser
import android.media.session.MediaController
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import it.gdanav.gdanav_app.auto.PonteAuto
import java.io.ByteArrayOutputStream

/**
 * Far partire la musica da zero: ▶ quando nessuna app ha un lettore aperto
 * (Spotify chiusa, il telefono appena acceso). Prima si comandava solo una
 * sessione già attiva, e senza si mandava il tasto play di sistema, che non
 * sempre fa partire qualcosa.
 *
 * **Quale app** lo dice [SceltaApp] (la scelta nelle impostazioni, Spotify
 * di serie, l'ultima che ha suonato); l'elenco sono le app installate che
 * offrono un `MediaBrowserService` ([installate]: per vederle da Android 11
 * servono le `<queries>` del manifesto).
 *
 * **Come**, tre strade, una dopo l'altra finché qualcosa suona:
 *
 * 1. il modo pulito: ci si collega al `MediaBrowserService` dell'app e si
 *    chiede `play()` alla sua sessione, che si aggancia subito. Molte app
 *    (Spotify fra queste, a quanto riportano gli sviluppatori) lo aprono
 *    solo ai pacchetti di cui si fidano (Android Auto, gli orologi…): con gli
 *    altri `onGetRoot` dà `null` e il collegamento fallisce
 *    (`onConnectionFailed`). Allora si passa subito alla seconda;
 * 2. il tasto ▶ mandato **all'app** (`ACTION_MEDIA_BUTTON` col suo
 *    ricevitore, `KEYCODE_MEDIA_PLAY`): è quello che fa il tasto delle
 *    cuffie, e Spotify riprende l'ultimo brano anche da chiusa. Se l'app
 *    scelta è anche l'ultima che ha suonato, dopo un po' anche il tasto di
 *    sistema (`AudioManager.dispatchMediaKeyEvent`), che il sistema dà
 *    all'ultima sessione;
 * 3. l'ultima: aprire l'app. **Solo sul telefono, da fermi e con lo schermo
 *    dell'auto spento**: mai dall'auto, dove si dice di aprirla sul telefono
 *    quando si è fermi.
 *
 * Intanto «Avvio Spotify…» ([inCorso]); quando la sessione suona la vede
 * [LettoreTelefono] (il suo ascolto delle sessioni attive) e lo dice qui
 * ([suona]); se dopo [ATTESA_MS] non suona niente, un messaggio ([esito]):
 * sul telefono nella pillola, sull'auto un `CarToast` breve.
 *
 * Si tocca solo dal filo principale.
 */
object AvvioMusica {
    /** Un'app della musica: il pacchetto, il nome, l'icona (piccola) e il suo PNG per il telefono. */
    class App(val pacchetto: String, val nome: String, val icona: Bitmap?, val iconaPng: ByteArray?)

    /** Un avvio in corso: quale app (`null`: il tasto di sistema), chi l'ha chiesto, da quando. */
    class InCorso(val app: App?, val dallAuto: Boolean, val daFermi: Boolean, val dal: Long)

    /** Com'è finito un avvio che non è partito: da dire una volta. */
    class Esito(val id: Int, val testo: String, val dallAuto: Boolean)

    private const val PREFERENZE = "gdanav"
    private const val SCELTA = "musica_app_scelta"
    private const val ULTIMA = "musica_app_ultima"

    /** L'azione con cui un'app dichiara il suo `MediaBrowserService`. */
    const val AZIONE_BROWSER = "android.media.browse.MediaBrowserService"

    /** Quanto si aspetta il collegamento al `MediaBrowserService` prima del tasto all'app. */
    private const val TASTO_APP_MS = 1_500L

    /** Quando provare anche il tasto di sistema (se l'app è l'ultima che ha suonato). */
    private const val TASTO_SISTEMA_MS = 3_000L

    /** Dopo quanto, se non suona niente, si dice che non è partito. */
    const val ATTESA_MS = 5_000L

    /** Dopo che suona, quanto si resta collegati al servizio dell'app prima di staccarsi. */
    private const val STACCA_MS = 3_000L

    /** Il lato dell'icona dell'app, in pixel. */
    private const val ICONA_PX = 96

    private val principale = Handler(Looper.getMainLooper())

    @Volatile var inCorso: InCorso? = null
        private set

    @Volatile var esito: Esito? = null
        private set
    private var ultimoEsito = 0

    /** L'app che parte con ▶, ricordata: si rifà con [rileggi]. */
    private var prossimaTenuta: App? = null
    private var prossimaLetta = false

    private var browser: MediaBrowser? = null
    private var tastoAllApp = false

    /**
     * Le strade provate dall'ultimo avvio, in ordine, e com'è finito
     * («Spotify: browser rifiutato → tasto all'app → suona dopo 1,2 s»): si
     * legge nelle impostazioni, sotto «App della musica», per sapere dal
     * telefono vero quale strada funziona.
     */
    @Volatile var ultimoAvvio: String = ""
        private set

    private fun preferenze(c: Context) = c.applicationContext.getSharedPreferences(PREFERENZE, Context.MODE_PRIVATE)

    /**
     * Le app installate che offrono un `MediaBrowserService`, Spotify per
     * prima, senza GdANav stessa (e senza chi la porta dentro).
     */
    @Suppress("DEPRECATION")
    fun installate(context: Context): List<App> {
        val pm = context.packageManager
        val trovate = try {
            pm.queryIntentServices(Intent(AZIONE_BROWSER), 0)
        } catch (_: Exception) {
            emptyList()
        }
        val app = trovate.mapNotNull { r ->
            val s = r.serviceInfo ?: return@mapNotNull null
            if (s.packageName == context.packageName) return@mapNotNull null
            val nome = try {
                pm.getApplicationLabel(pm.getApplicationInfo(s.packageName, 0)).toString()
            } catch (_: Exception) {
                r.loadLabel(pm)?.toString() ?: s.packageName
            }
            App(s.packageName, nome, null, null)
        }
        return SceltaApp.ordina(app, { it.pacchetto }, { it.nome })
    }

    /** L'app con l'icona (per la pillola e l'elenco delle impostazioni). */
    fun conIcona(context: Context, a: App): App {
        val icona = icona(context, a.pacchetto)
        return App(a.pacchetto, a.nome, icona, icona?.let(::png))
    }

    private fun icona(context: Context, pacchetto: String): Bitmap? = try {
        val d = context.packageManager.getApplicationIcon(pacchetto)
        val b = Bitmap.createBitmap(ICONA_PX, ICONA_PX, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, ICONA_PX, ICONA_PX)
        d.draw(Canvas(b))
        b
    } catch (_: Exception) {
        null
    } catch (_: OutOfMemoryError) {
        null
    }

    private fun png(b: Bitmap): ByteArray? = try {
        val out = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.PNG, 100, out)
        out.toByteArray()
    } catch (_: Exception) {
        null
    }

    /** La scelta salvata: un pacchetto, [SceltaApp.ULTIMA], o `null` (di serie). */
    fun scelta(context: Context): String? = preferenze(context).getString(SCELTA, null)

    /** L'ultima app che ha suonato, se se ne sa una. */
    fun ultima(context: Context): String? = preferenze(context).getString(ULTIMA, null)

    /** Cambia la scelta (dalle impostazioni del telefono): `null` torna a quella di serie. */
    fun scegli(context: Context, scelta: String?) {
        val p = preferenze(context).edit()
        if (scelta.isNullOrBlank()) p.remove(SCELTA) else p.putString(SCELTA, scelta)
        p.apply()
        rileggi(context)
    }

    /** Si rifà [prossima]: l'app scelta, o quelle installate, possono essere cambiate. */
    fun rileggi(context: Context) {
        prossimaLetta = false
        prossima(context)
    }

    /** L'app che parte con ▶ quando niente suona; `null` se non se ne sa nessuna. */
    fun prossima(context: Context): App? {
        if (prossimaLetta) return prossimaTenuta
        prossimaLetta = true
        val installate = installate(context)
        val ultima = ultima(context)
        val pacchetti = installate.map { it.pacchetto }.toMutableList()
        // L'ultima che ha suonato vale anche se non offre il servizio, se è
        // ancora sul telefono: il tasto ▶ la riprende lo stesso.
        val nomeUltima = ultima?.takeIf { it !in pacchetti }?.let { nomeDi(context, it) }
        if (nomeUltima != null) pacchetti += ultima
        val quale = SceltaApp.effettiva(scelta(context), ultima, pacchetti)
        val app = installate.firstOrNull { it.pacchetto == quale }
            ?: if (quale != null && quale == ultima && nomeUltima != null) App(quale, nomeUltima, null, null) else null
        prossimaTenuta = app?.let { conIcona(context, it) }
        return prossimaTenuta
    }

    private fun nomeDi(context: Context, pacchetto: String): String? = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pacchetto, 0)).toString()
    } catch (_: Exception) {
        null
    }

    /**
     * Una sessione di [pacchetto] suona: se è quella che si stava facendo
     * partire l'avvio è riuscito; e la si ricorda come l'ultima (per la
     * scelta «l'ultima che ha suonato» e per il tasto di sistema).
     */
    fun suona(context: Context, pacchetto: String) {
        if (pacchetto == context.packageName) return
        val c = inCorso
        if (c != null && (c.app == null || c.app.pacchetto == pacchetto)) riuscito()
        if (ultima(context) != pacchetto) {
            preferenze(context).edit().putString(ULTIMA, pacchetto).apply()
            // Di serie senza Spotify, o «l'ultima»: la prossima cambia.
            rileggi(context)
        }
    }

    /**
     * ▶ con niente che suona. [dallAuto]: dallo schermo dell'auto (mai
     * aprire l'app). [daFermi]: chi l'ha chiesto, sul telefono, è fermo.
     * Un avvio già in corso non si raddoppia.
     */
    fun parti(context: Context, dallAuto: Boolean, daFermi: Boolean) {
        val ctx = context.applicationContext
        if (inCorso != null) return
        contesto = ctx
        val app = prossima(ctx)
        inCorso = InCorso(app, dallAuto, daFermi, SystemClock.uptimeMillis())
        ultimoAvvio = "${app?.nome ?: "nessuna app"}${if (dallAuto) " (dall'auto)" else ""}:"
        tastoAllApp = false
        esito = null
        LettoreTelefono.avvioCambiato()
        if (app == null) {
            // Nessuna app da far partire: il tasto play di sistema, che
            // riprende l'ultima sessione se il sistema ne ricorda una.
            passo("tasto di sistema")
            tastoDiSistema(ctx)
        } else {
            collega(ctx, app)
            principale.postDelayed(tastoApp, TASTO_APP_MS)
            if (ultima(ctx) == app.pacchetto) principale.postDelayed(tastoSistema, TASTO_SISTEMA_MS)
        }
        principale.postDelayed(scaduto, ATTESA_MS)
    }

    private var contesto: Context? = null

    private val tastoApp = Runnable {
        val ctx = contesto
        val app = inCorso?.app
        if (ctx != null && app != null) mandaTastoAllApp(ctx, app.pacchetto)
    }

    private val tastoSistema = Runnable {
        val ctx = contesto
        if (ctx != null && inCorso != null) {
            passo("tasto di sistema")
            tastoDiSistema(ctx)
        }
    }

    private val scaduto = Runnable { nonPartita() }

    private val stacca = Runnable { staccaBrowser() }

    private fun passo(p: String) {
        ultimoAvvio = if (ultimoAvvio.isEmpty() || ultimoAvvio.endsWith(":")) "$ultimoAvvio $p".trim() else "$ultimoAvvio → $p"
    }

    private fun secondi(c: InCorso): String {
        val ms = SystemClock.uptimeMillis() - c.dal
        return "${ms / 1000},${(ms % 1000) / 100} s"
    }

    /** La strada pulita: il `MediaBrowserService` dell'app, e `play()` alla sua sessione. */
    private fun collega(context: Context, app: App) {
        staccaBrowser()
        val servizio = servizioDi(context, app.pacchetto)
        if (servizio == null) {
            passo("nessun browser")
            mandaTastoAllApp(context, app.pacchetto)
            return
        }
        var b: MediaBrowser? = null
        val richiamo = object : MediaBrowser.ConnectionCallback() {
            override fun onConnected() {
                val questo = b ?: return
                if (browser !== questo || inCorso == null) return
                passo("browser collegato")
                try {
                    val c = MediaController(context, questo.sessionToken)
                    // Agganciata subito: il pannello mostra brano e tasti
                    // anche prima che la sessione compaia fra le attive.
                    LettoreTelefono.aggancia(c)
                    c.transportControls.play()
                    passo("play")
                } catch (_: Exception) {
                    passo("play rifiutato")
                    mandaTastoAllApp(context, app.pacchetto)
                }
            }

            // L'app non apre il servizio a GdANav (Spotify, con le app che
            // non sono nel suo elenco): subito il tasto all'app.
            override fun onConnectionFailed() {
                if (browser !== b) return
                passo("browser rifiutato")
                browser = null
                if (inCorso != null) mandaTastoAllApp(context, app.pacchetto)
            }

            override fun onConnectionSuspended() {
                if (browser === b) browser = null
            }
        }
        b = try {
            MediaBrowser(context, servizio, richiamo, null)
        } catch (_: Exception) {
            null
        }
        browser = b
        if (b == null) {
            mandaTastoAllApp(context, app.pacchetto)
            return
        }
        try {
            b.connect()
        } catch (_: Exception) {
            browser = null
            passo("browser non si collega")
            mandaTastoAllApp(context, app.pacchetto)
        }
    }

    @Suppress("DEPRECATION")
    private fun servizioDi(context: Context, pacchetto: String): ComponentName? = try {
        context.packageManager.queryIntentServices(Intent(AZIONE_BROWSER).setPackage(pacchetto), 0)
            .firstNotNullOfOrNull { r -> r.serviceInfo?.let { ComponentName(it.packageName, it.name) } }
    } catch (_: Exception) {
        null
    }

    /**
     * Il tasto ▶ all'app sola, come quello delle cuffie: al suo ricevitore
     * dei tasti multimediali (se lo dichiara), se no al pacchetto. Una volta
     * per avvio.
     */
    @Suppress("DEPRECATION")
    private fun mandaTastoAllApp(context: Context, pacchetto: String) {
        if (tastoAllApp || inCorso == null) return
        tastoAllApp = true
        principale.removeCallbacks(tastoApp)
        passo("tasto all'app")
        val ricevitori = try {
            context.packageManager.queryBroadcastReceivers(Intent(Intent.ACTION_MEDIA_BUTTON).setPackage(pacchetto), 0)
                .mapNotNull { r -> r.activityInfo?.let { ComponentName(it.packageName, it.name) } }
        } catch (_: Exception) {
            emptyList()
        }
        for (azione in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            val evento = KeyEvent(azione, KeyEvent.KEYCODE_MEDIA_PLAY)
            val destinatari = ricevitori.ifEmpty { listOf(null) }
            for (r in destinatari) {
                val i = Intent(Intent.ACTION_MEDIA_BUTTON).putExtra(Intent.EXTRA_KEY_EVENT, evento)
                if (r != null) i.setComponent(r) else i.setPackage(pacchetto)
                try {
                    context.sendBroadcast(i)
                } catch (_: Exception) {
                    // L'app non lo riceve: restano il tasto di sistema e l'attesa.
                }
            }
        }
    }

    /** Il tasto play di sistema: il sistema lo dà all'ultima app che suonava. */
    fun tastoDiSistema(context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY))
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY))
        } catch (_: Exception) {
            // Nessuno che lo prenda: resta in silenzio.
        }
    }

    private fun fermaTempi() {
        principale.removeCallbacks(tastoApp)
        principale.removeCallbacks(tastoSistema)
        principale.removeCallbacks(scaduto)
    }

    private fun riuscito() {
        inCorso?.let { passo("suona dopo ${secondi(it)}") }
        fermaTempi()
        inCorso = null
        // Collegati ancora un poco: il servizio dell'app intanto si mette in
        // primo piano da sé (suona), poi ci si stacca.
        principale.removeCallbacks(stacca)
        principale.postDelayed(stacca, STACCA_MS)
        LettoreTelefono.avvioCambiato()
    }

    /**
     * Dopo [ATTESA_MS] non suona niente. Sul telefono, da fermi e con lo
     * schermo dell'auto spento, si apre l'app (l'ultima strada); dall'auto
     * mai. Poi il messaggio.
     */
    private fun nonPartita() {
        val c = inCorso ?: return
        val ctx = contesto
        fermaTempi()
        inCorso = null
        staccaBrowser()
        var aperta = false
        if (ctx != null && c.app != null && !c.dallAuto && c.daFermi && !PonteAuto.inAutoAdesso) {
            aperta = apri(ctx, c.app.pacchetto)
        }
        passo(if (aperta) "niente dopo ${secondi(c)}, app aperta" else "niente dopo ${secondi(c)}")
        esito = Esito(++ultimoEsito, SceltaApp.testoNonPartita(c.app?.nome, c.dallAuto, aperta, c.daFermi), c.dallAuto)
        LettoreTelefono.avvioCambiato()
    }

    private fun apri(context: Context, pacchetto: String): Boolean = try {
        val i = context.packageManager.getLaunchIntentForPackage(pacchetto)
        if (i == null) {
            false
        } else {
            context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        }
    } catch (_: Exception) {
        false
    }

    /** Il messaggio è stato detto (o è vecchio): non si ripete. */
    fun esitoDetto(id: Int) {
        if (esito?.id == id) {
            esito = null
            LettoreTelefono.avvioCambiato()
        }
    }

    private fun staccaBrowser() {
        principale.removeCallbacks(stacca)
        val b = browser ?: return
        browser = null
        try {
            b.disconnect()
        } catch (_: Exception) {}
    }

    /** «Musica nel navigatore» spenta, o il permesso tolto: niente avvio a metà. */
    fun annulla() {
        if (inCorso == null) return
        fermaTempi()
        inCorso = null
        staccaBrowser()
        LettoreTelefono.avvioCambiato()
    }

    /** Il lettore agganciato è [c]: se è quello dell'avvio, è dell'app che si fa partire. */
    fun eDellAvvio(c: MediaController?): Boolean {
        val app = inCorso?.app ?: return false
        return c?.packageName == app.pacchetto
    }
}
