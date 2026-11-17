package it.gdanav.gdanav_app.auto

/**
 * Dove sta il lettore musicale sulla mappa dell'auto, e su quale tasto è
 * caduto un tocco. Solo conti: niente di Android qui dentro, così si provano
 * da soli (`android/src/test/kotlin/.../auto/DisposizioneMusicaProva.kt`).
 *
 * Le misure sono in punti dell'auto (dp), moltiplicate per [Spazio.k]; quello
 * che esce è in pixel della superficie, gli stessi con cui [PannelloAuto]
 * disegna e con cui Android Auto dice dov'è caduto il dito
 * (`SurfaceCallback.onClick`). Disegno e tocco leggono la stessa [Disposta]:
 * un tasto non può essere disegnato in un posto e toccato in un altro.
 *
 * Quattro forme, dalla più grande alla più piccola; si prende la prima che
 * ci sta senza coprire niente:
 *
 * - [Forma.APERTO]: copertina, app, titolo, artista, la barra del brano e
 *   ⏮ ⏯ ⏭. Solo sugli schermi larghi;
 * - [Forma.COMPATTO]: il titolo su una riga, e sotto copertina, ⏯ e ⏭. Per la
 *   mappa a mezzo schermo;
 * - [Forma.PILLOLA]: copertina e ⏯. Quando lo si richiude, quando lo spazio è
 *   poco, e quando non c'è un brano (allora solo ▶);
 * - [Forma.SOLO_BRANO]: copertina, titolo e artista, senza tasti: sulle auto
 *   che non mandano i tocchi.
 *
 * Le zone di tocco sono larghe e alte almeno [TOCCO_DP] punti (le linee guida
 * di Google per l'auto chiedono 76), anche dove il disegno è più piccolo.
 */
object DisposizioneMusica {
    enum class Forma { APERTO, COMPATTO, PILLOLA, SOLO_BRANO }

    /** Dove è caduto un tocco. [PANNELLO]: sul lettore, ma su nessun tasto. */
    enum class Zona { FUORI, PANNELLO, PRECEDENTE, PLAY_PAUSA, SUCCESSIVO, LINGUETTA }

    /** Un rettangolo, in pixel della superficie. */
    data class Riq(val l: Float, val t: Float, val r: Float, val b: Float) {
        val w: Float get() = r - l
        val h: Float get() = b - t
        val cx: Float get() = (l + r) / 2f
        val cy: Float get() = (t + b) / 2f

        fun contiene(x: Float, y: Float) = x >= l && x < r && y >= t && y < b

        /** Se si toccano, o stanno a meno di [aria] l'uno dall'altro. */
        fun tocca(o: Riq, aria: Float = 0f) = l < o.r + aria && o.l < r + aria && t < o.b + aria && o.t < b + aria
    }

    /**
     * Lo spazio che c'è. [sinistra]…[basso]: dove il lettore può stare (l'area
     * che le schede di Android Auto lasciano libera, tolti i margini), con
     * [alto] sotto i tasti in alto. [centroX] e [larghezza]: il mezzo e la
     * larghezza dell'area che non cambia mai (lì in mezzo sta l'auto).
     * [aDestra]: quello che sta sul bordo destro (la striscia del traffico e
     * le sue etichette): il lettore gli sta a sinistra. [sopra]: quello sotto
     * cui il lettore scende se lo tocca (l'avviso dell'autovelox, in alto al
     * centro). [ostacoli]: quello che non si copre mai (tachimetro, barra dei
     * dati, la colonna dell'avviso di casa): se lo tocca, la forma non va.
     */
    data class Spazio(
        val sinistra: Float,
        val alto: Float,
        val destra: Float,
        val basso: Float,
        val centroX: Float,
        val larghezza: Float,
        val k: Float,
        val aDestra: List<Riq> = emptyList(),
        val sopra: List<Riq> = emptyList(),
        val ostacoli: List<Riq> = emptyList(),
    )

    /**
     * Il lettore disposto. I rettangoli dei tasti ([precedente], [playPausa],
     * [successivo], [linguetta]) sono le **zone di tocco**; il disegno sta al
     * loro centro ([centroTasto]). [copertina] è il disegno della copertina.
     * Le linee sono le linee di base dei testi; `null` quello che la forma non
     * ha.
     */
    data class Disposta(
        val forma: Forma,
        val box: Riq,
        val copertina: Riq,
        val testoX: Float,
        val testoLargo: Float,
        /** Il nome dell'app sta più stretto del titolo: accanto ha la linguetta. */
        val appLargo: Float,
        val lineaApp: Float?,
        val lineaTitolo: Float?,
        val lineaArtista: Float?,
        val avanzamento: Riq?,
        val precedente: Riq?,
        val playPausa: Riq?,
        val successivo: Riq?,
        val linguetta: Riq?,
        /** Dove si disegna la freccia della linguetta. */
        val freccia: Riq?,
        val k: Float,
    ) {
        /** Le zone di tocco, nell'ordine in cui si guardano. */
        val zone: List<Pair<Zona, Riq>>
            get() = listOfNotNull(
                precedente?.let { Zona.PRECEDENTE to it },
                playPausa?.let { Zona.PLAY_PAUSA to it },
                successivo?.let { Zona.SUCCESSIVO to it },
                linguetta?.let { Zona.LINGUETTA to it },
            )

        /** Il lettore si comanda col dito (ha almeno un tasto). */
        val coiTasti: Boolean get() = playPausa != null
    }

