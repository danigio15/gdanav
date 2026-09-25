package it.gdanav.gdanav.auto

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import it.gdanav.gdanav_app.auto.SessioneGdanav

/**
 * gdanav su Android Auto: un'app di navigazione. Gli schermi stanno nel
 * pacchetto `gdanav_app`, che li presta anche a gdahome; qui c'è solo il
 * servizio, col motore Flutter di quest'app.
 */
class GdanavCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    // Se l'app sul telefono non è aperta, la si accende qui.
    override fun onCreateSession(): Session = SessioneGdanav { MotoreFlutter.assicura(it) }
}
