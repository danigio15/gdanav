package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Manca la batteria per le soste: senza un'auto elettrica configurata, o con
 * la batteria che non si sa. Sulla mappa c'era solo il messaggio, senza tasti:
 * un vicolo cieco, perché in auto la batteria non si scrive. Qui il messaggio
 * ha il tasto per passare all'auto termica (il viaggio si rifà e parte), o
 * per tornare alla mappa.
 *
 * Se nel frattempo il telefono risolve da sé (la batteria arriva, si sceglie
 * un'altra meta), la proposta sparisce e lo schermo si chiude.
 */
class SchermoTermica(carContext: CarContext, private val id: String) : Screen(carContext), DefaultLifecycleObserver {
    private val controlla: () -> Unit = { if (PonteAuto.termica.id != id) finish() }

    init {
        lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        PonteAuto.ascolta(controlla)
    }

    override fun onStop(owner: LifecycleOwner) {
        PonteAuto.smetti(controlla)
    }

    override fun onGetTemplate(): Template {
        val t = PonteAuto.termica
        val usa = Action.Builder()
            .setTitle("Usa auto termica")
            .setOnClickListener {
                PonteAuto.usaTermica(id)
                finish()
            }
        // Senza auto elettrica la termica è la proposta; altrimenti una via d'uscita.
        if (t.primaria && carContext.carAppApiLevel >= 4) usa.setFlags(Action.FLAG_PRIMARY)
        return MessageTemplate.Builder(PonteAuto.messaggio ?: "Passiamo all'auto termica?")
            .setTitle(t.titolo ?: "Auto elettrica")
            .setHeaderAction(Action.BACK)
            .addAction(usa.build())
            .addAction(Action.Builder().setTitle("Annulla").setOnClickListener { finish() }.build())
            .build()
    }
}
