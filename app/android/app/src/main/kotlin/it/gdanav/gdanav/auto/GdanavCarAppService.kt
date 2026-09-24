package it.gdanav.gdanav.auto

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.hardware.CarHardwareManager
import androidx.car.app.hardware.common.CarValue
import androidx.car.app.hardware.common.OnCarDataAvailableListener
import androidx.car.app.hardware.info.EnergyLevel
import androidx.car.app.hardware.info.Mileage
import androidx.car.app.hardware.info.Speed
import androidx.car.app.validation.HostValidator
import androidx.core.content.ContextCompat

/** gdanav su Android Auto: un'app di navigazione. */
class GdanavCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = SessioneGdanav()
}

class SessioneGdanav : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        // Se l'app sul telefono non è aperta, la si accende qui.
        MotoreFlutter.assicura(carContext)
        ascoltaEnergia()
        // Android Auto fa parte di gdanav Premium.
        return if (PonteAuto.premium(carContext)) SchermoNavigazione(carContext) else SchermoPremium(carContext)
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
