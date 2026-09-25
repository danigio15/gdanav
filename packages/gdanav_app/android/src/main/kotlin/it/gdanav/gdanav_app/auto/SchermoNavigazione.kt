package it.gdanav.gdanav_app.auto

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
import androidx.car.app.navigation.model.Lane
import androidx.car.app.navigation.model.LaneDirection
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R
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

    /** In alto: Cerca, la casa (dentro gdahome), Menu e Fine; appena passata una segnalazione, «C'è ancora?» Sì / No. */
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
        // La casa, se chi porta gdanav dentro ne ha una (gdahome): al massimo
        // quattro tasti, e con Cerca, Menu e Fine ci sta.
        GdanavInAuto.casa?.let { casa ->
            striscia.addAction(tasto(R.drawable.auto_casa) { screenManager.push(casa(carContext)) })
        }
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
            val routing = RoutingInfo.Builder().setCurrentStep(passo(guida), distanza(guida.distanzaM))
            // Avvicinandosi a un'uscita o a un bivio: lo svincolo in grande,
            // con le corsie giuste e la freccia.
            guida.svincolo?.let { PonteAuto.svincoli[it] }?.let { vista ->
                routing.setJunctionImage(CarIcon.Builder(IconCompat.createWithBitmap(vista)).build())
            }
            guida.dopoTipo?.let { tipo ->
                val dopo = Step.Builder(guida.dopoStrada.ifEmpty { " " })
                    .setManeuver(Maneuver.Builder(IconeManovra.tipo(tipo)).setIcon(icona(IconeManovra.icona(tipo))).build())
                routing.setNextStep(dopo.build())
            }
            modello.setNavigationInfo(routing.build())
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

    /**
     * La manovra: freccia (con l'uscita nelle rotonde), strada, cartello
     * («Uscita 12 · A12 · Arnhem») e, avvicinandosi allo svincolo, le corsie
     * con quella giusta evidenziata.
     */
    private fun passo(guida: PonteAuto.Guida): Step {
        val manovra = Maneuver.Builder(IconeManovra.tipo(guida.tipo, guida.rotonda))
            .setIcon(icona(IconeManovra.icona(guida.tipo)))
        val rotonda = guida.rotonda
        if (guida.tipo == 26 && rotonda != null && rotonda > 0) manovra.setRoundaboutExitNumber(rotonda)
        val cartello = listOfNotNull(
            guida.uscita.takeIf { it.isNotEmpty() }?.let { "Uscita $it" },
            guida.verso.takeIf { it.isNotEmpty() },
        ).joinToString(" · ")
        val testo = when {
            cartello.isNotEmpty() -> cartello
            guida.strada.isNotEmpty() -> guida.strada
            else -> guida.istruzione
        }
        val passo = Step.Builder(testo).setManeuver(manovra.build())
        if (guida.strada.isNotEmpty()) passo.setRoad(guida.strada)
        if (guida.corsie.isNotEmpty()) {
            for (c in guida.corsie) {
                val corsia = Lane.Builder()
                val direzioni = c.direzioni.ifEmpty { listOf("dritto") }
                for (d in direzioni) {
                    val giusta = c.giusta && (c.consigliata == null || c.consigliata == d)
                    corsia.addDirection(LaneDirection.create(IconeManovra.formaCorsia(d), giusta))
                }
                passo.addLane(corsia.build())
            }
            passo.setLanesImage(
                CarIcon.Builder(IconCompat.createWithBitmap(ImmagineCorsie.disegna(guida.corsie))).build(),
            )
        }
        return passo.build()
    }

    private fun distanza(metri: Double): Distance =
        if (metri < 1000) {
            Distance.create((Math.round(metri / 10.0) * 10).toDouble(), Distance.UNIT_METERS)
        } else {
            Distance.create(metri / 1000.0, Distance.UNIT_KILOMETERS)
        }
}
