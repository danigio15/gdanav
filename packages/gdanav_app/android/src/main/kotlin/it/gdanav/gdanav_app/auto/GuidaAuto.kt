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
        val manovra = Maneuver.Builder(IconeManovra.tipo(g.tipo, g.rotonda, g.rotondaAngolo))
            .setIcon(icona(IconeManovra.icona(g.tipo, g.rotondaAngolo)))
        IconeManovra.uscitaEAngolo(manovra, g.tipo, g.rotonda, g.rotondaAngolo)
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
        val manovra = Maneuver.Builder(IconeManovra.tipo(tipo, g.dopoRotonda, g.dopoRotondaAngolo))
            .setIcon(icona(IconeManovra.icona(tipo, g.dopoRotondaAngolo)))
        IconeManovra.uscitaEAngolo(manovra, tipo, g.dopoRotonda, g.dopoRotondaAngolo)
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
        if (conTesto) testoDelViaggio(PonteAuto.cruscotto, g.pedaggio)?.let { stima.setTripText(it) }
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
         *
         * La riga va su una riga sola, e Android Auto taglia coi puntini
         * quello che non ci sta («Quando sta messo a riquadro doppio non
         * entra tutto nel riquadro delle info viaggio»: «… · 21° · 1,0…»).
         * Allora le varianti, dalla più lunga alla più corta
         * ([RigaDelViaggioAuto.varianti]): l'auto mostra la prima che ci sta.
         * La prima la sceglie [strettezza], dallo spazio della mappa
         * (`RendererMappa`), per le auto che guardano solo quella.
         */
        fun testoDelViaggio(
            c: PonteAuto.Cruscotto,
            pedaggio: String?,
            strettezza: Int = PonteAuto.strettezza,
        ): CarText? {
            val varianti = RigaDelViaggioAuto.varianti(
                batteria = c.batteria,
                stimata = c.batteriaStimata,
                // I km che resteranno all'arrivo; senza, quelli di adesso.
                autonomiaKm = c.autonomiaArrivoKm ?: c.autonomiaKm,
                arrivo = c.arrivoBatteria,
                meteoEmoji = c.meteoEmoji,
                temperatura = c.meteoTemperatura,
                pedaggioLungo = pedaggio,
                pedaggioBreve = c.pedaggio,
                strettezza = strettezza,
            )
            if (varianti.isEmpty()) return null
            val testo = CarText.Builder(colorata(varianti.first()))
            for (v in varianti.drop(1)) testo.addVariant(colorata(v))
            return testo.build()
        }

        /** Una variante coi colori dell'auto. */
        private fun colorata(tratti: List<RigaDelViaggioAuto.Tratto>): CharSequence {
            val testo = android.text.SpannableStringBuilder()
            for (t in tratti) {
                val da = testo.length
                testo.append(t.testo)
                val colore = when (t.colore) {
                    RigaDelViaggioAuto.Colore.ROSSO -> CarColor.RED
                    RigaDelViaggioAuto.Colore.VERDE -> CarColor.GREEN
                    RigaDelViaggioAuto.Colore.AMBRA -> CarColor.createCustom(AMBRA_GIORNO, AMBRA_NOTTE)
                    null -> null
                }
                colore?.let {
                    testo.setSpan(ForegroundCarColorSpan.create(it), da, testo.length, Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
                }
            }
            return testo
        }

        /** L'ambra della pastiglia del pedaggio sul telefono, di giorno e di notte. */
        private val AMBRA_GIORNO = android.graphics.Color.rgb(138, 83, 0)
        private val AMBRA_NOTTE = android.graphics.Color.rgb(255, 207, 112)

        /*
         * Le distanze con gli stessi passi del telefono (distanzaBreve in
         * gdanav_core, guida.dart): sotto i cento metri di dieci in dieci,
         * sotto il chilometro di cinquanta in cinquanta, sotto i dieci
         * chilometri di cento metri in cento, poi a chilometri interi. E si
         * arrotonda prima di scegliere l'unità: 975 metri sono «1 km», non
         * «1000 m». Prima l'auto arrotondava a dieci metri e il telefono a
         * cinquanta, e i due schermi dicevano numeri diversi.
         */

        /** I metri arrotondati al passo della loro distanza. */
        private fun metriArrotondati(metri: Double): Long =
            if (metri < 100) Math.round(metri / 10.0) * 10 else Math.round(metri / 50.0) * 50

        /** I decimi di chilometro (sotto i dieci) o i chilometri interi. */
        private fun chilometri(metri: Double): Double {
            val decimi = Math.round(metri / 100.0)
            return if (decimi < 100) decimi / 10.0 else Math.round(metri / 1000.0).toDouble()
        }

        fun distanza(metri: Double): Distance {
            val m = metriArrotondati(metri)
            return if (m < 1000) {
                Distance.create(m.toDouble(), Distance.UNIT_METERS)
            } else {
                Distance.create(chilometri(metri), Distance.UNIT_KILOMETERS)
            }
        }

        /** La distanza a parole, per la notifica e il pannello: «300 m», «1,2 km», «16 km». */
        fun distanzaTesto(metri: Double): String {
            val m = metriArrotondati(metri)
            if (m < 1000) return "$m m"
            val decimi = Math.round(metri / 100.0)
            if (decimi >= 100) return "${Math.round(metri / 1000.0)} km"
            return if (decimi % 10 == 0L) "${decimi / 10} km" else "${decimi / 10},${decimi % 10} km"
        }
    }
}
