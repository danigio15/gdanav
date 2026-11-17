package it.gdanav.gdanav_app.musica

/*
 * Le prove di [MusicaDiCasa]: l'elenco della musica di casa come lo manda il
 * telefono allo schermo dell'auto (dove suona ogni voce), quali radio suonano
 * qui (solo quelle in auto, con un flusso https), e il brano che il pannello
 * dell'auto mostra mentre suona una radio di casa ([LettoreDiCasa]).
 * Stazioni e playlist inventate. Come le altre prove, un `main` che si ferma
 * al primo conto sbagliato; ha bisogno delle classi di Android (finte, sul
 * banco) perché legge le immagini.
 */

/* Un `object` col suo `main`: nello stesso pacchetto c'è già quello di
 * `SceltaAppProva`, e due `main` in cima al file si scontrerebbero. */
object MusicaDiCasaProva {
    private var prove = 0

    private fun <T> uguale(cosa: String, avuto: T, atteso: T) {
        prove++
        check(avuto == atteso) { "NON VA: $cosa — avuto $avuto, atteso $atteso" }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        MusicaDiCasa.aggiorna(
            mapOf(
                "radio" to listOf(
                    mapOf("id" to "r2", "tipo" to "radio", "titolo" to "Onda Vesuviana", "dove" to "inAuto", "flusso" to "https://f.esempio.it/2"),
                    mapOf("id" to "r1", "tipo" to "radio", "titolo" to "Radio Lungomare", "dove" to "inAuto", "flusso" to "https://f.esempio.it/1"),
                    // Solo in chiaro: non suona qui.
                    mapOf("id" to "r3", "tipo" to "radio", "titolo" to "Radio Collina 98", "dove" to "soloInCasa"),
                    // Un indirizzo in chiaro non passa nemmeno se dice «in auto».
                    mapOf("id" to "r4", "tipo" to "radio", "titolo" to "In chiaro", "dove" to "inAuto", "flusso" to "http://f.esempio.it/4"),
                    mapOf("tipo" to "radio", "titolo" to "Senza id"),
                ),
                "playlist" to listOf(
                    mapOf(
                        "id" to "p1", "tipo" to "playlist", "titolo" to "Viaggio in auto", "provenienza" to "Spotify",
                        "dove" to "nellApp", "uri" to "spotify:playlist:1", "app" to "com.spotify.music",
                    ),
                    mapOf(
                        "id" to "p2", "tipo" to "playlist", "titolo" to "Cena tranquilla", "provenienza" to "Sonos",
                        "lettore" to "Sonos Soggiorno", "dove" to "soloInCasa",
                    ),
                    mapOf("id" to "p9", "tipo" to "playlist", "titolo" to "Dove sconosciuto", "dove" to "boh"),
                ),
                "ultima" to "r2",
            ),
        )
        uguale("le radio, nell'ordine del telefono, senza le rotte", MusicaDiCasa.radio.map { it.id }, listOf("r2", "r1", "r3", "r4"))
        uguale("le playlist", MusicaDiCasa.playlist.map { it.id }, listOf("p1", "p2", "p9"))
        uguale("l'ultima", MusicaDiCasa.ultima, "r2")
        uguale("conosciuta: c'è il tasto nel Menu", MusicaDiCasa.conosciuta, true)
        uguale("dove: nell'app", MusicaDiCasa.trova("p1")?.dove, MusicaDiCasa.Dove.NELL_APP)
        uguale("dove: solo in casa", MusicaDiCasa.trova("p2")?.dove, MusicaDiCasa.Dove.SOLO_IN_CASA)
        uguale("dove sconosciuto: solo in casa (nessuna promessa)", MusicaDiCasa.trova("p9")?.dove, MusicaDiCasa.Dove.SOLO_IN_CASA)
        uguale("il lettore di casa", MusicaDiCasa.trova("p2")?.lettore, "Sonos Soggiorno")
        uguale("il flusso in chiaro si butta", MusicaDiCasa.trova("r4")?.flusso, null)
        uguale(
            "suonano qui solo le radio in auto con un flusso https",
            MusicaDiCasa.radioDaSuonare().map { it.id },
            listOf("r2", "r1"),
        )
        uguale("sotto la radio: in diretta", MusicaDiCasa.radioDaSuonare().first().sotto, "In diretta")

        // Il brano per il pannello dell'auto, mentre suona una radio di casa.
        val radio = MusicaDiCasa.radioDaSuonare()
        LettoreDiCasa.perLeFoto(radio, 1, radio = true, suona = true, inOnda = null)
        val b = LettoreDiCasa.brano()!!
        uguale("l'app", b.app, "Radio di casa")
        uguale("il titolo", b.titolo, "Radio Lungomare")
        uguale("sotto, senza i metadati: in diretta", b.artista, "In diretta")
        uguale("in diretta: niente durata", b.durataMs, 0L)
        uguale("⏮ ⏭ fra le preferite", b.puoPrecedente && b.puoSuccessivo, true)
        LettoreDiCasa.perLeFoto(radio, 1, radio = true, suona = true, inOnda = "Le Lucciole - Strade di notte")
        uguale("cosa trasmette, se lo dice", LettoreDiCasa.brano()?.artista, "Le Lucciole - Strade di notte")
        LettoreDiCasa.perLeFoto(radio.take(1), 0, radio = true, suona = false, inOnda = null)
        uguale("una sola radio: ⏮ ⏭ spenti", LettoreDiCasa.brano()?.puoSuccessivo, false)
        uguale("in pausa", LettoreDiCasa.brano()?.suona, false)
        LettoreDiCasa.perLeFoto(emptyList(), 0, radio = true, suona = false, inOnda = null)
        uguale("niente di casa: niente brano", LettoreDiCasa.brano(), null)

        println("MusicaDiCasa: $prove conti, tutti giusti")
        System.exit(0)
    }
}
