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
 * lo sblocca (o lo ritrova dal Play Store), si passa alla navigazione.
 */
class SchermoPremium(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val controlla: () -> Unit = { if (PonteAuto.premium(carContext)) apriNavigazione() }

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
        screenManager.push(SchermoNavigazione(carContext))
        finish()
    }

    override fun onGetTemplate(): Template {
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
                    .setOnClickListener { if (PonteAuto.premium(carContext)) apriNavigazione() else invalidate() }
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
