package it.gdanav.gdanav_app.musica

/**
 * Quale app della musica parte con ▶ quando nessuna suona: solo conti,
 * niente di Android qui dentro, così si provano da soli
 * (`android/src/test/kotlin/.../musica/SceltaAppProva.kt`).
 *
 * La scelta si fa nelle impostazioni «Casa e musica in guida» («App della
 * musica») e vale:
 *
 * - un pacchetto: quell'app, finché è installata;
 * - [ULTIMA]: l'ultima che ha suonato (la ricorda [AvvioMusica] quando una
 *   sessione suona), e se non se ne sa nessuna Spotify;
 * - niente (di serie): Spotify se è installata, se no l'ultima che ha
 *   suonato.
 *
 * Se non resta niente (nessuna scelta valida, niente Spotify, nessuna app
 * che abbia mai suonato) `null`: ▶ propone la scelta sul telefono.
 */
object SceltaApp {
    const val SPOTIFY = "com.spotify.music"

    /** La scelta «l'ultima che ha suonato». */
    const val ULTIMA = "ultima"

    /**
     * L'app che parte. [installate]: le app che si possono far partire (chi
     * offre un `MediaBrowserService`, più l'ultima se è ancora sul telefono).
     */
    fun effettiva(scelta: String?, ultima: String?, installate: Collection<String>): String? {
        val ultimaValida = ultima?.takeIf { it in installate }
        val spotify = SPOTIFY.takeIf { it in installate }
        return when {
            scelta == ULTIMA -> ultimaValida ?: spotify
            scelta != null && scelta in installate -> scelta
            else -> spotify ?: ultimaValida
        }
    }

    /** L'elenco nelle impostazioni: Spotify per prima, poi per nome; ognuna una volta. */
    fun <T> ordina(elenco: List<T>, pacchetto: (T) -> String, nome: (T) -> String): List<T> =
        elenco.distinctBy(pacchetto).sortedWith(
            compareBy<T>({ pacchetto(it) != SPOTIFY }, { nome(it).lowercase() }, { pacchetto(it) }),
        )

    /** «Avvio Spotify…», o «Avvio…» se non si sa quale. */
    fun testoAvvio(nome: String?): String = if (nome.isNullOrBlank()) "Avvio…" else "Avvio $nome…"

    /**
     * Il messaggio se dopo l'attesa non suona niente. [dallAuto]: chiesto
     * dallo schermo dell'auto (lì non si apre mai l'app). [aperta]: sul
     * telefono, da fermi, si è aperta l'app. [daFermi]: chi l'ha chiesto era
     * fermo.
     */
    fun testoNonPartita(nome: String?, dallAuto: Boolean, aperta: Boolean, daFermi: Boolean): String = when {
        nome.isNullOrBlank() ->
            if (dallAuto) "Scegli l'app della musica sul telefono, da fermo" else "Scegli l'app della musica"
        aperta -> "Ho aperto $nome: premi ▶ lì"
        dallAuto -> "$nome non è partito: aprilo sul telefono quando sei fermo"
        !daFermi -> "$nome non è partito: aprilo quando sei fermo"
        else -> "$nome non è partito"
    }

    /**
     * Il messaggio quando una playlist della casa ([titolo]) non è partita
     * nell'app [nome]: dall'auto mai «aprila» se non da fermi sul telefono.
     */
    fun testoPlaylistNonPartita(titolo: String, nome: String?, dallAuto: Boolean, aperta: Boolean): String {
        val dove = nome?.takeIf { it.isNotBlank() }?.let { "in $it" } ?: "nell'app"
        return when {
            aperta -> "Ho aperto «$titolo» $dove: premi ▶ lì"
            dallAuto -> "«$titolo» non è partita $dove: aprila sul telefono quando sei fermo"
            else -> "«$titolo» non è partita $dove"
        }
    }
}
