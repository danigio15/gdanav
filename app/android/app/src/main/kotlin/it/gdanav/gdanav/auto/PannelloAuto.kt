package it.gdanav.gdanav.auto

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Sopra la mappa dell'auto, poco e in basso, perché la mappa si veda: in
 * basso a destra velocità e limite e, accanto, una barra sottile coi dati
 * dell'auto (batteria, km, alla meta), il meteo e la prossima sosta; in alto
 * solo l'avviso della segnalazione che si avvicina, finché serve. Tutto
 * dentro l'area lasciata libera da Android Auto. Disegna anche il cartello
 * dell'uscita sulla vista dello svincolo, per la scheda in alto a sinistra.
 */
class PannelloAuto(context: Context, private val densita: Float) : View(context) {
    /** L'area non coperta dalle schede di Android Auto. */
    var area: Rect? = null
        set(v) {
            field = v
            invalidate()
        }

    /** Più grande quando si disegna sull'immagine dello svincolo. */
    private var scala = 1f

    private fun dp(v: Float) = v * densita * scala

    private val testo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = dp(21f)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val testoPiccolo = Paint(testo).apply {
        textSize = dp(16f)
        typeface = Typeface.DEFAULT
        color = Color.argb(225, 255, 255, 255)
    }
    private val pieno = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bordo = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val numero = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    fun aggiorna() = postInvalidate()

    override fun onDraw(canvas: Canvas) {
        val a = area ?: Rect(0, 0, width, height)
        val margine = dp(10f)
        val c = PonteAuto.cruscotto
        val alto = a.top + margine
        val sinistra = a.left + margine
        val destra = a.right - margine

        // In alto niente, per vedere la strada davanti: solo l'avviso che si
        // avvicina (autovelox, polizia, incidente…), finché serve.
        avviso(canvas, sinistra, destra, alto)

        // In basso a destra, su una riga: velocità e limite, e accanto una
        // barra sottile coi dati dell'auto e il meteo.
        val tachimetro = velocita(canvas, a, c)
        barra(canvas, a, tachimetro, c)
    }

    /** L'ultima vista composta per la scheda: id, cartello, immagine. */
    private var composta: Triple<Int, String, Bitmap>? = null

    /**
     * La vista dello svincolo per la scheda di Android Auto (in alto a
     * sinistra), col cartello dell'uscita disegnato sopra dal lato giusto e
     * piantato coi suoi pali.
     */
    fun svincoloConCartello(vista: Bitmap, id: Int, g: PonteAuto.Guida): Bitmap {
        if (g.uscita.isEmpty() && g.verso.isEmpty()) return vista
        val chiave = "${g.uscita}|${g.verso}|${g.tipo}|${g.strada}"
        composta?.let { (i, k, b) -> if (i == id && k == chiave) return b }
        val b = vista.copy(Bitmap.Config.ARGB_8888, true)
        // Nella scheda l'immagine è larga circa 400 dp: il cartello in proporzione.
        scala = b.width / (400f * densita)
        try {
            val m = dp(10f)
            cartelloUscita(Canvas(b), m, b.width - m, m, b.width * 0.46f, g, pali = b.height * 0.5f)
        } finally {
            scala = 1f
        }
        composta = Triple(id, chiave, b)
        return b
    }

