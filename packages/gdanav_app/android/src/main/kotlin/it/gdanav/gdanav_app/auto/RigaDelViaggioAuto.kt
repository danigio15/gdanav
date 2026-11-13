package it.gdanav.gdanav_app.auto

import kotlin.math.roundToInt

/**
 * La riga dell'auto nella scheda dell'arrivo di Android Auto, sotto tempo,
 * ora e km (`TravelEstimate.setTripText`), nelle sue varianti: dalla più
 * lunga alla più corta, con gli stessi dati in tutte.
 *
 * Dal campo, con la foto, due volte: «schermo diviso a metà con la parte
 * grande il quadrato dei dati di viaggio continua ad essere tagliato» —
 * «41% · 169 km · arrivo 38% · 21° · 1,0…». La riga sta su una riga sola, e
 * quello che non ci sta Android Auto lo taglia coi puntini. La larghezza
 * della scheda la sa solo Android Auto: noi diamo tutte le varianti
 * ([varianti]), e lui mostra la prima che ci sta; e la prima la sceglie
 * [strettezza] dallo spazio che ha la mappa, per le auto che delle varianti
 * prendono solo la prima.
 *
 * Qui niente Android: solo testo e colori, per provarlo senza l'auto.
 * `GuidaAuto.testoDelViaggio` ne fa il `CarText` coi colori dell'auto.
 */
object RigaDelViaggioAuto {
    enum class Colore { ROSSO, VERDE, AMBRA }

    /** Un pezzo di testo, col suo colore se ne ha uno. */
    data class Tratto(val testo: String, val colore: Colore? = null)

    /** La mappa ha tutto lo schermo, o quasi: la riga lunga, con le parole. */
    const val LARGA = 0

    /** A mezzo schermo: «🔋 41% → 38%», il pedaggio senza la parola. */
    const val STRETTA = 1

    /** A un terzo: senza i simboli, e poi senza gli spazi. */
    const val STRETTISSIMA = 2

    /** Quante varianti ci sono, dalla [LARGA] alla più corta di tutte. */
    private const val VARIANTI = 4

    /** Sotto questa larghezza (in punti) la mappa è a mezzo schermo. */
    const val LARGHEZZA_STRETTA_DP = 1000f

    /** Sotto questa, a un terzo dello schermo. */
    const val LARGHEZZA_STRETTISSIMA_DP = 600f

    /**
     * Larga meno di due volte l'altezza: non è lo schermo intero di un'auto
     * larga (1920×720 è 2,7; 1280×720 è 1,8, e lì la scheda è stretta lo
     * stesso: la riga corta dice le stesse cose).
     */
    const val PROPORZIONE_STRETTA = 2.0f

    /**
     * Quanto è stretta la mappa, da [LARGA] a [STRETTISSIMA].
     *
     * [larghezzaPx] e [altezzaPx] sono la superficie che Android Auto dà alla
     * mappa; [stabilePx] la larghezza della sua area stabile, se l'ha già
     * detta. Si guardava solo la superficie: ma a schermo diviso la
     * superficie può restare quella di tutto lo schermo, con l'altra app
     * sopra («con lo schermo diviso la navigazione si nasconde sotto l'altro
     * pezzo di schermo», vedi `RendererMappa.areaPerIlCentro`), e allora la
     * mappa sembrava larga e la riga restava quella lunga, tagliata. L'area
     * stabile toglie proprio l'altra app (le schede no): è lei che dice
     * quanto è larga la mappa.
     */
    fun strettezza(larghezzaPx: Int, altezzaPx: Int, densita: Float, stabilePx: Int? = null): Int {
        val px = stabilePx?.takeIf { it in 1..larghezzaPx } ?: larghezzaPx
        if (px <= 0 || densita <= 0f) return LARGA
        val dp = px / densita
        return when {
            dp < LARGHEZZA_STRETTISSIMA_DP -> STRETTISSIMA
            dp < LARGHEZZA_STRETTA_DP -> STRETTA
            altezzaPx > 0 && px.toFloat() / altezzaPx < PROPORZIONE_STRETTA -> STRETTA
            else -> LARGA
        }
    }