    /** Il lato minimo di una zona di tocco, in punti. */
    const val TOCCO_DP = 76f

    /** Aperto: largo da 320 a 380 punti, e mai più di questa parte dello schermo. */
    const val APERTO_MIN_DP = 320f
    const val APERTO_MAX_DP = 380f
    const val APERTO_ALTO_DP = 192f
    private const val APERTO_PARTE = 0.38f

    const val COMPATTO_MIN_DP = 252f
    const val COMPATTO_MAX_DP = 280f
    const val COMPATTO_ALTO_DP = 126f

    const val PILLOLA_LARGA_DP = 156f
    const val PILLOLA_ALTA_DP = 68f

    const val SOLO_BRANO_MIN_DP = 200f
    const val SOLO_BRANO_MAX_DP = 330f
    const val SOLO_BRANO_ALTO_DP = 72f

    /** Quanta aria resta fra il lettore e quello che non deve coprire. */
    const val ARIA_DP = 8f

    /** Quanto il lettore sta a destra del mezzo, dove c'è la strada davanti all'auto. */
    const val ARIA_CENTRO_DP = 20f

    /**
     * Il lettore nello spazio [s]. [conBrano]: un'app ha un lettore aperto
     * (se no, solo ▶ nella pillola). [ridotto]: chi guida l'ha richiuso.
     * [comandabile]: l'auto manda i tocchi. `null`: non ci sta, non si
     * disegna.
     */
    fun disponi(s: Spazio, conBrano: Boolean, ridotto: Boolean, comandabile: Boolean): Disposta? {
        val forme = when {
            !comandabile -> if (conBrano) listOf(Forma.SOLO_BRANO) else emptyList()
            !conBrano || ridotto -> listOf(Forma.PILLOLA)
            else -> listOf(Forma.APERTO, Forma.COMPATTO, Forma.PILLOLA)
        }
        for (f in forme) prova(f, s, conBrano)?.let { return it }
        return null
    }

    /** Su cosa è caduto il tocco in ([x], [y]), pixel della superficie. */
    fun tocco(d: Disposta?, x: Float, y: Float): Zona {
        d ?: return Zona.FUORI
        for ((zona, dove) in d.zone) if (dove.contiene(x, y)) return zona
        return if (d.box.contiene(x, y)) Zona.PANNELLO else Zona.FUORI
    }

    private fun prova(f: Forma, s: Spazio, conBrano: Boolean): Disposta? {
        val k = s.k
        val aria = ARIA_DP * k
        val alta = when (f) {
            Forma.APERTO -> APERTO_ALTO_DP
            Forma.COMPATTO -> COMPATTO_ALTO_DP
            Forma.PILLOLA -> PILLOLA_ALTA_DP
            Forma.SOLO_BRANO -> SOLO_BRANO_ALTO_DP
        } * k

        fun scatola(alto: Float): Riq? {
            // A sinistra di quello che sta sul bordo destro, alla sua altezza.
            var destra = s.destra
            for (o in s.aDestra) if (o.t < alto + alta + aria && alto < o.b + aria) destra = minOf(destra, o.l - aria)
            // La pillola è piccola e sta in alto: può stare sopra la strada
            // lontana. Le altre no: a destra del mezzo.
            val sinistra = if (f == Forma.PILLOLA) s.sinistra else maxOf(s.sinistra, s.centroX + ARIA_CENTRO_DP * k)
            val posto = destra - sinistra
            val larga = when (f) {
                Forma.APERTO -> {
                    if (s.larghezza * APERTO_PARTE < APERTO_MIN_DP * k) return null
                    minOf((s.larghezza * APERTO_PARTE).coerceAtMost(APERTO_MAX_DP * k), posto)
                        .takeIf { it >= APERTO_MIN_DP * k }
                }
                Forma.COMPATTO -> minOf(COMPATTO_MAX_DP * k, posto).takeIf { it >= COMPATTO_MIN_DP * k }
                Forma.PILLOLA -> (PILLOLA_LARGA_DP * k).takeIf { it <= posto }
                Forma.SOLO_BRANO -> minOf(SOLO_BRANO_MAX_DP * k, posto).takeIf { it >= SOLO_BRANO_MIN_DP * k }
            } ?: return null
            return Riq(destra - larga, alto, destra, alto + alta)
        }

        var box = scatola(s.alto) ?: return null
        // Sotto l'avviso in alto, se lo tocca.
        val sotto = s.sopra.filter { it.tocca(box, aria) }.maxOfOrNull { it.b }
        if (sotto != null) box = scatola(sotto + aria) ?: return null
        if (box.b > s.basso) return null
        if (s.sopra.any { it.tocca(box, aria / 2) }) return null
        if (s.ostacoli.any { it.tocca(box, aria) }) return null
        return when (f) {
            Forma.APERTO -> aperto(box, k)
            Forma.COMPATTO -> compatto(box, k)
            Forma.PILLOLA -> pillola(box, k, conBrano)
            Forma.SOLO_BRANO -> soloBrano(box, k)
        }
    }

