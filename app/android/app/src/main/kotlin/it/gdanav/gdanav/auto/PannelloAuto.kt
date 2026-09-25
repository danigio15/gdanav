package it.gdanav.gdanav.auto

import android.content.Context
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
 * Sopra la mappa dell'auto, come sul telefono: in basso a destra velocità e
 * limite, sopra la batteria (adesso e all'arrivo), la prossima sosta e il
 * meteo; in alto l'avviso della segnalazione che si avvicina. Tutto dentro
 * l'area lasciata libera da Android Auto.
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
        textSize = dp(17f)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val testoPiccolo = Paint(testo).apply {
        textSize = dp(14f)
        typeface = Typeface.DEFAULT
    }
    private val sfondo = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(230, 32, 38, 51) }
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
        var basso = a.bottom - margine
        val destra = a.right - margine

        // Velocità e limite, in basso a destra.
        val r = dp(30f)
        c.velocita?.let { v ->
            val cx = destra - r
            val cy = basso - r
            val oltre = c.limite != null && v > c.limite + 3
            pieno.color = if (oltre) Color.rgb(229, 57, 53) else Color.WHITE
            canvas.drawCircle(cx, cy, r, pieno)
            bordo.color = Color.argb(60, 0, 0, 0)
            bordo.strokeWidth = dp(1.5f)
            canvas.drawCircle(cx, cy, r, bordo)
            numero.color = if (oltre) Color.WHITE else Color.rgb(32, 38, 51)
            numero.textSize = dp(22f)
            canvas.drawText("${v.roundToInt()}", cx, cy + dp(4f), numero)
            numero.textSize = dp(10f)
            canvas.drawText("km/h", cx, cy + dp(17f), numero)
            c.limite?.let { l -> cartello(canvas, cx - r * 2 - dp(8f), cy, r * 0.9f, l) }
            basso = cy - r - dp(8f)
        }

        // Sosta e meteo: una scheda per riga, allineate a destra, sopra la
        // batteria.
        val righe = mutableListOf<Pair<String, String?>>()
        if (c.sostaNome != null) {
            val dettagli = listOfNotNull(
                c.sostaKm?.let { "tra ${it.roundToInt()} km" },
                c.sostaBatteria?.let { "arrivi col ${it.roundToInt()}%" },
            ).joinToString(" · ")
            righe += "⚡ ${accorcia(c.sostaNome, 26)}" to dettagli.ifEmpty { null }
        }
        if (c.meteoTemperatura != null) {
            righe += "${c.meteoEmoji ?: ""} ${c.meteoTemperatura.roundToInt()}°" to c.meteoDove
        }
        c.batteria?.let { b -> basso = batteria(canvas, destra, basso, b, c) - dp(6f) }
        for ((titolo, sotto) in righe.asReversed()) {
            val larghezza = max(testo.measureText(titolo), sotto?.let { testoPiccolo.measureText(it) } ?: 0f) + dp(24f)
            val altezza = if (sotto != null) dp(50f) else dp(34f)
            val box = RectF(destra - larghezza, basso - altezza, destra, basso)
            canvas.drawRoundRect(box, dp(14f), dp(14f), sfondo)
            canvas.drawText(titolo, box.left + dp(12f), box.top + dp(23f), testo)
            sotto?.let { canvas.drawText(it, box.left + dp(12f), box.top + dp(42f), testoPiccolo) }
            basso = box.top - dp(6f)
        }

        // L'avviso in alto, al centro: autovelox, polizia, incidente…
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
        if (riga1 != null) {
            val icona = av.tipo?.let { PonteAuto.immagini["segnala-$it"] }
            val spazioIcona = if (icona != null) dp(44f) else 0f
            val spazioLimite = if (av.limite != null) dp(48f) else 0f
            val larghezza = max(testo.measureText(riga1), riga2?.let { testoPiccolo.measureText(it) } ?: 0f) +
                dp(28f) + spazioIcona + spazioLimite
            val cx = (a.left + a.right) / 2f
            val box = RectF(cx - larghezza / 2, a.top + margine, cx + larghezza / 2, a.top + margine + dp(56f))
            pieno.color = colore
            canvas.drawRoundRect(box, dp(18f), dp(18f), pieno)
            icona?.let {
                val lato = dp(36f)
                val dst = RectF(box.left + dp(10f), box.centerY() - lato / 2, box.left + dp(10f) + lato, box.centerY() + lato / 2)
                canvas.drawBitmap(it, null, dst, null)
            }
            val x = box.left + dp(14f) + spazioIcona
            canvas.drawText(riga1, x, box.top + dp(25f), testo)
            riga2?.let { canvas.drawText(it, x, box.top + dp(45f), testoPiccolo) }
            av.limite?.let { l -> cartello(canvas, box.right - dp(30f), box.centerY(), dp(21f), l) }
        }
    }

    /**
     * La batteria come un'icona vera, piena quanto l'auto e colorata (verde,
     * gialla, rossa), con la percentuale grande; sotto l'autonomia adesso
     * (dall'auto o stimata sul consumo vero) e la batteria all'arrivo.
     * Restituisce il bordo alto della scheda.
     */
    private fun batteria(canvas: Canvas, destra: Float, basso: Float, b: Double, c: PonteAuto.Cruscotto): Float {
        val livello = (b / 100.0).coerceIn(0.0, 1.0).toFloat()
        val colore = when {
            b < 20 -> Color.rgb(229, 57, 53)
            b < 50 -> Color.rgb(255, 179, 0)
            else -> Color.rgb(67, 160, 71)
        }
        val grande = Paint(testo).apply { textSize = dp(24f) }
        val percentuale = "${b.roundToInt()}%"
        val autonomia = c.autonomiaKm?.let { "${it.roundToInt()} km" }
        val fonte = if (c.autonomiaKm == null) null else if (c.autonomiaAuto) "dall'auto" else "stimati"
        val arrivo = c.arrivoBatteria?.let { "${it.roundToInt()}% all'arrivo" }
        val lIcona = dp(40f)
        val larghezza = maxOf(
            lIcona + dp(10f) + grande.measureText(percentuale),
            (autonomia?.let { testo.measureText(it) + dp(6f) } ?: 0f) + (fonte?.let { testoPiccolo.measureText(it) } ?: 0f),
            arrivo?.let { testoPiccolo.measureText(it) } ?: 0f,
        ) + dp(26f)
        val altezza = dp(44f) + (if (autonomia != null) dp(24f) else 0f) + (if (arrivo != null) dp(20f) else 0f)
        val box = RectF(destra - larghezza, basso - altezza, destra, basso)
        canvas.drawRoundRect(box, dp(16f), dp(16f), sfondo)
        // L'icona: corpo, polo, riempimento.
        val x = box.left + dp(13f)
        val y = box.top + dp(12f)
        val corpo = RectF(x, y, x + lIcona - dp(4f), y + dp(20f))
        bordo.color = Color.WHITE
        bordo.strokeWidth = dp(2f)
        canvas.drawRoundRect(corpo, dp(4f), dp(4f), bordo)
        pieno.color = Color.WHITE
        canvas.drawRoundRect(RectF(corpo.right + dp(1f), y + dp(6f), corpo.right + dp(4f), y + dp(14f)), dp(1f), dp(1f), pieno)
        pieno.color = colore
        val dentro = RectF(corpo.left + dp(3f), corpo.top + dp(3f), corpo.right - dp(3f), corpo.bottom - dp(3f))
        canvas.drawRoundRect(RectF(dentro.left, dentro.top, dentro.left + dentro.width() * max(livello, 0.04f), dentro.bottom), dp(2f), dp(2f), pieno)
        canvas.drawText(percentuale, x + lIcona + dp(8f), y + dp(19f), grande)
        var riga = box.top + dp(44f)
        autonomia?.let {
            canvas.drawText(it, box.left + dp(13f), riga + dp(16f), testo)
            fonte?.let { f -> canvas.drawText(f, box.left + dp(19f) + testo.measureText(it), riga + dp(16f), testoPiccolo) }
            riga += dp(24f)
        }
        arrivo?.let { canvas.drawText(it, box.left + dp(13f), riga + dp(14f), testoPiccolo) }
        return box.top
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
