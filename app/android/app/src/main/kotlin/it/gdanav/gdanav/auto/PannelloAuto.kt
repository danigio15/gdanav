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
 * Sopra la mappa dell'auto, come sul telefono. In alto, avvicinandosi a
 * un'uscita, lo svincolo in grande col cartello verde (numero e direzioni);
 * sotto, grandi e in fila, batteria (adesso, autonomia, all'arrivo), prossima
 * sosta e meteo; poi l'avviso della segnalazione che si avvicina. In basso a
 * destra velocità e limite. Tutto dentro l'area lasciata libera da Android
 * Auto: la mappa continua sotto.
 */
class PannelloAuto(context: Context, private val densita: Float) : View(context) {
    /** L'area non coperta dalle schede di Android Auto. */
    var area: Rect? = null
        set(v) {
            field = v
            invalidate()
        }

    private fun dp(v: Float) = v * densita

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
    private val sfondo = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(235, 32, 38, 51) }
    private val pieno = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bordo = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val numero = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val immagine = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    fun aggiorna() = postInvalidate()

    override fun onDraw(canvas: Canvas) {
        val a = area ?: Rect(0, 0, width, height)
        val margine = dp(10f)
        val c = PonteAuto.cruscotto
        val g = PonteAuto.guida
        var alto = a.top + margine
        val sinistra = a.left + margine
        val destra = a.right - margine

        // 1. Lo svincolo in grande, in alto, col cartello; o, un po' prima,
        // il cartello da solo.
        val vista = g?.svincolo?.let { PonteAuto.svincoli[it] }
        val conCartello = g != null && (g.uscita.isNotEmpty() || g.verso.isNotEmpty()) && g.distanzaM <= 2500
        if (g != null && vista != null) {
            val box = svincolo(canvas, a, alto, vista, g)
            if (conCartello) cartelloUscita(canvas, box.left + dp(10f), box.top + dp(10f), box.width() * 0.6f, g)
            alto = box.bottom + dp(8f)
        } else if (g != null && conCartello) {
            val box = cartelloUscita(canvas, sinistra, alto, (a.width() * 0.55f).coerceAtMost(dp(420f)), g)
            // I dati accanto, se ci stanno; se no sotto.
            val accanto = dati(canvas, box.right + dp(8f), alto, destra, c, prova = true) != null
            alto = if (accanto) {
                max(box.bottom, dati(canvas, box.right + dp(8f), alto, destra, c) ?: alto) + dp(8f)
            } else {
                (dati(canvas, sinistra, box.bottom + dp(8f), destra, c) ?: box.bottom) + dp(8f)
            }
            avviso(canvas, a, alto)
            velocita(canvas, a, c)
            return
        }

        // 2. I dati dell'auto, grandi, in fila in alto a destra.
        dati(canvas, sinistra, alto, destra, c)?.let { alto = it + dp(8f) }

        // 3. L'avviso: autovelox, polizia, incidente…
        avviso(canvas, a, alto)

        // 4. Velocità e limite in basso a destra.
        velocita(canvas, a, c)
    }

    /** Lo svincolo disegnato dall'app, largo quanto l'area, con la distanza sotto. */
    private fun svincolo(canvas: Canvas, a: Rect, alto: Float, vista: Bitmap, g: PonteAuto.Guida): RectF {
        val margine = dp(10f)
        var w = a.width() - margine * 2
        var h = w * vista.height / vista.width
        val massima = a.height() * 0.52f
        if (h > massima) {
            h = massima
            w = h * vista.width / vista.height
        }
        val cx = (a.left + a.right) / 2f
        val box = RectF(cx - w / 2, alto, cx + w / 2, alto + h)
        val raggio = dp(18f)
        canvas.save()
        val forma = android.graphics.Path().apply { addRoundRect(box, raggio, raggio, android.graphics.Path.Direction.CW) }
        canvas.clipPath(forma)
        canvas.drawBitmap(vista, null, box, immagine)
        // La distanza che manca, in basso: barra che si accorcia e metri.
        val striscia = RectF(box.left, box.bottom - dp(40f), box.right, box.bottom)
        canvas.drawRect(striscia, sfondo)
        val quanto = (g.distanzaM / 800.0).coerceIn(0.0, 1.0).toFloat()
        pieno.color = Color.rgb(51, 153, 255)
        canvas.drawRect(RectF(striscia.left, striscia.top, striscia.left + striscia.width() * quanto, striscia.top + dp(5f)), pieno)
        val metri = distanza(g.distanzaM)
        val grande = Paint(testo).apply { textSize = dp(24f) }
        canvas.drawText(metri, striscia.left + dp(14f), striscia.bottom - dp(9f), grande)
        val dopo = g.strada.ifEmpty { g.istruzione }
        if (dopo.isNotEmpty()) {
            val x = striscia.left + dp(28f) + grande.measureText(metri)
            canvas.drawText(accorcia(dopo, 40), x, striscia.bottom - dp(11f), testoPiccolo)
        }
        canvas.restore()
        bordo.color = Color.argb(90, 255, 255, 255)
        bordo.strokeWidth = dp(1.5f)
        canvas.drawRoundRect(box, raggio, raggio, bordo)
        return box
    }

    /**
     * Il cartello dell'uscita come in autostrada: verde, bordo bianco, in alto
     * «USCITA» col numero, sotto le strade (A1, E45) e le direzioni. Blu se non
     * è un'uscita numerata (strada extraurbana). Restituisce dove sta.
     */
    private fun cartelloUscita(canvas: Canvas, x: Float, y: Float, larghezzaMassima: Float, g: PonteAuto.Guida): RectF {
        val autostrada = g.uscita.isNotEmpty() || Regex("^[AE] ?\\d").containsMatchIn(g.verso)
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
        val larghezzaTesto = maxOf(
            righeLuoghi.maxOfOrNull { nome.measureText(it) } ?: 0f,
            sigle.sumOf { (sigla.measureText(it) + dp(22f)).toDouble() }.toFloat(),
            if (g.uscita.isNotEmpty()) etichetta.measureText("USCITA") + dp(60f) else 0f,
        )
        val w = (larghezzaTesto + interno * 2 + dp(36f)).coerceIn(dp(180f), larghezzaMassima.coerceAtLeast(dp(180f)))
        val h = interno + hTesta + hSigle + hRiga * righeLuoghi.size.coerceAtLeast(1) + interno - dp(6f)
        val box = RectF(x, y, x + w, y + h)
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
        val freccia = when (g.tipo) {
            9, 10, 11, 18, 20, 23, 37 -> "↗"
            14, 15, 16, 19, 21, 24, 38 -> "↖"
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

    /**
     * Batteria, sosta e meteo in fila, allineati a destra partendo da [alto];
     * se non ci stanno, vanno a capo. Restituisce il fondo, o `null` se non
     * c'è niente (o, con [prova], se non ci stanno fra [sinistra] e [destra]).
     */
    private fun dati(canvas: Canvas, sinistra: Float, alto: Float, destra: Float, c: PonteAuto.Cruscotto, prova: Boolean = false): Float? {
        val schede = mutableListOf<Pair<Float, (Float, Float) -> Float>>()
        c.batteria?.let { b -> schede += larghezzaBatteria(b, c) to { x: Float, y: Float -> batteria(canvas, x, y, b, c) } }
        if (c.sostaNome != null) {
            val titolo = "⚡ ${accorcia(c.sostaNome, 22)}"
            val sotto = listOfNotNull(
                c.sostaKm?.let { "tra ${it.roundToInt()} km" },
                c.sostaBatteria?.let { "arrivi col ${it.roundToInt()}%" },
            ).joinToString(" · ").ifEmpty { null }
            schede += larghezzaScheda(titolo, sotto) to { x: Float, y: Float -> scheda(canvas, x, y, titolo, sotto) }
        }
        if (c.meteoTemperatura != null) {
            val titolo = "${c.meteoEmoji ?: ""} ${c.meteoTemperatura.roundToInt()}°".trim()
            val sotto = c.meteoDove?.let { accorcia(it, 22) }
            schede += larghezzaScheda(titolo, sotto, grande = true) to { x: Float, y: Float -> scheda(canvas, x, y, titolo, sotto, grande = true) }
        }
        if (schede.isEmpty()) return null
        val spazio = dp(8f)
        if (prova) {
            val tutta = schede.sumOf { it.first.toDouble() }.toFloat() + spazio * (schede.size - 1)
            return if (tutta <= destra - sinistra) 0f else null
        }
        var x = destra
        var y = alto
        var fondo = alto
        for ((w, disegna) in schede) {
            if (x - w < sinistra && x < destra) {
                x = destra
                y = fondo + spazio
            }
            val basso = disegna(x - w, y)
            fondo = max(fondo, basso)
            x -= w + spazio
        }
        return fondo
    }

    private fun larghezzaScheda(titolo: String, sotto: String?, grande: Boolean = false): Float {
        val t = if (grande) Paint(testo).apply { textSize = dp(28f) } else testo
        return max(t.measureText(titolo), sotto?.let { testoPiccolo.measureText(it) } ?: 0f) + dp(28f)
    }

    /** Una scheda: titolo grande, sotto una riga. Restituisce il fondo. */
    private fun scheda(canvas: Canvas, x: Float, y: Float, titolo: String, sotto: String?, grande: Boolean = false): Float {
        val t = if (grande) Paint(testo).apply { textSize = dp(28f) } else testo
        val w = larghezzaScheda(titolo, sotto, grande)
        val h = dp(if (grande) 40f else 34f) + if (sotto != null) dp(24f) else 0f
        val box = RectF(x, y, x + w, y + h)
        canvas.drawRoundRect(box, dp(16f), dp(16f), sfondo)
        canvas.drawText(titolo, box.left + dp(14f), box.top + dp(if (grande) 33f else 27f), t)
        sotto?.let { canvas.drawText(it, box.left + dp(14f), box.bottom - dp(11f), testoPiccolo) }
        return box.bottom
    }

    private fun larghezzaBatteria(b: Double, c: PonteAuto.Cruscotto): Float {
        val grande = Paint(testo).apply { textSize = dp(30f) }
        val autonomia = c.autonomiaKm?.let { "${it.roundToInt()} km" }
        val fonte = if (c.autonomiaKm == null) null else if (c.autonomiaAuto) "dall'auto" else "stimati"
        val arrivo = c.arrivoBatteria?.let { "${it.roundToInt()}% all'arrivo" }
        return maxOf(
            dp(50f) + dp(10f) + grande.measureText("${b.roundToInt()}%"),
            (autonomia?.let { testo.measureText(it) + dp(6f) } ?: 0f) + (fonte?.let { testoPiccolo.measureText(it) } ?: 0f),
            arrivo?.let { testo.measureText(it) } ?: 0f,
        ) + dp(30f)
    }

    /**
     * La batteria come un'icona vera, piena quanto l'auto e colorata (verde,
     * gialla, rossa), con la percentuale grande; sotto l'autonomia adesso
     * (dall'auto o stimata sul consumo vero) e la batteria all'arrivo.
     * Restituisce il fondo della scheda.
     */
    private fun batteria(canvas: Canvas, x0: Float, y0: Float, b: Double, c: PonteAuto.Cruscotto): Float {
        val livello = (b / 100.0).coerceIn(0.0, 1.0).toFloat()
        val colore = when {
            b < 20 -> Color.rgb(229, 57, 53)
            b < 50 -> Color.rgb(255, 179, 0)
            else -> Color.rgb(67, 160, 71)
        }
        val grande = Paint(testo).apply { textSize = dp(30f) }
        val percentuale = "${b.roundToInt()}%"
        val autonomia = c.autonomiaKm?.let { "${it.roundToInt()} km" }
        val fonte = if (c.autonomiaKm == null) null else if (c.autonomiaAuto) "dall'auto" else "stimati"
        val arrivo = c.arrivoBatteria?.let { "${it.roundToInt()}% all'arrivo" }
        val lIcona = dp(50f)
        val larghezza = larghezzaBatteria(b, c)
        val altezza = dp(52f) + (if (autonomia != null) dp(28f) else 0f) + (if (arrivo != null) dp(28f) else 0f)
        val box = RectF(x0, y0, x0 + larghezza, y0 + altezza)
        canvas.drawRoundRect(box, dp(16f), dp(16f), sfondo)
        // L'icona: corpo, polo, riempimento.
        val x = box.left + dp(15f)
        val y = box.top + dp(14f)
        val corpo = RectF(x, y, x + lIcona - dp(5f), y + dp(25f))
        bordo.color = Color.WHITE
        bordo.strokeWidth = dp(2.5f)
        canvas.drawRoundRect(corpo, dp(5f), dp(5f), bordo)
        pieno.color = Color.WHITE
        canvas.drawRoundRect(RectF(corpo.right + dp(1f), y + dp(8f), corpo.right + dp(5f), y + dp(17f)), dp(1f), dp(1f), pieno)
        pieno.color = colore
        val dentro = RectF(corpo.left + dp(3.5f), corpo.top + dp(3.5f), corpo.right - dp(3.5f), corpo.bottom - dp(3.5f))
        canvas.drawRoundRect(RectF(dentro.left, dentro.top, dentro.left + dentro.width() * max(livello, 0.04f), dentro.bottom), dp(2f), dp(2f), pieno)
        canvas.drawText(percentuale, x + lIcona + dp(10f), y + dp(24f), grande)
        var riga = box.top + dp(52f)
        autonomia?.let {
            canvas.drawText(it, box.left + dp(15f), riga + dp(20f), testo)
            fonte?.let { f -> canvas.drawText(f, box.left + dp(21f) + testo.measureText(it), riga + dp(20f), testoPiccolo) }
            riga += dp(28f)
        }
        arrivo?.let {
            val colorato = Paint(testo).apply { color = if ((c.arrivoBatteria ?: 100.0) < 10) Color.rgb(255, 138, 128) else Color.rgb(165, 214, 167) }
            canvas.drawText(it, box.left + dp(15f), riga + dp(20f), colorato)
        }
        return box.bottom
    }

    /** L'avviso a centro area, da [alto]: restituisce il fondo. */
    private fun avviso(canvas: Canvas, a: Rect, alto: Float): Float {
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
        if (riga1 == null) return alto
        val icona = av.tipo?.let { PonteAuto.immagini["segnala-$it"] }
        val spazioIcona = if (icona != null) dp(48f) else 0f
        val spazioLimite = if (av.limite != null) dp(52f) else 0f
        val larghezza = max(testo.measureText(riga1), riga2?.let { testoPiccolo.measureText(it) } ?: 0f) +
            dp(30f) + spazioIcona + spazioLimite
        val cx = (a.left + a.right) / 2f
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
        return box.bottom + dp(8f)
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
