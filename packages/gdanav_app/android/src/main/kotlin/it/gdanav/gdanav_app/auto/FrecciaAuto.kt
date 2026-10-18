package it.gdanav.gdanav_app.auto

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.view.View
import kotlin.math.abs

/**
 * Il segnaposto sullo schermo dell'auto (la freccia, o l'auto vista
 * dall'alto), disegnato sopra la mappa e non dentro.
 *
 * Dentro la mappa era un punto di una sorgente GeoJSON, riscritto a ogni
 * fotogramma: MapLibre la rilegge per conto suo, su un altro filo, e la mostra
 * uno, due o tre fotogrammi dopo la telecamera, che invece si sposta subito.
 * Seguendo l'auto, la freccia ballava avanti e indietro intorno al suo posto
 * di quel tanto che l'auto fa in quei fotogrammi (a 90 all'ora, metri), e a
 * ogni fotogramma la mappa rifaceva il riquadro del segnaposto.
 *
 * Qui la freccia sta dove la telecamera mette l'auto: seguendola, sempre nello
 * stesso punto dello schermo, e la mappa le scorre sotto. Si gira di quanto la
 * strada è girata rispetto alla mappa e, in 3D, si schiaccia come la mappa
 * inclinata ([schiaccia], il coseno dell'inclinazione), così sembra disegnata
 * per terra come prima.
 */
internal class FrecciaAuto(context: Context) : View(context) {
    private val immagini = HashMap<String, Bitmap>()
    private val matrice = Matrix()
    private val pennello = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    private var nome = "freccia"
    private var x = 0f
    private var y = 0f
    private var angolo = 0f
    private var scala = 1f
    private var schiaccia = 1f
    private var visibile = false

    init {
        // Non prende i tocchi: vanno alla mappa (o ad Android Auto).
        isClickable = false
        isFocusable = false
    }

    /** Un'immagine del segnaposto, decodificata altrove. */
    fun immagine(nome: String, bitmap: Bitmap) {
        immagini[nome] = bitmap
        if (nome == this.nome) invalidate()
    }

    /** La densità dell'immagine che si usa adesso (quella che MapLibre usava per scalarla), o 0. */
    fun densitaImmagine(): Int = immagini[nome]?.density ?: 0

    /**
     * Il segnaposto in ([x], [y]) sullo schermo, girato di [angolo] gradi,
     * grande [scala] volte l'immagine, schiacciato di [schiaccia] in verticale.
     * Si ridisegna solo se cambia qualcosa che si vede.
     */
    fun metti(nome: String, x: Float, y: Float, angolo: Float, scala: Float, schiaccia: Float) {
        if (visibile && nome == this.nome && abs(x - this.x) < 0.05f && abs(y - this.y) < 0.05f &&
            abs(angolo - this.angolo) < 0.05f && abs(scala - this.scala) < 0.001f && abs(schiaccia - this.schiaccia) < 0.001f
        ) {
            return
        }
        this.nome = nome
        this.x = x
        this.y = y
        this.angolo = angolo
        this.scala = scala
        this.schiaccia = schiaccia
        visibile = true
        invalidate()
    }

    fun nascondi() {
        if (!visibile) return
        visibile = false
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (!visibile) return
        val b = immagini[nome] ?: immagini["freccia"] ?: return
        matrice.reset()
        matrice.postTranslate(-b.width / 2f, -b.height / 2f)
        matrice.postRotate(angolo)
        matrice.postScale(scala, scala * schiaccia)
        matrice.postTranslate(x, y)
        canvas.drawBitmap(b, matrice, pennello)
    }
}
