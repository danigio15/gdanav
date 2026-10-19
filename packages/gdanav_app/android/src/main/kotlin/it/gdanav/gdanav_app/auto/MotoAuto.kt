package it.gdanav.gdanav_app.auto

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * L'auto che scorre sullo schermo dell'auto, fra una posizione e l'altra: il
 * conto di `MotoFluido` (gdanav_core, con le sue prove), rifatto qui coi suoi
 * numeri. Lì la spiegazione; in breve:
 *
 *  - fra due posizioni l'auto va avanti da sola con la velocità e la curva
 *    dell'ultima, al più per [OLTRE_AL_PIU_S];
 *  - lungo la strada la freccia ha una velocità sua, quella dell'auto più o
 *    meno quanto serve a recuperare lo scarto in [TAU_LUNGO_S], che cambia
 *    piano ([TAU_VELOCITA_S]) e non scende mai sotto un quarto di quella
 *    dell'auto: andando non si ferma e non torna indietro;
 *  - di lato e nella direzione insegue con la costante [TAU_S];
 *  - da fermi rallenta fino al punto, e se il punto è appena dietro resta.
 *
 * In guida il telefono manda con la posizione un pezzo del percorso (la
 * pista): allora la freccia scorre **sopra la linea**, inseguendo i metri
 * fatti invece di un punto, come `MotoSullaStrada` in gdanav_core. Dal campo:
 * «non segue la strada agli svincoli e rotonde, l'auto va fuori strada» — la
 * previsione tirava dritto (o girava come prima) per un secondo e mezzo, e
 * allo svincolo finiva nel prato.
 *
 * Niente oggetti nuovi a ogni fotogramma: lo stato sta in numeri, e quello che
 * si disegna si legge da [lat], [lon], [rotta] e [rottaMappa].
 */
internal class MotoAuto {
    /** Dove è disegnata l'auto, e girata come (gradi da nord). */
    var lat = 0.0
        private set
    var lon = 0.0
        private set
    var rotta = 0.0
        private set

    /** Dove guarda la mappa (in guida un po' avanti), portata avanti come la freccia. */
    var rottaMappa = 0.0
        private set

    /** La velocità della freccia adesso, in m/s. */
    var velocitaMostrata = 0.0
        private set

    /** Non servono più fotogrammi finché non arriva una posizione nuova. */
    var fermo = true
        private set

    /** Se c'è già qualcosa da disegnare. */
    var mostrata = false
        private set

    private var haFix = false
    private var fixLat = 0.0
    private var fixLon = 0.0
    private var fixRotta = 0.0
    private var fixRottaMappa = 0.0
    private var fixVelocita = 0.0
    private var fixGira = 0.0
    private var fixNs = 0L
    private var ultimoNs = 0L

    // La pista: il pezzo di percorso, coi metri cumulati; [mostrataM] i
    // metri a cui è disegnata la freccia, [fixM] quelli dell'ultima posizione.
    private var suPista = false
    private var pistaLat = DoubleArray(0)
    private var pistaLon = DoubleArray(0)
    private var pistaCum = DoubleArray(0)
    private var fixM = 0.0
    private var mostrataM = 0.0
    private var aLat = 0.0
    private var aLon = 0.0

    // La previsione di adesso: si riempie in [prevedi], senza oggetti.
    private var pLat = 0.0
    private var pLon = 0.0
    private var pRotta = 0.0
    private var pRottaMappa = 0.0

    /** L'ultima posizione: per sapere se una nuova lo è davvero. */
    fun stessaPosizione(lat: Double, lon: Double) = haFix && lat == fixLat && lon == fixLon

    /**
     * Una posizione nuova: [rotta] quella della strada (della freccia),
     * [rottaMappa] dove guarda la mappa, [velocitaMs] lungo la strada, [adessoNs]
     * sull'orologio dei fotogrammi (`System.nanoTime`).
     */
    fun posizione(
        lat: Double,
        lon: Double,
        rotta: Double,
        rottaMappa: Double,
        velocitaMs: Double,
        adessoNs: Long,
        pista: DoubleArray? = null,
        pistaQui: Double = 0.0,
    ) {
        val passo = (adessoNs - fixNs) / 1e9
        fixGira = if (haFix && velocitaMs >= 2.0 && passo >= 0.2 && passo <= 3.0) {
            (giro(fixRotta, rotta) / passo).coerceIn(-GIRA_AL_PIU, GIRA_AL_PIU)
        } else if (!haFix || passo > 0.2) {
            0.0
        } else {
            fixGira
        }
        haFix = true
        fixLat = lat
        fixLon = lon
        fixRotta = rotta
        fixRottaMappa = rottaMappa
        fixVelocita = if (velocitaMs.isFinite() && velocitaMs > 0.0) velocitaMs else 0.0
        fixNs = adessoNs
        fermo = false
        if (pista == null) {
            suPista = false
            return
        }
        prendiPista(pista)
        // La freccia si ritrova sul pezzo nuovo dov'era; se non c'è, si salta.
        if (mostrata) {
            val lontano = proietta(this.lat, this.lon)
            if (lontano > RITROVATA_ENTRO_M) dimentica()
        }
        suPista = true
        fixM = pistaQui.coerceIn(0.0, pistaCum.last())
    }

