package it.gdanav.gdanav_app.auto

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.model.Action
import androidx.car.app.model.Alert
import androidx.car.app.model.AlertCallback
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText

/**
 * Chi decide quale avviso sta sullo schermo dell'auto.
 *
 * Android Auto ne mostra **uno solo alla volta**, e solo sopra la mappa: un
 * `showAlert` nuovo toglie quello in vista, e con un altro schermo in cima
 * (il Menu, la ricerca, la casa) l'avviso viene annullato. Prima ognuno
 * chiamava `showAlert` per conto suo — l'avviso di casa, la strada proposta,
 * «Quasi a casa» di GdAHome — e si cancellavano a vicenda senza saperlo.
 *
 * Qui passano tutti, con una precedenza ([URGENTE] > [STRADA] >
 * [QUASI_A_CASA] > [INFORMATIVO]):
 *
 * - vince la precedenza più alta; a parità resta quello in vista;
 * - quello scalzato resta in fila e **torna** quando l'altro finisce, col
 *   tempo che gli resta (se nel frattempo è scaduto, no);
 * - con la mappa non in cima niente `showAlert`: subito un messaggio breve
 *   col titolo, e l'avviso quando la mappa torna ([mappaTornata]);
 * - se l'auto lo rifiuta (`REASON_NOT_SUPPORTED`) si riprova poco dopo, al
 *   più tre volte, poi si aspetta il ritorno della mappa;
 * - come è finito lo sa chi l'ha chiesto ([Avviso.alFine]).
 *
 * Regge anche un `showAlert` fatto senza passare di qui (GdAHome costruita
 * contro un GdANav di prima): l'avviso in vista sparisce senza un perché, e
 * allora chi conta più di «Quasi a casa» torna subito, gli altri dopo che
 * quello ha avuto il suo tempo. Al più due volte: niente giri senza fine.
 *
 * Si usa solo dal filo principale. Lo schermo della mappa
 * ([SchermoNavigazione]) lo collega quando nasce e lo scollega quando muore:
 * senza, [mostra] risponde `false` e chi chiama fa come sa.
 */
object ArbitroAvvisi {
    /** Le precedenze: vince la più alta. */
    const val INFORMATIVO = 0
    const val QUASI_A_CASA = 1
    const val STRADA = 2
    const val URGENTE = 3

    /** Come è finito un avviso: un suo tasto, chiuso a mano, o il tempo. */
    enum class Fine { TASTO, CHIUSO, SCADUTO }

    /** Un tasto dell'avviso (al più due). Toccato, l'avviso si chiude. */
    class Tasto(val etichetta: String, val principale: Boolean = false, val premi: () -> Unit)

    /**
     * Un avviso da mostrare. [chiave] dice di chi è: uno nuovo con la stessa
     * chiave prende il posto del vecchio. [durataMs] conta da adesso, anche
     * mentre aspetta il suo turno. [alFine] arriva una volta, se l'avviso
     * finisce da sé; tolto con [togli] (o sostituito) no.
     */
    class Avviso(
        val chiave: String,
        val precedenza: Int,
        val titolo: String,
        val testo: String? = null,
        val icona: CarIcon? = null,
        val durataMs: Long,
        val tasti: List<Tasto> = emptyList(),
        val alFine: (Fine) -> Unit = {},
    )

    private class Voce(val avviso: Avviso, val scadeMs: Long, val ordine: Long) {
        /** Il numero dell'`Alert` mentre è sullo schermo. */
        var numero: Int? = null

        /** Il titolo è già stato detto con un messaggio breve. */
        var detto = false
        var rifiuti = 0
        var estranei = 0

        /** Non si riprova prima di allora ([SOSPESA]: fino al ritorno della mappa). */
        var nonPrimaDi = 0L
    }

    private val principale = Handler(Looper.getMainLooper())
    private val voci = LinkedHashMap<String, Voce>()
    private var inVista: Voce? = null
    private var contesto: CarContext? = null
    private var inCima: () -> Boolean = { false }
    private var ordine = 0L
    private var prossimoNumero = PRIMO_NUMERO

    /** Dopo un avviso arrivato da fuori: fin qui passa solo chi conta più di «Quasi a casa». */
    private var fermoFinoA = 0L

    /** Quando è già in programma il prossimo [rivedi]. */
    private var sveglia = Long.MAX_VALUE
    private val rivediPoi = Runnable {
        sveglia = Long.MAX_VALUE
        rivedi()
    }

