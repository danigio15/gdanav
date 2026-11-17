package it.gdanav.gdanav_app.auto

import it.gdanav.gdanav_app.auto.DisposizioneMusica.Disposta
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Forma
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Riq
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Spazio
import it.gdanav.gdanav_app.auto.DisposizioneMusica.Zona

/*
 * Le prove di [DisposizioneMusica]: dove sta il lettore musicale sulla mappa
 * dell'auto e su quale tasto cade un tocco. Niente librerie: un `main` che si
 * ferma al primo conto sbagliato, così si lancia col solo compilatore Kotlin
 * (Gradle qui non compila i file dell'auto senza l'SDK di Android):
 *
 *   kotlinc DisposizioneMusica.kt DisposizioneMusicaProva.kt -include-runtime -d prova.jar
 *   java -cp prova.jar it.gdanav.gdanav_app.auto.DisposizioneMusicaProvaKt
 */

private var prove = 0

private fun vero(cosa: String, v: Boolean) {
    prove++
    check(v) { "NON VA: $cosa" }
}

private fun <T> uguale(cosa: String, avuto: T, atteso: T) {
    prove++
    check(avuto == atteso) { "NON VA: $cosa — avuto $avuto, atteso $atteso" }
}

/**
 * Uno schermo largo [largo] e alto [alto] punti a densità [k]: i tasti in
 * alto finiscono a 92 punti, a destra 78 punti di tasti della mappa, margine
 * di 10. Con [schede], la colonna delle schede di Android Auto a sinistra
 * (340 punti) è tolta dall'area libera, non da quella stabile.
 */
private fun schermo(
    largo: Float,
    alto: Float = 653f,
    k: Float = 1.5f,
    schede: Boolean = false,
    aDestra: List<Riq> = emptyList(),
    sopra: List<Riq> = emptyList(),
    ostacoli: List<Riq> = emptyList(),
) = Spazio(
    sinistra = ((if (schede) 340f else 0f) + 10f) * k,
    alto = (92f + 10f) * k,
    destra = (largo - 78f - 10f) * k,
    basso = (alto - 10f) * k,
    centroX = (largo - 78f) / 2f * k,
    larghezza = (largo - 78f) * k,
    k = k,
    aDestra = aDestra,
    sopra = sopra,
    ostacoli = ostacoli,
)

private fun disponi(
    s: Spazio,
    conBrano: Boolean = true,
    ridotto: Boolean = false,
    comandabile: Boolean = true,
    etichettaDp: Float = 0f,
) = DisposizioneMusica.disponi(s, conBrano, ridotto, comandabile, etichettaDp)

/** Quello che deve valere per ogni lettore disposto, qualunque forma abbia. */
private fun regole(nome: String, d: Disposta, s: Spazio) {
    val k = s.k
    val minimo = DisposizioneMusica.TOCCO_DP * k - 0.01f
    vero("$nome: sta nello spazio", d.box.l >= s.sinistra - 0.01f && d.box.r <= s.destra + 0.01f && d.box.t >= s.alto - 0.01f && d.box.b <= s.basso + 0.01f)
    for ((zona, r) in d.zone) {
        vero("$nome: $zona larga almeno 76 punti (${r.w / k})", r.w >= minimo)
        vero("$nome: $zona alta almeno 76 punti (${r.h / k})", r.h >= minimo)
        // Il tocco al centro della zona è di quel tasto; e anche negli angoli.
        uguale("$nome: il centro di $zona", DisposizioneMusica.tocco(d, r.cx, r.cy), zona)
        uguale("$nome: l'angolo in alto a sinistra di $zona", DisposizioneMusica.tocco(d, r.l + 1f, r.t + 1f), zona)
        uguale("$nome: l'angolo in basso a destra di $zona", DisposizioneMusica.tocco(d, r.r - 1f, r.b - 1f), zona)
        // La zona non esce dal lettore (la pillola: di quattro punti sopra e sotto).
        val fuori = if (d.forma == Forma.PILLOLA) 4f * k + 0.01f else 0.01f
        vero("$nome: $zona dentro il lettore", r.l >= d.box.l - 0.01f && r.r <= d.box.r + 0.01f && r.t >= d.box.t - fuori && r.b <= d.box.b + fuori)
    }
    // Nessun punto appartiene a due tasti.
    val zone = d.zone
    for (i in zone.indices) for (j in i + 1 until zone.size) {
        vero("$nome: ${zone[i].first} e ${zone[j].first} non si sovrappongono", !zone[i].second.tocca(zone[j].second))
    }
    // La copertina e la barra stanno dentro il lettore.
    vero("$nome: la copertina dentro", d.copertina.l >= d.box.l && d.copertina.r <= d.box.r && d.copertina.t >= d.box.t && d.copertina.b <= d.box.b)
    d.avanzamento?.let { vero("$nome: la barra dentro", it.l >= d.box.l && it.r <= d.box.r && it.t > d.copertina.b && it.b < (d.playPausa?.t ?: d.box.b)) }
    // Fuori dal lettore il tocco è della mappa.
    uguale("$nome: a sinistra del lettore", DisposizioneMusica.tocco(d, d.box.l - 6f * k, d.box.cy), Zona.FUORI)
    uguale("$nome: sotto il lettore", DisposizioneMusica.tocco(d, d.box.cx, d.box.b + 6f * k), Zona.FUORI)
    uguale("$nome: sopra il lettore", DisposizioneMusica.tocco(d, d.box.cx, d.box.t - 6f * k), Zona.FUORI)
    uguale("$nome: a destra del lettore", DisposizioneMusica.tocco(d, d.box.r + 1f, d.box.cy), Zona.FUORI)
}

