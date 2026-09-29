package it.gdanav.gdanav_app.auto

import androidx.annotation.OptIn
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.annotations.ExperimentalCarApi
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.MapController
import androidx.car.app.navigation.model.MapWithContentTemplate
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R

/**
 * La scheda di un punto toccato sulla mappa dell'auto: una colonnina, un
 * distributore, un ristorante.
 *
 * Con Android Auto recente (livello 7 delle auto) la scheda sta sopra la
 * mappa, sulla sinistra: la mappa resta dov'è, col punto acceso del colore
 * del suo stato, e la freccia indietro la lascia com'era. Sulle auto più
 * vecchie la scheda è una pagina a sé, col cerchio grande dello stato.
 *
 * Le righe arrivano dal telefono già scritte (`schedaInAuto`): il disegno a
 * sinistra col suo colore, la riga, la linea sotto. Il colore va solo sul
 * disegno: sul testo della riga Android Auto rifiuta tutta la scheda.
 */
class SchermoPunto(
    carContext: CarContext,
    private val info: Map<String, Any?>,
    private val renderer: RendererMappa,
    private val lat: Double,
    private val lon: Double,
) : Screen(carContext), DefaultLifecycleObserver {
    private val sullaMappa by lazy { carContext.carAppApiLevel >= 7 }

    init {
        lifecycle.addObserver(this)
    }

    override fun onCreate(owner: LifecycleOwner) {
        if (sullaMappa) renderer.mostra(lat, lon, info["stato"] as? String)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        renderer.nascondi()
    }

    override fun onGetTemplate(): Template = if (sullaMappa) sopraLaMappa() else scheda()

    /** La scheda sopra la mappa; a lato sposta, + e − e Centra, come sulla mappa. */
    @OptIn(ExperimentalCarApi::class)
    private fun sopraLaMappa(): Template {
        val comandi = ActionStrip.Builder()
            .addAction(Action.PAN)
            .addAction(tasto(R.drawable.auto_piu) { renderer.zoom(1.0) })
            .addAction(tasto(R.drawable.auto_meno) { renderer.zoom(-1.0) })
            .addAction(tasto(R.drawable.auto_centra) { renderer.segui() })
            .build()
        return MapWithContentTemplate.Builder()
            .setContentTemplate(scheda())
            .setMapController(
                MapController.Builder()
                    .setMapActionStrip(comandi)
                    // Finito di spostarla col dito la mappa resta lì: sull'auto
                    // torna quando si chiude la scheda.
                    .setPanModeListener { }
                    .build(),
            )
            .build()
    }

    private fun scheda(): PaneTemplate {
        val pannello = Pane.Builder()
        val righe = righe()
        if (righe.isEmpty()) pannello.addRow(Row.Builder().setTitle(info["titolo"] as? String ?: "Punto").build())
        righe.forEach { pannello.addRow(it) }
        vai()?.let { pannello.addAction(it) }
        // Sulla pagina a sé, accanto alle righe, il cerchio grande dello stato.
        if (!sullaMappa && carContext.carAppApiLevel >= 4) {
            coloreStato()?.let { pannello.setImage(icona(R.drawable.auto_scheda_colonnina, it)) }
        }
        return PaneTemplate.Builder(pannello.build())
            .setTitle(info["titolo"] as? String ?: "Punto")
            .setHeaderAction(Action.BACK)
            .build()
    }

    /** Quattro righe al massimo: è il limite delle auto. */
    private fun righe(): List<Row> =
        (info["voci"] as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }.take(4).mapNotNull { voce ->
            val titolo = (voce["titolo"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val r = Row.Builder().setTitle(titolo)
            (voce["testo"] as? String)?.takeIf { it.isNotBlank() }?.let { r.addText(it) }
            disegno(voce["icona"] as? String)?.let {
                r.setImage(icona(it, colore(voce["colore"] as? String)), Row.IMAGE_TYPE_ICON)
            }
            r.build()
        }

    /** «Vai» (o «Passa di qui»): il tasto principale, colorato. */
    private fun vai(): Action? {
        @Suppress("UNCHECKED_CAST")
        val luogo = (info["luogo"] as? Map<String, Any?>)?.let { PonteAuto.luogoDa(it) } ?: return null
        val a = Action.Builder()
            .setTitle(info["vai"] as? String ?: "Vai")
            .setBackgroundColor(CarColor.BLUE)
            .setOnClickListener {
                PonteAuto.passa(luogo)
                screenManager.popToRoot()
            }
        if (carContext.carAppApiLevel >= 4) a.setFlags(Action.FLAG_PRIMARY)
        return a.build()
    }

    /** Il colore del cerchio grande: solo per una colonnina di cui si sa lo stato. */
    private fun coloreStato(): CarColor? = when (info["stato"] as? String) {
        "libera" -> CarColor.GREEN
        "piena", "guasta" -> CarColor.RED
        "ignota" -> CarColor.DEFAULT
        else -> null
    }

    private fun disegno(nome: String?): Int? = when (nome) {
        "potenza" -> R.drawable.icona_potenza
        "presa" -> R.drawable.icona_presa
        "prezzo" -> R.drawable.icona_prezzo
        "distributore" -> R.drawable.icona_distributore
        "luogo" -> R.drawable.icona_luogo
        else -> null
    }

    private fun colore(nome: String?): CarColor = when (nome) {
        "verde" -> CarColor.GREEN
        "rosso" -> CarColor.RED
        "giallo" -> CarColor.YELLOW
        "blu" -> CarColor.BLUE
        else -> CarColor.DEFAULT
    }

    private fun icona(id: Int, colore: CarColor = CarColor.DEFAULT): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, id)).setTint(colore).build()

    private fun tasto(id: Int, azione: () -> Unit) =
        Action.Builder().setIcon(icona(id)).setOnClickListener { azione() }.build()
}