    /**
     * Il cartello dell'uscita come in autostrada: verde, bordo bianco, in alto
     * «USCITA» col numero, sotto le strade (A1, E45) e le direzioni. Blu se non
     * è un'uscita numerata (strada extraurbana). Sta dal lato dell'uscita
     * fra [sinistra] e [destra] (al centro se si va dritto); con [pali], i
     * due pali fin lì sotto. Restituisce dove sta.
     */
    private fun cartelloUscita(
        canvas: Canvas,
        sinistra: Float,
        destra: Float,
        y: Float,
        larghezzaMassima: Float,
        g: PonteAuto.Guida,
        pali: Float? = null,
    ): RectF {
        val autostrada = g.uscita.isNotEmpty() || g.tipo in 18..21 || Regex("^[AE] ?\\d").containsMatchIn(g.verso)
        val colore = if (autostrada) Color.rgb(0, 122, 61) else Color.rgb(21, 88, 176)
        val parti = g.verso.split(" · ", ";").flatMap { it.split(", ", "/") }.map { it.trim() }.filter { it.isNotEmpty() }
        val sigle = parti.filter { Regex("^[AESTR]{1,2} ?\\d+[a-z]?$").matches(it) }.take(3)
        val luoghi = parti.filter { it !in sigle }.take(3)
        val nome = Paint(testo).apply { textSize = dp(22f) }
        val etichetta = Paint(testo).apply { textSize = dp(13f) }
        val sigla = Paint(testo).apply { textSize = dp(16f) }
        val righeLuoghi = luoghi.ifEmpty { listOf(g.strada.ifEmpty { g.istruzione }) }.filter { it.isNotEmpty() }
        val interno = dp(14f)
        val hTesta = if (g.uscita.isNotEmpty()) dp(34f) else 0f
        val hSigle = if (sigle.isNotEmpty()) dp(32f) else 0f
        val hRiga = dp(28f)
        // Nomi lunghi: prima si rimpicciolisce un po' il testo, poi si taglia.
        val spazioNomi = larghezzaMassima - interno * 2 - dp(36f)
        val piuLungo = righeLuoghi.maxOfOrNull { nome.measureText(it) } ?: 0f
        if (piuLungo > spazioNomi && spazioNomi > 0) nome.textSize *= max(0.7f, spazioNomi / piuLungo)
        val larghezzaTesto = maxOf(
            righeLuoghi.maxOfOrNull { nome.measureText(it) } ?: 0f,
            sigle.sumOf { (sigla.measureText(it) + dp(22f)).toDouble() }.toFloat(),
            if (g.uscita.isNotEmpty()) etichetta.measureText("USCITA") + dp(60f) else 0f,
        )
        val w = (larghezzaTesto + interno * 2 + dp(36f)).coerceIn(dp(180f), larghezzaMassima.coerceAtLeast(dp(180f)))
        val h = interno + hTesta + hSigle + hRiga * righeLuoghi.size.coerceAtLeast(1) + interno - dp(6f)
        val x = when (lato(g.tipo)) {
            1 -> destra - w
            -1 -> sinistra
            else -> (sinistra + destra - w) / 2
        }
        val box = RectF(x, y, x + w, y + h)
        pali?.let { fondo ->
            // Due pali grigi sotto il cartello, fino alla strada.
            pieno.color = Color.rgb(120, 126, 134)
            for (f in listOf(0.22f, 0.78f)) {
                val px = box.left + box.width() * f
                canvas.drawRect(RectF(px - dp(3f), box.bottom - dp(4f), px + dp(3f), max(fondo, box.bottom)), pieno)
            }
        }
        pieno.color = colore
        canvas.drawRoundRect(box, dp(10f), dp(10f), pieno)
        bordo.color = Color.WHITE
        bordo.strokeWidth = dp(2.5f)
        val dentro = RectF(box.left + dp(4f), box.top + dp(4f), box.right - dp(4f), box.bottom - dp(4f))
        canvas.drawRoundRect(dentro, dp(7f), dp(7f), bordo)
        var riga = box.top + interno
        if (g.uscita.isNotEmpty()) {
            // «USCITA 12» in un riquadro bianco col numero verde.
            canvas.drawText("USCITA", box.left + interno, riga + dp(19f), etichetta)
            val n = accorcia(g.uscita, 6)
            val nw = sigla.measureText(n) + dp(16f)
            val xn = box.left + interno + etichetta.measureText("USCITA") + dp(8f)
            pieno.color = Color.WHITE
            canvas.drawRoundRect(RectF(xn, riga, xn + nw, riga + dp(26f)), dp(5f), dp(5f), pieno)
            val numeroVerde = Paint(sigla).apply { color = colore }
            canvas.drawText(n, xn + dp(8f), riga + dp(19f), numeroVerde)
            riga += hTesta
        }
        if (sigle.isNotEmpty()) {
            var xs = box.left + interno
            for (s in sigle) {
                // Autostrade: riquadro verde chiaro; strade europee: verde col bordo.
                val sw = sigla.measureText(s) + dp(14f)
                pieno.color = if (s.startsWith("E")) Color.rgb(0, 150, 70) else Color.WHITE
                canvas.drawRoundRect(RectF(xs, riga, xs + sw, riga + dp(24f)), dp(5f), dp(5f), pieno)
                val t = Paint(sigla).apply { color = if (s.startsWith("E")) Color.WHITE else colore }
                canvas.drawText(s, xs + dp(7f), riga + dp(18f), t)
                xs += sw + dp(8f)
            }
            riga += hSigle
        }
        // Le direzioni, con la freccia verso l'uscita.
        val freccia = when (lato(g.tipo)) {
            1 -> "↗"
            -1 -> "↖"
            else -> "↑"
        }
        for ((i, l) in righeLuoghi.withIndex()) {
            val spazio = box.right - interno - box.left - interno - dp(30f)
            var t = l
            while (nome.measureText(t) > spazio && t.length > 4) t = t.dropLast(2) + "…"
            canvas.drawText(t, box.left + interno, riga + dp(21f), nome)
            if (i == 0) {
                val f = Paint(nome).apply { textAlign = Paint.Align.RIGHT; textSize = dp(26f) }
                canvas.drawText(freccia, box.right - interno, riga + dp(22f), f)
            }
            riga += hRiga
        }
        return box
    }

