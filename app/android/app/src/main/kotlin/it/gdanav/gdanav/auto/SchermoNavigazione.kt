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
import it.gdanav.gdanav.R
import java.util.TimeZone

/**
 * Lo schermo dell'auto: la mappa di gdanav sotto (col cruscotto), sopra la
 * prossima manovra con la distanza e l'arrivo, come vuole Android Auto. In
 * alto Cerca, Menu e Fine; a lato sposta, + e −, 2D/3D e Centra.
 */
class SchermoNavigazione(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val renderer = RendererMappa(carContext)
    private val navigazione = carContext.getCarService(NavigationManager::class.java)
    private var navigando = false
    private var versione = -1
    private val aggiorna: () -> Unit = {
        renderer.aggiorna()
        sincronizzaNavigazione()
        // Il modello si rifà solo se cambia qualcosa che mostra: l'auto
        // concede pochi aggiornamenti.
        if (PonteAuto.versioneModello != versione) {
            versione = PonteAuto.versioneModello
            invalidate()
        }
    }

    init {
        lifecycle.addObserver(this)
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(renderer)
        renderer.alCambio = { invalidate() }
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

    private fun icona(id: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, id)).build()

    private fun tasto(id: Int, azione: () -> Unit) =
        Action.Builder().setIcon(icona(id)).setOnClickListener { azione() }.build()

    /** In alto: Cerca, Menu e Fine; appena passata una segnalazione, «C'è ancora?» Sì / No. */
    private fun azioni(): ActionStrip {
        val striscia = ActionStrip.Builder()
        val ancora = PonteAuto.avviso.ancoraId
        if (ancora != null) {
            striscia.addAction(
                Action.Builder().setTitle("C'è ancora").setOnClickListener { PonteAuto.ancora(ancora, true) }.build(),
            )
            striscia.addAction(tasto(R.drawable.auto_no) { PonteAuto.ancora(ancora, false) })
            return striscia.build()
        }
        striscia.addAction(tasto(R.drawable.auto_cerca) { screenManager.push(SchermoCerca(carContext)) })
        if (PonteAuto.guida != null) {
            striscia.addAction(tasto(R.drawable.auto_menu) { screenManager.push(SchermoMenu(carContext, renderer)) })
            striscia.addAction(Action.Builder().setTitle("Fine").setOnClickListener { PonteAuto.fermaDallAuto() }.build())
        } else {
            striscia.addAction(
                Action.Builder()
                    .setTitle("Menu")
                    .setIcon(icona(R.drawable.auto_menu))
                    .setOnClickListener { screenManager.push(SchermoMenu(carContext, renderer)) }
                    .build(),
            )
        }
        return striscia.build()
    }

    /** A lato della mappa: sposta, + e −, e 2D/3D (o Centra se la si è spostata). */
    private fun azioniMappa(): ActionStrip {
        val striscia = ActionStrip.Builder()
        if (carContext.carAppApiLevel >= 2) striscia.addAction(Action.PAN)
        striscia.addAction(tasto(R.drawable.auto_piu) { renderer.zoom(1.0) })
        striscia.addAction(tasto(R.drawable.auto_meno) { renderer.zoom(-1.0) })
        if (renderer.libera) {
            striscia.addAction(tasto(R.drawable.auto_centra) { renderer.segui() })
        } else {
            striscia.addAction(
                tasto(if (renderer.tridimensionale) R.drawable.auto_2d else R.drawable.auto_3d) {
                    renderer.alternaVista()
                    invalidate()
                },
            )
        }
        return striscia.build()
    }

    override fun onGetTemplate(): Template {
        versione = PonteAuto.versioneModello
        val guida = PonteAuto.guida
        val modello = NavigationTemplate.Builder()
            .setActionStrip(azioni())
            .setMapActionStrip(azioniMappa())
        if (carContext.carAppApiLevel >= 2) {
            modello.setPanModeListener { inPan -> if (!inPan) renderer.segui() }
        }
        if (guida != null) {
            val manovra = Maneuver.Builder(IconeManovra.tipo(guida.tipo))
                .setIcon(icona(IconeManovra.icona(guida.tipo)))
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
                MessageInfo.Builder("GDA NAV")
                    .setText(PonteAuto.messaggio ?: "Tocca la lente per cercare, o Menu per Casa, Lavoro e colonnine.")
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
