package it.gdanav.gdanav_app.musica

import it.gdanav.gdanav_app.musica.SceltaApp.SPOTIFY
import it.gdanav.gdanav_app.musica.SceltaApp.ULTIMA

/*
 * Le prove di [SceltaApp]: quale app della musica parte con ▶ quando niente
 * suona, e cosa si dice. Come quelle della disposizione del lettore, un
 * `main` che si ferma al primo conto sbagliato, col solo compilatore Kotlin:
 *
 *   kotlinc SceltaApp.kt SceltaAppProva.kt -include-runtime -d prova.jar
 *   java -cp prova.jar it.gdanav.gdanav_app.musica.SceltaAppProvaKt
 */

private var prove = 0

private fun <T> uguale(cosa: String, avuto: T, atteso: T) {
    prove++
    check(avuto == atteso) { "NON VA: $cosa — avuto $avuto, atteso $atteso" }
}

private const val YT = "com.google.android.apps.youtube.music"
private const val RADIO = "it.esempio.radio"

fun main() {
    val tutte = listOf(YT, SPOTIFY, RADIO)
    val senzaSpotify = listOf(YT, RADIO)

    // --- di serie (nessuna scelta) ---------------------------------------
    uguale("di serie: Spotify se c'è", SceltaApp.effettiva(null, null, tutte), SPOTIFY)
    uguale("di serie: Spotify anche se l'ultima è un'altra", SceltaApp.effettiva(null, YT, tutte), SPOTIFY)
    uguale("di serie senza Spotify: l'ultima", SceltaApp.effettiva(null, RADIO, senzaSpotify), RADIO)
    uguale("di serie senza Spotify né ultima: niente (si propone la scelta)", SceltaApp.effettiva(null, null, senzaSpotify), null)
    uguale("di serie: l'ultima disinstallata non vale", SceltaApp.effettiva(null, "via.di.qui", senzaSpotify), null)
    uguale("nessuna app installata", SceltaApp.effettiva(null, null, emptyList()), null)

    // --- una scelta --------------------------------------------------------
    uguale("scelta: quella", SceltaApp.effettiva(YT, SPOTIFY, tutte), YT)
    uguale("scelta disinstallata: di serie, Spotify", SceltaApp.effettiva("via.di.qui", null, tutte), SPOTIFY)
    uguale("scelta disinstallata, senza Spotify: l'ultima", SceltaApp.effettiva("via.di.qui", YT, senzaSpotify), YT)
    uguale("«l'ultima»: l'ultima", SceltaApp.effettiva(ULTIMA, YT, tutte), YT)
    uguale("«l'ultima» senza ultima: Spotify", SceltaApp.effettiva(ULTIMA, null, tutte), SPOTIFY)
    uguale("«l'ultima» senza ultima né Spotify: niente", SceltaApp.effettiva(ULTIMA, null, senzaSpotify), null)

    // --- l'elenco: Spotify per prima, poi per nome, senza doppioni --------
    val elenco = listOf(YT to "YouTube Music", RADIO to "aRadio", SPOTIFY to "Spotify", YT to "YouTube Music")
    uguale(
        "l'elenco in ordine",
        SceltaApp.ordina(elenco, { it.first }, { it.second }).map { it.first },
        listOf(SPOTIFY, RADIO, YT),
    )

    // --- i testi --------------------------------------------------------------
    uguale("avvio", SceltaApp.testoAvvio("Spotify"), "Avvio Spotify…")
    uguale("avvio senza nome", SceltaApp.testoAvvio(null), "Avvio…")
    uguale(
        "non partito, dall'auto: mai aprire, da fermo sul telefono",
        SceltaApp.testoNonPartita("Spotify", dallAuto = true, aperta = false, daFermi = false),
        "Spotify non è partito: aprilo sul telefono quando sei fermo",
    )
    uguale(
        "non partito, telefono in marcia",
        SceltaApp.testoNonPartita("Spotify", dallAuto = false, aperta = false, daFermi = false),
        "Spotify non è partito: aprilo quando sei fermo",
    )
    uguale(
        "telefono da fermi: aperta l'app",
        SceltaApp.testoNonPartita("Spotify", dallAuto = false, aperta = true, daFermi = true),
        "Ho aperto Spotify: premi ▶ lì",
    )
    uguale(
        "dall'auto senza app: scegliere sul telefono",
        SceltaApp.testoNonPartita(null, dallAuto = true, aperta = false, daFermi = false),
        "Scegli l'app della musica sul telefono, da fermo",
    )

    println("SceltaApp: $prove conti, tutti giusti")
}
