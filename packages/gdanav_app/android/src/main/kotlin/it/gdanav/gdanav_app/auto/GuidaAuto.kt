package it.gdanav.gdanav_app.auto

import android.content.Context
import android.graphics.Bitmap
import androidx.car.app.model.CarIcon
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Distance
import androidx.car.app.navigation.model.Destination
import androidx.car.app.navigation.model.Lane
import androidx.car.app.navigation.model.LaneDirection
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.navigation.model.Trip
import androidx.core.graphics.drawable.IconCompat
import java.util.TimeZone

/**
 * La guida nei modi di Android Auto, gli stessi per tutti: la scheda della
 * manovra e l'arrivo sullo schermo (NF-2), il viaggio per il cruscotto
 * dell'auto (NF-4) e la notifica di navigazione (NF-3) partono da qui.
 */
class GuidaAuto(private val context: Context) {
    /** Compone lo svincolo col cartello: la stessa grafica del pannello. */
    private val pannello = PannelloAuto(context, context.resources.displayMetrics.density)

    private fun icona(id: Int) = CarIcon.Builder(IconCompat.createWithResource(context, id)).build()

    /**
     * La manovra: freccia (con l'uscita nelle rotonde), strada, cartello
     * («Uscita 12 · A12 · Arnhem») e, avvicinandosi allo svincolo, le corsie
     * con quella giusta evidenziata.
     */
    fun passo(g: PonteAuto.Guida, conCorsie: Boolean = true): Step {
        val manovra = Maneuver.Builder(IconeManovra.tipo(g.tipo, g.rotonda)).setIcon(icona(IconeManovra.icona(g.tipo)))
        val rotonda = g.rotonda
        if (g.tipo == 26 && rotonda != null && rotonda > 0) manovra.setRoundaboutExitNumber(rotonda)
        val passo = Step.Builder(testo(g)).setManeuver(manovra.build())
        if (g.strada.isNotEmpty()) passo.setRoad(g.strada)
        if (conCorsie && g.corsie.isNotEmpty()) {
            for (c in g.corsie) {
                val corsia = Lane.Builder()
                for (d in c.direzioni.ifEmpty { listOf("dritto") }) {
                    val giusta = c.giusta && (c.consigliata == null || c.consigliata == d)
                    corsia.addDirection(LaneDirection.create(IconeManovra.formaCorsia(d), giusta))
                }
                passo.addLane(corsia.build())
            }
            passo.setLanesImage(CarIcon.Builder(IconCompat.createWithBitmap(corsie(g.corsie))).build())
        }
        return passo.build()
    }

    /** Cosa dire della manovra: il cartello, se c'è, altrimenti la strada. */
    fun testo(g: PonteAuto.Guida): String {
        val cartello = listOfNotNull(
            g.uscita.takeIf { it.isNotEmpty() }?.let { "Uscita $it" },
            g.verso.takeIf { it.isNotEmpty() },
        ).joinToString(" · ")
        return when {
            cartello.isNotEmpty() -> cartello
            g.strada.isNotEmpty() -> g.strada
            g.istruzione.isNotEmpty() -> g.istruzione
            else -> " "
        }
    }

    /** La manovra dopo, piccola sotto la scheda («Poi»). */
    private fun dopo(g: PonteAuto.Guida): Step? {
        val tipo = g.dopoTipo ?: return null
        return Step.Builder(g.dopoStrada.ifEmpty { " " })
            .setManeuver(Maneuver.Builder(IconeManovra.tipo(tipo)).setIcon(icona(IconeManovra.icona(tipo))).build())
            .build()
    }

    /** La scheda della manovra, con lo svincolo col cartello avvicinandosi a un'uscita. */
    fun scheda(g: PonteAuto.Guida): RoutingInfo {
        val routing = RoutingInfo.Builder().setCurrentStep(passo(g), distanza(g.distanzaM))
        dopo(g)?.let { routing.setNextStep(it) }
        svincolo(g)?.let { routing.setJunctionImage(CarIcon.Builder(IconCompat.createWithBitmap(it)).build()) }
        return routing.build()
    }

    /** Arrivo, tempo e km che restano. */
    fun stima(g: PonteAuto.Guida): TravelEstimate =
        TravelEstimate.Builder(distanza(g.restantiM), DateTimeWithZone.create(g.arrivoMs, TimeZone.getDefault()))
            .setRemainingTimeSeconds(g.restantiS.coerceAtLeast(0))
            .build()

    /** Il tempo alla prossima manovra, alla velocità media di quello che resta. */
    private fun stimaPasso(g: PonteAuto.Guida): TravelEstimate {
        val secondi = if (g.restantiM > 0) (g.restantiS * g.distanzaM / g.restantiM).toLong() else 0L
        return TravelEstimate.Builder(
            distanza(g.distanzaM),
            DateTimeWithZone.create(System.currentTimeMillis() + secondi * 1000, TimeZone.getDefault()),
        ).setRemainingTimeSeconds(secondi.coerceAtLeast(0)).build()
    }

    /** Il viaggio per il cruscotto dell'auto e le altre schermate (NF-4). */
    fun viaggio(g: PonteAuto.Guida): Trip {
        val meta = Destination.Builder().setName(g.destinazione.ifEmpty { "Destinazione" }).build()
        val viaggio = Trip.Builder()
            .addDestination(meta, stima(g))
            .addStep(passo(g), stimaPasso(g))
            .setLoading(false)
        if (g.strada.isNotEmpty()) viaggio.setCurrentRoad(g.strada)
        return viaggio.build()
    }

    /** Le corsie già disegnate, per non rifarle a ogni aggiornamento. */
    private var corsieFatte: Pair<List<PonteAuto.CorsiaAuto>, Bitmap>? = null

    private fun corsie(c: List<PonteAuto.CorsiaAuto>): Bitmap =
        corsieFatte?.takeIf { it.first == c }?.second ?: ImmagineCorsie.disegna(c).also { corsieFatte = c to it }

    private fun svincolo(g: PonteAuto.Guida): Bitmap? {
        val id = g.svincolo ?: return null
        val vista = PonteAuto.svincoli[id] ?: return null
        return pannello.svincoloConCartello(vista, id, g)
    }

    companion object {
        fun distanza(metri: Double): Distance =
            if (metri < 1000) {
                Distance.create((Math.round(metri / 10.0) * 10).toDouble(), Distance.UNIT_METERS)
            } else {
                Distance.create(metri / 1000.0, Distance.UNIT_KILOMETERS)
            }

        /** La distanza a parole, per la notifica: «300 m», «1,2 km». */
        fun distanzaTesto(m: Double): String =
            if (m < 1000) "${Math.round(m / 10.0) * 10} m" else String.format(java.util.Locale.ITALY, "%.1f km", m / 1000)
    }
}
