package it.gdanav.gdanav_app.musica

import android.content.Intent
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * Dove suona la musica di casa: ExoPlayer con la sua sessione media3
 * ([LettoreDiCasa] lo comanda con un `MediaController`).
 *
 * È un `MediaLibraryService` e non solo un `MediaSessionService` perché così
 * la sessione si sfoglia: le radio di casa ([MusicaDiCasa]) compaiono anche
 * nella musica di Android Auto, se l'app che porta GdANav dichiara la musica
 * per l'auto (`<uses name="media"/>` nel suo `automotive_app_desc.xml`), e il
 * tocco su una radio lì la fa suonare ([Richiami.onAddMediaItems]: la voce
 * arriva col solo id, l'indirizzo lo mette questo servizio).
 *
 * Comandarla (⏯ ⏮ ⏭) può chiunque abbia una sessione da comandare: il
 * sistema, la notifica, i tasti del volante e delle cuffie. **Sfogliarla**
 * solo GdANav stessa, Android Auto e il sistema ([fidato]): l'elenco delle
 * radio della casa alle altre app del telefono non si dà.
 *
 * La notifica e il servizio in primo piano li fa media3 da sé mentre suona.
 * Il focus audio lo chiede ExoPlayer (`handleAudioFocus`), e la musica si
 * ferma da sola se si staccano le cuffie o il Bluetooth dell'auto.
 */
class ServizioLettoreDiCasa : MediaLibraryService() {
    private var sessione: MediaLibrarySession? = null

    override fun onCreate() {
        super.onCreate()
        val lettore = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        sessione = MediaLibrarySession.Builder(this, lettore, Richiami()).setId("gdanav_musica_di_casa").build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = sessione

    /** L'app tolta dalle recenti: se non suona, il servizio se ne va. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = sessione?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        sessione?.run {
            player.release()
            release()
        }
        sessione = null
        super.onDestroy()
    }

    private inner class Richiami : MediaLibrarySession.Callback {
        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(cartella(RADICE, "Musica di casa"), params))

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            // L'elenco delle radio della casa solo a chi è fidato.
            val figli: List<MediaItem> = if (!fidato(browser.packageName)) emptyList() else when (parentId) {
                RADICE -> listOf(cartella(RADIO, "Radio di casa"))
                // Solo quelle che suonano qui: le playlist di Spotify o di
                // casa non sono di questo lettore.
                RADIO -> MusicaDiCasa.radioDaSuonare().map { LettoreDiCasa.elemento(it, radio = true) }
                else -> emptyList()
            }
            return Futures.immediateFuture(LibraryResult.ofItemList(ImmutableList.copyOf(figli), params))
        }

        /** Una radio scelta dalla musica dell'auto arriva col solo id: le si mette l'indirizzo. */
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> {
            val radio = MusicaDiCasa.radioDaSuonare()
            val pieni = mediaItems.map { m ->
                if (m.localConfiguration != null) {
                    m
                } else {
                    radio.firstOrNull { it.id == m.mediaId }?.let { LettoreDiCasa.elemento(it, radio = true) } ?: m
                }
            }
            return Futures.immediateFuture(pieni.toMutableList())
        }
    }

    private fun cartella(id: String, titolo: String): MediaItem = MediaItem.Builder()
        .setMediaId(id)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(titolo)
                .setIsBrowsable(true)
                .setIsPlayable(false)
                .setMediaType(
                    if (id == RADIO) MediaMetadata.MEDIA_TYPE_FOLDER_RADIO_STATIONS else MediaMetadata.MEDIA_TYPE_FOLDER_MIXED,
                )
                .build(),
        )
        .build()

    /** GdANav (e chi la porta dentro), Android Auto, il sistema. */
    private fun fidato(pacchetto: String): Boolean = pacchetto == packageName || pacchetto in FIDATI

    private companion object {
        const val RADICE = "casa"
        const val RADIO = "casa/radio"

        val FIDATI = setOf(
            "android",
            "com.android.systemui",
            "com.android.bluetooth",
            "com.google.android.projection.gearhead",
            "com.google.android.carassistant",
            "com.google.android.googlequicksearchbox",
            "com.google.android.apps.automotive.media",
        )
    }
}
