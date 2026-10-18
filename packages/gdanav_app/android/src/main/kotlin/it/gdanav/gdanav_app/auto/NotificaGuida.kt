package it.gdanav.gdanav_app.auto

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import androidx.car.app.notification.CarAppExtender
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * La notifica di navigazione (NF-3): parte con la guida, si aggiorna a ogni
 * manovra (sempre la stessa, non una nuova) e sparisce alla fine. L'auto la
 * usa per mostrare la manovra quando si è su un'altra schermata, il telefono
 * per tenere la guida in vista con l'app dietro. Suona (in silenzio: parla
 * già la voce) solo quando cambia la manovra, non a ogni metro.
 *
 * Con Android Auto collegato il telefono sta zitto: la guida è sullo schermo
 * dell'auto. Se lì davanti c'è GdANav la notifica non serve e non c'è; se
 * c'è un'altra app (la musica, il telefono) serve all'auto per la manovra in
 * alto, e sul telefono passa per un canale al minimo: niente icona, niente
 * finestrella, in fondo alle notifiche.
 */
object NotificaGuida {
    const val CANALE = "gdanav_guida"
    const val CANALE_IN_AUTO = "gdanav_guida_in_auto"
    private const val ID = 4201

    private var ultimaManovra: String? = null
    private var canaliFatti = false

    /** La sessione di Android Auto è aperta. */
    @Volatile var inAuto = false

    /** Sullo schermo dell'auto, davanti, c'è GdANav. */
    @Volatile var davantiInAuto = false

    private fun canali(context: Context) {
        if (canaliFatti || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val c = NotificationChannel(CANALE, "Guida", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "La prossima manovra mentre GdANav ti guida"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        val a = NotificationChannel(CANALE_IN_AUTO, "Guida in auto", NotificationManager.IMPORTANCE_MIN).apply {
            description = "La manovra per lo schermo dell'auto: sul telefono non si vede"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannels(listOf(c, a))
        canaliFatti = true
    }

    private fun puo(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Aggiorna la notifica con la guida, o la toglie se non si guida più. */
    @SuppressLint("MissingPermission")
    fun aggiorna(context: Context, g: PonteAuto.Guida?) {
        val gestore = NotificationManagerCompat.from(context)
        if (g == null || (inAuto && davantiInAuto)) {
            if (ultimaManovra != null) gestore.cancel(ID)
            ultimaManovra = null
            return
        }
        if (!puo(context)) return
        canali(context)
        val testo = testo(g)
        val titolo = "${GuidaAuto.distanzaTesto(g.distanzaM)} · ${IconeManovra.frase(g.tipo)}"
        val chiave = "${g.tipo}|$testo"
        val nuova = chiave != ultimaManovra
        ultimaManovra = chiave
        val icona = IconeManovra.icona(g.tipo)
        val grande = bitmap(context, icona)
        val apri = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val arrivo = java.text.SimpleDateFormat("HH:mm", java.util.Locale.ITALY).format(java.util.Date(g.arrivoMs))
        val meta = g.destinazione.ifEmpty { "la meta" }
        val auto = CarAppExtender.Builder()
            .setContentTitle(titolo)
            .setContentText(testo)
            .setSmallIcon(icona)
            .setImportance(if (nuova) NotificationManagerCompat.IMPORTANCE_HIGH else NotificationManagerCompat.IMPORTANCE_LOW)
        grande?.let { auto.setLargeIcon(it) }
        apri?.let { auto.setContentIntent(it) }
        val n = NotificationCompat.Builder(context, if (inAuto) CANALE_IN_AUTO else CANALE)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setSmallIcon(icona)
            .setContentTitle(titolo)
            .setContentText(testo)
            .setSubText("$meta · arrivo $arrivo")
            .setOngoing(true)
            .setOnlyAlertOnce(!nuova || inAuto)
            .setSilent(inAuto)
            .setShowWhen(false)
            .setPriority(if (inAuto) NotificationCompat.PRIORITY_MIN else NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .extend(auto.build())
        grande?.let { n.setLargeIcon(it) }
        apri?.let { n.setContentIntent(it) }
        try {
            gestore.notify(ID, n.build())
        } catch (e: SecurityException) {
            // Permesso tolto nel frattempo: niente notifica, la guida va avanti.
        }
    }

    private fun testo(g: PonteAuto.Guida): String {
        val cartello = listOfNotNull(
            g.uscita.takeIf { it.isNotEmpty() }?.let { "Uscita $it" },
            g.verso.takeIf { it.isNotEmpty() },
        ).joinToString(" · ")
        return when {
            cartello.isNotEmpty() -> cartello
            g.strada.isNotEmpty() -> g.strada
            else -> g.istruzione
        }
    }

    private fun bitmap(context: Context, id: Int): Bitmap? {
        val d = ContextCompat.getDrawable(context, id)?.mutate() ?: return null
        val lato = (64 * context.resources.displayMetrics.density).toInt()
        val b = Bitmap.createBitmap(lato, lato, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawColor(Color.rgb(32, 33, 36))
        val m = lato / 8
        d.setTint(Color.WHITE)
        d.setBounds(m, m, lato - m, lato - m)
        d.draw(c)
        return b
    }
}
