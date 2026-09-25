package it.gdanav.gdanav.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav.R

/** «Dove andiamo?» sull'auto: Cerca, poi Casa, Lavoro, i preferiti e i recenti. */
class SchermoDestinazioni(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val aggiorna: () -> Unit = { invalidate() }

    init {
        lifecycle.addObserver(this)
    }

    override fun onCreate(owner: LifecycleOwner) {
        PonteAuto.ascolta(aggiorna)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PonteAuto.smetti(aggiorna)
    }

    override fun onGetTemplate(): Template {
        val elenco = ItemList.Builder()
        elenco.addItem(
            Row.Builder()
                .setTitle("Cerca un indirizzo o un posto")
                .setImage(icona(R.drawable.auto_cerca, CarColor.BLUE), Row.IMAGE_TYPE_ICON)
                .setOnClickListener { screenManager.push(SchermoCerca(carContext)) }
                .setBrowsable(true)
                .build(),
        )
        // L'auto decide quante righe si vedono: una è già «Cerca».
        val massimo = righeMassime() - 1
        for (l in PonteAuto.luoghi.take(massimo)) {
            val riga = Row.Builder().setTitle(titolo(l)).setOnClickListener { scegli(l) }
            riga.setImage(
                when (l.tipo) {
                    "casa" -> icona(R.drawable.icona_casa, CarColor.BLUE)
                    "lavoro" -> icona(R.drawable.icona_lavoro, CarColor.BLUE)
                    "recente" -> icona(R.drawable.icona_recenti)
                    else -> icona(R.drawable.icona_stella, CarColor.YELLOW)
                },
                Row.IMAGE_TYPE_ICON,
            )
            val sotto = if (l.tipo == "recente") l.descrizione else l.nome
            if (sotto.isNotEmpty()) riga.addText(sotto)
            elenco.addItem(riga.build())
        }
        return ListTemplate.Builder()
            .setTitle("Dove andiamo?")
            .setHeaderAction(Action.BACK)
            .setSingleList(elenco.build())
            .build()
    }

    private fun icona(id: Int, colore: CarColor = CarColor.DEFAULT): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, id)).setTint(colore).build()

    private fun titolo(l: PonteAuto.Luogo): String = when (l.tipo) {
        "casa" -> "Casa"
        "lavoro" -> "Lavoro"
        else -> l.etichetta
    }

    private fun scegli(l: PonteAuto.Luogo) {
        PonteAuto.vai(l)
        screenManager.popToRoot()
    }

    private fun righeMassime(): Int = try {
        carContext.getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
    } catch (e: Exception) {
        6
    }
}
