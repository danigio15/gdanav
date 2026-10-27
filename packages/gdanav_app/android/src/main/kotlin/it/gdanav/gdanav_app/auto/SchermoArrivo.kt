package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Arrivati: «Sei arrivato a …» e il riepilogo del viaggio — durata e
 * distanza, il consumo, le ricariche, il costo col suo dettaglio.
 *
 * «All'arrivo non si blocca il percorso e non è presente il report dei
 * costi»: il riepilogo stava in una riga sola sopra la mappa, e la scheda di
 * Android Auto la tagliava dopo il nome della meta. Qui ogni cosa ha la sua
 * riga. «Fine» chiude il viaggio, come sul telefono; se lo chiude il
 * telefono, la schermata se ne va da sé.
 */
class SchermoArrivo(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private var mostrato: PonteAuto.Arrivo? = PonteAuto.arrivo

    private val controlla: () -> Unit = {
        val ora = PonteAuto.arrivo
        when {
            ora == null -> finish()
            ora != mostrato -> {
                mostrato = ora
                invalidate()
            }
        }
    }

    init {
        lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        PonteAuto.ascolta(controlla)
        controlla()
    }

    override fun onStop(owner: LifecycleOwner) {
        PonteAuto.smetti(controlla)
    }

    override fun onGetTemplate(): Template {
        val a = mostrato ?: PonteAuto.arrivo
        // Quante righe mostra quest'auto: il costo è l'ultima, e non si perde.
        val limite = try {
            carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_PANE)
        } catch (e: Exception) {
            4
        }.coerceAtLeast(1)
        val righe = a?.righe.orEmpty().let { tutte ->
            if (tutte.size <= limite) tutte else tutte.take(limite - 1) + tutte.last()
        }
        val pane = Pane.Builder()
        // Una schermata senza righe Android Auto non la disegna.
        if (righe.isEmpty()) pane.addRow(Row.Builder().setTitle(a?.titolo ?: "Sei arrivato").build())
        for ((titolo, testo) in righe) {
            pane.addRow(Row.Builder().setTitle(titolo).addText(testo).build())
        }
        val fine = Action.Builder()
            .setTitle("Fine")
            .setOnClickListener {
                PonteAuto.fermaDallAuto()
                finish()
            }
        if (carContext.carAppApiLevel >= 4) fine.setFlags(Action.FLAG_PRIMARY)
        pane.addAction(fine.build())
        return PaneTemplate.Builder(pane.build())
            .setTitle(a?.titolo ?: "Sei arrivato")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
