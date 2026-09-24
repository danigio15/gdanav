package it.gdanav.gdanav.auto

import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Distance
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.TimeZone

/**
 * Lo schermo dell'auto: la mappa di gdanav sotto, e sopra la prossima
 * manovra con la distanza e l'arrivo, come vuole Android Auto.
 */
class SchermoNavigazione(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val renderer = RendererMappa(carContext)
    private val navigazione = carContext.getCarService(NavigationManager::class.java)
    private var navigando = false
    private val aggiorna: () -> Unit = {
        renderer.aggiorna()
        sincronizzaNavigazione()
        invalidate()
    }

    init {
        lifecycle.addObserver(this)
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(renderer)
        navigazione.setNavigationManagerCallback(object : NavigationManagerCallback {
            override fun onStopNavigation() {
                PonteAuto.fermaDallAuto()
            }

            override fun onAutoDriveEnabled() {}
        })
    }

    override fun onCreate(owner: LifecycleOwner) {
        PonteAuto.ascolta(aggiorna)
        sincronizzaNavigazione()
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PonteAuto.smetti(aggiorna)
        if (navigando) navigazione.navigationEnded()
        navigando = false
    }

    /** Android Auto vuole sapere quando si naviga, per le altre app e l'assistente. */
    private fun sincronizzaNavigazione() {
        val guida = PonteAuto.guida != null
        if (guida && !navigando) {
            navigazione.navigationStarted()
            navigando = true
        } else if (!guida && navigando) {
            navigazione.navigationEnded()
            navigando = false
        }
    }

    override fun onGetTemplate(): Template {
        val guida = PonteAuto.guida
        val azione = Action.Builder()
            .setTitle(if (guida != null) "Fine" else "gdanav")
            .setOnClickListener { if (PonteAuto.guida != null) PonteAuto.fermaDallAuto() }
            .build()
        val modello = NavigationTemplate.Builder()
            .setActionStrip(ActionStrip.Builder().addAction(azione).build())
        if (guida != null) {
            val manovra = Maneuver.Builder(IconeManovra.tipo(guida.tipo))
                .setIcon(CarIcon.Builder(IconCompat.createWithResource(carContext, IconeManovra.icona(guida.tipo))).build())
                .build()
            val passo = Step.Builder(guida.strada.ifEmpty { guida.istruzione }).setManeuver(manovra)
            if (guida.strada.isNotEmpty()) passo.setRoad(guida.strada)
            modello.setNavigationInfo(
                RoutingInfo.Builder().setCurrentStep(passo.build(), distanza(guida.distanzaM)).build(),
            )
            modello.setDestinationTravelEstimate(
                TravelEstimate.Builder(
                    distanza(guida.restantiM),
                    DateTimeWithZone.create(guida.arrivoMs, TimeZone.getDefault()),
                ).setRemainingTimeSeconds(guida.restantiS).build(),
            )
        } else {
            modello.setNavigationInfo(
                MessageInfo.Builder("gdanav")
                    .setText("Scegli la destinazione sul telefono e premi Avvia.")
                    .build(),
            )
        }
        return modello.build()
    }

    private fun distanza(metri: Double): Distance =
        if (metri < 1000) {
            Distance.create((Math.round(metri / 10.0) * 10).toDouble(), Distance.UNIT_METERS)
        } else {
            Distance.create(metri / 1000.0, Distance.UNIT_KILOMETERS)
        }
}
