package it.gdanav.gdanav_app.musica

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Il servizio che Android vuole per lasciar vedere i lettori delle altre app
 * (`MediaSessionManager.getActiveSessions`): l'utente lo accende da
 * «Accesso alle notifiche». GdANav non legge le notifiche: questo servizio non
 * guarda né tiene niente di quello che arriva, serve solo come chiave per il
 * lettore musicale ([LettoreTelefono]).
 */
class AscoltoNotifiche : NotificationListenerService() {
    // Collegato dal sistema: il permesso è appena stato dato (o l'app è
    // appena partita con il permesso). Lo si dice al lettore, che parte
    // subito: vedi [LettoreTelefono.servizio].
    override fun onListenerConnected() {
        LettoreTelefono.servizio(applicationContext, true)
    }

    override fun onListenerDisconnected() {
        LettoreTelefono.servizio(applicationContext, false)
    }

    override fun onDestroy() {
        LettoreTelefono.servizio(applicationContext, false)
        super.onDestroy()
    }

    // Le notifiche non interessano: niente si legge, niente si conserva.
    override fun onNotificationPosted(sbn: StatusBarNotification?) {}

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}
}
