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
 * Sopra la mappa dell'auto, come sul telefono: in alto a destra una scheda
 * sola coi dati dell'auto (batteria, km, all'arrivo), il meteo e la prossima
 * sosta; accanto l'avviso della segnalazione che si avvicina; in basso a
 * destra velocità e limite. Tutto dentro l'area lasciata libera da Android
 * Auto: la mappa continua sotto. Disegna anche il cartello dell'uscita sulla
 * vista dello svincolo, per la scheda in alto a sinistra.
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

        // 1. I dati dell'auto e il meteo: una scheda sola, in alto a destra.
        val scheda = cruscotto(canvas, destra, alto, c)

        // 2. L'avviso (autovelox, polizia, incidente…): in alto, accanto alla
        // scheda se ci sta, se no sotto.
        val fine = scheda?.left?.minus(dp(8f)) ?: destra
        if (!avviso(canvas, sinistra, fine, alto, prova = true)) {
            avviso(canvas, sinistra, fine, alto)
        } else {
            avviso(canvas, sinistra, destra, (scheda?.bottom ?: alto) + dp(8f))
        }

        // 3. Velocità e limite in basso a destra.
        velocita(canvas, a, c)
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
    private val sfondoScheda = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(238, 24, 28, 36) }

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
     * La scheda del cruscotto, larga sempre uguale e allineata a destra da
     * [alto]: in cima batteria (icona e percentuale grande) e meteo; sotto i
     * km che restano (dall'auto o stimati); poi la batteria all'arrivo con la
     * sua barra; sotto una riga, la prossima sosta. Con l'auto termica solo
     * il meteo. Restituisce dove sta, o `null` se non c'è niente.
     */
    private fun cruscotto(canvas: Canvas, destra: Float, alto: Float, c: PonteAuto.Cruscotto): RectF? {
        val b = c.batteria
        val meteo = c.meteoTemperatura
        if (b == null && meteo == null) return null
        val p = dp(16f)
        val grande = font(32f)
        val medio = font(21f)
        val piccolo = font(15f, grassetto = false, colore = muto)
        val temperatura = meteo?.let { "${c.meteoEmoji ?: ""} ${it.roundToInt()}°".trim() }
        val tempFont = font(if (b == null) 30f else 24f)
        // Larga sempre uguale; con la termica, quanto il meteo.
        val w = if (b != null || c.sostaNome != null) {
            dp(290f)
        } else {
            tempFont.measureText(temperatura ?: "") + (c.meteoDove?.let { piccolo.measureText(it) + dp(14f) } ?: 0f) + p * 2
        }
        val x = destra - w

        // Quanto è alta.
        var h = p + dp(38f)
        val autonomia = c.autonomiaKm?.let { "${it.roundToInt()} km" }
        val arrivo = c.arrivoBatteria
        if (b != null && autonomia != null) h += dp(30f)
        if (b != null && arrivo != null) h += dp(36f)
        val sosta = c.sostaNome
        if (sosta != null) h += dp(17f) + dp(50f)
        h += p - dp(4f)
        val box = RectF(x, alto, destra, alto + h)
        canvas.drawRoundRect(box, dp(20f), dp(20f), sfondoScheda)

        var y = alto + p
        if (b != null) {
            // Riga 1: icona, percentuale; a destra il meteo.
            val colore = when {
                b < 20 -> Color.rgb(239, 83, 80)
                b < 50 -> Color.rgb(255, 193, 7)
                else -> Color.rgb(102, 187, 106)
            }
            val corpo = RectF(x + p, y + dp(8f), x + p + dp(44f), y + dp(32f))
            bordo.color = Color.WHITE
            bordo.strokeWidth = dp(2.5f)
            canvas.drawRoundRect(corpo, dp(5f), dp(5f), bordo)
            pieno.color = Color.WHITE
            canvas.drawRoundRect(RectF(corpo.right + dp(1.5f), corpo.top + dp(7f), corpo.right + dp(5f), corpo.bottom - dp(7f)), dp(1.5f), dp(1.5f), pieno)
            pieno.color = colore
            val dentro = RectF(corpo.left + dp(4f), corpo.top + dp(4f), corpo.right - dp(4f), corpo.bottom - dp(4f))
            val livello = (b / 100.0).coerceIn(0.04, 1.0).toFloat()
            canvas.drawRoundRect(RectF(dentro.left, dentro.top, dentro.left + dentro.width() * livello, dentro.bottom), dp(2f), dp(2f), pieno)
            canvas.drawText("${b.roundToInt()}%", corpo.right + dp(14f), y + dp(32f), grande)
            temperatura?.let {
                tempFont.textAlign = Paint.Align.RIGHT
                canvas.drawText(it, destra - p, y + dp(28f), tempFont)
            }
            y += dp(38f)
            // Riga 2: i km; a destra dove vale il meteo.
            autonomia?.let {
                canvas.drawText(it, x + p, y + dp(22f), medio)
                val fonte = if (c.autonomiaAuto) "dall'auto" else "stimati"
                canvas.drawText(fonte, x + p + medio.measureText(it) + dp(7f), y + dp(22f), piccolo)
                y += dp(30f)
            }
            c.meteoDove?.let {
                val d = Paint(piccolo).apply { textAlign = Paint.Align.RIGHT }
                canvas.drawText(taglia(d, it, dp(100f)), destra - p, alto + p + dp(38f) + dp(22f), d)
            }
            // Riga 3: all'arrivo, con la barra.
            arrivo?.let { v ->
                val basso = v < 10
                val coloreArrivo = if (basso) Color.rgb(239, 83, 80) else Color.rgb(102, 187, 106)
                canvas.drawText("Alla meta", x + p, y + dp(20f), piccolo)
                val valore = font(19f, colore = coloreArrivo).apply { textAlign = Paint.Align.RIGHT }
                val testo = "${v.roundToInt()}%"
                canvas.drawText(testo, destra - p, y + dp(21f), valore)
                val bx = x + p + piccolo.measureText("Alla meta") + dp(12f)
                val bFine = destra - p - valore.measureText(testo) - dp(10f)
                val barra = RectF(bx, y + dp(10f), bFine, y + dp(18f))
                pieno.color = Color.argb(60, 255, 255, 255)
                canvas.drawRoundRect(barra, dp(4f), dp(4f), pieno)
                pieno.color = coloreArrivo
                val quanto = (v / 100.0).coerceIn(0.03, 1.0).toFloat()
                canvas.drawRoundRect(RectF(barra.left, barra.top, barra.left + barra.width() * quanto, barra.bottom), dp(4f), dp(4f), pieno)
                y += dp(36f)
            }
        } else if (temperatura != null) {
            // Auto termica: solo il meteo, grande, e dove vale.
            canvas.drawText(temperatura, x + p, y + dp(32f), tempFont)
            c.meteoDove?.let {
                val d = Paint(piccolo).apply { textAlign = Paint.Align.RIGHT }
                canvas.drawText(it, destra - p, y + dp(30f), d)
            }
            y += dp(38f)
        }
        // La prossima sosta, sotto una riga.
        if (sosta != null) {
            y += dp(6f)
            pieno.color = Color.argb(45, 255, 255, 255)
            canvas.drawRect(RectF(x + p, y, destra - p, y + dp(1f)), pieno)
            y += dp(11f)
            val titolo = font(18f)
            canvas.drawText(taglia(titolo, "⚡ $sosta", w - p * 2), x + p, y + dp(20f), titolo)
            val sotto = listOfNotNull(
                c.sostaKm?.let { "tra ${it.roundToInt()} km" },
                c.sostaBatteria?.let { "arrivi col ${it.roundToInt()}%" },
            ).joinToString(" · ")
            if (sotto.isNotEmpty()) canvas.drawText(taglia(piccolo, sotto, w - p * 2), x + p, y + dp(42f), piccolo)
        }
        return box
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

    /** Velocità e limite, in basso a destra. */
    private fun velocita(canvas: Canvas, a: Rect, c: PonteAuto.Cruscotto) {
        val v = c.velocita ?: return
        val margine = dp(10f)
        val r = dp(34f)
        val cx = a.right - margine - r
        val cy = a.bottom - margine - r
        val oltre = c.limite != null && v > c.limite + 3
        pieno.color = if (oltre) Color.rgb(229, 57, 53) else Color.WHITE
        canvas.drawCircle(cx, cy, r, pieno)
        bordo.color = Color.argb(60, 0, 0, 0)
        bordo.strokeWidth = dp(1.5f)
        canvas.drawCircle(cx, cy, r, bordo)
        numero.color = if (oltre) Color.WHITE else Color.rgb(32, 38, 51)
        numero.textSize = dp(25f)
        canvas.drawText("${v.roundToInt()}", cx, cy + dp(5f), numero)
        numero.textSize = dp(11f)
        canvas.drawText("km/h", cx, cy + dp(20f), numero)
        c.limite?.let { l -> cartello(canvas, cx - r * 2 - dp(8f), cy, r * 0.9f, l) }
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