    private fun prendiPista(pista: DoubleArray) {
        val n = pista.size / 2
        pistaLat = DoubleArray(n) { pista[2 * it] }
        pistaLon = DoubleArray(n) { pista[2 * it + 1] }
        pistaCum = DoubleArray(n)
        val coslat = cos(Math.toRadians(pistaLat[0]))
        for (i in 1 until n) {
            val dx = (pistaLon[i] - pistaLon[i - 1]) * METRI_PER_GRADO * coslat
            val dy = (pistaLat[i] - pistaLat[i - 1]) * METRI_PER_GRADO
            pistaCum[i] = pistaCum[i - 1] + sqrt(dx * dx + dy * dy)
        }
    }

    /** Proietta un punto sulla pista: mette i metri in [mostrataM], dà quanto è lontano. */
    private fun proietta(lat: Double, lon: Double): Double {
        val kx = METRI_PER_GRADO * cos(Math.toRadians(lat))
        var migliore = Double.MAX_VALUE
        for (i in 1 until pistaLat.size) {
            val ax = (pistaLon[i - 1] - lon) * kx
            val ay = (pistaLat[i - 1] - lat) * METRI_PER_GRADO
            val dx = (pistaLon[i] - lon) * kx - ax
            val dy = (pistaLat[i] - lat) * METRI_PER_GRADO - ay
            val l2 = dx * dx + dy * dy
            val t = if (l2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / l2).coerceIn(0.0, 1.0)
            val px = ax + t * dx
            val py = ay + t * dy
            val d = sqrt(px * px + py * py)
            if (d < migliore) {
                migliore = d
                mostrataM = pistaCum[i - 1] + t * (pistaCum[i] - pistaCum[i - 1])
            }
        }
        return migliore
    }

    /** Il punto della pista a [metri], in [aLat] e [aLon]. */
    private fun puntoA(metri: Double) {
        val c = pistaCum
        val m = metri.coerceIn(0.0, c.last())
        var basso = 1
        var alto = c.size - 1
        while (basso < alto) {
            val mezzo = (basso + alto) ushr 1
            if (c[mezzo] < m) basso = mezzo + 1 else alto = mezzo
        }
        val j = basso
        val f = if (c[j] == c[j - 1]) 0.0 else ((m - c[j - 1]) / (c[j] - c[j - 1])).coerceIn(0.0, 1.0)
        aLat = pistaLat[j - 1] + f * (pistaLat[j] - pistaLat[j - 1])
        aLon = pistaLon[j - 1] + f * (pistaLon[j] - pistaLon[j - 1])
    }

    /** La freccia sulla pista a [metri]: il punto, e la direzione della strada lì (vedi `sullaStrada`). */
    private fun sullaPista(metri: Double) {
        val l = pistaCum.last()
        var da = metri - MEZZA_CORDA_M
        var a = metri + MEZZA_CORDA_M
        if (a > l) {
            da -= a - l
            a = l
        }
        if (da < 0) {
            a = min(l, a - da)
            da = 0.0
        }
        puntoA(da)
        val daLat = aLat
        val daLon = aLon
        puntoA(a)
        val est = (aLon - daLon) * METRI_PER_GRADO * cos(Math.toRadians(daLat))
        val nord = (aLat - daLat) * METRI_PER_GRADO
        if (est * est + nord * nord > 1e-4) rotta = norma(Math.toDegrees(atan2(est, nord)))
        puntoA(metri)
        lat = aLat
        lon = aLon
    }

    /** Dove l'auto dovrebbe essere ad [adessoNs], in metri sulla pista. */
    private fun metaPista(adessoNs: Long): Double {
        if (fixVelocita < FERMO_SOTTO_MS) return fixM
        val t = ((adessoNs - fixNs) / 1e9).coerceIn(0.0, OLTRE_AL_PIU_S)
        return (fixM + fixVelocita * t).coerceIn(0.0, pistaCum.last())
    }

