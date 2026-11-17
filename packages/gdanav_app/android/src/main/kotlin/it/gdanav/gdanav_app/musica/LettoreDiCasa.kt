package it.gdanav.gdanav_app.musica

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import it.gdanav.gdanav_app.auto.PonteAuto
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Il lettore della musica di casa **in auto**: le radio preferite della casa
 * (e i brani di Home Assistant raggiungibili da fuori) suonano qui, nel
 * telefono, quindi nelle casse dell'auto; non sui lettori di casa.
 *
 * A suonare è ExoPlayer, **dentro il processo dell'app** e senza una
 * sessione multimediale esposta al sistema: niente servizio in primo piano,
 * niente notifica della musica, niente tasti del volante o delle cuffie,
 * niente scheda nella musica di Android Auto. Si comanda solo da GdANav: dal
 * pannello sulla mappa dell'auto (⏮ ⏯ ⏭ da toccare), dal telefono e dal Menu
 * «Musica di casa».
 *
 * Il focus audio lo chiede ExoPlayer (`setAudioAttributes(…, true)`: un
 * `AudioFocusRequest` come quello di una sessione): la voce del navigatore,
 * che chiede il focus per un attimo, la abbassa e poi la rialza; una
 * telefonata la mette in pausa e alla fine riparte; un'altra app che suona la
 * ferma. Staccate le cuffie o il Bluetooth dell'auto si ferma da sé.
 *
 * Senza servizio in primo piano il processo resta vivo finché qualcosa lo
 * tiene davanti: con Android Auto collegato lo schermo dell'auto
 * (`CarAppService` legato da Android Auto, e il servizio della posizione in
 * auto, `PosizioneInAuto`), sul telefono l'app aperta. Sul solo telefono,
 * con l'app dietro e l'auto staccata, Android lo congelerebbe o lo
 * chiuderebbe dopo un po', e la radio morirebbe a caso: allora la si mette in
 * pausa noi, dopo [ATTESA_SOTTOFONDO_MS], e lo si dice al ritorno
 * ([sottofondo]).
 *
 * Le radio si passano tutte insieme ([suona]): ⏮ ⏭ passano alla radio prima
 * o dopo fra le preferite. Una radio in diretta dice spesso cosa sta
 * trasmettendo (i metadati ICY): si mostra al posto di «In diretta»
 * ([inOnda]).
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

    /** Si sta caricando il flusso. */
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
    private var lettore: ExoPlayer? = null

    /** L'app sul telefono è davanti (la dice `GdanavAppPlugin`). */
    @Volatile private var telefonoDavanti = false

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

    /** Una voce per ExoPlayer: l'indirizzo e il titolo (per riconoscere i metadati ICY). */
    private fun elemento(f: Flusso): MediaItem {
        val b = MediaItem.Builder()
            .setMediaId(f.id)
            .setUri(f.url)
            .setMediaMetadata(MediaMetadata.Builder().setTitle(f.titolo).build())
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
        val l = lettore ?: crea(ctx) ?: run {
            fallito("Il lettore non parte")
            return null
        }
        try {
            l.setMediaItems(buone.map(::elemento), indice, 0L)
            l.prepare()
            l.play()
        } catch (_: Exception) {
            fallito("Il lettore non parte")
        }
        // Fatta partire con l'app dietro e senza l'auto: non resterebbe viva.
        sottofondo()
        return null
    }

    /** ExoPlayer, nel processo dell'app: il focus audio lo chiede lui, la sessione non c'è. */
    private fun crea(ctx: Context): ExoPlayer? = try {
        ExoPlayer.Builder(ctx)
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build()
            .also {
                it.addListener(richiamo)
                lettore = it
            }
    } catch (_: Exception) {
        null
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
            durataMs = lettore?.duration?.takeIf { it > 0L } ?: 0L
            avvisa()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            val i = lettore?.currentMediaItemIndex ?: return
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

    /** ⏯ ⏮ ⏭ dal pannello dell'auto, dal Menu o dal telefono: solo da GdANav. */
    fun comando(quale: String) {
        val l = lettore
        if (l == null) {
            contesto?.let { if (quale == "playPausa" && attivo) riprendi(it) }
            return
        }
        try {
            when (quale) {
                "playPausa" -> if (l.isPlaying) l.pause() else {
                    if (l.mediaItemCount == 0) contesto?.let { riprendi(it) } else l.play()
                }
                "successivo" -> if (voci.size > 1) l.seekToNextMediaItem()
                "precedente" -> if (voci.size > 1) l.seekToPreviousMediaItem()
            }
        } catch (_: Exception) {}
    }

    /** Si riprende quello che c'era (il lettore era stato chiuso). */
    private fun riprendi(ctx: Context) {
        suona(ctx, voci, indice, nome, radio)
    }

    /** A che punto è il brano (0 per una radio in diretta). Dal filo principale. */
    fun posizioneMs(): Long = try {
        if (durataMs > 0L) lettore?.currentPosition?.coerceIn(0L, durataMs) ?: 0L else 0L
    } catch (_: Exception) {
        0L
    }

    /** La musica di casa si ferma, se ne va dal pannello, e il lettore si chiude. */
    fun ferma() {
        principale.removeCallbacks(controlloSottofondo)
        val l = lettore
        lettore = null
        try {
            l?.removeListener(richiamo)
            l?.stop()
            l?.release()
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

    // --- In sottofondo, senza l'auto ---------------------------------------

    /**
     * Se la musica di casa deve fermarsi: senza servizio in primo piano il
     * processo lo tengono vivo solo l'app aperta sul telefono o lo schermo
     * dell'auto. Pubblica per le prove.
     */
    fun daFermareInSottofondo(telefonoDavanti: Boolean, inAuto: Boolean): Boolean = !telefonoDavanti && !inAuto

    /** Il messaggio al ritorno, quando la si è messa in pausa noi. */
    const val TESTO_SOTTOFONDO = "La musica di casa si è fermata: senza Android Auto suona solo con l'app aperta"

    /** Quanto si aspetta prima di fermarla: un giro veloce in un'altra app, o una rotazione, non la ferma. */
    const val ATTESA_SOTTOFONDO_MS = 4_000L

    /** L'app sul telefono è venuta davanti o è andata dietro (`GdanavAppPlugin`). */
    fun telefonoDavanti(si: Boolean) {
        telefonoDavanti = si
        sottofondo()
    }

    /**
     * Qualcosa è cambiato (l'app sul telefono, lo schermo dell'auto: lo dice
     * anche `PonteAuto.inAuto`): se adesso nessuno tiene vivo il processo, fra
     * [ATTESA_SOTTOFONDO_MS] la si mette in pausa, invece di lasciarla morire
     * a caso quando Android congela l'app.
     */
    fun sottofondo() {
        principale.removeCallbacks(controlloSottofondo)
        if (attivo && daFermareInSottofondo(telefonoDavanti, PonteAuto.inAutoAdesso)) {
            principale.postDelayed(controlloSottofondo, ATTESA_SOTTOFONDO_MS)
        }
    }

    private val controlloSottofondo = Runnable {
        val l = lettore
        if (!attivo || !daFermareInSottofondo(telefonoDavanti, PonteAuto.inAutoAdesso)) return@Runnable
        if (l == null || !(l.isPlaying || l.playWhenReady)) return@Runnable
        try {
            l.pause()
        } catch (_: Exception) {}
        errore = TESTO_SOTTOFONDO
        avvisa()
    }

    /** Solo per le fotografie: lo stato messo a mano, senza il lettore. */
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
