package it.gdanav.gdanav_app.auto

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.graphics.PathParser

/**
 * L'immagine delle corsie per Android Auto, come sul cartello: le corsie
 * giuste su blu con la freccia da seguire bianca, le altre spente. Le frecce
 * sono le stesse icone Material del telefono.
 */
object ImmagineCorsie {
    private val frecce = mapOf(
        "dritto" to "M11 6.83 9.41 8.41 8 7l4-4 4 4-1.41 1.41L13 6.83V21h-2z",
        "leggeraDestra" to "M12.34 6V4H18v5.66h-2V7.41l-5 5V20H9v-7.58c0-.53.21-1.04.59-1.41l5-5h-2.25z",
        "destra" to "m17.17 11-1.59 1.59L17 14l4-4-4-4-1.41 1.41L17.17 9H9c-1.1 0-2 .9-2 2v9h2v-9h8.17z",
        "destraStretta" to "m18 6.83 1.59 1.59L21 7l-4-4-4 4 1.41 1.41L16 6.83V13H8c-1.1 0-2 .9-2 2v6h2v-6h8c1.1 0 2-.9 2-2V6.83z",
        "leggeraSinistra" to "M11.66 6V4H6v5.66h2V7.41l5 5V20h2v-7.58c0-.53-.21-1.04-.59-1.41l-5-5h2.25z",
        "sinistra" to "m6.83 11 1.59 1.59L7 14l-4-4 4-4 1.41 1.41L6.83 9H15c1.1 0 2 .9 2 2v9h-2v-9H6.83z",
        "sinistraStretta" to "M6 6.83 4.41 8.41 3 7l4-4 4 4-1.41 1.41L8 6.83V13h8c1.1 0 2 .9 2 2v6h-2v-6H8c-1.1 0-2-.9-2-2V6.83z",
        "inversioneSinistra" to "M18 9v12h-2V9c0-2.21-1.79-4-4-4S8 6.79 8 9v4.17l1.59-1.59L11 13l-4 4-4-4 1.41-1.41L6 13.17V9c0-3.31 2.69-6 6-6s6 2.69 6 6z",
        "inversioneDestra" to "M6 9v12h2V9c0-2.21 1.79-4 4-4s4 1.79 4 4v4.17l-1.59-1.59L13 13l4 4 4-4-1.41-1.41L18 13.17V9c0-3.31-2.69-6-6-6S6 5.69 6 9z",
    )

    fun disegna(corsie: List<PonteAuto.CorsiaAuto>, altezza: Int = 120): Bitmap {
        val larghezzaCorsia = altezza
        val b = Bitmap.createBitmap(larghezzaCorsia * corsie.size, altezza, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val fondo = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(47, 111, 228) }
        val riga = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(140, 255, 255, 255)
            strokeWidth = altezza * 0.03f
            pathEffect = DashPathEffect(floatArrayOf(altezza * 0.1f, altezza * 0.08f), 0f)
        }
        val freccia = Paint(Paint.ANTI_ALIAS_FLAG)
        val margine = altezza * 0.06f
        corsie.forEachIndexed { i, corsia ->
            val x = i * larghezzaCorsia.toFloat()
            if (corsia.giusta) {
                c.drawRoundRect(RectF(x + margine, margine, x + larghezzaCorsia - margine, altezza - margine), altezza * 0.14f, altezza * 0.14f, fondo)
            }
            if (i > 0) c.drawLine(x, altezza * 0.1f, x, altezza * 0.9f, riga)
            val direzioni = corsia.direzioni.ifEmpty { listOf("dritto") }
            // Prima le frecce spente, poi quella da seguire sopra.
            for (d in direzioni.sortedBy { corsia.giusta && (corsia.consigliata == null || corsia.consigliata == it) }) {
                val dati = frecce[d] ?: continue
                val percorso = PathParser.createPathFromPathData(dati)
                val scala = altezza * 0.78f / 24f
                val m = Matrix()
                m.setScale(scala, scala)
                m.postTranslate(x + (larghezzaCorsia - 24 * scala) / 2, (altezza - 24 * scala) / 2)
                percorso.transform(m)
                val accesa = corsia.giusta && (corsia.consigliata == null || corsia.consigliata == d)
                freccia.color = when {
                    accesa -> Color.WHITE
                    corsia.giusta -> Color.argb(110, 255, 255, 255)
                    else -> Color.argb(90, 255, 255, 255)
                }
                c.drawPath(percorso, freccia)
            }
        }
        return b
    }
}