    /** Si ricomincia: la prossima volta si disegna dov'è, senza inseguire. */
    fun dimentica() {
        mostrata = false
        velocitaMostrata = 0.0
    }

    /** Si va subito lì (il volo di ritorno sull'auto, un salto). */
    fun salta(adessoNs: Long) {
        if (!haFix) return
        prevedi(adessoNs)
        if (suPista) {
            mostrataM = metaPista(adessoNs)
            sullaPista(mostrataM)
        } else {
            lat = pLat
            lon = pLon
            rotta = pRotta
        }
        rottaMappa = pRottaMappa
        velocitaMostrata = if (andando(adessoNs)) fixVelocita else 0.0
        ultimoNs = adessoNs
        mostrata = true
    }

    private fun andando(adessoNs: Long) = fixVelocita >= FERMO_SOTTO_MS && (adessoNs - fixNs) / 1e9 < OLTRE_AL_PIU_S

    /** La previsione: l'ultima posizione portata avanti fino ad [adessoNs]. */
    private fun prevedi(adessoNs: Long) {
        pLat = fixLat
        pLon = fixLon
        pRotta = fixRotta
        pRottaMappa = fixRottaMappa
        if (fixVelocita < FERMO_SOTTO_MS) return
        val t = ((adessoNs - fixNs) / 1e9).coerceIn(0.0, OLTRE_AL_PIU_S)
        val r0 = Math.toRadians(fixRotta)
        val w = Math.toRadians(fixGira)
        val est: Double
        val nord: Double
        if (abs(w) < 1e-4) {
            est = fixVelocita * t * sin(r0)
            nord = fixVelocita * t * cos(r0)
        } else {
            val r1 = r0 + w * t
            est = fixVelocita / w * (cos(r0) - cos(r1))
            nord = fixVelocita / w * (sin(r1) - sin(r0))
        }
        pLat = fixLat + nord / METRI_PER_GRADO
        pLon = fixLon + est / (METRI_PER_GRADO * cos(Math.toRadians(fixLat)))
        pRotta = norma(fixRotta + fixGira * t)
        pRottaMappa = norma(fixRottaMappa + fixGira * t)
    }

    /** Un fotogramma ad [adessoNs]. `false` se non c'è ancora niente da disegnare. */
    fun fotogramma(adessoNs: Long): Boolean {
        if (!haFix) return false
        prevedi(adessoNs)
        if (suPista) return fotogrammaSullaPista(adessoNs)
        val coslat = cos(Math.toRadians(lat))
        val dx = (pLon - lon) * METRI_PER_GRADO * coslat
        val dy = (pLat - lat) * METRI_PER_GRADO
        val vaAvanti = andando(adessoNs)
        if (!mostrata || sqrt(dx * dx + dy * dy) > SALTO_M) {
            salta(adessoNs)
            fermo = !vaAvanti
            return true
        }
        val dt = ((adessoNs - ultimoNs) / 1e9).coerceIn(0.0, FOTOGRAMMA_AL_PIU_S)
        ultimoNs = adessoNs
        val r = Math.toRadians(pRotta)
        val ve = sin(r)
        val vn = cos(r)
        val lungo = dx * ve + dy * vn
        val lato = dx * vn - dy * ve
        val k = if (dt <= 0.0) 0.0 else 1 - exp(-dt / TAU_S)
        val kv = if (dt <= 0.0) 0.0 else 1 - exp(-dt / TAU_VELOCITA_S)
        var arrivata = false
        val avanti: Double
        if (vaAvanti) {
            val minima = fixVelocita * ALMENO_DELLA_VELOCITA
            val massima = max(fixVelocita * 2, fixVelocita + 10)
            val scarto = lungo - velocitaMostrata * dt
            val voluta = (fixVelocita + scarto / TAU_LUNGO_S).coerceIn(minima, massima)
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if (velocitaMostrata < minima) velocitaMostrata = minima
            avanti = velocitaMostrata * dt
        } else if (lungo < 0 && lungo > -INDIETRO_AL_PIU_M) {
            velocitaMostrata = 0.0
            avanti = 0.0
            arrivata = abs(lato) < 0.3
        } else if (lungo < 0) {
            velocitaMostrata = 0.0
            avanti = lungo * k
        } else {
            val voluta = lungo / TAU_LUNGO_S * 2
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if (velocitaMostrata < 0) velocitaMostrata = 0.0
            avanti = min(velocitaMostrata * dt, lungo)
            arrivata = lungo - avanti < 0.3 && abs(lato) < 0.3
            if (arrivata) velocitaMostrata = 0.0
        }
        val diLato = lato * k
        val est = avanti * ve + diLato * vn
        val nord = avanti * vn - diLato * ve
        lat += nord / METRI_PER_GRADO
        lon += est / (METRI_PER_GRADO * coslat)
        rotta = verso(rotta, pRotta, k)
        rottaMappa = verso(rottaMappa, pRottaMappa, k)
        fermo = !vaAvanti && arrivata && abs(giro(rotta, pRotta)) < 0.5 && abs(giro(rottaMappa, pRottaMappa)) < 0.5
        return true
    }

