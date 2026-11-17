package it.gdanav.gdanav_app.auto

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Disposta
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Forma
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Riq
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Zona
import it.gdanav.gdanav_app.musica.LettoreTelefono
import kotlin.math.roundToInt

/**
 * Dove stanno i comandi della musica sull'auto: nel lettore disegnato sulla
 * mappa ([PannelloAuto], che si tocca) o fra i tasti in alto
 * ([SchermoNavigazione.azioni]). Mai in tutti e due.
 *
 * Il lettore sulla mappa si comanda col dito solo se l'auto manda i tocchi
 * (`SurfaceCallback.onClick`, dall'API 5 dell'auto, e non su tutte: una con
 * la sola manopola non ne manda). Non c'è modo di chiederlo prima: lo si
 * impara. Finché non si è visto un tocco su quest'auto ([tocchi]) i tasti
 * restano anche in alto, come prima; al primo tocco (uno qualsiasi, anche
 * sulla mappa) se ne vanno, e si ricorda. Su un'auto dove si entra nel modo
 * «sposta» (la manopola) senza averne mai visto uno, il lettore torna quello
 * da guardare, coi tasti in alto.
 *
 * Si tocca solo dal filo principale.
 */
object MusicaInAuto {
    /** Dall'API 5 l'auto può mandare i tocchi sulla mappa. */
    @Volatile var api5 = false

    /** Su quest'auto si è visto un tocco sulla mappa (anche in un viaggio di prima). */
    @Volatile var tocchi = false

    /** Un tocco visto in questa sessione: l'auto di adesso li manda di sicuro. */
    @Volatile var tocchiOra = false

    /** L'auto non manda tocchi (si è usata la manopola senza averne mai visto uno). */
    @Volatile var senzaTocchi = false

    /** Richiuso a pillola da chi guida: vale per la sessione. */
    @Volatile var ridotto = false

    /**
     * L'ultima volta che si è disegnato, il lettore coi tasti c'era. Se non
     * ha posto (la mappa strettissima, un avviso di casa sopra) i tasti
     * tornano in alto finché non torna lui.
     */
    @Volatile var inVista = true

    /** Il lettore sulla mappa si disegna coi tasti. */
    val coiTasti: Boolean get() = api5 && !senzaTocchi

    /** I comandi stanno nel lettore sulla mappa: in alto non servono. */
    val nelLettore: Boolean get() = coiTasti && tocchi && inVista

    /** Finita la sessione sull'auto: la prossima può essere un'altra auto. */
    fun fineSessione() {
        ridotto = false
        inVista = true
        tocchiOra = false
        senzaTocchi = false
    }
}

/**
 * Disegna il lettore musicale disposto da [DisposizioneMusica]: lo sfondo
 * scuro (di notte con un filo chiaro intorno, che lo stacca dalla mappa
 * scura), la copertina tagliata al centro con gli angoli tondi, i testi su
 * una riga con i puntini, la barra del brano e i tasti. I tasti sono disegni
 * (non caratteri: ⏮ ⏯ ⏭ sul telefono sono emoji a colori).
 */