    /** I controlli «l'auto non ha più detto niente», da togliere a fine sessione. */
    private val gettone = Any()

    /** Chiamato quando cambia quello che c'è sullo schermo (per [scalzata]). */
    var alCambio: (() -> Unit)? = null

    /**
     * Un avviso di Android Auto è sullo schermo adesso, sopra la mappa: chi
     * disegna sulla mappa (il lettore musicale) non gli finisce sotto.
     */
    val unAvvisoInVista: Boolean get() = inVista != null

    /**
     * Lo schermo della mappa c'è. [mappaInCima]: è lui in cima e si vede
     * (almeno `STARTED`), cioè un avviso adesso si può mostrare.
     */
    fun collega(carContext: CarContext, mappaInCima: () -> Boolean) {
        azzera()
        contesto = carContext
        inCima = mappaInCima
    }

    /** Lo schermo della mappa non c'è più: via tutto, in silenzio. */
    fun scollega(carContext: CarContext) {
        if (contesto !== carContext) return
        azzera()
        contesto = null
        inCima = { false }
        alCambio = null
    }

    private fun azzera() {
        principale.removeCallbacks(rivediPoi)
        principale.removeCallbacksAndMessages(gettone)
        sveglia = Long.MAX_VALUE
        voci.clear()
        inVista = null
        fermoFinoA = 0L
    }

    /**
     * Mette in fila [avviso] e lo mostra appena tocca a lui. `false` se qui
     * non si può (nessuna mappa sull'auto, o un'auto senza avvisi, prima
     * dell'API 5): allora chi chiama fa da sé.
     */
    fun mostra(avviso: Avviso): Boolean {
        val c = contesto ?: return false
        if (c.carAppApiLevel < 5) return false
        voci.remove(avviso.chiave)?.let { ritira(it) }
        val scade = SystemClock.elapsedRealtime() + avviso.durataMs.coerceAtLeast(MINIMO_MS)
        voci[avviso.chiave] = Voce(avviso, scade, ordine++)
        rivedi()
        return true
    }

    /** Toglie l'avviso di [chiave], in vista o in fila: tocca al prossimo. */
    fun togli(chiave: String) {
        val v = voci.remove(chiave) ?: return
        ritira(v)
        rivedi()
    }

    /**
     * Se l'avviso di [chiave] aspetta perché sullo schermo ce n'è uno che
     * conta di più: chi l'ha chiesto può dirlo in un altro modo (la strada
     * proposta coi tasti in alto).
     */
    fun scalzata(chiave: String): Boolean {
        val v = voci[chiave] ?: return false
        val davanti = inVista ?: return false
        return davanti !== v && davanti.avviso.precedenza > v.avviso.precedenza
    }

    /**
     * La mappa è tornata in cima: si riprova, appena l'auto l'ha ridisegnata.
     * Quello che era in vista quando la mappa è stata coperta non si sa se
     * l'auto l'ha tenuto: lo si rimette, col tempo che gli resta.
     */
    fun mappaTornata() {
        if (contesto == null) return
        inVista?.let { v ->
            val numero = v.numero
            v.numero = null
            inVista = null
            if (numero != null) chiudi(numero)
            cambiato()
        }
        for (v in voci.values) {
            if (v.nonPrimaDi == SOSPESA) {
                v.nonPrimaDi = 0L
                v.rifiuti = 0
            }
        }
        programma(DOPO_IL_RITORNO_MS)
    }

    /** Toglie [v] dallo schermo, se c'è. Dalla fila la toglie chi chiama. */
    private fun ritira(v: Voce) {
        val numero = v.numero
        v.numero = null
        if (inVista === v) {
            inVista = null
            cambiato()
        }
        if (numero != null) chiudi(numero)
    }

    private fun chiudi(numero: Int) {
        try {
            contesto?.getCarService(AppManager::class.java)?.dismissAlert(numero)
        } catch (_: Exception) {
            // Un'auto che non risponde: l'avviso se ne va col suo tempo.
        }
    }

