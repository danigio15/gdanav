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

        // Batteria, sosta e meteo: una scheda per riga, allineate a destra.
        val righe = mutableListOf<Pair<String, String?>>()
        c.batteria?.let { b ->
            val sotto = when {
                c.arrivoBatteria != null -> "${c.arrivoBatteria.roundToInt()}% all'arrivo"
                c.autonomiaKm != null -> "${c.autonomiaKm.roundToInt()} km di autonomia"
                else -> null
            }
            righe += "🔋 ${b.roundToInt()}%" to sotto
        }
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