internal class DisegnoMusica(private val dp: (Float) -> Float) {
    private val pieno = Paint(Paint.ANTI_ALIAS_FLAG)
    private val filo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val immagine = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val grassetto = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)

    private fun font(sp: Float, forte: Boolean, colore: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = dp(sp)
        typeface = if (forte) grassetto else Typeface.DEFAULT
        color = colore
    }

    private val app = font(13f, true, Color.argb(175, 255, 255, 255))
    private val titolo = font(21f, true, Color.WHITE)
    private val titoloCompatto = font(19f, true, Color.WHITE)
    private val titoloSolo = font(20f, true, Color.WHITE)
    private val artista = font(17f, false, CHIARO)
    private val artistaSolo = font(15f, false, CHIARO)

    private fun RectF.metti(r: Riq): RectF {
        set(r.l, r.t, r.r, r.b)
        return this
    }

    private val rf = RectF()
    private val src = Rect()
    private val via = Path()

    /**
     * [premuta]: il tasto appena toccato, da accendere per un attimo.
     * [avanzamento]: quanta parte del brano è passata (0…1), `null` se non
     * si sa. Restituisce quanti pixel è lunga la parte piena della barra (0
     * se non c'è): chi ridisegna ogni secondo lo fa solo se cambia.
     */
    fun disegna(
        canvas: Canvas,
        d: Disposta,
        b: LettoreTelefono.Brano?,
        notte: Boolean,
        premuta: Zona?,
        avanzamento: Float?,
    ): Int {
        val box = d.box
        val raggio = if (d.forma == Forma.PILLOLA) box.h / 2f else dp(20f)
        pieno.color = if (notte) FONDO_NOTTE else FONDO_GIORNO
        canvas.drawRoundRect(rf.metti(box), raggio, raggio, pieno)
        if (notte) {
            filo.color = Color.argb(70, 255, 255, 255)
            filo.strokeWidth = dp(1.5f)
            canvas.drawRoundRect(rf.metti(box), raggio, raggio, filo)
        }
        copertina(canvas, d, b)

        val brano = b?.titolo?.ifEmpty { null } ?: if (b?.suona == true) "In riproduzione" else "In pausa"
        when (d.forma) {
            Forma.APERTO -> {
                b?.app?.takeIf { it.isNotEmpty() }?.let {
                    canvas.drawText(taglia(it.uppercase(), app, d.appLargo), d.testoX, d.lineaApp ?: 0f, app)
                }
                canvas.drawText(taglia(brano, titolo, d.testoLargo), d.testoX, d.lineaTitolo ?: 0f, titolo)
                b?.artista?.takeIf { it.isNotEmpty() }?.let {
                    canvas.drawText(taglia(it, artista, d.testoLargo), d.testoX, d.lineaArtista ?: 0f, artista)
                }
            }
            Forma.COMPATTO ->
                canvas.drawText(taglia(brano, titoloCompatto, d.testoLargo), d.testoX, d.lineaTitolo ?: 0f, titoloCompatto)
            Forma.SOLO_BRANO -> {
                canvas.drawText(taglia(brano, titoloSolo, d.testoLargo), d.testoX, d.lineaTitolo ?: 0f, titoloSolo)
                val sotto = listOf(b?.artista ?: "", b?.app ?: "").filter { it.isNotEmpty() }.joinToString(" · ")
                if (sotto.isNotEmpty()) {
                    canvas.drawText(taglia(sotto, artistaSolo, d.testoLargo), d.testoX, d.lineaArtista ?: 0f, artistaSolo)
                }
            }
            Forma.PILLOLA -> {}
        }

        var pienaPx = 0
        d.avanzamento?.let { barra ->
            pieno.color = Color.argb(60, 255, 255, 255)
            canvas.drawRoundRect(rf.metti(barra), barra.h / 2f, barra.h / 2f, pieno)
            if (avanzamento != null) {
                pienaPx = (barra.w * avanzamento.coerceIn(0f, 1f)).roundToInt()
                if (pienaPx > 0) {
                    pieno.color = AZZURRO
                    rf.set(barra.l, barra.t, barra.l + pienaPx.toFloat().coerceAtLeast(barra.h), barra.b)
                    canvas.drawRoundRect(rf, barra.h / 2f, barra.h / 2f, pieno)
                }
            }
        }

        d.precedente?.let { salto(canvas, it, avanti = false, acceso = b?.puoPrecedente != false, premuto = premuta == Zona.PRECEDENTE) }
        d.successivo?.let { salto(canvas, it, avanti = true, acceso = b?.puoSuccessivo != false, premuto = premuta == Zona.SUCCESSIVO) }
        d.playPausa?.let {
            playPausa(
                canvas,
                it,
                suona = b?.suona == true,
                acceso = b?.puoPlayPausa != false,
                premuto = premuta == Zona.PLAY_PAUSA,
                diametro = dp(if (d.forma == Forma.APERTO) 60f else 54f),
            )
        }
        d.freccia?.let { linguetta(canvas, d, it, premuta == Zona.LINGUETTA) }
        return pienaPx
    }

    /** La copertina, tagliata al centro (un'immagine larga non si schiaccia); senza, una nota. */
    private fun copertina(canvas: Canvas, d: Disposta, b: LettoreTelefono.Brano?) {
        val dove = rf.metti(d.copertina)
        val raggio = if (d.forma == Forma.PILLOLA) dove.width() / 2f else dp(10f)
        val cop: Bitmap? = b?.copertina
        if (cop != null && !cop.isRecycled && cop.width > 0 && cop.height > 0) {
            val lato = minOf(cop.width, cop.height)
            val x0 = (cop.width - lato) / 2
            val y0 = (cop.height - lato) / 2
            src.left = x0
            src.top = y0
            src.right = x0 + lato
            src.bottom = y0 + lato
            val salva = canvas.save()
            via.reset()
            via.addRoundRect(dove, raggio, raggio, Path.Direction.CW)
            canvas.clipPath(via)
            canvas.drawBitmap(cop, src, dove, immagine)
            canvas.restoreToCount(salva)
            return
        }
        pieno.color = Color.rgb(43, 96, 222)
        canvas.drawRoundRect(dove, raggio, raggio, pieno)
        nota(canvas, dove.centerX(), dove.centerY(), dove.width() * 0.5f)
    }

    /** Una nota musicale bianca, alta [lato], col centro in ([cx], [cy]). */
    private fun nota(canvas: Canvas, cx: Float, cy: Float, lato: Float) {
        pieno.color = Color.WHITE
        val u = lato / 10f
        // La testa, in basso a sinistra; il gambo; la bandierina.
        rf.set(cx - 3.6f * u, cy + 1.4f * u, cx + 0.6f * u, cy + 4.8f * u)
        canvas.drawOval(rf, pieno)
        canvas.drawRect(cx - 0.6f * u, cy - 4.6f * u, cx + 0.6f * u, cy + 3.2f * u, pieno)
        canvas.drawRect(cx - 0.6f * u, cy - 4.6f * u, cx + 3.6f * u, cy - 2.2f * u, pieno)
    }

    /** ⏯: un disco bianco col triangolo o le due barre scure. */
    private fun playPausa(canvas: Canvas, zona: Riq, suona: Boolean, acceso: Boolean, premuto: Boolean, diametro: Float) {
        val cx = zona.cx
        val cy = zona.cy
        val r = diametro / 2f
        pieno.color = when {
            !acceso -> Color.argb(70, 255, 255, 255)
            premuto -> AZZURRO
            else -> Color.WHITE
        }
        canvas.drawCircle(cx, cy, r, pieno)
        pieno.color = if (acceso) SCURO else Color.argb(150, 18, 22, 30)
        val s = r * 0.42f
        if (suona) {
            rf.set(cx - s, cy - s, cx - s * 0.28f, cy + s)
            canvas.drawRoundRect(rf, s * 0.16f, s * 0.16f, pieno)
            rf.set(cx + s * 0.28f, cy - s, cx + s, cy + s)
            canvas.drawRoundRect(rf, s * 0.16f, s * 0.16f, pieno)
        } else {
            via.reset()
            via.moveTo(cx - s * 0.72f, cy - s * 1.05f)
            via.lineTo(cx + s * 1.1f, cy)
            via.lineTo(cx - s * 0.72f, cy + s * 1.05f)
            via.close()
            canvas.drawPath(via, pieno)
        }
    }

    /** ⏮ o ⏭: un triangolo e una barra, bianchi; spento, quasi trasparente. */
    private fun salto(canvas: Canvas, zona: Riq, avanti: Boolean, acceso: Boolean, premuto: Boolean) {
        val cx = zona.cx
        val cy = zona.cy
        if (premuto && acceso) {
            pieno.color = Color.argb(64, 255, 255, 255)
            canvas.drawCircle(cx, cy, dp(34f), pieno)
        }
        pieno.color = if (acceso) Color.WHITE else Color.argb(80, 255, 255, 255)
        val s = dp(13f)
        val v = if (avanti) 1f else -1f
        via.reset()
        via.moveTo(cx - v * s, cy - s)
        via.lineTo(cx + v * s * 0.45f, cy)
        via.lineTo(cx - v * s, cy + s)
        via.close()
        canvas.drawPath(via, pieno)
        val x0 = cx + v * s * 0.62f
        val x1 = cx + v * s
        rf.set(minOf(x0, x1), cy - s, maxOf(x0, x1), cy + s)
        canvas.drawRoundRect(rf, dp(1.5f), dp(1.5f), pieno)
    }

    /**
     * La linguetta: aperto, una freccia in su nell'angolo (richiudi); sulla
     * copertina, un dischetto con la freccia (in su per richiudere, in giù
     * per riaprire).
     */
    private fun linguetta(canvas: Canvas, d: Disposta, dove: Riq, premuta: Boolean) {
        val cx = dove.cx
        val cy = dove.cy
        val r = dove.w / 2f
        if (d.forma == Forma.APERTO) {
            if (premuta) {
                pieno.color = Color.argb(64, 255, 255, 255)
                canvas.drawCircle(cx, cy, r + dp(4f), pieno)
            }
            filo.color = CHIARO
        } else {
            pieno.color = if (premuta) AZZURRO else Color.WHITE
            canvas.drawCircle(cx, cy, r, pieno)
            filo.color = SCURO
        }
        filo.strokeWidth = dp(if (d.forma == Forma.APERTO) 3f else 2.5f)
        val s = r * if (d.forma == Forma.APERTO) 0.5f else 0.42f
        // In su per richiudere (va verso i tasti in alto), in giù per riaprire.
        val v = if (d.forma == Forma.PILLOLA) 1f else -1f
        via.reset()
        via.moveTo(cx - s, cy - v * s * 0.5f)
        via.lineTo(cx, cy + v * s * 0.5f)
        via.lineTo(cx + s, cy - v * s * 0.5f)
        canvas.drawPath(via, filo)
    }

    /** Taglia [s] coi puntini finché non sta in [spazio]: mai a capo. */
    private fun taglia(s: String, p: Paint, spazio: Float): String {
        if (p.measureText(s) <= spazio) return s
        var t = s
        while (t.length > 1 && p.measureText("$t…") > spazio) t = t.dropLast(1)
        return "${t.trimEnd()}…"
    }

    private companion object {
        val FONDO_GIORNO = Color.argb(240, 18, 22, 30)
        val FONDO_NOTTE = Color.argb(244, 30, 36, 48)
        val CHIARO = Color.rgb(205, 209, 216)
        val SCURO = Color.rgb(18, 22, 30)
        val AZZURRO = Color.rgb(58, 176, 255)
    }
}
