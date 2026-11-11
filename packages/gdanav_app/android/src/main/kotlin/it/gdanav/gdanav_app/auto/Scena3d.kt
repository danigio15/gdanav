package it.gdanav.gdanav_app.auto

import android.view.View

/**
 * La scena 3D sullo schermo dell'auto, comunque sia fatta: dentro l'app
 * ([Scena3dAuto]) o in un processo suo ([Scena3dLontana]). [RendererMappa] la
 * mette al posto della mappa e le passa i messaggi della regia.
 */
internal interface Scena3d {
    /** La vista da mettere nella Presentation, sopra la mappa. */
    val vista: View

    /** Quanti pixel dell'auto fa un punto della pagina; `null` finché non si sa. */
    val scala: Float?

    /** Chiamata quando [scala] cambia. */
    var alMisurato: (() -> Unit)?

    /** La pagina ha detto qualcosa: è viva. */
    val haParlato: Boolean

    /** La scena si vede già: la mappa sotto si può nascondere. */
    val visibile: Boolean

    /** Chiamata quando [visibile] diventa vero. */
    var alVisibile: (() -> Unit)?

    /** Il JavaScript della regia (`window.gdanav3d.ricevi(…)`). */
    fun esegui(js: String)

    fun distruggi()
}