    /** Guarda chi tocca adesso, e se è il caso lo mostra. */
    private fun rivedi() {
        val c = contesto ?: return
        val ora = SystemClock.elapsedRealtime()
        // Scaduti mentre aspettavano: non si mostrano più.
        for (v in voci.values.filter { it !== inVista && it.scadeMs - ora < MINIMO_MS }) {
            voci.remove(v.avviso.chiave)
            finita(v, Fine.SCADUTO)
        }
        // La prossima occhiata: quando scade chi aspetta, quando si può
        // riprovare, quando finisce il tempo lasciato a un avviso di fuori.
        var prossima = Long.MAX_VALUE
        for (v in voci.values) {
            if (v === inVista) continue
            prossima = minOf(prossima, v.scadeMs - MINIMO_MS + 50L)
            if (v.nonPrimaDi > ora && v.nonPrimaDi != SOSPESA) prossima = minOf(prossima, v.nonPrimaDi)
            if (ora < fermoFinoA && v.avviso.precedenza <= QUASI_A_CASA) prossima = minOf(prossima, fermoFinoA)
        }
        if (prossima != Long.MAX_VALUE) programma(prossima - ora)

        val scelta = voci.values
            .filter { it.nonPrimaDi <= ora && (ora >= fermoFinoA || it.avviso.precedenza > QUASI_A_CASA) }
            .maxWithOrNull(compareBy<Voce>({ it.avviso.precedenza }, { -it.ordine }))
            ?: return
        val v = inVista
        if (scelta === v) return
        // A parità resta quello in vista: l'altro aspetta che finisca.
        if (v != null && scelta.avviso.precedenza <= v.avviso.precedenza) return
        if (!inCima()) {
            // Sopra la mappa c'è un altro schermo, dove gli avvisi non
            // esistono: intanto il titolo, l'avviso quando la mappa torna.
            if (!scelta.detto) {
                scelta.detto = true
                toast(c, scelta.avviso.titolo)
            }
            return
        }
        if (v != null) {
            // Scalzato da uno che conta di più: resta in fila, e torna dopo.
            val numero = v.numero
            v.numero = null
            inVista = null
            if (numero != null) chiudi(numero)
        }
        mostraOra(c, scelta, ora)
    }

    private fun mostraOra(c: CarContext, v: Voce, ora: Long) {
        val a = v.avviso
        val numero = prossimoNumero
        prossimoNumero = if (numero >= ULTIMO_NUMERO) PRIMO_NUMERO else numero + 1
        val resta = (v.scadeMs - ora).coerceAtLeast(MINIMO_MS)
        try {
            val avviso = Alert.Builder(numero, CarText.create(a.titolo), resta)
            a.testo?.takeIf { it.isNotEmpty() }?.let { avviso.setSubtitle(CarText.create(it)) }
            a.icona?.let { avviso.setIcon(it) }
            var primario = false
            for (t in a.tasti.take(2)) {
                val tasto = Action.Builder().setTitle(t.etichetta).setOnClickListener { toccato(v, numero, t) }
                if (t.principale && !primario) {
                    primario = true
                    tasto.setFlags(Action.FLAG_PRIMARY)
                }
                avviso.addAction(tasto.build())
            }
            avviso.setCallback(object : AlertCallback {
                override fun onCancel(reason: Int) {
                    annullato(v, numero, reason)
                }

                override fun onDismiss() {
                    tolto(v, numero)
                }
            })
            c.getCarService(AppManager::class.java).showAlert(avviso.build())
        } catch (e: Exception) {
            // Un'auto che non mostra gli avvisi: almeno il titolo, e avanti.
            if (voci[a.chiave] === v) voci.remove(a.chiave)
            if (!v.detto) {
                v.detto = true
                toast(c, a.titolo)
            }
            finita(v, Fine.SCADUTO)
            cambiato()
            return
        }
        v.numero = numero
        inVista = v
        cambiato()
        // Se l'auto non dice più niente (un avviso tolto senza avvisare),
        // allo scadere lo si dà per finito: la fila non resta ferma.
        principale.postAtTime(
            { if (sulloSchermo(v, numero)) fine(v, Fine.SCADUTO, togli = true) },
            gettone,
            SystemClock.uptimeMillis() + resta + MARGINE_MS,
        )
    }

    /**
     * Se sullo schermo c'è [v] mostrato col numero [numero]. Quello che
     * l'auto dice di un avviso arriva un attimo dopo: nel frattempo lo
     * stesso avviso può essere stato tolto e rimesso (con un numero nuovo),
     * e allora quella voce parla di una volta che non conta più.
     */
    private fun sulloSchermo(v: Voce, numero: Int) = inVista === v && v.numero == numero

    /** Un tasto dell'avviso: l'auto lo chiude da sé. */
    private fun toccato(v: Voce, numero: Int, t: Tasto) {
        if (sulloSchermo(v, numero)) {
            if (voci[v.avviso.chiave] === v) voci.remove(v.avviso.chiave)
            v.numero = null
            inVista = null
            cambiato()
            finita(v, Fine.TASTO)
        }
        t.premi()
        rivedi()
    }

