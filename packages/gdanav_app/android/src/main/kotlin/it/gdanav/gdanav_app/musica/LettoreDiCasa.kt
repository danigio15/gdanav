package it.gdanav.gdanav_app.musica

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Il lettore della musica di casa **in auto**: le radio preferite della casa
 * (e i brani di Home Assistant raggiungibili da fuori) suonano qui, nel
 * telefono, quindi nelle casse dell'auto; non sui lettori di casa.
 *
 * A suonare è ExoPlayer, dentro [ServizioLettoreDiCasa] (un
 * `MediaLibraryService` di media3): la sua sessione dà la notifica, chiede il
 * focus audio (un'altra app che parte la mette in pausa, una telefonata
 * pure), risponde ai tasti del volante e delle cuffie, e compare fra i
 * lettori di Android (e, se l'app dichiara la musica per Android Auto, nella
 * scheda della musica dell'auto). Qui si tiene un `MediaController` collegato
 * a quella sessione: è da lui che si comanda, e da lui si sa cosa suona.
 *
 * Le radio si passano tutte insieme ([suona]): ⏮ ⏭ (sul pannello, sul
 * volante) passano alla radio prima o dopo fra le preferite. Una radio in
 * diretta dice spesso cosa sta trasmettendo (i metadati ICY): si mostra al
 * posto di «In diretta» ([inOnda]).
 *
 * Lo leggono [LettoreTelefono] (che lo mette al posto del lettore delle altre
 * app mentre suona: il pannello sulla mappa dell'auto e il telefono non
 * cambiano) e gli schermi dell'auto. Si tocca dal filo principale.
 */
object LettoreDiCasa {
    /** Una voce da suonare: una radio, o un brano di una playlist di casa. */
    class Flusso(
        val id: String,
        val titolo: String,
        val sotto: String,
        val url: String,
        val mime: String?,
        val immagine: Bitmap?,
        /** L'immagine com'è arrivata (PNG o JPEG), per il telefono. */
        val immagineByte: ByteArray?,
    )

    @Volatile var voci: List<Flusso> = emptyList()
        private set

    /** Quale delle [voci] suona. */
    @Volatile var indice = 0
        private set

    /** Il nome della playlist, sotto il brano; `null` per le radio. */
    @Volatile var nome: String? = null
        private set

    /** Sono le radio preferite (⏮ ⏭ cambiano radio). */
    @Volatile var radio = false
        private set

    @Volatile var suona = false
        private set

    /** Si sta collegando o caricando il flusso. */
    @Volatile var carica = false
        private set

    /** Cosa trasmette adesso la radio («Artista - Brano»), se lo dice. */
    @Volatile var inOnda: String? = null
        private set

    /** Quanto dura il brano (0 per una radio). */
    @Volatile var durataMs = 0L
        private set

    /** Un flusso che non si è riusciti a suonare, da dire una volta. */
    @Volatile var errore: String? = null
        private set

    /** Se c'è qualcosa della casa da mostrare e comandare. */
    val attivo: Boolean get() = voci.isNotEmpty()

    val attuale: Flusso? get() = voci.getOrNull(indice)

    private val principale = Handler(Looper.getMainLooper())
    private val ascoltatori = CopyOnWriteArrayList<() -> Unit>()
    private var contesto: Context? = null
    private var futuro: ListenableFuture<MediaController>? = null
    private var controllore: MediaController? = null

    /** Quello da suonare appena il controllore è collegato. */
    private var daSuonare: Pair<List<MediaItem>, Int>? = null

    fun ascolta(f: () -> Unit) = ascoltatori.add(f)

    fun smetti(f: () -> Unit) = ascoltatori.remove(f)

    private fun avvisa() {
        for (f in ascoltatori) f()
    }

    /** Il brano come lo vede il pannello dell'auto ([LettoreTelefono]). */
    fun brano(): LettoreTelefono.Brano? {
        val f = attuale ?: return null
        val molte = voci.size > 1
        return LettoreTelefono.Brano(
            app = if (radio) "Radio di casa" else "Dalla casa",
            titolo = f.titolo,
            artista = inOnda?.takeIf { it.isNotBlank() } ?: nome ?: f.sotto,
            suona = suona || carica,
            copertina = f.immagine,
            durataMs = durataMs,
            puoPrecedente = molte,
            puoSuccessivo = molte,
            puoPlayPausa = true,
        )
    }

    /** L'immagine di una voce dai suoi byte, piccola (al più 256 punti). */
    fun immagine(byte: ByteArray?): Bitmap? {
        if (byte == null || byte.isEmpty()) return null
        return try {
            val misura = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(byte, 0, byte.size, misura)
            var passo = 1
            while (maxOf(misura.outWidth, misura.outHeight) / (passo * 2) >= 256) passo *= 2
            BitmapFactory.decodeByteArray(byte, 0, byte.size, BitmapFactory.Options().apply { inSampleSize = passo })
        } catch (_: Exception) {
            null
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    /** Le voci in [ServizioLettoreDiCasa]: l'indirizzo, il titolo, il logo. */
    internal fun elemento(f: Flusso, radio: Boolean): MediaItem {
        val m = MediaMetadata.Builder()
            .setTitle(f.titolo)
            .setArtist(f.sotto)
            .setStation(if (radio) f.titolo else null)
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setMediaType(if (radio) MediaMetadata.MEDIA_TYPE_RADIO_STATION else MediaMetadata.MEDIA_TYPE_MUSIC)
        f.immagineByte?.let { m.setArtworkData(it, MediaMetadata.PICTURE_TYPE_FRONT_COVER) }
        val b = MediaItem.Builder().setMediaId(f.id).setUri(f.url).setMediaMetadata(m.build())
        f.mime?.let { b.setMimeType(it) }
        return b.build()
    }

    /**
     * Fa suonare [voci] dalla [da]-esima: le radio preferite ([radio]) o i
     * brani di una playlist ([nome]). Torna `null`, o il messaggio se non si
     * può (niente da suonare).
     */
    fun suona(context: Context, voci: List<Flusso>, da: Int, nome: String?, radio: Boolean): String? {
        val buone = voci.filter { it.url.startsWith("https://") }
        if (buone.isEmpty()) return "Niente da suonare"
        val ctx = context.applicationContext
        contesto = ctx
        // La musica di casa prende il posto di un avvio a metà (▶ Spotify).
        AvvioMusica.annulla()
        this.voci = buone
        this.indice = da.coerceIn(0, buone.size - 1)
        this.nome = nome
        this.radio = radio
        inOnda = null
        errore = null
        durataMs = 0L
        carica = true
        suona = false
        avvisa()
        daSuonare = buone.map { elemento(it, radio) } to indice
        collega(ctx)
        return null
    }

    /** Ci si collega alla sessione del servizio (lo fa partire, se serve). */
    private fun collega(ctx: Context) {
        controllore?.let {
            suonaQuelloInAttesa(it)
            return
        }
        if (futuro != null) return
        val f = try {
            MediaController.Builder(ctx, SessionToken(ctx, ComponentName(ctx, ServizioLettoreDiCasa::class.java))).buildAsync()
        } catch (_: Exception) {
            null
        }
        if (f == null) {
            fallito("Il lettore non parte")
            return
        }
        futuro = f
        f.addListener(
            {
                val c = try {
                    f.get()
                } catch (_: Exception) {
                    null
                }
                futuro = null
                if (c == null) {
                    fallito("Il lettore non parte")
                    return@addListener
                }
                controllore = c
                c.addListener(richiamo)
                suonaQuelloInAttesa(c)
            },
            MoreExecutors.directExecutor(),
        )
    }

    private fun suonaQuelloInAttesa(c: MediaController) {
        val (elementi, da) = daSuonare ?: return
        daSuonare = null
        try {
            c.setMediaItems(elementi, da, 0L)
            c.prepare()
            c.play()
        } catch (_: Exception) {
            fallito("Il lettore non parte")
        }
    }

    private fun fallito(testo: String) {
        carica = false
        suona = false
        errore = testo
        avvisa()
    }

    private val richiamo = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            suona = isPlaying
            if (isPlaying) carica = false
            avvisa()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            carica = playbackState == Player.STATE_BUFFERING
            durataMs = controllore?.duration?.takeIf { it > 0L } ?: 0L
            avvisa()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            val i = controllore?.currentMediaItemIndex ?: return
            if (i in voci.indices) indice = i
            inOnda = null
            avvisa()
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            // Una radio dice cosa trasmette (ICY): il titolo cambia da quello
            // della stazione a «Artista - Brano».
            val t = mediaMetadata.title?.toString()?.trim()
            val stazione = attuale?.titolo
            val nuovo = t?.takeIf { it.isNotEmpty() && it != stazione }
            if (nuovo != inOnda) {
                inOnda = nuovo
                avvisa()
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            fallito("«${attuale?.titolo ?: "La radio"}» non si sente adesso")
        }
    }

    /** ⏯ ⏮ ⏭ dal pannello dell'auto o dal telefono. */
    fun comando(quale: String) {
        val c = controllore
        if (c == null) {
            contesto?.let { if (quale == "playPausa" && attivo) riprendi(it) }
            return
        }
        try {
            when (quale) {
                "playPausa" -> if (c.isPlaying) c.pause() else {
                    if (c.mediaItemCount == 0) contesto?.let { riprendi(it) } else c.play()
                }
                "successivo" -> if (voci.size > 1) c.seekToNextMediaItem()
                "precedente" -> if (voci.size > 1) c.seekToPreviousMediaItem()
            }
        } catch (_: Exception) {}
    }

    /** Si riprende quello che c'era (il servizio era stato chiuso). */
    private fun riprendi(ctx: Context) {
        suona(ctx, voci, indice, nome, radio)
    }

    /** A che punto è il brano (0 per una radio in diretta). Dal filo principale. */
    fun posizioneMs(): Long = try {
        if (durataMs > 0L) controllore?.currentPosition?.coerceIn(0L, durataMs) ?: 0L else 0L
    } catch (_: Exception) {
        0L
    }

    /** La musica di casa si ferma e se ne va dal pannello. */
    fun ferma() {
        try {
            controllore?.stop()
            controllore?.clearMediaItems()
        } catch (_: Exception) {}
        voci = emptyList()
        indice = 0
        suona = false
        carica = false
        inOnda = null
        avvisa()
    }

    /** L'errore è stato detto: non si ripete. */
    fun erroreDetto() {
        if (errore == null) return
        errore = null
        avvisa()
    }

    /** Solo per le fotografie: lo stato messo a mano, senza il servizio. */
    fun perLeFoto(voci: List<Flusso>, indice: Int, radio: Boolean, suona: Boolean, inOnda: String?) {
        this.voci = voci
        this.indice = indice
        this.radio = radio
        this.suona = suona
        this.carica = false
        this.inOnda = inOnda
        this.nome = null
    }
}