    /**
     * Le varianti della riga, dalla più lunga che serve a [strettezza] alla
     * più corta; vuota se non c'è niente da dire.
     *
     * - larga: «🔋 41% · 169 km · arrivo 38% · ☀ 21° · ~1,05 € pedaggio»
     * - stretta: «🔋 41% → 38% · 169 km · ☀ 21° · ~1,05 €»
     * - più stretta: «41%→38% · 169 km · 21° · ~1,05 €»
     * - la più corta: «41%→38% 169km 21° ~1,05€»
     *
     * [pedaggioLungo] è quello della scheda («~1,05 € pedaggio»),
     * [pedaggioBreve] quello della barra («~1,05 €»).
     */
    fun varianti(
        batteria: Double?,
        stimata: Boolean,
        autonomiaKm: Double?,
        arrivo: Double?,
        meteoEmoji: String?,
        temperatura: Double?,
        pedaggioLungo: String?,
        pedaggioBreve: String?,
        strettezza: Int = LARGA,
    ): List<List<Tratto>> {
        val tutte = (0 until VARIANTI).map {
            variante(it, batteria, stimata, autonomiaKm, arrivo, meteoEmoji, temperatura, pedaggioLungo, pedaggioBreve)
        }
        if (tutte.all { it.isEmpty() }) return emptyList()
        val dalla = strettezza.coerceIn(LARGA, VARIANTI - 1)
        // Due varianti uguali (niente batteria, niente pedaggio…) una volta sola.
        return tutte.drop(dalla).filter { it.isNotEmpty() }.distinctBy { testo(it) }
    }

    /** Il testo di una variante, senza colori. */
    fun testo(tratti: List<Tratto>): String = tratti.joinToString("") { it.testo }

    private fun variante(
        n: Int,
        batteria: Double?,
        stimata: Boolean,
        autonomiaKm: Double?,
        arrivo: Double?,
        meteoEmoji: String?,
        temperatura: Double?,
        pedaggioLungo: String?,
        pedaggioBreve: String?,
    ): List<Tratto> {
        val conParole = n == 0
        val conSimboli = n <= 1
        val compatta = n >= 3
        // Lo spazio che non va a capo dentro un pezzo, se l'auto va a capo:
        // si va a capo solo fra un pezzo e l'altro.
        val spazio = if (compatta) "" else NBSP
        val fra = if (compatta) " " else " · "
        val freccia = if (conSimboli) "$NBSP→$NBSP" else "→"
        val tratti = mutableListOf<Tratto>()
        fun pezzo(vararg t: Tratto) {
            if (tratti.isNotEmpty()) tratti += Tratto(fra)
            tratti += t
        }
        val circa = if (stimata) "~" else ""
        batteria?.let { b ->
            val pila = if (conSimboli) "🔋$NBSP" else ""
            val ora = Tratto("$pila$circa${b.roundToInt()}%", if (b < 20) Colore.ROSSO else null)
            val dopo = arrivo?.let { Tratto("${it.roundToInt()}%", if (it < 10) Colore.ROSSO else Colore.VERDE) }
            if (dopo != null && !conParole) pezzo(ora, Tratto(freccia), dopo) else pezzo(ora)
            autonomiaKm?.let { pezzo(Tratto("$circa${it.roundToInt()}${spazio}km")) }
            if (dopo != null && conParole) pezzo(Tratto("arrivo$NBSP"), dopo)
        }
        temperatura?.let { m ->
            val sole = meteoEmoji?.takeIf { conSimboli && it.isNotEmpty() }?.let { "$it$NBSP" } ?: ""
            pezzo(Tratto("$sole${m.roundToInt()}°"))
        }
        val costo = if (conParole) pedaggioLungo else pedaggioBreve ?: pedaggioLungo?.removeSuffix(" pedaggio")
        if (!costo.isNullOrEmpty()) {
            pezzo(Tratto(if (compatta) costo.replace(" ", "").replace(NBSP, "") else costo, Colore.AMBRA))
        }
        return tratti
    }

    /**
     * Lo spazio che non va a capo: «Guarda il meteo», il sole restava in
     * fondo a una riga e i gradi andavano sotto. Dentro un pezzo (il sole e
     * i gradi, «arrivo» e la percentuale, i km) non si va a capo; si va a
     * capo solo fra un pezzo e l'altro, dove c'è il «·».
     */
    const val NBSP = " "
}