    /** Il fotogramma in guida: lungo la pista, coi conti di sopra su un numero solo. */
    private fun fotogrammaSullaPista(adessoNs: Long): Boolean {
        val meta = metaPista(adessoNs)
        val vaAvanti = andando(adessoNs)
        if (!mostrata || abs(meta - mostrataM) > SALTO_M) {
            salta(adessoNs)
            fermo = !vaAvanti
            return true
        }
        val dt = ((adessoNs - ultimoNs) / 1e9).coerceIn(0.0, FOTOGRAMMA_AL_PIU_S)
        ultimoNs = adessoNs
        val lungo = meta - mostrataM
        val k = if (dt <= 0.0) 0.0 else 1 - exp(-dt / TAU_S)
        val kv = if (dt <= 0.0) 0.0 else 1 - exp(-dt / TAU_VELOCITA_S)
        var arrivata = false
        val avanti: Double
        if (vaAvanti) {
            val minima = fixVelocita * ALMENO_DELLA_VELOCITA
            val massima = max(fixVelocita * 2, fixVelocita + 10)
            val scarto = lungo - velocitaMostrata * dt
            val voluta = (fixVelocita + scarto / TAU_LUNGO_S).coerceIn(minima, massima)
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if (velocitaMostrata < minima) velocitaMostrata = minima
            avanti = velocitaMostrata * dt
        } else if (lungo < 0 && lungo > -INDIETRO_AL_PIU_M) {
            velocitaMostrata = 0.0
            avanti = 0.0
            arrivata = true
        } else if (lungo < 0) {
            velocitaMostrata = 0.0
            avanti = lungo * k
        } else {
            val voluta = lungo / TAU_LUNGO_S * 2
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if (velocitaMostrata < 0) velocitaMostrata = 0.0
            avanti = min(velocitaMostrata * dt, lungo)
            arrivata = lungo - avanti < 0.3
            if (arrivata) velocitaMostrata = 0.0
        }
        mostrataM = (mostrataM + avanti).coerceIn(0.0, pistaCum.last())
        sullaPista(mostrataM)
        rottaMappa = verso(rottaMappa, pRottaMappa, k)
        fermo = !vaAvanti && arrivata && abs(giro(rottaMappa, pRottaMappa)) < 0.5
        return true
    }

    companion object {
        /** I numeri di `MotoFluido` (gdanav_core). */
        const val TAU_S = 0.2
        const val TAU_LUNGO_S = 1.0
        const val TAU_VELOCITA_S = 0.25
        const val OLTRE_AL_PIU_S = 1.5
        const val SALTO_M = 120.0
        const val FERMO_SOTTO_MS = 0.5
        const val GIRA_AL_PIU = 45.0
        const val ALMENO_DELLA_VELOCITA = 0.25
        const val INDIETRO_AL_PIU_M = 8.0
        const val FOTOGRAMMA_AL_PIU_S = 0.25
        const val METRI_PER_GRADO = 111195.08

        /** Come `MotoSullaStrada.ritrovataEntroM` e `mezzaCordaM`. */
        const val RITROVATA_ENTRO_M = 15.0
        const val MEZZA_CORDA_M = 6.0

        /** Di quanto si gira da [da] ad [a], fra -180 e 180. */
        fun giro(da: Double, a: Double): Double = ((a - da + 540.0) % 360.0 + 360.0) % 360.0 - 180.0

        /** Da un angolo all'altro per la via più corta, di una parte [t]. */
        fun verso(da: Double, a: Double, t: Double): Double = norma(da + giro(da, a) * t)

        fun norma(g: Double): Double = (g % 360.0 + 360.0) % 360.0
    }
}
