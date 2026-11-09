package it.gdanav.gdanav_app.auto

import android.content.Context
import android.graphics.Bitmap
import android.text.Spanned
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.ForegroundCarColorSpan
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
import kotlin.math.roundToInt

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
        // Le frasi dalla più lunga alla più corta: sugli schermi piccoli
        // l'auto prende quella che ci sta («2ª uscita»).
        val passo = Step.Builder(cue(g.frasi, testo(g))).setManeuver(manovra.build())
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

    /**
     * Il testo della manovra con le sue varianti, dalla più lunga: l'auto
     * mostra la prima che ci sta. Senza frasi (un'app di prima) [riserva].
     */
    private fun cue(frasi: List<String>, riserva: String): CarText {
        if (frasi.isEmpty()) return CarText.create(riserva)
        val t = CarText.Builder(frasi.first())
        for (f in frasi.drop(1)) t.addVariant(f)
        return t.build()
    }

    /**
     * La manovra dopo, piccola sotto la scheda («Poi»). L'app la manda solo
     * se arriva entro 150 m da questa (`poiVicino`), come Mappe di Apple.
     */
    private fun dopo(g: PonteAuto.Guida): Step? {
        val tipo = g.dopoTipo ?: return null
        val manovra = Maneuver.Builder(IconeManovra.tipo(tipo, g.dopoRotonda)).setIcon(icona(IconeManovra.icona(tipo)))
        val rotonda = g.dopoRotonda
        if (tipo == 26 && rotonda != null && rotonda > 0) manovra.setRoundaboutExitNumber(rotonda)
        return Step.Builder(cue(g.dopoFrasi, g.dopoStrada.ifEmpty { " " }))
            .setManeuver(manovra.build())
            .build()
    }

    /** La scheda della manovra, con lo svincolo col cartello avvicinandosi a un'uscita. */
    fun scheda(g: PonteAuto.Guida): RoutingInfo {
        val routing = RoutingInfo.Builder().setCurrentStep(passo(g), distanza(g.distanzaM))
        dopo(g)?.let { routing.setNextStep(it) }
        svincolo(g)?.let { routing.setJunctionImage(CarIcon.Builder(IconCompat.createWithBitmap(it)).build()) }
        return routing.build()
    }

    /**
     * Arrivo, tempo e km che restano. Con [conTesto] (l'auto ha l'API 5)
     * accanto anche quello che stava nella barra sopra la mappa: la batteria,
     * i km che le restano, la batteria all'arrivo, il meteo e il pedaggio
     * che resta ([testoDelViaggio]).
     */
    fun stima(g: PonteAuto.Guida, conTesto: Boolean = false): TravelEstimate {
        val stima = TravelEstimate.Builder(distanza(g.restantiM), DateTimeWithZone.create(g.arrivoMs, TimeZone.getDefault()))
            .setRemainingTimeSeconds(g.restantiS.coerceAtLeast(0))
        // Il tempo che resta col colore del traffico, come sul telefono:
        // arancio con un ritardo, rosso da dieci minuti. L'ora d'arrivo ha
        // già dentro il ritardo; il colore dice che è per le code.
        when {
            g.trafficoMin >= 10 -> stima.setRemainingTimeColor(CarColor.RED)
            g.trafficoMin >= 1 -> stima.setRemainingTimeColor(CarColor.YELLOW)
        }
        if (conTesto) testoDelViaggio(PonteAuto.cruscotto, g.pedaggio)?.let { stima.setTripText(CarText.create(it)) }
        return stima.build()
    }

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
        /**
         * La riga dell'auto nella scheda dell'arrivo, sotto tempo, ora e km:
         * «🔋 51% · 200 km · arrivo 46% · ☀ 12° · pedaggio ~12,40 €».
         *
         * «Non mi piace la predisposizione batteria: ingloba in km residui e
         * tempo di arrivo», e poi «togli anche il simbolo del meteo e ingloba
         * nel quadrato». «Arrivo» e non «all'arrivo»: la scheda è stretta, e
         * la riga deve starci intera. Stava in una barra sopra la mappa, accanto al
         * tachimetro, e copriva la strada; adesso è una riga della scheda
         * che Android Auto disegna già. La batteria all'arrivo in verde (in
         * rosso sotto il 10%), il pedaggio in ambra come sul telefono; i
         * colori l'auto può ignorarli, il testo resta. `null` se non c'è
         * niente da dire.
         */
        /*
         * [stretto]: la mappa ha mezzo schermo (accanto la musica, il
         * telefono), e la scheda è più stretta. «Quando sta messo a riquadro
         * doppio non entra tutto nel riquadro delle info viaggio»: il
         * pedaggio finiva tagliato («1,0…»). Allora la riga si accorcia:
         * «🔋 99% → 93%» al posto di «🔋 99% · arrivo 93%», e il pedaggio
         * senza la parola («1,05 €», in ambra).
         */
        fun testoDelViaggio(
            c: PonteAuto.Cruscotto,
            pedaggio: String?,
            stretto: Boolean = PonteAuto.mappaStretta,
        ): CharSequence? {
            val testo = android.text.SpannableStringBuilder()
            fun pezzo(t: String, colore: CarColor? = null) {
                if (testo.isNotEmpty()) testo.append(" · ")
                val da = testo.length
                testo.append(t)
                colore?.let {
                    testo.setSpan(ForegroundCarColorSpan.create(it), da, testo.length, Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
                }
            }
            val circa = if (c.batteriaStimata) "~" else ""
            c.batteria?.let { b ->
                pezzo("🔋$NBSP$circa${b.roundToInt()}%", if (b < 20) CarColor.RED else null)
                // Stretta: la batteria all'arrivo subito dopo quella di adesso.
                val arrivo = c.arrivoBatteria
                if (stretto && arrivo != null) {
                    testo.append("${NBSP}→$NBSP")
                    val da = testo.length
                    testo.append("${arrivo.roundToInt()}%")
                    testo.setSpan(
                        ForegroundCarColorSpan.create(if (arrivo < 10) CarColor.RED else CarColor.GREEN),
                        da,
                        testo.length,
                        Spanned.SPAN_INCLUSIVE_EXCLUSIVE,
                    )
                }
                c.autonomiaKm?.let { pezzo("$circa${it.roundToInt()}${NBSP}km") }
                c.arrivoBatteria?.takeIf { !stretto }?.let { v ->
                    if (testo.isNotEmpty()) testo.append(" · ")
                    testo.append("arrivo$NBSP")
                    val da = testo.length
                    testo.append("${v.roundToInt()}%")
                    testo.setSpan(
                        ForegroundCarColorSpan.create(if (v < 10) CarColor.RED else CarColor.GREEN),
                        da,
                        testo.length,
                        Spanned.SPAN_INCLUSIVE_EXCLUSIVE,
                    )
                }
            }
            c.meteoTemperatura?.let { m -> pezzo("${c.meteoEmoji?.let { "$it$NBSP" } ?: ""}${m.roundToInt()}°") }
            val costo = if (stretto) c.pedaggio ?: pedaggio?.removeSuffix(" pedaggio") else pedaggio
            if (!costo.isNullOrEmpty()) pezzo(costo, CarColor.createCustom(AMBRA_GIORNO, AMBRA_NOTTE))
            return testo.takeIf { it.isNotEmpty() }
        }

        /**
         * Lo spazio che non va a capo: «Guarda il meteo», il sole restava in
         * fondo a una riga e i gradi andavano sotto. Dentro un pezzo (il sole e
         * i gradi, «arrivo» e la percentuale, i km) non si va a capo; si va a
         * capo solo fra un pezzo e l'altro, dove c'è il «·».
         */
        private const val NBSP = "\u00A0"

        /** L'ambra della pastiglia del pedaggio sul telefono, di giorno e di notte. */
        private val AMBRA_GIORNO = android.graphics.Color.rgb(138, 83, 0)
        private val AMBRA_NOTTE = android.graphics.Color.rgb(255, 207, 112)

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
