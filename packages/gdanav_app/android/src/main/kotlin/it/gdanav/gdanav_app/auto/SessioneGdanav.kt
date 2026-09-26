package it.gdanav.gdanav_app.auto

import android.content.Context
import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.hardware.CarHardwareManager
import androidx.car.app.hardware.common.CarValue
import androidx.car.app.hardware.common.OnCarDataAvailableListener
import androidx.car.app.hardware.info.EnergyLevel
import androidx.car.app.hardware.info.Mileage
import androidx.car.app.hardware.info.Speed
import androidx.core.content.ContextCompat

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
    override fun onCreateScreen(intent: Intent): Screen {
        accendi(carContext)
        ascoltaEnergia()
        // Android Auto fa parte di gdanav Premium.
        if (!PonteAuto.premium(carContext)) return SchermoPremium(carContext)
        val schermo = SchermoNavigazione(carContext)
        naviga(intent)
        return schermo
    }

    /** «Ok Google, naviga verso…» o un'altra app, con gdanav già aperto sull'auto. */
    override fun onNewIntent(intent: Intent) {
        if (intent.action != CarContext.ACTION_NAVIGATE || !PonteAuto.premium(carContext)) return
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
}
