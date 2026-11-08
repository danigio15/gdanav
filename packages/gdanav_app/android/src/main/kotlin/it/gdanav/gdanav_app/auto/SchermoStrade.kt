package it.gdanav.gdanav_app.auto

import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import androidx.activity.OnBackPressedCallback
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.DurationSpan
import androidx.car.app.model.ForegroundCarColorSpan
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.RoutePreviewNavigationTemplate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Le strade fra cui scegliere, prima di partire: le stesse carte della
 * scheda del telefono — più rapida, risparmia energia, tempo simile, più
 * lenta — con la durata, da dove passa, i km, la batteria all'arrivo, il
 * consumo, il pedaggio e il traffico. Sotto, sulla mappa, la linea della
 * strada scelta.
 *
 * «Quando c'è il calcolo percorso questo non esce su Android Auto»: l'auto
 * vedeva solo la linea. Toccando una strada la si sceglie anche sul
 * telefono; «Avvia» parte con quella. Indietro chiude il viaggio, come
 * «Fine». Partiti (dall'auto o dal telefono), la schermata se ne va da sé.
 */
class SchermoStrade(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val id: String? = PonteAuto.strade?.id
    private var mostrate: PonteAuto.Strade? = PonteAuto.strade

    /** Se chiude perché si è partiti o il viaggio è cambiato, e non per «Indietro». */
    private var finita = false

    private val controlla: () -> Unit = {
        val ora = PonteAuto.strade
        when {
            ora == null || ora.id != id || PonteAuto.guida != null -> {
                finita = true
                finish()
            }
            ora != mostrate -> {
                mostrate = ora
                invalidate()
            }
        }
    }

    init {
        lifecycle.addObserver(this)
        // «Indietro»: niente viaggio, come «Fine» sul telefono. Solo il tasto:
        // se la schermata chiude perché l'auto si spegne, il viaggio resta.
        carContext.onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    if (!finita && PonteAuto.guida == null) PonteAuto.fermaDallAuto()
                    finita = true
                    finish()
                }
            },
        )
    }

    override fun onCreate(owner: LifecycleOwner) {
        PonteAuto.ascolta(controlla)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PonteAuto.smetti(controlla)
    }

    override fun onGetTemplate(): Template {
        val s = mostrate ?: PonteAuto.strade
        val lista = ItemList.Builder()
        if (s == null) {
            return RoutePreviewNavigationTemplate.Builder()
                .setTitle("Strade")
                .setHeaderAction(Action.BACK)
                .setLoading(true)
                .build()
        }
        for (v in s.voci) lista.addItem(riga(v))
        lista.setSelectedIndex(s.scelta.coerceIn(0, s.voci.size - 1))
        lista.setOnSelectedListener { i ->
            mostrate = s.copy(scelta = i)
            PonteAuto.scegliStrada(s.id, i)
        }
        val avvia = Action.Builder()
            .setTitle("Avvia")
            .setOnClickListener { PonteAuto.avvia(s.id, mostrate?.scelta ?: s.scelta) }
        return RoutePreviewNavigationTemplate.Builder()
            .setTitle(s.meta.ifEmpty { "Strade" })
            .setHeaderAction(Action.BACK)
            .setItemList(lista.build())
            .setNavigateAction(avvia.build())
            .build()
    }

    /**
     * Una strada: nel titolo la durata (Android Auto la vuole come
     * [DurationSpan]) e il nome; sotto da dove
     * passa, i km e la batteria all'arrivo; poi consumo, pedaggio e traffico.
     */
    private fun riga(v: PonteAuto.VoceStrada): Row {
        // Nel titolo niente colori (Android Auto non li vuole lì): il verde
        // della strada che risparmia sta nel consumo, sotto.
        val titolo = SpannableString("  · ${v.nome}")
        titolo.setSpan(DurationSpan.create(v.durataS), 0, 1, Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
        val riga = Row.Builder().setTitle(titolo)
        riga.addText(listOfNotNull(v.via.ifEmpty { null }, v.km, v.arrivo?.let { "arrivi con il $it%" }).joinToString(" · "))
        val sotto = SpannableStringBuilder()
        fun pezzo(t: String, colore: CarColor? = null) {
            if (sotto.isNotEmpty()) sotto.append(" · ")
            val da = sotto.length
            sotto.append(t)
            colore?.let { sotto.setSpan(ForegroundCarColorSpan.create(it), da, sotto.length, Spanned.SPAN_INCLUSIVE_EXCLUSIVE) }
        }
        v.consumo?.let { pezzo(if (v.risparmio != null) "$it (${v.risparmio})" else it, if (v.eco) CarColor.GREEN else null) }
        v.pedaggio?.let { pezzo(it, if (v.paga) CarColor.YELLOW else CarColor.GREEN) }
        v.traffico?.let { pezzo(it, if (it.startsWith("+")) CarColor.YELLOW else null) }
        if (sotto.isNotEmpty()) riga.addText(sotto)
        return riga.build()
    }
}
