package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Senza gdanav Premium: si dice come sbloccarlo dal telefono. Appena l'app
 * lo sblocca (o lo ritrova dal Play Store), si passa alla navigazione. Con
 * una versione troppo vecchia ([PonteAuto.aggiorna]) si dice invece di
 * aggiornare gdanav sul telefono.
 */
class SchermoPremium(
    carContext: CarContext,
    /** Aperto sopra la navigazione (versione da aggiornare): chiudendolo si torna lì. */
    private val sopraLaMappa: Boolean = false,
) : Screen(carContext), DefaultLifecycleObserver {
    private val controlla: () -> Unit = { if (PonteAuto.guidaInAuto(carContext)) apriNavigazione() }

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
            return MessageTemplate.Builder("Aggiorna gdanav sul telefono: questa versione non è più attiva.")
                .setTitle("C'è una versione nuova di gdanav")
                .setHeaderAction(Action.APP_ICON)
                .addAction(
                    Action.Builder()
                        .setTitle("Ho aggiornato")
                        .setOnClickListener { if (PonteAuto.guidaInAuto(carContext)) apriNavigazione() else invalidate() }
                        .build(),
                )
                .build()
        }
        val ospite = PonteAuto.premiumOspite(carContext)
        val messaggio = MessageTemplate.Builder(
            if (ospite) {
                "La navigazione in auto fa parte del Premium di gdahome. Attivalo dall'app gdahome sul telefono."
            } else {
                "La navigazione in auto fa parte di gdanav Premium. Sbloccalo dall'app sul telefono: menu → Premium."
            },
        )
            .setTitle(if (ospite) "gdahome Premium" else "gdanav Premium")
            .setHeaderAction(Action.APP_ICON)
            .addAction(
                Action.Builder()
                    .setTitle("Ho sbloccato")
                    .setOnClickListener { if (PonteAuto.guidaInAuto(carContext)) apriNavigazione() else invalidate() }
                    .build(),
            )
        // Dentro gdahome la casa non è Premium: ci si arriva anche da qui.
        GdanavInAuto.casa?.let { casa ->
            messaggio.addAction(
                Action.Builder().setTitle("Casa").setOnClickListener { screenManager.push(casa(carContext)) }.build(),
            )
        }
        return messaggio.build()
    }
}
