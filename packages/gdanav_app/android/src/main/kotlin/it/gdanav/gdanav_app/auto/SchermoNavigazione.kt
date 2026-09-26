package it.gdanav.gdanav_app.auto

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R

/**
 * Lo schermo dell'auto: la mappa di gdanav sotto (con velocità, limite e dati
 * dell'auto), sopra la prossima manovra con corsie, svincolo e arrivo nelle
 * schede di Android Auto. In alto Cerca, Menu e Fine; a lato sposta, + e −,
 * 2D/3D e Centra. In guida il viaggio va anche al cruscotto dell'auto e
 * nella notifica di navigazione.
 */
class SchermoNavigazione(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val renderer = RendererMappa(carContext)
    private val navigazione = carContext.getCarService(NavigationManager::class.java)
    private var navigando = false
    private var versione = -1
    private val guidaAuto = GuidaAuto(carContext)
    private val aggiorna: () -> Unit = {
        renderer.aggiorna()
        sincronizzaNavigazione()
        // Il modello si rifà solo se cambia qualcosa che mostra: l'auto
        // concede pochi aggiornamenti.
        if (PonteAuto.versioneModello != versione) {
            versione = PonteAuto.versioneModello
            viaggioAlCruscotto()
            invalidate()
        }
    }

    /** Il viaggio anche al cruscotto dell'auto e alle altre schermate (NF-4). */
    private fun viaggioAlCruscotto() {
        val g = PonteAuto.guida ?: return
        if (!navigando) return
        try {
            navigazione.updateTrip(guidaAuto.viaggio(g))
        } catch (e: Exception) {
            // Un'auto senza cruscotto per le app: si guida lo stesso.
        }
    }

    init {
        lifecycle.addObserver(this)
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(renderer)
        renderer.alCambio = { invalidate() }
        // Tocco su un distributore, una colonnina o un ristorante: la scheda.
        renderer.alPunto = { proprieta, lat, lon ->
            PonteAuto.punto(proprieta, lat, lon) { info ->
                if (info != null) screenManager.push(SchermoPunto(carContext, info))
            }
        }
        navigazione.setNavigationManagerCallback(object : NavigationManagerCallback {
            override fun onStopNavigation() {
                PonteAuto.fermaDallAuto()
            }

            // La prova di guida (NF-7): il revisore la accende da fermo, e il
            // telefono percorre il viaggio da solo.
            override fun onAutoDriveEnabled() {
                PonteAuto.provaDiGuida()
            }
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
            chiediNotifiche()
            viaggioAlCruscotto()
        } else if (!guida && navigando) {
            navigazione.navigationEnded()
            navigando = false
        }
    }

    private var notificheChieste = false

    /** Da Android 13 le notifiche (quella della guida) vanno chieste: una volta. */
    private fun chiediNotifiche() {
        if (notificheChieste || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        notificheChieste = true
        if (ContextCompat.checkSelfPermission(carContext, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        try {
            carContext.requestPermissions(listOf(Manifest.permission.POST_NOTIFICATIONS)) { concessi, _ ->
                if (concessi.isNotEmpty()) NotificaGuida.aggiorna(carContext, PonteAuto.guida)
            }
        } catch (e: Exception) {
            // Chi non può chiederlo in auto lo chiederà l'app sul telefono.
        }
    }

    private fun icona(id: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, id)).build()

    private fun tasto(id: Int, azione: () -> Unit) =
        Action.Builder().setIcon(icona(id)).setOnClickListener { azione() }.build()

    /** In alto: Cerca, la casa (dentro gdahome) e Menu (in guida anche Fine); appena passata una segnalazione, «C'è ancora?» Sì / No. */
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
        if (PonteAuto.guida != null) {
            // In guida c'è poco spazio: solo la lente.
            striscia.addAction(tasto(R.drawable.auto_cerca) { screenManager.push(SchermoCerca(carContext)) })
            casa(striscia)
            striscia.addAction(tasto(R.drawable.auto_menu) { screenManager.push(SchermoMenu(carContext, renderer)) })
            striscia.addAction(Action.Builder().setTitle("Fine").setOnClickListener { PonteAuto.fermaDallAuto() }.build())
        } else {
            // Da fermi, come Google Maps: «Cerca» e «Menu» ben leggibili.
            striscia.addAction(
                Action.Builder()
                    .setTitle("Cerca")
                    .setIcon(icona(R.drawable.auto_cerca))
                    .setOnClickListener { screenManager.push(SchermoCerca(carContext)) }
                    .build(),
            )
            casa(striscia)
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

    /**
     * La casa, se chi porta gdanav dentro ne ha una (gdahome): un tasto col
     * solo disegno. Al massimo quattro tasti, e con Cerca, Menu e Fine ci sta.
     */
    private fun casa(striscia: ActionStrip.Builder) {
        GdanavInAuto.casa?.let { casa ->
            striscia.addAction(tasto(R.drawable.auto_casa) { screenManager.push(casa(carContext)) })
        }
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
            // La manovra (freccia, distanza, corsie, svincolo col cartello)
            // e l'arrivo nelle schede di Android Auto, come vuole Google per
            // i navigatori (NF-2): sulla mappa restano velocità, limite e dati
            // dell'auto.
            modello.setNavigationInfo(guidaAuto.scheda(guida))
            modello.setDestinationTravelEstimate(guidaAuto.stima(guida))
        } else {
            // Da fermi la mappa resta pulita; il riquadro solo se c'è qualcosa
            // da dire («Calcolo il percorso…», un errore).
            PonteAuto.messaggio?.let { testo ->
                modello.setNavigationInfo(MessageInfo.Builder(testo).build())
            }
        }
        return modello.build()
    }
}