    private fun annullato(v: Voce, numero: Int, motivo: Int) {
        if (!sulloSchermo(v, numero)) return
        when (motivo) {
            AlertCallback.REASON_NOT_SUPPORTED -> {
                // L'auto non l'ha mostrato (sotto non c'è la mappa, o non
                // ancora): non è «mostrato». Subito il titolo, e si riprova.
                inVista = null
                v.numero = null
                v.rifiuti++
                v.nonPrimaDi = if (v.rifiuti >= RIFIUTI_AL_PIU) SOSPESA else SystemClock.elapsedRealtime() + RIPROVA_MS
                if (!v.detto) {
                    v.detto = true
                    contesto?.let { toast(it, v.avviso.titolo) }
                }
                cambiato()
                rivedi()
            }
            AlertCallback.REASON_USER_ACTION -> fine(v, Fine.CHIUSO, togli = false)
            else -> fine(v, Fine.SCADUTO, togli = false)
        }
    }

    /**
     * L'auto l'ha tolto senza dire perché (dopo un annullamento, un tasto o
     * un nostro `dismissAlert` qui non si arriva: non è più lui in vista).
     * Con un altro schermo in cima torna con la mappa. Con la mappa in cima
     * l'ha scalzato un avviso mostrato senza passare di qui.
     */
    private fun tolto(v: Voce, numero: Int) {
        if (!sulloSchermo(v, numero)) return
        inVista = null
        v.numero = null
        if (!inCima()) {
            v.nonPrimaDi = SOSPESA
        } else {
            v.estranei++
            if (v.estranei > ESTRANEI_AL_PIU) {
                if (voci[v.avviso.chiave] === v) voci.remove(v.avviso.chiave)
                finita(v, Fine.SCADUTO)
            } else {
                fermoFinoA = SystemClock.elapsedRealtime() + DOPO_ESTRANEO_MS
            }
        }
        cambiato()
        rivedi()
    }

    private fun fine(v: Voce, come: Fine, togli: Boolean) {
        if (voci[v.avviso.chiave] === v) voci.remove(v.avviso.chiave)
        val numero = v.numero
        v.numero = null
        if (inVista === v) {
            inVista = null
            cambiato()
        }
        if (togli && numero != null) chiudi(numero)
        finita(v, come)
        rivedi()
    }

    /** Lo si dice a chi l'aveva chiesto, fuori da questo giro. */
    private fun finita(v: Voce, come: Fine) {
        principale.post { v.avviso.alFine(come) }
    }

    private fun cambiato() {
        alCambio?.invoke()
    }

    private fun programma(traMs: Long) {
        val quando = SystemClock.uptimeMillis() + traMs.coerceAtLeast(0L)
        if (quando >= sveglia) return
        sveglia = quando
        principale.removeCallbacks(rivediPoi)
        principale.postAtTime(rivediPoi, quando)
    }

    private fun toast(c: CarContext, testo: String) {
        try {
            CarToast.makeText(c, testo, CarToast.LENGTH_LONG).show()
        } catch (_: Exception) {
            // Un'auto che non lo mostra: resta l'avviso, quando si può.
        }
    }

    /** Meno di così non vale la pena mostrarlo. */
    private const val MINIMO_MS = 1_500L

    /** Quanto si aspetta l'auto oltre la durata, prima di darlo per finito. */
    private const val MARGINE_MS = 2_500L

    /** Dopo un rifiuto dell'auto. */
    private const val RIPROVA_MS = 1_500L
    private const val RIFIUTI_AL_PIU = 3

    /** Quante volte uno scalzato da fuori si rimette. */
    private const val ESTRANEI_AL_PIU = 2

    /** Il tempo lasciato a un avviso mostrato da fuori («Quasi a casa»: 15 s). */
    private const val DOPO_ESTRANEO_MS = 16_000L

    /** Tornati sulla mappa, il tempo che l'auto la ridisegni. */
    private const val DOPO_IL_RITORNO_MS = 700L

    /** In attesa del ritorno della mappa. */
    private const val SOSPESA = Long.MAX_VALUE

    /** I numeri degli `Alert`: un giro suo, lontano da quelli di chi ospita. */
    private const val PRIMO_NUMERO = 710_000
    private const val ULTIMO_NUMERO = 719_999
}
