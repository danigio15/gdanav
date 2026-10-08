package it.gdanav.gdanav_app.auto

import android.content.Context
import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.hardware.CarHardwareManager
import androidx.car.app.hardware.common.CarValue
import androidx.car.app.hardware.common.OnCarDataAvailableListener
import androidx.car.app.hardware.info.CarHardwareLocation
import androidx.car.app.hardware.info.CarSensors
import androidx.car.app.hardware.info.EnergyLevel
import androidx.car.app.hardware.info.Mileage
import androidx.car.app.hardware.info.Speed
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Quello che l'app che porta gdanav dentro può aggiungere in auto.
 *
 * L'app gdanav non aggiunge niente. gdahome aggiunge la casa: un tasto in
 * alto sulla mappa, e sullo schermo del Premium, che apre i suoi schermi.
 */
object GdanavInAuto {
    /** Lo schermo della casa, se chi ospita gdanav ne ha uno. */
    @Volatile var casa: ((CarContext) -> Screen)? = null
}

/**
 * gdanav su Android Auto: la sessione di un'app di navigazione.
 *
 * [accendi] accende il motore Flutter se l'app sul telefono non è aperta:
 * ogni app ha il suo (l'app gdanav il suo `MotoreFlutter`, gdahome il suo).
 */
open class SessioneGdanav(private val accendi: (Context) -> Unit) : Session() {
    /*
     * Finché lo schermo dell'auto è acceso, il telefono lo sa.
     *
     * Non è un dettaglio da niente: è l'unico modo che ha il telefono di
     * sapere che **qualcuno sta guardando** mentre lui sta in tasca. Da lì
     * dipende se i dati dell'auto si chiedono freschi o si lasciano
     * invecchiare — «i dati batteria non si aggiornano finché non apro l'app
     * dal cellulare» nasceva da qui.
     *
     * Si guarda il ciclo di vita della sessione e non quello di uno schermo:
     * gli schermi si aprono e si chiudono fra loro — il menu, le colonnine,
     * le impostazioni — e in macchina ci si resta lo stesso.
     *
     * E per tutta la sessione la posizione resta accesa anche col telefono
     * in tasca (`PosizioneInAuto`): nasce con la sessione, muore con lei, e
     * se Android all'inizio dice di no ci si riprova a ogni ritorno sullo
     * schermo dell'auto.
     */
    init {
        lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onCreate(owner: LifecycleOwner) = PosizioneInAuto.accendi(carContext)

                override fun onStart(owner: LifecycleOwner) {
                    PonteAuto.inAuto(true)
                    PosizioneInAuto.riprova()
                }

                override fun onStop(owner: LifecycleOwner) = PonteAuto.inAuto(false)

                override fun onDestroy(owner: LifecycleOwner) {
                    smettiPosizioneDellAuto()
                    PosizioneInAuto.spegni(carContext)
                }
            },
        )
    }

    override fun onCreateScreen(intent: Intent): Screen {
        accendi(carContext)
        ascoltaEnergia()
        ascoltaPosizioneDellAuto()
        // Android Auto fa parte di gdanav Premium (dentro gdahome senza una
        // casa abbinata si guida base: `PonteAuto.guidaInAuto`).
        if (!PonteAuto.guidaInAuto(carContext)) return SchermoPremium(carContext)
        val schermo = SchermoNavigazione(carContext)
        naviga(intent)
        return schermo
    }

    /** «Ok Google, naviga verso…» o un'altra app, con gdanav già aperto sull'auto. */
    override fun onNewIntent(intent: Intent) {
        if (intent.action != CarContext.ACTION_NAVIGATE || !PonteAuto.guidaInAuto(carContext)) return
        carContext.getCarService(androidx.car.app.ScreenManager::class.java).popToRoot()
        naviga(intent)
    }

    /**
     * Una richiesta di navigazione (NF-6, VC-1): `geo:45.4,9.1?q=…` o
     * `geo:0,0?q=Via Roma 1, Milano`. La legge il telefono, che cerca se serve
     * e parte.
     */
    private fun naviga(intent: Intent) {
        if (intent.action != CarContext.ACTION_NAVIGATE) return
        val uri = intent.dataString ?: return
        PonteAuto.naviga(uri)
    }

    /** Batteria, autonomia, velocità e contachilometri dall'auto, se li passa: molte non lo fanno. */
    private fun ascoltaEnergia() {
        val hardware = try {
            carContext.getCarService(CarHardwareManager::class.java)
        } catch (e: Exception) {
            return
        }
        val esecutore = ContextCompat.getMainExecutor(carContext)
        // Ogni ascolto per conto suo: un'auto può dare la velocità ma non la batteria.
        try {
            hardware.carInfo.addEnergyLevelListener(esecutore, OnCarDataAvailableListener<EnergyLevel> { energia ->
                val batteria = energia.batteryPercent
                val autonomia = energia.rangeRemainingMeters
                if (batteria.status == CarValue.STATUS_SUCCESS) {
                    batteria.value?.let { b ->
                        PonteAuto.energiaDallAuto(b, if (autonomia.status == CarValue.STATUS_SUCCESS) autonomia.value else null)
                    }
                }
            })
        } catch (e: Exception) {
            // Senza dati dell'auto si guida lo stesso: la batteria arriva da altre fonti.
        }
        try {
            hardware.carInfo.addSpeedListener(esecutore, OnCarDataAvailableListener<Speed> { v ->
                val ms = if (v.displaySpeedMetersPerSecond.status == CarValue.STATUS_SUCCESS) {
                    v.displaySpeedMetersPerSecond.value
                } else if (v.rawSpeedMetersPerSecond.status == CarValue.STATUS_SUCCESS) {
                    v.rawSpeedMetersPerSecond.value
                } else {
                    null
                }
                ms?.let { PonteAuto.velocitaDallAuto(it) }
            })
        } catch (e: Exception) {
        }
        try {
            hardware.carInfo.addMileageListener(esecutore, OnCarDataAvailableListener<Mileage> { m ->
                if (m.odometerMeters.status == CarValue.STATUS_SUCCESS) {
                    m.odometerMeters.value?.let { PonteAuto.contachilometriDallAuto(it) }
                }
            })
        } catch (e: Exception) {
        }
    }

    /** I sensori dell'auto mentre se ne ascolta il GPS, per smettere a fine sessione. */
    private var sensori: CarSensors? = null

    private val gpsDellAuto = OnCarDataAvailableListener<CarHardwareLocation> { l ->
        val posizione = l.location
        if (posizione.status == CarValue.STATUS_SUCCESS) {
            posizione.value?.let { PonteAuto.posizioneDallAuto(it) }
        }
    }

    /**
     * Il GPS dell'auto, se lo passa.
     *
     * L'antenna dell'auto sta sul tetto, il telefono in tasca o in un vano: il
     * telefono mette queste posizioni nel flusso del GPS del Dart, che le
     * preferisce alle sue finché arrivano. Tante auto non le danno
     * (UNAVAILABLE o UNIMPLEMENTED): allora qui non passa niente e resta il
     * GPS del telefono, come prima. Serve il permesso della posizione, che
     * gdanav ha già; se manca, o la libreria dell'auto è troppo vecchia, la
     * chiamata fallisce e si va avanti senza.
     */
    private fun ascoltaPosizioneDellAuto() {
        if (sensori != null) return
        try {
            val s = carContext.getCarService(CarHardwareManager::class.java).carSensors
            s.addCarHardwareLocationListener(
                CarSensors.UPDATE_RATE_FASTEST,
                ContextCompat.getMainExecutor(carContext),
                gpsDellAuto,
            )
            sensori = s
        } catch (e: Exception) {
        }
    }

    /** A fine sessione: l'auto smette di mandare la posizione a chi non c'è più. */
    private fun smettiPosizioneDellAuto() {
        try {
            sensori?.removeCarHardwareLocationListener(gpsDellAuto)
        } catch (e: Exception) {
        }
        sensori = null
    }
}
