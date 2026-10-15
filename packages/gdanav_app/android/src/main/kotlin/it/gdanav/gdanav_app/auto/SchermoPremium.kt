package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Senza gdanav Premium: si dice che in auto la navigazione è Premium, e
 * basta. Appena l'app lo sblocca (o lo ritrova dal Play Store) si passa da sé
 * alla navigazione. Con una versione troppo vecchia ([PonteAuto.aggiorna]) si
 * dice invece che serve un aggiornamento.
 *
 * Niente «fallo dal telefono» e niente tasti che lo chiedono: chi guida non
 * deve prendere in mano il telefono, e Google ha rifiutato l'app per questo
 * («Visual info on phone»). Si dice com'è; il resto succede da solo, perché
 * lo schermo ascolta l'app ([controlla]). Finché l'app non ha detto niente
 * (la prima volta, con l'auto accesa prima del telefono) si aspetta, invece
 * di dare il muro a chi Premium ce l'ha.
 */
class SchermoPremium(
    carContext: CarContext,
    /** Aperto sopra la navigazione (versione da aggiornare): chiudendolo si torna lì. */
    private val sopraLaMappa: Boolean = false,
) : Screen(carContext), DefaultLifecycleObserver {
    private val controlla: () -> Unit = {
        if (PonteAuto.guidaInAuto(carContext) && !PonteAuto.aggiorna(carContext)) apriNavigazione() else invalidate()
    }

    init {
        lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        PonteAuto.ascolta(controlla)
    }

    override fun onStop(owner: LifecycleOwner) {
        PonteAuto.smetti(controlla)
    }

    private fun apriNavigazione() {
        PonteAuto.smetti(controlla)
        if (!sopraLaMappa) screenManager.push(SchermoNavigazione(carContext))
        finish()
    }

    override fun onGetTemplate(): Template {
        if (PonteAuto.aggiorna(carContext)) {
            return MessageTemplate.Builder("Questa versione non è più attiva: serve un aggiornamento.")
                .setTitle("C'è una versione nuova di gdanav")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }
        if (!PonteAuto.premiumNoto(carContext)) {
            return MessageTemplate.Builder("Un momento…")
                .setTitle("gdanav")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }
        val ospite = PonteAuto.premiumOspite(carContext)
        val messaggio = MessageTemplate.Builder(
            if (ospite) {
                "La navigazione in auto è inclusa in gdahome Premium."
            } else {
                "La navigazione in auto è inclusa in gdanav Premium."
            },
        )
            .setTitle(if (ospite) "gdahome Premium" else "gdanav Premium")
            .setHeaderAction(Action.APP_ICON)
        // Dentro gdahome la casa non è Premium: ci si arriva anche da qui.
        GdanavInAuto.casa?.let { casa ->
            messaggio.addAction(
                Action.Builder().setTitle("Casa").setOnClickListener { screenManager.push(casa(carContext)) }.build(),
            )
        }
        return messaggio.build()
    }
}
