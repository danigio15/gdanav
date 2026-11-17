package it.gdanav.gdanav_app.musica

import android.content.Context
import android.graphics.Bitmap

/**
 * Le radio e le playlist della casa per lo schermo dell'auto (Android Auto:
 * Menu › Musica di casa). L'elenco lo chiede il telefono alla casa
 * (`GestoreMusicaDiCasa` in `lib/componenti/musica_di_casa.dart`) e lo manda
 * qui già in ordine (le ultime suonate per prime: guidando l'auto taglia le
 * liste lunghe) e con **dove suona** ogni voce, deciso là ([Dove]).
 *
 * Il tocco ([tocca]): una radio, o un flusso già risolto, suona subito qui
 * ([LettoreDiCasa]); una playlist di Spotify parte nell'app senza aprirla
 * ([AvvioMusica.suonaNellApp]); il resto (un file da firmare adesso, una
 * playlist da far partire sui lettori di casa) lo fa il telefono, che parla
 * con la casa, e torna il messaggio da dire.
 */
object MusicaDiCasa {
    /** Dove suona una voce, come l'ha deciso il telefono (`DoveSuona`). */
    enum class Dove { IN_AUTO, NELL_APP, APRI_DA_FERMO, SOLO_IN_CASA }

    class Voce(
        val id: String,
        val radio: Boolean,
        val titolo: String,
        val provenienza: String,
        val lettore: String?,
        val immagine: Bitmap?,
        val immagineByte: ByteArray?,
        val dove: Dove,
        val flusso: String?,
        val mime: String?,
        val uri: String?,
        val cerca: String?,
        val app: String?,
    )

    @Volatile var radio: List<Voce> = emptyList()
        private set

    @Volatile var playlist: List<Voce> = emptyList()
        private set

    /** L'id dell'ultima suonata, per «Riprendi». */
    @Volatile var ultima: String? = null
        private set

    /** Si cambia a ogni elenco nuovo: gli schermi dell'auto si rifanno. */
    @Volatile var versione = 0
        private set

    /** Se il telefono ha mai mandato un elenco (dentro GdAHome). */
    val conosciuta: Boolean get() = versione > 0

    private val immagini = HashMap<String, Pair<ByteArray, Bitmap?>>()

    /** L'elenco dal telefono: `{radio: [...], playlist: [...], ultima}`. */
    fun aggiorna(grezzo: Any?) {
        val m = grezzo as? Map<*, *> ?: return
        fun voci(l: Any?): List<Voce> = (l as? List<*>).orEmpty().mapNotNull { voce(it) }
        radio = voci(m["radio"])
        playlist = voci(m["playlist"])
        ultima = m["ultima"] as? String
        versione++
    }

    fun voce(grezzo: Any?): Voce? {
        val v = grezzo as? Map<*, *> ?: return null
        fun testo(k: String) = (v[k] as? String)?.takeIf { it.isNotBlank() }
        val id = testo("id") ?: return null
        val titolo = testo("titolo") ?: return null
        val byte = v["immagine"] as? ByteArray
        return Voce(
            id = id,
            radio = v["tipo"] == "radio",
            titolo = titolo,
            provenienza = testo("provenienza") ?: "",
            lettore = testo("lettore"),
            immagine = byte?.let { immagineDi(id, it) },
            immagineByte = byte,
            dove = when (v["dove"]) {
                "inAuto" -> Dove.IN_AUTO
                "nellApp" -> Dove.NELL_APP
                "apriDaFermo" -> Dove.APRI_DA_FERMO
                else -> Dove.SOLO_IN_CASA
            },
            flusso = testo("flusso")?.takeIf { it.startsWith("https://") },
            mime = testo("mime"),
            uri = testo("uri"),
            cerca = testo("cerca"),
            app = testo("app"),
        )
    }

    /** L'immagine si rifà solo se cambia: l'elenco torna uguale a ogni giro. */
    private fun immagineDi(id: String, byte: ByteArray): Bitmap? {
        immagini[id]?.let { (b, img) -> if (b.contentEquals(byte)) return img }
        val img = LettoreDiCasa.immagine(byte)
        immagini[id] = byte to img
        return img
    }

    private fun flusso(v: Voce) = LettoreDiCasa.Flusso(
        id = v.id,
        titolo = v.titolo,
        sotto = if (v.radio) "In diretta" else v.provenienza,
        url = v.flusso ?: "",
        mime = v.mime,
        immagine = v.immagine,
        immagineByte = v.immagineByte,
    )

    /** Le radio che suonano qui, nell'ordine dell'elenco. */
    fun radioDaSuonare(): List<LettoreDiCasa.Flusso> =
        radio.filter { it.dove == Dove.IN_AUTO && it.flusso != null }.map(::flusso)

    /** Una voce per id, fra radio e playlist. */
    fun trova(id: String): Voce? = radio.firstOrNull { it.id == id } ?: playlist.firstOrNull { it.id == id }

    /**
     * Una voce toccata sullo schermo dell'auto. [risposta]: il messaggio da
     * dire (un `CarToast`), quando c'è; `null` se è partita senza bisogno di
     * dirlo. Dall'auto un'app non si apre mai.
     */
    fun tocca(context: Context, id: String, risposta: (String?) -> Unit) {
        val v = trova(id) ?: return risposta("Non c'è più: riapri l'elenco")
        when {
            v.dove == Dove.IN_AUTO && v.radio && v.flusso != null -> {
                val tutte = radioDaSuonare()
                risposta(LettoreDiCasa.suona(context, tutte, tutte.indexOfFirst { it.id == v.id }.coerceAtLeast(0), null, true))
            }
            v.dove == Dove.IN_AUTO && v.flusso != null -> risposta(LettoreDiCasa.suona(context, listOf(flusso(v)), 0, null, false))
            v.dove == Dove.NELL_APP && v.app != null -> {
                AvvioMusica.suonaNellApp(context, v.app, v.uri, v.cerca ?: v.titolo, v.titolo, dallAuto = true, daFermi = false)
                risposta(null)
            }
            v.dove == Dove.APRI_DA_FERMO -> risposta("Si apre sul telefono, da fermo")
            // Un flusso da firmare adesso, o «solo in casa»: lo fa il telefono.
            else -> if (!LettoreTelefono.chiediAlTelefono(id, risposta)) risposta("Il telefono non risponde: riprova")
        }
    }

    /** Solo per le fotografie. */
    fun perLeFoto(radio: List<Voce>, playlist: List<Voce>, ultima: String?) {
        this.radio = radio
        this.playlist = playlist
        this.ultima = ultima
        versione++
    }
}
