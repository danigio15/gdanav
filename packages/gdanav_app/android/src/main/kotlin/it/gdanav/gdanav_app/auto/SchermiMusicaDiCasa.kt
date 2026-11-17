package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R
import it.gdanav.gdanav_app.musica.LettoreDiCasa
import it.gdanav.gdanav_app.musica.LettoreTelefono
import it.gdanav.gdanav_app.musica.MusicaDiCasa

/*
 * La musica di casa sullo schermo dell'auto: Menu › «Musica di casa» (il
 * tasto in alto nel Menu, che non toglie righe), poi «Radio di casa» o
 * «Playlist di casa». I passi dalla mappa: la mappa (1), il Menu (2), Musica
 * di casa (3), le radio o le playlist (4): sotto i cinque che Android Auto
 * concede. Toccata una voce si torna alla mappa (indietro non conta), dove
 * il lettore la mostra.
 *
 * Guidando l'auto taglia le liste lunghe (sei righe, di solito): per questo le
 * voci arrivano dal telefono già in ordine, le ultime suonate per prime.
 */

/** Il riquadro di una voce: il logo o la copertina, se c'è. */
private fun immagineDi(v: MusicaDiCasa.Voce): CarIcon? =
    v.immagine?.let { CarIcon.Builder(IconCompat.createWithBitmap(it)).build() }

/**
 * Uno schermo della musica di casa: si rifà quando cambia l'elenco o quello
 * che suona (li dice [LettoreTelefono], non il ponte della guida).
 */
abstract class SchermoDellaCasa(carContext: CarContext) : SchermoAggiornato(carContext) {
    private var vista: Any? = null
    private val cambio: () -> Unit = {
        val ora = firma()
        if (ora != vista) {
            vista = ora
            invalidate()
        }
    }

    override fun onCreate(owner: LifecycleOwner) {
        super.onCreate(owner)
        vista = firma()
        LettoreTelefono.ascolta(cambio)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        LettoreTelefono.smetti(cambio)
        super.onDestroy(owner)
    }

    /** Una voce toccata: parte (e si torna alla mappa), o il messaggio. */
    protected fun tocca(v: MusicaDiCasa.Voce) {
        val torna = v.dove == MusicaDiCasa.Dove.IN_AUTO || v.dove == MusicaDiCasa.Dove.NELL_APP
        MusicaDiCasa.tocca(carContext, v.id) { detto ->
            if (!detto.isNullOrBlank()) CarToast.makeText(carContext, detto, CarToast.LENGTH_LONG).show()
        }
        if (torna) screenManager.popToRoot()
    }

    /** Dove suona, detto sotto il titolo. */
    protected fun comeSuona(v: MusicaDiCasa.Voce): String = when (v.dove) {
        MusicaDiCasa.Dove.IN_AUTO -> listOf(v.provenienza.ifEmpty { null }, "suona qui").filterNotNull().joinToString(" · ")
        MusicaDiCasa.Dove.NELL_APP -> "${v.provenienza.ifEmpty { "App" }} · parte nell'app del telefono"
        MusicaDiCasa.Dove.APRI_DA_FERMO -> "${v.provenienza} · si apre sul telefono, da fermo"
        MusicaDiCasa.Dove.SOLO_IN_CASA ->
            "Tocca: parte in casa${v.lettore?.let { ", su $it" } ?: ""}"
    }
}

/**
 * «Musica di casa»: riprendi l'ultima, le radio, le playlist, e (se suona)
 * fermala. Tre o quattro righe: ci stanno anche guidando.
 */
class SchermoMusicaDiCasa(carContext: CarContext) : SchermoDellaCasa(carContext) {
    override fun firma(): Any? = listOf(MusicaDiCasa.versione, LettoreDiCasa.attivo, LettoreDiCasa.attuale?.id)

    override fun onCreate(owner: LifecycleOwner) {
        super.onCreate(owner)
        // L'elenco fresco dalla casa (lo chiede il telefono).
        LettoreTelefono.chiediAlTelefono("") {}
    }

