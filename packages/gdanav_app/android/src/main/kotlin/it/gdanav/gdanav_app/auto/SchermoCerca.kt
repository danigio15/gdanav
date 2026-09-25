package it.gdanav.gdanav_app.auto

import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.SearchTemplate
import androidx.car.app.model.Template

/**
 * La ricerca sull'auto: si scrive (o si detta) e si sceglie. Con [imposta]
 * («casa» o «lavoro») il posto scelto si salva invece di partire.
 */
class SchermoCerca(carContext: CarContext, private val imposta: String? = null) : Screen(carContext) {
    private val attesa = Handler(Looper.getMainLooper())
    private var risultati: List<PonteAuto.Luogo> = emptyList()
    private var cercando = false
    private var ultima = 0

    private val richiamo = object : SearchTemplate.SearchCallback {
        override fun onSearchTextChanged(testo: String) {
            // Una richiesta quando si smette di scrivere, non una per lettera.
            attesa.removeCallbacksAndMessages(null)
            attesa.postDelayed({ cerca(testo) }, 500)
        }

        override fun onSearchSubmitted(testo: String) {
            attesa.removeCallbacksAndMessages(null)
            cerca(testo)
        }
    }

    private fun cerca(testo: String) {
        if (testo.trim().length < 3) return
        val questa = ++ultima
        cercando = true
        invalidate()
        PonteAuto.cerca(testo) { trovati ->
            if (questa != ultima) return@cerca
            risultati = trovati
            cercando = false
            invalidate()
        }
    }

    override fun onGetTemplate(): Template {
        val modello = SearchTemplate.Builder(richiamo)
            .setHeaderAction(Action.BACK)
            .setSearchHint(
                when (imposta) {
                    "casa" -> "Indirizzo di Casa"
                    "lavoro" -> "Indirizzo del Lavoro"
                    else -> "Dove andiamo?"
                },
            )
            .setShowKeyboardByDefault(true)
        if (cercando) return modello.setLoading(true).build()
        val elenco = ItemList.Builder().setNoItemsMessage("Scrivi almeno tre lettere")
        for (l in risultati.take(6)) {
            val riga = Row.Builder().setTitle(l.nome).setOnClickListener { scegli(l) }
            if (l.descrizione.isNotEmpty()) riga.addText(l.descrizione)
            elenco.addItem(riga.build())
        }
        return modello.setItemList(elenco.build()).build()
    }

    private fun scegli(l: PonteAuto.Luogo) {
        val tipo = imposta
        if (tipo == null) {
            PonteAuto.vai(l)
            screenManager.popToRoot()
            return
        }
        PonteAuto.imposta(tipo, l) { fatto ->
            val nome = if (tipo == "casa") "Casa" else "Lavoro"
            CarToast.makeText(
                carContext,
                if (fatto) "$nome salvato: ${l.nome}" else "Non si è potuto salvare $nome",
                CarToast.LENGTH_LONG,
            ).show()
            screenManager.pop()
        }
    }
}
