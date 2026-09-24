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
        ascoltaEnergia()
        return SchermoNavigazione(carContext)
    }

    /** Batteria e autonomia dall'auto, se le passa: molte non lo fanno. */
    private fun ascoltaEnergia() {
        try {
            val hardware = carContext.getCarService(CarHardwareManager::class.java)
            val ascoltatore = OnCarDataAvailableListener<EnergyLevel> { energia ->
                val batteria = energia.batteryPercent
                val autonomia = energia.rangeRemainingMeters
                if (batteria.status == CarValue.STATUS_SUCCESS) {
                    batteria.value?.let { b ->
                        PonteAuto.energiaDallAuto(b, if (autonomia.status == CarValue.STATUS_SUCCESS) autonomia.value else null)
                    }
                }
            }
            hardware.carInfo.addEnergyLevelListener(ContextCompat.getMainExecutor(carContext), ascoltatore)
        } catch (e: Exception) {
            // Senza dati dell'auto si guida lo stesso: la batteria arriva da altre fonti.
        }
    }
}