    override fun schermata(): Template {
        val radio = MusicaDiCasa.radio
        val playlist = MusicaDiCasa.playlist
        val inAuto = playlist.count { it.dove != MusicaDiCasa.Dove.SOLO_IN_CASA }
        val ultima = MusicaDiCasa.ultima?.let { MusicaDiCasa.trova(it) }
        val righe = mutableListOf<Row>()
        if (ultima != null && LettoreDiCasa.attuale?.id != ultima.id) {
            righe += riga("Riprendi: ${ultima.titolo}", comeSuona(ultima), icona = immagineDi(ultima)) { tocca(ultima) }
        }
        if (radio.isNotEmpty()) {
            val soloInCasa = radio.count { it.dove != MusicaDiCasa.Dove.IN_AUTO }
            righe += riga(
                "Radio di casa",
                listOfNotNull(
                    "${radio.size} ${if (radio.size == 1) "stazione" else "stazioni"}",
                    if (soloInCasa < radio.size) "suonano qui in auto" else null,
                    soloInCasa.takeIf { it > 0 }?.let { "$it solo in casa" },
                ).joinToString(" · "),
                sfoglia = true,
                icona = icona(R.drawable.icona_radio, CarColor.BLUE),
            ) { screenManager.push(SchermoRadioDiCasa(carContext)) }
        }
        if (playlist.isNotEmpty()) {
            righe += riga(
                "Playlist di casa",
                listOf(
                    "${playlist.size} playlist",
                    if (inAuto > 0) "$inAuto in auto" else null,
                    (playlist.size - inAuto).takeIf { it > 0 }?.let { "$it solo in casa" },
                ).filterNotNull().joinToString(" · "),
                sfoglia = true,
                icona = icona(R.drawable.icona_playlist, CarColor.GREEN),
            ) { screenManager.push(SchermoPlaylistDiCasa(carContext)) }
        }
        if (LettoreDiCasa.attivo) {
            righe += riga("Ferma la musica di casa", LettoreDiCasa.attuale?.titolo, icona = icona(R.drawable.auto_pausa)) {
                LettoreDiCasa.ferma()
                screenManager.popToRoot()
            }
        }
        return elenco(
            "Musica di casa",
            righe,
            vuoto = if (MusicaDiCasa.conosciuta) {
                "Nella plancia non ci sono radio preferite né playlist"
            } else {
                "Chiedo alla casa…"
            },
        )
    }
}

/**
 * Le radio di casa, a griglia coi loghi: toccata una, suona qui (le altre con
 * ⏮ ⏭), e si torna alla mappa.
 */
class SchermoRadioDiCasa(carContext: CarContext) : SchermoDellaCasa(carContext) {
    override fun firma(): Any? = listOf(MusicaDiCasa.versione, LettoreDiCasa.attuale?.id)

    override fun schermata(): Template {
        val lista = ItemList.Builder().setNoItemsMessage("Nessuna radio preferita nella plancia")
        for (v in MusicaDiCasa.radio) {
            val g = GridItem.Builder().setTitle(v.titolo).setOnClickListener { tocca(v) }
            when {
                LettoreDiCasa.attuale?.id == v.id -> g.setText(if (LettoreDiCasa.suona) "In onda" else "In pausa")
                // Solo in chiaro (http), o che Radio Browser non ha: qui non suona.
                v.dove != MusicaDiCasa.Dove.IN_AUTO -> g.setText("Solo in casa")
            }
            g.setImage(immagineDi(v) ?: icona(R.drawable.icona_radio, CarColor.BLUE), GridItem.IMAGE_TYPE_LARGE)
            lista.addItem(g.build())
        }
        return GridTemplate.Builder()
            .setTitle("Radio di casa")
            .setHeaderAction(Action.BACK)
            .setSingleList(lista.build())
            .build()
    }
}

/**
 * Le playlist di casa: prima quelle che suonano in auto (Spotify nell'app del
 * telefono, i brani di Home Assistant qui), poi quelle **solo di casa**, con
 * scritto che il tocco le fa partire in casa, sul loro lettore.
 */
class SchermoPlaylistDiCasa(carContext: CarContext) : SchermoDellaCasa(carContext) {
    override fun firma(): Any? = MusicaDiCasa.versione

    override fun schermata(): Template {
        fun r(v: MusicaDiCasa.Voce): Row {
            val b = Row.Builder().setTitle(v.titolo).addText(comeSuona(v)).setOnClickListener { tocca(v) }
            immagineDi(v)?.let { b.setImage(it, Row.IMAGE_TYPE_LARGE) }
                ?: b.setImage(icona(R.drawable.icona_playlist, CarColor.GREEN), Row.IMAGE_TYPE_ICON)
            return b.build()
        }
        val (inCasa, inAuto) = MusicaDiCasa.playlist.partition { it.dove == MusicaDiCasa.Dove.SOLO_IN_CASA }
        if (inCasa.isEmpty() || inAuto.isEmpty()) {
            return elenco("Playlist di casa", MusicaDiCasa.playlist.map(::r), vuoto = "Nessuna playlist nei lettori di casa")
        }
        return sezioni(
            "Playlist di casa",
            listOf("In auto" to inAuto.map(::r), "Solo sui lettori di casa" to inCasa.map(::r)),
        )
    }
}