    private val muto = Color.argb(185, 255, 255, 255)
    private val sfondoScheda = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(230, 24, 28, 36) }

    private fun font(sp: Float, grassetto: Boolean = true, colore: Int = Color.WHITE) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = dp(sp)
        typeface = if (grassetto) Typeface.create(Typeface.DEFAULT, Typeface.BOLD) else Typeface.DEFAULT
        color = colore
    }

    private fun taglia(p: Paint, t: String, spazio: Float): String {
        var s = t
        while (p.measureText(s) > spazio && s.length > 3) s = s.dropLast(2) + "…"
        return s
    }

    /**
     * La barra dei dati, sottile, in basso a destra accanto al tachimetro:
     * batteria (icona e %), km che restano, batteria alla meta, meteo; sopra,
     * piccola, la prossima sosta. Con la termica solo il meteo. Se accanto al
     * tachimetro non ci sta, va sopra.
     */
    private fun barra(canvas: Canvas, a: Rect, tachimetro: RectF?, c: PonteAuto.Cruscotto) {
        val b = c.batteria
        val meteo = c.meteoTemperatura
        if (b == null && meteo == null && c.sostaNome == null) return
        val margine = dp(10f)
        val forte = font(20f)
        val piccolo = font(13f, grassetto = false, colore = muto)
        val p = dp(14f)
        val spazio = dp(9f)

        // I pezzi della riga: larghezza e come disegnarli da x, alla linea y.
        val pezzi = mutableListOf<Pair<Float, (Float, Float) -> Unit>>()
        if (b != null) {
            val colore = when {
                b < 20 -> Color.rgb(239, 83, 80)
                b < 50 -> Color.rgb(255, 193, 7)
                else -> Color.rgb(102, 187, 106)
            }
            val t = "${b.roundToInt()}%"
            pezzi += (dp(32f) + forte.measureText(t)) to { x: Float, y: Float ->
                val corpo = RectF(x, y - dp(15f), x + dp(24f), y - dp(2f))
                bordo.color = Color.WHITE
                bordo.strokeWidth = dp(2f)
                canvas.drawRoundRect(corpo, dp(3f), dp(3f), bordo)
                pieno.color = Color.WHITE
                canvas.drawRect(RectF(corpo.right + dp(1f), y - dp(11f), corpo.right + dp(3f), y - dp(6f)), pieno)
                pieno.color = colore
                val livello = (b / 100.0).coerceIn(0.06, 1.0).toFloat()
                canvas.drawRect(RectF(corpo.left + dp(3f), corpo.top + dp(3f), corpo.left + dp(3f) + (corpo.width() - dp(6f)) * livello, corpo.bottom - dp(3f)), pieno)
                canvas.drawText(t, x + dp(32f), y, forte)
            }
            c.autonomiaKm?.let { km ->
                val t = "${km.roundToInt()} km"
                pezzi += forte.measureText(t) to { x: Float, y: Float -> canvas.drawText(t, x, y, forte) }
            }
            c.arrivoBatteria?.let { v ->
                val t = "${v.roundToInt()}%"
                val colore2 = if (v < 10) Color.rgb(239, 83, 80) else Color.rgb(102, 187, 106)
                val valore = font(20f, colore = colore2)
                val etichetta = font(14f, grassetto = false, colore = muto)
                val spazioEtichetta = etichetta.measureText("meta") + dp(6f)
                pezzi += (spazioEtichetta + valore.measureText(t)) to { x: Float, y: Float ->
                    canvas.drawText("meta", x, y, etichetta)
                    canvas.drawText(t, x + spazioEtichetta, y, valore)
                }
            }
        }
        meteo?.let { m ->
            val t = "${c.meteoEmoji ?: ""} ${m.roundToInt()}°".trim()
            pezzi += forte.measureText(t) to { x: Float, y: Float -> canvas.drawText(t, x, y, forte) }
        }
        val larghezzaRiga = pezzi.sumOf { it.first.toDouble() }.toFloat() + spazio * 2 * (pezzi.size - 1).coerceAtLeast(0)
        val sosta = c.sostaNome?.let { nome ->
            listOfNotNull(
                "⚡ $nome",
                c.sostaKm?.let { "${it.roundToInt()} km" },
                c.sostaBatteria?.let { "arrivi col ${it.roundToInt()}%" },
            ).joinToString(" · ")
        }
        // Larga quanto la riga; la sosta, se è più lunga, si accorcia.
        val w = (if (pezzi.isEmpty()) dp(220f) else larghezzaRiga) + p * 2
        val hRiga = dp(54f)
        val hSosta = if (sosta != null) dp(24f) else 0f
        val h = hRiga + hSosta

        // Dove: accanto al tachimetro se ci sta, se no sopra.
        val destra = a.right - margine
        val limiteSinistro = a.left + margine
        val (x, basso) = if (tachimetro != null && tachimetro.left - dp(10f) - w >= limiteSinistro) {
            (tachimetro.left - dp(10f) - w) to tachimetro.bottom
        } else if (tachimetro != null) {
            (destra - w) to (tachimetro.top - dp(8f))
        } else {
            (destra - w) to (a.bottom - margine)
        }
        val box = RectF(x, basso - h, x + w, basso)
        canvas.drawRoundRect(box, dp(18f), dp(18f), sfondoScheda)
        sosta?.let {
            val t = taglia(piccolo, it, w - p * 2)
            canvas.drawText(t, box.left + p, box.top + dp(19f), piccolo)
        }
        val linea = box.bottom - hRiga / 2 + dp(7f)
        var cx = box.left + p + (w - p * 2 - larghezzaRiga).coerceAtLeast(0f) / 2
        for ((i, pezzo) in pezzi.withIndex()) {
            if (i > 0) {
                pieno.color = Color.argb(60, 255, 255, 255)
                canvas.drawRect(RectF(cx + spazio - dp(0.5f), linea - dp(17f), cx + spazio + dp(0.5f), linea + dp(3f)), pieno)
                cx += spazio * 2
            }
            pezzo.second(cx, linea)
            cx += pezzo.first
        }
    }

    /**
     * L'avviso al centro fra [sinistra] e [destra], da [alto]. Con [prova] non
     * disegna: dice solo se non ci sta (o se non c'è niente da dire).
     */
    private fun avviso(canvas: Canvas, sinistra: Float, destra: Float, alto: Float, prova: Boolean = false): Boolean {
        val av = PonteAuto.avviso
        val titoloAvviso = av.titolo
        val (riga1, riga2, colore) = when {
            titoloAvviso != null -> Triple(
                titoloAvviso,
                av.metri?.let { "tra ${distanza(it)}" },
                when (av.tipo) {
                    "autovelox" -> Color.rgb(245, 124, 0)
                    "polizia" -> Color.rgb(30, 136, 229)
                    "incidente", "chiusura" -> Color.rgb(229, 57, 53)
                    else -> Color.rgb(251, 140, 0)
                },
            )
            av.ancoraTesto != null -> Triple(av.ancoraTesto, "Rispondi coi tasti in alto", Color.argb(235, 32, 38, 51))
            else -> Triple(null, null, 0)
        }
        if (riga1 == null) return false
        val icona = av.tipo?.let { PonteAuto.immagini["segnala-$it"] }
        val spazioIcona = if (icona != null) dp(48f) else 0f
        val spazioLimite = if (av.limite != null) dp(52f) else 0f
        val larghezza = max(testo.measureText(riga1), riga2?.let { testoPiccolo.measureText(it) } ?: 0f) +
            dp(30f) + spazioIcona + spazioLimite
        if (prova) return larghezza > destra - sinistra
        val cx = (sinistra + destra) / 2f
        val box = RectF(cx - larghezza / 2, alto, cx + larghezza / 2, alto + dp(62f))
        pieno.color = colore
        canvas.drawRoundRect(box, dp(18f), dp(18f), pieno)
        icona?.let {
            val lato = dp(40f)
            val dst = RectF(box.left + dp(10f), box.centerY() - lato / 2, box.left + dp(10f) + lato, box.centerY() + lato / 2)
            canvas.drawBitmap(it, null, dst, null)
        }
        val x = box.left + dp(15f) + spazioIcona
        canvas.drawText(riga1, x, box.top + dp(28f), testo)
        riga2?.let { canvas.drawText(it, x, box.top + dp(50f), testoPiccolo) }
        av.limite?.let { l -> cartello(canvas, box.right - dp(32f), box.centerY(), dp(23f), l) }
        return false
    }

    /**
     * In basso a destra, in una capsula sola: arrivo, tempo e km che restano
     * (in guida), il limite e la velocità. Restituisce dove sta.
     */
    private fun velocita(canvas: Canvas, a: Rect, c: PonteAuto.Cruscotto): RectF? {
        val v = c.velocita
        val g = PonteAuto.guida
        if (v == null && g == null) return null
        val margine = dp(10f)
        val h = dp(54f)
        val destra = a.right - margine
        val basso = a.bottom - margine
        val cy = basso - h / 2
        val r = dp(22f)

        // Da destra: velocità, limite, poi arrivo e tempo.
        var x = destra - dp(5f)
        val cxVelocita = v?.let { x - r }
        if (v != null) x -= r * 2 + dp(6f)
        val cxLimite = c.limite?.takeIf { v != null }?.let { x - r * 0.9f }
        if (cxLimite != null) x -= r * 1.8f + dp(8f)
        val ora = g?.let { java.text.SimpleDateFormat("HH:mm", java.util.Locale.ITALY).format(java.util.Date(it.arrivoMs)) }
        val sotto = g?.let { "${tempo(it.restantiS)} · ${distanza(it.restantiM)}" }
        val forte = font(21f)
        val piccolo = font(13f, grassetto = false, colore = muto)
        val larghezzaTesti = if (g != null) max(forte.measureText(ora!!), piccolo.measureText(sotto!!)) + dp(18f) + dp(8f) else dp(5f)
        val box = RectF(x - larghezzaTesti, basso - h, destra, basso)
        canvas.drawRoundRect(box, h / 2, h / 2, sfondoScheda)
        if (g != null) {
            canvas.drawText(ora!!, box.left + dp(18f), cy - dp(1f), forte)
            canvas.drawText(sotto!!, box.left + dp(18f), cy + dp(17f), piccolo)
        }
        cxLimite?.let { cartello(canvas, it, cy, r * 0.9f, c.limite!!) }
        if (v != null && cxVelocita != null) {
            val oltre = c.limite != null && v > c.limite + 3
            pieno.color = if (oltre) Color.rgb(229, 57, 53) else Color.WHITE
            canvas.drawCircle(cxVelocita, cy, r, pieno)
            numero.color = if (oltre) Color.WHITE else Color.rgb(32, 38, 51)
            numero.textSize = dp(19f)
            canvas.drawText("${v.roundToInt()}", cxVelocita, cy + dp(4f), numero)
            numero.textSize = dp(8.5f)
            canvas.drawText("km/h", cxVelocita, cy + dp(15f), numero)
        }
        return box
    }

    private fun tempo(secondi: Long): String {
        val minuti = ((secondi + 30) / 60).coerceAtLeast(1)
        return if (minuti < 60) "$minuti min" else "${minuti / 60} h ${"%02d".format(minuti % 60)}"
    }

    /** Da che parte va la manovra: 1 destra, -1 sinistra, 0 dritto. */
    private fun lato(tipo: Int) = when (tipo) {
        9, 10, 11, 18, 20, 23, 37 -> 1
        14, 15, 16, 19, 21, 24, 38 -> -1
        else -> 0
    }

    /** Il cartello del limite: cerchio bianco col bordo rosso. */
    private fun cartello(canvas: Canvas, cx: Float, cy: Float, r: Float, limite: Int) {
        pieno.color = Color.WHITE
        canvas.drawCircle(cx, cy, r, pieno)
        bordo.color = Color.rgb(211, 47, 47)
        bordo.strokeWidth = r * 0.2f
        canvas.drawCircle(cx, cy, r - bordo.strokeWidth / 2, bordo)
        numero.color = Color.BLACK
        numero.textSize = r * if (limite >= 100) 0.72f else 0.85f
        canvas.drawText("$limite", cx, cy + numero.textSize * 0.35f, numero)
    }

    private fun distanza(m: Double): String =
        if (m < 1000) "${(Math.round(m / 10.0) * 10)} m" else String.format(java.util.Locale.ITALY, "%.1f km", m / 1000)

    private fun accorcia(s: String, n: Int) = if (s.length <= n) s else s.take(n - 1) + "…"
}