fun main() {
    // --- lo schermo largo: aperto, coi tre tasti e la linguetta ----------
    for (k in listOf(1f, 1.5f, 2f, 2.625f)) {
        val s = schermo(1333f, k = k)
        val d = disponi(s)!!
        uguale("largo, k=$k: la forma", d.forma, Forma.APERTO)
        uguale("largo, k=$k: largo 380 punti", d.box.w / k, 380f)
        uguale("largo, k=$k: alto 192 punti", d.box.h / k, 192f)
        uguale("largo, k=$k: in alto a destra", d.box.r to d.box.t, s.destra to s.alto)
        uguale("largo, k=$k: le zone", d.zone.map { it.first }, listOf(Zona.PRECEDENTE, Zona.PLAY_PAUSA, Zona.SUCCESSIVO, Zona.LINGUETTA))
        regole("largo, k=$k", d, s)
        // I tre tasti, uno accanto all'altro, da sinistra.
        vero("largo, k=$k: ⏮ ⏯ ⏭ da sinistra", d.precedente!!.cx < d.playPausa!!.cx && d.playPausa!!.cx < d.successivo!!.cx)
        // La copertina, il titolo, la barra: il tocco è del lettore, e non fa niente.
        uguale("largo, k=$k: sulla copertina", DisposizioneMusica.tocco(d, d.copertina.cx, d.copertina.cy), Zona.PANNELLO)
        uguale("largo, k=$k: sul titolo", DisposizioneMusica.tocco(d, d.testoX + 20f * k, d.lineaTitolo!! - 5f * k), Zona.PANNELLO)
        uguale("largo, k=$k: sulla barra", DisposizioneMusica.tocco(d, d.avanzamento!!.cx, d.avanzamento!!.cy), Zona.PANNELLO)
        // Le stesse misure in punti a ogni densità: cambia solo la scala.
        val uno = disponi(schermo(1333f, k = 1f))!!
        vero("largo, k=$k: come a densità 1, per k", kotlin.math.abs(d.playPausa!!.cx - uno.playPausa!!.cx * k) < 0.01f && kotlin.math.abs(d.box.l - uno.box.l * k) < 0.01f)
    }

    // --- quale forma, secondo lo spazio ---------------------------------
    // 960 punti: aperto, largo il 38% dell'area stabile.
    disponi(schermo(960f, 460f, 1f)).let { d ->
        uguale("960: aperto", d?.forma, Forma.APERTO)
        vero("960: largo 335 punti", kotlin.math.abs(d!!.box.w - 882f * 0.38f) < 0.01f)
        regole("960", d, schermo(960f, 460f, 1f))
    }
    // 800 punti: l'aperto prenderebbe troppa mappa.
    for (largo in listOf(830f, 800f, 760f)) {
        val s = schermo(largo, schede = true)
        val d = disponi(s)
        uguale("$largo: compatto", d?.forma, Forma.COMPATTO)
        regole("$largo", d!!, s)
        uguale("$largo: le zone", d.zone.map { it.first }, listOf(Zona.PLAY_PAUSA, Zona.SUCCESSIVO, Zona.LINGUETTA))
        vero("$largo: a destra del mezzo (la strada davanti all'auto)", d.box.l >= s.centroX + 20f * s.k - 0.01f)
        uguale("$largo: sulla copertina si richiude", DisposizioneMusica.tocco(d, d.copertina.cx, d.copertina.cy), Zona.LINGUETTA)
        uguale("$largo: sul titolo niente", DisposizioneMusica.tocco(d, d.box.cx, d.box.t + 20f * s.k), Zona.PANNELLO)
    }
    // Stretta: la pillola (che può stare sopra la strada lontana).
    for (largo in listOf(640f, 520f, 400f, 260f)) {
        val s = schermo(largo)
        val d = disponi(s)
        uguale("$largo: pillola", d?.forma, Forma.PILLOLA)
        regole("$largo", d!!, s)
        uguale("$largo: le zone", d.zone.map { it.first }, listOf(Zona.PLAY_PAUSA, Zona.LINGUETTA))
        uguale("$largo: sulla copertina si riapre", DisposizioneMusica.tocco(d, d.copertina.cx, d.copertina.cy), Zona.LINGUETTA)
    }
    // Strettissima: niente.
    uguale("230: niente", disponi(schermo(230f)), null)
    // Bassa: sotto i tasti non c'è altezza nemmeno per la pillola.
    uguale("alta 170: niente", disponi(schermo(1333f, alto = 170f)), null)
    uguale("alta 200: la pillola", disponi(schermo(1333f, alto = 200f))?.forma, Forma.PILLOLA)
    uguale("alta 300: il compatto", disponi(schermo(1333f, alto = 300f))?.forma, Forma.COMPATTO)

    // --- richiuso, senza brano, senza tocchi -----------------------------
    val largo = schermo(1333f)
    disponi(largo, ridotto = true)!!.let { d ->
        uguale("richiuso: pillola", d.forma, Forma.PILLOLA)
        uguale("richiuso: in alto a destra", d.box.r to d.box.t, largo.destra to largo.alto)
        regole("richiuso", d, largo)
    }
    disponi(largo, conBrano = false)!!.let { d ->
        uguale("senza brano: pillola", d.forma, Forma.PILLOLA)
        uguale("senza brano: solo ▶", d.zone.map { it.first }, listOf(Zona.PLAY_PAUSA))
        // Tutta la pillola fa partire la musica, anche la nota.
        uguale("senza brano: anche sulla nota ▶", DisposizioneMusica.tocco(d, d.copertina.cx, d.copertina.cy), Zona.PLAY_PAUSA)
        uguale("senza brano, senza nome: larga 156 punti", d.box.w / largo.k, 156f)
        uguale("senza brano, senza nome: niente testo", d.lineaTitolo, null)
        vero("senza brano: ▶ disegnato a destra", d.discoPlay!!.r == d.box.r && d.discoPlay!!.w / largo.k == 76f)
        regole("senza brano", d, largo)
    }
    // «▶ Spotify»: il nome dell'app allarga la pillola verso sinistra, resta
    // in alto a destra, e tutta è il tasto.
    for (k in listOf(1f, 1.5f, 2.625f)) {
        val s = schermo(1333f, k = k)
        val d = disponi(s, conBrano = false, etichettaDp = 70f)!!
        uguale("▶ Spotify, k=$k: pillola", d.forma, Forma.PILLOLA)
        uguale("▶ Spotify, k=$k: larga 156 + 70 punti", d.box.w / k, 226f)
        uguale("▶ Spotify, k=$k: in alto a destra", d.box.r to d.box.t, s.destra to s.alto)
        uguale("▶ Spotify, k=$k: un solo tasto, tutto", d.zone.single().second.let { it.l to it.r }, d.box.l to d.box.r)
        vero("▶ Spotify, k=$k: il nome fra l'icona e ▶", d.testoX >= d.copertina.r && d.testoX + d.testoLargo <= d.discoPlay!!.l + 0.01f)
        vero("▶ Spotify, k=$k: il nome a metà altezza", d.lineaTitolo!! > d.box.cy && d.lineaTitolo!! < d.box.b)
        uguale("▶ Spotify, k=$k: sul nome ▶", DisposizioneMusica.tocco(d, d.testoX + 10f * k, d.box.cy), Zona.PLAY_PAUSA)
        regole("▶ Spotify, k=$k", d, s)
    }
    // Un nome lunghissimo si ferma a 170 punti (poi i puntini, li mette il disegno).
    uguale(
        "▶ nome lungo: al più 156 + 170 punti",
        disponi(largo, conBrano = false, etichettaDp = 400f)!!.box.w / largo.k,
        326f,
    )
    // Dove il nome non ci sta, la pillola col solo ▶.
    schermo(400f, alto = 300f).let { s ->
        val d = disponi(s, conBrano = false, etichettaDp = 160f)!!
        uguale("▶ stretto: resta la pillola", d.forma, Forma.PILLOLA)
        uguale("▶ stretto: senza nome", d.box.w / s.k to d.lineaTitolo, 156f to null)
        regole("▶ stretto", d, s)
    }
    // Col brano il nome non cambia niente.
    uguale("col brano l'etichetta non conta", disponi(largo, etichettaDp = 70f)!!.forma, Forma.APERTO)
    disponi(largo, comandabile = false)!!.let { d ->
        uguale("senza tocchi: solo il brano", d.forma, Forma.SOLO_BRANO)
        uguale("senza tocchi: nessun tasto", d.zone.size, 0)
        vero("senza tocchi: non si comanda", !d.coiTasti)
        uguale("senza tocchi: largo 330 punti", d.box.w / largo.k, 330f)
    }
    uguale("senza tocchi e senza brano: niente", disponi(largo, conBrano = false, comandabile = false), null)
    uguale("nessun lettore disposto: il tocco è della mappa", DisposizioneMusica.tocco(null, 100f, 100f), Zona.FUORI)

    // --- la striscia del traffico: il lettore le sta a sinistra ----------
    val k = 1.5f
    val tubo = Riq(1209f * k, 102f * k, 1241f * k, 643f * k)
    schermo(1333f, schede = true, aDestra = listOf(tubo)).let { s ->
        val d = disponi(s)!!
        uguale("striscia: aperto", d.forma, Forma.APERTO)
        uguale("striscia: otto punti a sinistra della striscia", d.box.r, tubo.l - 8f * k)
        regole("striscia", d, s.copy(destra = tubo.l - 8f * k))
    }
    // Un'etichetta all'altezza del lettore lo sposta ancora; una più in basso no.
    val etichettaAlta = Riq(1120f * k, 200f * k, 1201f * k, 240f * k)
    val etichettaBassa = Riq(1120f * k, 400f * k, 1201f * k, 440f * k)
    uguale("etichetta alta: a sinistra dell'etichetta", disponi(schermo(1333f, schede = true, aDestra = listOf(tubo, etichettaAlta)))!!.box.r, etichettaAlta.l - 8f * k)
    uguale("etichetta bassa: non conta", disponi(schermo(1333f, schede = true, aDestra = listOf(tubo, etichettaBassa)))!!.box.r, tubo.l - 8f * k)
    // Appena sotto il lettore (a meno di otto punti) conta ancora.
    val etichettaSotto = Riq(1120f * k, (102f + 192f + 4f) * k, 1201f * k, 340f * k)
    uguale("etichetta appena sotto: conta", disponi(schermo(1333f, schede = true, aDestra = listOf(tubo, etichettaSotto)))!!.box.r, etichettaSotto.l - 8f * k)

    // --- l'avviso in alto al centro: il lettore gli va sotto se lo tocca --
    val avvisoLontano = Riq(500f * k, 102f * k, 760f * k, 164f * k)
    uguale("avviso lontano: il lettore non si muove", disponi(schermo(1333f, sopra = listOf(avvisoLontano)))!!.box.t, largo.alto)
    val avvisoVicino = Riq(700f * k, 102f * k, 1000f * k, 164f * k)
    disponi(schermo(1333f, sopra = listOf(avvisoVicino)))!!.let { d ->
        uguale("avviso vicino: aperto", d.forma, Forma.APERTO)
        uguale("avviso vicino: otto punti sotto l'avviso", d.box.t, avvisoVicino.b + 8f * k)
        vero("avviso vicino: non lo tocca", !d.box.tocca(avvisoVicino))
    }

    // --- quello che non si copre mai --------------------------------------
    // A mezzo schermo il tachimetro e la barra dei dati stanno sotto: il
    // lettore non scende su di loro.
    val barraDati = Riq(10f * k, 300f * k, 300f * k, 354f * k)
    val tachimetro = Riq(10f * k, 362f * k, 190f * k, 454f * k)
    schermo(480f, alto = 464f, ostacoli = listOf(barraDati, tachimetro)).let { s ->
        val d = disponi(s)!!
        vero("mezzo schermo: non tocca la barra dei dati", !d.box.tocca(barraDati, 8f * k))
        vero("mezzo schermo: non tocca il tachimetro", !d.box.tocca(tachimetro, 8f * k))
    }
    val barraAlta = Riq(10f * k, 150f * k, 300f * k, 204f * k)
    uguale("la barra dei dati dove starebbe la pillola: niente", disponi(schermo(380f, alto = 300f, ostacoli = listOf(barraAlta))), null)
    // La colonna dell'avviso di casa (400 punti da sinistra).
    fun colonna(alto: Float) = Riq(0f, 0f, 400f * k, alto * k)
    uguale("avviso di casa, schermo largo: resta aperto", disponi(schermo(1333f, schede = true, ostacoli = listOf(colonna(653f))))?.forma, Forma.APERTO)
    uguale("avviso di casa, 830: resta compatto", disponi(schermo(830f, schede = true, ostacoli = listOf(colonna(653f))))?.forma, Forma.COMPATTO)
    uguale("avviso di casa, 640: non c'è posto", disponi(schermo(640f, schede = true, ostacoli = listOf(colonna(653f)))), null)

    println("DisposizioneMusica: $prove conti, tutti giusti")
}