    private fun aperto(box: Riq, k: Float): Disposta {
        val l = box.l
        val t = box.t
        val r = box.r
        val terzo = box.w / 3f
        val tasti = t + 108f * k
        return Disposta(
            forma = Forma.APERTO,
            box = box,
            copertina = Riq(l + 12f * k, t + 12f * k, l + 88f * k, t + 88f * k),
            testoX = l + 100f * k,
            testoLargo = r - 12f * k - (l + 100f * k),
            appLargo = r - 56f * k - (l + 100f * k),
            lineaApp = t + 29f * k,
            lineaTitolo = t + 58f * k,
            lineaArtista = t + 82f * k,
            avanzamento = Riq(l + 12f * k, t + 99f * k, r - 12f * k, t + 103f * k),
            precedente = Riq(l, tasti, l + terzo, box.b),
            playPausa = Riq(l + terzo, tasti, l + terzo * 2f, box.b),
            successivo = Riq(l + terzo * 2f, tasti, r, box.b),
            linguetta = Riq(r - TOCCO_DP * k, t, r, t + TOCCO_DP * k),
            freccia = Riq(r - 40f * k, t + 12f * k, r - 12f * k, t + 40f * k),
            k = k,
        )
    }

    private fun compatto(box: Riq, k: Float): Disposta {
        val l = box.l
        val t = box.t
        val r = box.r
        val riga = t + 40f * k
        val maniglia = 84f * k
        val meta = (box.w - maniglia) / 2f
        return Disposta(
            forma = Forma.COMPATTO,
            box = box,
            copertina = Riq(l + 10f * k, t + 48f * k, l + 78f * k, t + 116f * k),
            testoX = l + 14f * k,
            testoLargo = box.w - 28f * k,
            appLargo = box.w - 28f * k,
            lineaApp = null,
            lineaTitolo = t + 29f * k,
            lineaArtista = null,
            avanzamento = null,
            precedente = null,
            playPausa = Riq(l + maniglia, riga, l + maniglia + meta, box.b),
            successivo = Riq(l + maniglia + meta, riga, r, box.b),
            // La copertina fa da maniglia: toccata, il lettore si richiude.
            linguetta = Riq(l, riga, l + maniglia, box.b),
            freccia = Riq(l + 56f * k, t + 94f * k, l + 82f * k, t + 120f * k),
            k = k,
        )
    }

    private fun pillola(box: Riq, k: Float, conBrano: Boolean): Disposta {
        val l = box.l
        val t = box.t
        // Le zone escono di quattro punti sopra e sotto la pillola: alte 76.
        val su = t - (TOCCO_DP - PILLOLA_ALTA_DP) / 2f * k
        val giu = box.b + (TOCCO_DP - PILLOLA_ALTA_DP) / 2f * k
        val meta = l + TOCCO_DP * k
        return Disposta(
            forma = Forma.PILLOLA,
            box = box,
            copertina = Riq(l + 6f * k, t + 6f * k, l + 62f * k, t + 62f * k),
            testoX = 0f,
            testoLargo = 0f,
            appLargo = 0f,
            lineaApp = null,
            lineaTitolo = null,
            lineaArtista = null,
            avanzamento = null,
            precedente = null,
            playPausa = Riq(meta, su, box.r, giu),
            successivo = null,
            // Senza un brano non c'è niente da riaprire.
            linguetta = if (conBrano) Riq(l, su, meta, giu) else null,
            freccia = if (conBrano) Riq(l + 44f * k, t + 44f * k, l + 66f * k, t + 66f * k) else null,
            k = k,
        )
    }

    private fun soloBrano(box: Riq, k: Float): Disposta {
        val l = box.l
        val t = box.t
        return Disposta(
            forma = Forma.SOLO_BRANO,
            box = box,
            copertina = Riq(l + 8f * k, t + 8f * k, l + 64f * k, t + 64f * k),
            testoX = l + 76f * k,
            testoLargo = box.w - 88f * k,
            appLargo = box.w - 88f * k,
            lineaApp = null,
            lineaTitolo = t + 31f * k,
            lineaArtista = t + 55f * k,
            avanzamento = null,
            precedente = null,
            playPausa = null,
            successivo = null,
            linguetta = null,
            freccia = null,
            k = k,
        )
    }
}
