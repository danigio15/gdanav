package it.gdanav.gdanav_app.auto

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * La scena 3D vera sullo schermo dell'auto: la stessa pagina del telefono
 * (`assets/web3d`, MapLibre GL JS e three.js: viadotti in quota, alberi,
 * edifici, l'auto 3D) in una WebView dentro la Presentation di
 * [RendererMappa], al posto della mappa di MapLibre.
 *
 * «Certo, voglio la scena reale anche in macchina.» La pagina parla col
 * telefono come sul telefono: i messaggi della regia (`Regia3d`, in Dart)
 * arrivano qui come JavaScript da eseguire ([esegui]); quelli della pagina
 * (`Gdanav3d.postMessage`) tornano alla regia ([PonteAuto.dalla3d]). Se la
 * pagina dice che non ce la fa, la regia lo dice all'auto
 * ([PonteAuto.nonVa3d]) e torna la mappa di sempre.
 *
 * [allaRegia]: dove vanno i messaggi della pagina. Dentro l'app è
 * [PonteAuto.dalla3d]; nel processo della scena ([Scena3dServizio]) tornano
 * all'app per il suo canale, e [PonteAuto] lì non si tocca.
 */
internal class Scena3dAuto(
    context: Context,
    notte: Boolean,
    private val allaRegia: (String) -> Unit = { PonteAuto.dalla3d(it) },
) : Scena3d {
    private val principale = Handler(Looper.getMainLooper())

    @SuppressLint("SetJavaScriptEnabled")
    override val vista: WebView = WebView(context).apply {
        // Prima che la pagina disegni: il colore della foschia, non un lampo bianco.
        setBackgroundColor(if (notte) Color.rgb(0x1D, 0x27, 0x40) else Color.rgb(0xE2, 0xEA, 0xF1))
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = true
        settings.mediaPlaybackRequiresUserGesture = true
        // I tocchi vanno ad Android Auto (e alla mappa), non alla pagina.
        isClickable = false
        isFocusable = false
        isFocusableInTouchMode = false
        addJavascriptInterface(Ponte(), CANALE)
        webViewClient = object : WebViewClient() {
            // La pagina è dentro l'app: niente si apre altrove.
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url.toString()
                return !(url.startsWith("file:") || url.startsWith("about:"))
            }

            override fun onPageFinished(view: WebView, url: String?) {
                misura()
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) allaRegia("{\"tipo\":\"errore\",\"motivo\":\"pagina\"}")
            }
        }
        loadUrl(PAGINA)
        addOnLayoutChangeListener { _, sx, su, dx, gi, vsx, vsu, vdx, vgi ->
            if (dx - sx != vdx - vsx || gi - su != vgi - vsu) post { misura() }
        }
    }

    private var finita = false

    /**
     * Quanti pixel dello schermo dell'auto fa un punto della pagina, misurato
     * nella pagina stessa (`window.innerWidth`): la WebView dentro la
     * Presentation non usa per forza la densità dell'auto. Con quella
     * sbagliata lo spazio delle schede, detto in punti, era troppo grande per
     * la pagina e l'auto finiva in un angolo, lontana («lo zoom troppo
     * lontano e piatto»). `null` finché non si sa.
     */
    @Volatile override var scala: Float? = null
        private set

    /** Chiamata quando [scala] cambia. */
    override var alMisurato: (() -> Unit)? = null

    /** Dentro l'app la WebView si vede appena messa. */
    override val visibile = true
    override var alVisibile: (() -> Unit)? = null

    /** Misura [scala]; si rifà quando la WebView cambia grandezza. */
    fun misura() {
        if (finita || vista.width <= 0) return
        vista.evaluateJavascript("window.innerWidth") { r ->
            val punti = r?.trim('"')?.toFloatOrNull() ?: return@evaluateJavascript
            if (punti <= 0f || finita) return@evaluateJavascript
            val nuova = vista.width / punti
            if (scala == null || kotlin.math.abs(nuova - scala!!) > 0.01f) {
                scala = nuova
                alMisurato?.invoke()
            }
        }
    }

    /** La pagina ha detto qualcosa: è viva. */
    @Volatile override var haParlato = false
        private set

    /** Il JavaScript della regia (`window.gdanav3d.ricevi(…)`). */
    override fun esegui(js: String) {
        if (finita) return
        vista.evaluateJavascript(js, null)
    }

    override fun distruggi() {
        if (finita) return
        finita = true
        vista.stopLoading()
        vista.removeJavascriptInterface(CANALE)
        vista.destroy()
    }

    /** `window.Gdanav3d.postMessage(…)`, come il canale di webview_flutter sul telefono. */
    private inner class Ponte {
        @JavascriptInterface
        fun postMessage(testo: String) {
            // Arriva dal filo di Chromium: alla regia dal filo principale.
            haParlato = true
            principale.post { if (!finita) allaRegia(testo) }
        }
    }

    companion object {
        /** Lo stesso nome del canale sul telefono (`canale3d`). */
        private const val CANALE = "Gdanav3d"

        /** GdANav è un pacchetto: la pagina sta sotto `packages/gdanav_app/`, nell'app GdANav e in GdAHome. */
        private const val PAGINA = "file:///android_asset/flutter_assets/packages/gdanav_app/assets/web3d/index.html"
    }
}
