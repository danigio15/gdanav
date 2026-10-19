package it.gdanav.gdanav_app.auto

import android.app.Presentation
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Point
import android.graphics.Rect
import android.graphics.RectF
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.FrameLayout
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln

/**
 * Disegna la mappa di GdANav sullo schermo dell'auto: una MapView di
 * MapLibre dentro una Presentation su un display virtuale che scrive sulla
 * superficie data da Android Auto, con sopra il segnaposto ([FrecciaAuto]) e
 * il cruscotto. Stesso stile, stessi dati e stesso segnaposto del telefono. Si
 * sposta e si ingrandisce col dito (o la manopola): dopo un po' torna da sola
 * sull'auto.
 *
 * Tutto quello che tocca la mappa sta sul filo principale (MapLibre lo vuole),
 * e il filo principale è anche quello che risponde ad Android Auto: qui niente
 * che possa aspettare a lungo. Vedi «L'app non risponde» più sotto.
 */
class RendererMappa(
    private val carContext: CarContext,
    /** Sul quadro strumenti (NF-9): solo la mappa, niente sopra. */
    private val soloMappa: Boolean = false,
) : SurfaceCallback {
    private var display: VirtualDisplay? = null
    private var presentazione: Presentation? = null
    private var mappaView: MapView? = null
    private var pannello: PannelloAuto? = null
    private var freccia: FrecciaAuto? = null
    private var mappa: MapLibreMap? = null
    private var stile: Style? = null
    private var stileCaricato: String? = null
    private var inclinataOra: Boolean? = null
    private var immaginiCaricate: Map<String, Bitmap>? = null
    private var larghezza = 0
    private var altezza = 0
    private var densita = 1f
    private val principale = Handler(Looper.getMainLooper())

    /** Spostata col dito: non segue l'auto finché non si torna. */
    var libera = false
        private set

    /** Chiamata quando [libera] cambia, per mostrare «Centra». */
    var alCambio: () -> Unit = {}

    private val preferenze = carContext.getSharedPreferences("gdanav", Context.MODE_PRIVATE)

    /** 3D (inclinata, girata come vai) o 2D (dall'alto, nord in su): si ricorda. */
    var tridimensionale: Boolean = preferenze.getBoolean("auto_3d", true)
        private set

    /** Lo zoom quando segue l'auto in guida: i tasti + e − lo cambiano. */
    private var zoomGuida = preferenze.getFloat("auto_zoom_guida", 16.5f).toDouble()

    /*
     * Senza percorso lo zoom non è più uno solo (prima `auto_zoom_fermo`, 15,5
     * o quello lasciato coi tasti): lo dà la velocità ([zoomLibero]), e i tasti
     * + e − lo spostano di qualche livello, che si ricorda. Il valore di prima
     * non si legge più: era quello che teneva la mappa così lontana.
     */
    private var scartoLibero = preferenze.getFloat("auto_zoom_libero_scarto", 0f).toDouble()

    private val torna = Runnable { segui() }

    override fun onSurfaceAvailable(contenitore: SurfaceContainer) {
        val superficie = contenitore.surface ?: return
        val gestore = carContext.getSystemService(DisplayManager::class.java)
        val d = gestore.createVirtualDisplay(
            if (soloMappa) "gdanav-quadro" else "gdanav-auto",
            contenitore.width,
            contenitore.height,
            contenitore.dpi,
            superficie,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
        )
        display = d
        larghezza = contenitore.width
        altezza = contenitore.height
        /* L'area libera di prima vale per la superficie di prima. Dal campo,
         * col video: a mezzo schermo (la mappa da una parte, la musica
         * dall'altra) l'auto finiva sul bordo destro della mappa, perché la
         * si centrava ancora nell'area dello schermo intero. Se non ci sta
         * più dentro, si dimentica: la rimanda Android Auto, e intanto vale
         * tutta la superficie. */
        areaVisibile?.let { if (it.right > larghezza || it.bottom > altezza) areaVisibile = null }
        densita = contenitore.dpi / 160f
        MapLibre.getInstance(carContext)
        val p = Presentation(carContext, d.display)
        val contenuto = FrameLayout(p.context)
        val vista = MapView(p.context)
        val segnaposto = FrecciaAuto(p.context)
        val sopra = if (soloMappa) null else PannelloAuto(p.context, contenitore.dpi / 160f)
        sopra?.area = areaVisibile
        val tutto = FrameLayout.LayoutParams.MATCH_PARENT
        contenuto.addView(vista, FrameLayout.LayoutParams(tutto, tutto))
        contenuto.addView(segnaposto, FrameLayout.LayoutParams(tutto, tutto))
        sopra?.let { contenuto.addView(it, FrameLayout.LayoutParams(tutto, tutto)) }
        p.setContentView(contenuto)
        // Il traffico che arriva sull'auto, da leggere poi sul telefono. Solo
        // sulla mappa grande: quella del quadro strumenti conterebbe due volte.
        if (!soloMappa) {
            DiagnosiTraffico.inizia(carContext)
            vista.addOnTileActionListener { operazione, _, _, _, _, _, sorgente ->
                DiagnosiTraffico.riquadro(operazione, sorgente)
            }
        }
        /* Il calore in auto: trenta fotogrammi al secondo sono il tetto, e lo
         * scorrere ne usa al più tanti (vedi «L'auto che scorre»). */
        vista.setMaximumFps(FPS_MASSIMI)
        vista.addOnDidFinishRenderingFrameListener(dopoIlDisegno)
        vista.addOnCameraIsChangingListener(cameraCheCambia)
        vista.onCreate(null)
        vista.onStart()
        vista.onResume()
        vista.getMapAsync { m ->
            mappa = m
            m.uiSettings.isAttributionEnabled = true
            m.uiSettings.isLogoEnabled = false
            aggiorna()
        }
        p.show()
        presentazione = p
        mappaView = vista
        pannello = sopra
        freccia = segnaposto
        caricaSegnaposto(segnaposto)
        if (!soloMappa) principale.postDelayed(contaTraffico, CONTA_TRAFFICO_MS)
    }

    /** Ogni tanto, quanti tratti di coda ci sono sullo schermo: solo se la mappa disegna. */
    private val contaTraffico: Runnable = object : Runnable {
        override fun run() {
            val m = mappa
            if (m != null && stile != null && disegnoVivo()) DiagnosiTraffico.contaTratti(m, larghezza, altezza)
            if (mappaView != null) principale.postDelayed(this, CONTA_TRAFFICO_MS)
        }
    }

    override fun onSurfaceDestroyed(contenitore: SurfaceContainer) {
        principale.removeCallbacks(torna)
        principale.removeCallbacks(chiudi)
        principale.removeCallbacks(contaTraffico)
        /* La mappa rifatta segue l'auto: ferma dov'era, ripartirebbe dal
         * mezzo del mondo, e senza più il tempo che la riporta sull'auto. Il
         * punto della scheda, se è ancora aperta, resta acceso. */
        chiudendo = false
        liberaPrima = false
        if (libera) {
            libera = false
            eraLibera = false
            alCambio()
        }
        if (!soloMappa) DiagnosiTraffico.salva()
        // Prima di tutto si smette di chiedere fotogrammi: nessun passo in coda
        // deve toccare una mappa che si sta chiudendo.
        spegniFotogrammi()
        inVolo = false
        inAttesaDaMs = 0L
        moto.dimentica()
        cameraPronta = false
        sorgentiCaricate.clear()
        mappaView?.let {
            it.removeOnDidFinishRenderingFrameListener(dopoIlDisegno)
            it.removeOnCameraIsChangingListener(cameraCheCambia)
            it.onPause()
            it.onStop()
            it.onDestroy()
        }
        presentazione?.dismiss()
        display?.release()
        mappaView = null
        presentazione = null
        display = null
        pannello = null
        freccia = null
        mappa = null
        stile = null
        stileCaricato = null
        inclinataOra = null
        immaginiCaricate = null
    }

    /** L'area non coperta dalle schede di Android Auto. */
    private var areaVisibile: Rect? = null

    /** L'area libera, sempre dentro la superficie di adesso. */
    private fun areaLibera(): Rect {
        val tutta = Rect(0, 0, larghezza, altezza)
        val a = areaVisibile ?: return tutta
        val dentro = Rect(a)
        return if (dentro.intersect(tutta) && !dentro.isEmpty) dentro else tutta
    }

    override fun onVisibleAreaChanged(area: Rect) {
        areaVisibile = Rect(area)
        pannello?.area = areaVisibile
        aggiorna()
        // La scheda di un punto s'è appena aperta, e magari lo copre.
        tieniInVista()
    }

    override fun onStableAreaChanged(area: Rect) {
        if (areaVisibile == null) {
            areaVisibile = Rect(area)
            pannello?.area = areaVisibile
        }
    }

    /** Un punto toccato sulla mappa: proprietà, latitudine, longitudine. */
    var alPunto: (Map<String, Any?>, Double, Double) -> Unit = { _, _, _ -> }

    /**
     * Un tocco sulla mappa (Android Auto dalla versione 5 dell'auto): se sotto
     * il dito c'è un distributore, una colonnina o un punto di interesse, la
     * sua scheda.
     */
    override fun onClick(x: Float, y: Float) {
        // Il tap sulla mappa arriva dal thread dell'host Android Auto: un
        // layer che nel frattempo e' stato ricreato, o una geometria POI
        // inattesa, non deve mai abbattere la sessione dell'auto.
        try {
            val m = mappa ?: return
            // Chiedere alla mappa cosa c'è sotto il dito vuol dire aspettare il
            // filo che disegna: se è bloccato, si aspetterebbe con lui (vedi
            // «L'app non risponde»). Meglio un tocco a vuoto.
            if (!disegnoVivo()) return
            val raggio = 28f
            val trovati = m.queryRenderedFeatures(
                RectF(x - raggio, y - raggio, x + raggio, y + raggio),
                "gdanav-distributori",
                "gdanav-vicine",
                "nomi-poi",
            )
            // Il più vicino al dito.
            val punto = trovati.mapNotNull { f ->
                val g = f.geometry() as? org.maplibre.geojson.Point ?: return@mapNotNull null
                val schermo = m.projection.toScreenLocation(LatLng(g.latitude(), g.longitude()))
                Triple(f, g, (schermo.x - x) * (schermo.x - x) + (schermo.y - y) * (schermo.y - y))
            }.minByOrNull { it.third } ?: return
            val proprieta = HashMap<String, Any?>()
            punto.first.properties()?.entrySet()?.forEach { (chiave, valore) ->
                if (valore.isJsonPrimitive) {
                    val v = valore.asJsonPrimitive
                    proprieta[chiave] = if (v.isNumber) v.asDouble else v.asString
                }
            }
            alPunto(proprieta, punto.second.latitude(), punto.second.longitude())
        } catch (_: Exception) {
            // Android Auto resta sulla mappa: un POI non valido non e' un
            // motivo per chiudere l'app.
        }
    }

    // --- col dito o con la manopola -------------------------------------

    override fun onScroll(distanceX: Float, distanceY: Float) {
        val m = mappa ?: return
        liberaPerUnPo()
        m.scrollBy(-distanceX, -distanceY)
    }

    override fun onFling(velocityX: Float, velocityY: Float) {
        val m = mappa ?: return
        liberaPerUnPo()
        m.scrollBy(velocityX / 8f, velocityY / 8f, 300)
    }

    override fun onScale(focusX: Float, focusY: Float, scaleFactor: Float) {
        val m = mappa ?: return
        // Il doppio tocco arriva con un fattore negativo: si ingrandisce di uno.
        val passo = if (scaleFactor <= 0f) 1.0 else ln(scaleFactor.toDouble()) / ln(2.0)
        if (passo == 0.0) return
        liberaPerUnPo()
        if (focusX < 0 || focusY < 0) {
            m.moveCamera(CameraUpdateFactory.zoomBy(passo))
        } else {
            m.moveCamera(CameraUpdateFactory.zoomBy(passo, Point(focusX.toInt(), focusY.toInt())))
        }
    }

    /** I tasti + e −: seguendo l'auto cambiano lo zoom (in guida, o lo scarto senza percorso), e si ricorda. */
    fun zoom(passo: Double) {
        val m = mappa ?: return
        if (libera) {
            liberaPerUnPo()
            m.animateCamera(CameraUpdateFactory.zoomBy(passo), 300)
            return
        }
        if (PonteAuto.guida != null) {
            zoomGuida = (zoomGuida + passo).coerceIn(12.0, 19.0)
            preferenze.edit().putFloat("auto_zoom_guida", zoomGuida.toFloat()).apply()
        } else {
            scartoLibero = (scartoLibero + passo).coerceIn(SCARTO_LIBERO_MIN, SCARTO_LIBERO_MAX)
            preferenze.edit().putFloat("auto_zoom_libero_scarto", scartoLibero.toFloat()).apply()
        }
        aggiorna()
    }

    fun alternaVista() {
        tridimensionale = !tridimensionale
        preferenze.edit().putBoolean("auto_3d", tridimensionale).apply()
        segui()
    }

    /** «Centra»: di nuovo sull'auto. */
    fun segui() {
        principale.removeCallbacks(torna)
        // Chiesto con la scheda di un punto aperta: chiusa, resta sull'auto.
        liberaPrima = false
        if (libera) {
            libera = false
            alCambio()
        }
        aggiorna()
    }

    private fun liberaPerUnPo() {
        principale.removeCallbacks(torna)
        // Con la scheda di un punto aperta la mappa aspetta che la si chiuda.
        if (evidenziato == null) principale.postDelayed(torna, 20_000)
        if (!libera) {
            libera = true
            alCambio()
        }
    }

    // --- il punto della scheda aperta -------------------------------------

    /** Il punto della scheda aperta sopra la mappa, e il suo stato (colonnine). */
    private var evidenziato: LatLng? = null
    private var statoEvidenziato: String? = null

    /** Com'era la mappa prima della scheda: già spostata col dito, o sull'auto. */
    private var liberaPrima = false
    private var chiudendo = false
    private val chiudi = Runnable {
        chiudendo = false
        if (liberaPrima) liberaPerUnPo() else segui()
    }

    /**
     * La scheda di un punto s'apre sopra la mappa: il punto s'accende col
     * colore del suo stato, e la mappa smette di seguire l'auto finché la
     * scheda è aperta. Resta dov'è; se la scheda copre il punto, lo porta nel
     * mezzo di quello che si vede.
     */
    fun mostra(lat: Double, lon: Double, stato: String?) {
        if (evidenziato == null && !chiudendo) liberaPrima = libera
        principale.removeCallbacks(chiudi)
        chiudendo = false
        principale.removeCallbacks(torna)
        evidenziato = LatLng(lat, lon)
        statoEvidenziato = stato
        if (!libera) {
            libera = true
            alCambio()
        }
        stile?.let { accendi(it) }
        tieniInVista()
    }

    /** La scheda si chiude: il punto si spegne, e la mappa torna com'era. */
    fun nascondi() {
        if (evidenziato == null) return
        evidenziato = null
        statoEvidenziato = null
        stile?.let { accendi(it) }
        // Un giro dopo: se al posto di questa scheda se ne apre un'altra (un
        // altro punto toccato), la mappa non va sull'auto per poi tornare.
        chiudendo = true
        principale.post(chiudi)
    }

    private fun accendi(s: Style) {
        val p = evidenziato
        val stato = statoEvidenziato?.replace("\"", "")
        s.getSourceAs<GeoJsonSource>(SORGENTE_EVIDENZA)?.setGeoJson(
            if (p == null) {
                VUOTA
            } else {
                "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\"," +
                    "\"geometry\":{\"type\":\"Point\",\"coordinates\":[${p.longitude},${p.latitude}]}," +
                    "\"properties\":{${if (stato == null) "" else "\"stato\":\"$stato\""}}}]}"
            },
        )
    }

    /** Se la scheda copre il punto, la mappa lo porta nel mezzo di quello che resta. */
    private fun tieniInVista() {
        val m = mappa ?: return
        val p = evidenziato ?: return
        if (!libera) return
        val a = areaLibera()
        val margine = 32 * densita
        val s = m.projection.toScreenLocation(p)
        if (s.x >= a.left + margine && s.x <= a.right - margine && s.y >= a.top + margine && s.y <= a.bottom - margine) {
            return
        }
        val posizione = CameraPosition.Builder(m.cameraPosition)
            .target(p)
            .padding(
                a.left.toDouble(),
                a.top.toDouble(),
                (larghezza - a.right).toDouble().coerceAtLeast(0.0),
                (altezza - a.bottom).toDouble().coerceAtLeast(0.0),
            )
            .build()
        m.animateCamera(CameraUpdateFactory.newCameraPosition(posizione), 500)
    }

    // --- i dati dal telefono --------------------------------------------

    /** Chiamata a ogni novità dal telefono. */
    fun aggiorna() {
        pannello?.aggiorna()
        val m = mappa ?: return
        val json = (if (carContext.isDarkMode) PonteAuto.stileScuro else PonteAuto.stileChiaro) ?: return
        if (json != stileCaricato) {
            stileCaricato = json
            stile = null
            inclinataOra = null
            immaginiCaricate = null
            sorgentiCaricate.clear()
            m.setStyle(Style.Builder().fromJson(json)) { s ->
                stile = s
                if (!soloMappa) {
                    DiagnosiTraffico.strato = s.getSource(DiagnosiTraffico.SORGENTE) != null &&
                        s.getLayer(DiagnosiTraffico.SORGENTE) != null
                }
                // Il segnaposto lo disegna [FrecciaAuto], sopra la mappa: la
                // sorgente dello stile resta vuota.
                s.getSourceAs<GeoJsonSource>(SORGENTE_IO)?.setGeoJson(VUOTA)
                aggiornaDati(m, s)
                accendi(s)
            }
            return
        }
        stile?.let { aggiornaDati(m, it) }
    }

    private val sorgentiCaricate = HashMap<String, String>()

    private fun aggiornaDati(m: MapLibreMap, s: Style) {
        // Solo le sorgenti cambiate: rileggere il percorso a ogni novità del
        // cruscotto fa perdere fotogrammi.
        for ((id, dati) in PonteAuto.sorgenti) {
            if (sorgentiCaricate[id] === dati) continue
            s.getSourceAs<GeoJsonSource>(id)?.setGeoJson(dati)
            sorgentiCaricate[id] = dati
            richiesta()
        }
        // Le icone delle segnalazioni: solo quelle nuove o cambiate. Prima si
        // ricaricavano tutte appena ne cambiava il numero.
        val immagini = PonteAuto.immagini
        if (immagini !== immaginiCaricate) {
            val prima = immaginiCaricate
            for ((nome, bitmap) in immagini) {
                if (prima?.get(nome) !== bitmap) s.addImage(nome, bitmap)
            }
            immaginiCaricate = immagini
        }
        // In 3D anche senza guida: la vista scelta è una, guidando o no.
        val inclinata = tridimensionale
        if (inclinata != inclinataOra) {
            inclinataOra = inclinata
            s.getLayer("edifici")?.setProperties(PropertyFactory.visibility(if (inclinata) Property.NONE else Property.VISIBLE))
            s.getLayer("edifici-3d")?.setProperties(PropertyFactory.visibility(if (inclinata) Property.VISIBLE else Property.NONE))
        }
        muovi(m)
    }

    // --- l'auto che scorre -----------------------------------------------

    /*
     * Dal campo, due volte. La prima: «la freccia sulla mappa non è fluida,
     * prende pause e poi cammina». La seconda, dopo la prima correzione: «ha
     * ancora dei piccoli frame lag, deve essere continuo con il movimento
     * dell'auto». Tre cause, e tre rimedi:
     *
     * 1. Il ritmo. I fotogrammi li dava un Handler ogni 40 ms (25 al secondo),
     *    la mappa ne disegna al più 30: un fotogramma su sei mostrava la stessa
     *    posizione del precedente, cinque piccoli intoppi al secondo, più
     *    quelli del filo principale in ritardo. Adesso il passo dopo lo chiede
     *    la mappa stessa, appena ha finito di disegnare il fotogramma
     *    ([dopoIlDisegno]): un passo per ogni fotogramma disegnato, mai due
     *    nello stesso, mai uno saltato. Se la mappa non disegna (niente da
     *    cambiare, o è ferma), un Handler di riserva.
     *
     * 2. Le piccole pause del conto: vedi [MotoAuto] (e `MotoFluido` in
     *    gdanav_core). La freccia ha una velocità sua, che cambia piano, e
     *    andando non si ferma più a ogni posizione un po' indietro.
     *
     * 3. La freccia in ritardo sulla mappa: era un punto GeoJSON riscritto a
     *    ogni fotogramma, che MapLibre mostra qualche fotogramma dopo la
     *    telecamera. Adesso la disegna [FrecciaAuto], sopra la mappa, dove la
     *    telecamera mette l'auto. E niente più testo JSON da comporre e
     *    rileggere trenta volte al secondo.
     */

    private val moto = MotoAuto()

    /** La telecamera che si vuole (dall'ultima novità) e quella che si vede. */
    private var zoomVoluto = 16.5
    private var inclinazioneVoluta = 0.0
    private var bussolaInclinata = false
    private val marginiVoluti = DoubleArray(4)
    private var zoomMostrato = 16.5
    private var inclinazioneMostrata = 0.0
    private var bussolaMostrata = 0.0
    private val marginiMostrati = DoubleArray(4)
    private var cameraPronta = false

    private var scorrendo = false
    private var inVolo = false
    private var eraLibera = false
    private var ultimoPassoNs = 0L

    /** L'icona del segnaposto, letta una volta per nome: niente stringhe nuove a ogni fotogramma. */
    private var iconaLetta: String? = null
    private var nomeIcona = "freccia"

    private val passo = Runnable { fotogramma() }

    /** La mappa ha finito un fotogramma: il prossimo passo, subito. */
    private val dopoIlDisegno = MapView.OnDidFinishRenderingFrameListener { _, _, _ ->
        inAttesaDaMs = 0L
        if (scorrendo) {
            principale.removeCallbacks(passo)
            principale.post(passo)
        }
    }

    /** La mappa spostata col dito, o in volo: il segnaposto la segue. */
    private val cameraCheCambia = MapView.OnCameraIsChangingListener {
        if (libera || inVolo) mettiFreccia()
    }

    private fun accendiFotogrammi() {
        if (scorrendo) return
        scorrendo = true
        ultimoPassoNs = 0L
        principale.post(passo)
    }

    private fun spegniFotogrammi() {
        scorrendo = false
        principale.removeCallbacks(passo)
    }

    /** Una novità dal telefono: la posizione, e la telecamera che si vuole. */
    private fun muovi(m: MapLibreMap) {
        val qui = PonteAuto.qui
        if (qui == null) {
            spegniFotogrammi()
            moto.dimentica()
            freccia?.nascondi()
            return
        }
        val guida = PonteAuto.guida
        val inclinata = tridimensionale
        val a = areaLibera()
        /* Senza percorso, come in guida: vicina, in 3D, con l'auto più in
         * basso. Prima era a 15,5 con l'auto in mezzo, e in 3D si vedeva fino
         * all'orizzonte (e la mappa disegnava chilometri di palazzi). */
        val sopra: Double
        if (guida != null) {
            zoomVoluto = zoomGuida + zoomInSvolta(guida) + zoomLontano(PonteAuto.velocita, guida.distanzaM)
            sopra = 0.3
        } else {
            zoomVoluto = zoomLibero(PonteAuto.velocita, scartoLibero)
            sopra = if (inclinata) 0.3 else 0.0
        }
        inclinazioneVoluta = if (inclinata) INCLINAZIONE else 0.0
        bussolaInclinata = inclinata
        marginiVoluti[0] = a.left.toDouble()
        marginiVoluti[1] = a.top + a.height() * sopra
        marginiVoluti[2] = (larghezza - a.right).toDouble().coerceAtLeast(0.0)
        marginiVoluti[3] = (altezza - a.bottom).toDouble().coerceAtLeast(0.0)
        val ora = System.nanoTime()
        if (!moto.stessaPosizione(qui[0], qui[1])) {
            moto.posizione(qui[0], qui[1], PonteAuto.rottaIo, PonteAuto.rotta, PonteAuto.velocita, ora, PonteAuto.pista, PonteAuto.pistaQui)
        }
        // Tornando a seguire l'auto dopo averla spostata col dito: un volo.
        if (eraLibera && !libera) {
            eraLibera = false
            vola(m, ora)
            return
        }
        eraLibera = libera
        accendiFotogrammi()
    }

    /** Il volo di ritorno sull'auto: dove sarà quando il volo finisce. */
    private fun vola(m: MapLibreMap, ora: Long) {
        moto.salta(ora + VOLO_MS * 1_000_000L)
        prendiVoluta()
        inVolo = true
        accendiFotogrammi()
        m.animateCamera(
            CameraUpdateFactory.newCameraPosition(camera()),
            VOLO_MS.toInt(),
            object : MapLibreMap.CancelableCallback {
                override fun onFinish() {
                    inVolo = false
                }

                override fun onCancel() {
                    inVolo = false
                }
            },
        )
    }

    /** La telecamera mostrata diventa subito quella voluta. */
    private fun prendiVoluta() {
        zoomMostrato = zoomVoluto
        inclinazioneMostrata = inclinazioneVoluta
        bussolaMostrata = if (bussolaInclinata) moto.rottaMappa else 0.0
        System.arraycopy(marginiVoluti, 0, marginiMostrati, 0, 4)
        cameraPronta = true
    }

    /** Un passo: uno per fotogramma disegnato. */
    private fun fotogramma() {
        principale.removeCallbacks(passo)
        if (!scorrendo) return
        val m = mappa
        if (m == null || stile == null) {
            scorrendo = false
            return
        }
        val ora = System.nanoTime()
        val dt = if (ultimoPassoNs == 0L) 0.0 else ((ora - ultimoPassoNs) / 1e9).coerceIn(0.0, MotoAuto.FOTOGRAMMA_AL_PIU_S)
        ultimoPassoNs = ora
        val primo = !moto.mostrata
        if (!moto.fotogramma(ora)) {
            scorrendo = false
            return
        }
        if (primo || !cameraPronta) {
            prendiVoluta()
        } else {
            val kz = 1 - exp(-dt / TAU_ZOOM_S)
            val kc = 1 - exp(-dt / TAU_CAMERA_S)
            zoomMostrato += (zoomVoluto - zoomMostrato) * kz
            inclinazioneMostrata += (inclinazioneVoluta - inclinazioneMostrata) * kc
            for (i in 0 until 4) marginiMostrati[i] += (marginiVoluti[i] - marginiMostrati[i]) * kc
            bussolaMostrata = MotoAuto.verso(bussolaMostrata, if (bussolaInclinata) moto.rottaMappa else 0.0, kc)
        }
        // Con la mappa che non disegna da un po' non le si riempie la coda: la
        // telecamera riparte da dov'è l'auto appena torna a disegnare. Dopo
        // qualche secondo si riprova comunque (un fotogramma perso per strada
        // non deve fermare la telecamera per sempre).
        if (inAttesaDaMs != 0L && SystemClock.uptimeMillis() - inAttesaDaMs > RIPROVA_MS) inAttesaDaMs = 0L
        if (!libera && !inVolo && disegnoVivo()) {
            m.moveCamera(CameraUpdateFactory.newCameraPosition(camera()))
            richiesta()
        }
        mettiFreccia()
        val ferma = moto.fermo && cameraArrivata()
        if (ferma && !inVolo) {
            scorrendo = false
            return
        }
        // Il prossimo lo chiede la mappa, appena ha disegnato questo. Se non
        // disegna (spostata col dito: la telecamera non cambia), ogni
        // fotogramma da qui.
        principale.postDelayed(passo, if (libera || inVolo) FOTOGRAMMA_LIBERA_MS else RISERVA_MS)
    }

    private fun cameraArrivata(): Boolean {
        if (abs(zoomVoluto - zoomMostrato) > 0.01 || abs(inclinazioneVoluta - inclinazioneMostrata) > 0.1) return false
        for (i in 0 until 4) if (abs(marginiVoluti[i] - marginiMostrati[i]) > 0.5) return false
        return abs(MotoAuto.giro(bussolaMostrata, if (bussolaInclinata) moto.rottaMappa else 0.0)) < 0.1
    }

    private fun camera() = CameraPosition.Builder()
        .target(LatLng(moto.lat, moto.lon))
        .bearing(bussolaMostrata)
        .zoom(zoomMostrato)
        .tilt(inclinazioneMostrata)
        .padding(marginiMostrati[0], marginiMostrati[1], marginiMostrati[2], marginiMostrati[3])
        .build()

    /** Il segnaposto dove la mappa mette l'auto. */
    private fun mettiFreccia() {
        val f = freccia ?: return
        val m = mappa ?: return
        if (!moto.mostrata) {
            f.nascondi()
            return
        }
        val icona = PonteAuto.icona
        if (icona !== iconaLetta) {
            iconaLetta = icona
            nomeIcona = icona.replace("\"", "")
        }
        val x: Float
        val y: Float
        val bussola: Double
        val zoom: Double
        val inclinazione: Double
        if (!libera && !inVolo) {
            // Seguendo l'auto, la telecamera la mette nel mezzo dell'area dentro i margini.
            x = (marginiMostrati[0] + (larghezza - marginiMostrati[0] - marginiMostrati[2]) / 2).toFloat()
            y = (marginiMostrati[1] + (altezza - marginiMostrati[1] - marginiMostrati[3]) / 2).toFloat()
            bussola = bussolaMostrata
            zoom = zoomMostrato
            inclinazione = inclinazioneMostrata
        } else {
            val c = m.cameraPosition
            val s = m.projection.toScreenLocation(LatLng(moto.lat, moto.lon))
            x = s.x
            y = s.y
            bussola = c.bearing
            zoom = c.zoom
            inclinazione = c.tilt
        }
        // Grande come la disegnava MapLibre: l'immagine alla sua densità,
        // per la densità dello schermo dell'auto, per `icon-size` dello stile.
        val densitaImmagine = f.densitaImmagine().takeIf { it > 0 } ?: 160
        val scala = (dimensioneIcona(zoom) * densita * 160.0 / densitaImmagine).toFloat()
        f.metti(
            nomeIcona,
            x,
            y,
            MotoAuto.giro(bussola, moto.rotta).toFloat(),
            scala,
            cos(Math.toRadians(inclinazione)).toFloat(),
        )
    }

    // --- «L'app non risponde» ---------------------------------------------

    /*
     * Dal campo: in guida, all'improvviso, sull'auto «L'app gdahome non
     * risponde» (Esci / Attendi). Android Auto lo dice quando il filo
     * principale dell'app non gli risponde per qualche secondo.
     *
     * La mappa la disegna un altro filo (quello di OpenGL), ma due chiamate
     * dal filo principale lo aspettano: `queryRenderedFeatures` (il conteggio
     * del traffico ogni dieci secondi, su tutto lo schermo, e il tocco su un
     * punto) chiede al filo che disegna e resta fermo finché non risponde. Se
     * quel filo è bloccato — un fotogramma 3D pesante (a 15,5 inclinata si
     * disegnavano chilometri di palazzi fino all'orizzonte), o lo schermo
     * dell'auto che per un momento non prende più fotogrammi (il video verso
     * l'auto che si inceppa: il filo che disegna resta fermo ad aspettare un
     * posto libero) — il filo principale resta fermo con lui, e Android Auto
     * dopo qualche secondo chiede se chiudere.
     *
     * Adesso: si chiede alla mappa solo se ha disegnato da poco quello che le
     * si è chiesto ([disegnoVivo]); il conteggio del traffico è ogni trenta
     * secondi invece di dieci; le immagini si decodificano fuori dal filo
     * principale (qui e in [PonteAuto]); e i fotogrammi non si accumulano:
     * il passo dopo lo chiede la mappa quando ha finito, e se la mappa è ferma
     * si va avanti piano invece di riempirle la coda.
     */

    /**
     * Da quando la mappa ha un cambiamento chiesto e non ancora disegnato (0:
     * nessuno). Lo azzera ogni fotogramma finito.
     */
    private var inAttesaDaMs = 0L

    /** Si è chiesto qualcosa alla mappa (la telecamera, una sorgente): da disegnare. */
    private fun richiesta() {
        if (inAttesaDaMs == 0L) inAttesaDaMs = SystemClock.uptimeMillis()
    }

    /** La mappa disegna: niente in attesa, o in attesa da poco. */
    private fun disegnoVivo(): Boolean =
        inAttesaDaMs == 0L || SystemClock.uptimeMillis() - inAttesaDaMs < DISEGNO_VIVO_MS

    /**
     * Le immagini del segnaposto, prese dagli asset dell'app Flutter, lette e
     * decodificate fuori dal filo principale (una volta per processo). GdANav
     * è un pacchetto: le sue immagini stanno sotto `packages/gdanav_app/`, sia
     * nell'app GdANav sia dentro GdAHome (il posto vecchio resta come riserva).
     */
    private fun caricaSegnaposto(f: FrecciaAuto) {
        segnaposti?.let { pronte ->
            for ((nome, b) in pronte) f.immagine(nome, b)
            return
        }
        val assets = carContext.assets
        lavoro.execute {
            val lette = HashMap<String, Bitmap>()
            for (nome in NOMI_SEGNAPOSTO) {
                for (cartella in CARTELLE_SEGNAPOSTO) {
                    val bitmap = try {
                        assets.open("$cartella/$nome.png").use { BitmapFactory.decodeStream(it) }
                    } catch (e: Exception) {
                        null
                    }
                    if (bitmap != null) {
                        lette[nome] = bitmap
                        break
                    }
                }
            }
            principale.post {
                segnaposti = lette
                freccia?.let { for ((nome, b) in lette) it.immagine(nome, b) }
                mettiFreccia()
            }
        }
    }

    companion object {
        private const val VUOTA = "{\"type\":\"FeatureCollection\",\"features\":[]}"
        private const val SORGENTE_IO = "gdanav-io"

        /** Il tetto dei fotogrammi della mappa sull'auto. */
        private const val FPS_MASSIMI = 30

        /** Se la mappa non chiede il passo dopo entro questo tempo, lo si fa da qui. */
        private const val RISERVA_MS = 100L

        /** Con la mappa spostata col dito la telecamera non cambia: il segnaposto si muove a questo ritmo. */
        private const val FOTOGRAMMA_LIBERA_MS = 33L

        /** Il volo di ritorno sull'auto. */
        private const val VOLO_MS = 700L

        /** Quanto insegue la telecamera: lo zoom piano (cambia con la velocità), il resto come la freccia. */
        private const val TAU_ZOOM_S = 0.8
        private const val TAU_CAMERA_S = 0.3

        /** L'inclinazione in 3D, in guida e senza percorso. */
        private const val INCLINAZIONE = 55.0

        /** Il conteggio del traffico per la diagnosi. */
        private const val CONTA_TRAFFICO_MS = 30_000L

        /** Oltre questo tempo senza un fotogramma dopo una richiesta, la mappa non disegna. */
        private const val DISEGNO_VIVO_MS = 800L

        /** Dopo tanto senza fotogrammi la telecamera riprova a muoversi. */
        private const val RIPROVA_MS = 3_000L

        /** Quanto i tasti + e − spostano lo zoom senza percorso. */
        private const val SCARTO_LIBERO_MIN = -4.0
        private const val SCARTO_LIBERO_MAX = 2.0

        /** Lo zoom in più vicino a una svolta, e da dove a dove si avvicina. */
        private const val ZOOM_IN_SVOLTA = 1.5
        private const val INIZIO_SVOLTA_M = 600.0
        private const val VICINO_SVOLTA_M = 150.0

        /** Il cerchio intorno al punto della scheda aperta (`stile.dart`). */
        private const val SORGENTE_EVIDENZA = "gdanav-evidenza"
        private val NOMI_SEGNAPOSTO = listOf("freccia", "auto_blu", "auto_bianca", "auto_rossa", "auto_nera", "auto_grigia")
        private val CARTELLE_SEGNAPOSTO = listOf(
            "flutter_assets/packages/gdanav_app/assets/segnaposto",
            "flutter_assets/assets/segnaposto",
        )

        /** Le immagini del segnaposto, decodificate una volta. */
        @Volatile private var segnaposti: Map<String, Bitmap>? = null

        /** Il filo per i lavori lenti (leggere e decodificare immagini), fuori dal principale. */
        internal val lavoro = Executors.newSingleThreadExecutor { r -> Thread(r, "gdanav-auto-lavoro").apply { isDaemon = true } }

        /*
         * La mappa senza percorso: il conto di `telecameraLibera` (gdanav_core,
         * con le sue prove). 17,5 fino a 30 all'ora, 16,2 da 110 in su, e in
         * mezzo si passa piano; i tasti + e − lo spostano di [scarto].
         */
        private const val ZOOM_LIBERO_LENTO = 17.5
        private const val ZOOM_LIBERO_VELOCE = 16.2
        private const val LENTO_SOTTO_KMH = 30.0
        private const val VELOCE_SOPRA_KMH = 110.0

        fun zoomLibero(velocitaMs: Double, scarto: Double): Double {
            val kmh = if (velocitaMs.isFinite() && velocitaMs > 0) velocitaMs * 3.6 else 0.0
            val t = ((kmh - LENTO_SOTTO_KMH) / (VELOCE_SOPRA_KMH - LENTO_SOTTO_KMH)).coerceIn(0.0, 1.0)
            val s = t * t * (3 - 2 * t)
            return (ZOOM_LIBERO_LENTO + (ZOOM_LIBERO_VELOCE - ZOOM_LIBERO_LENTO) * s + scarto).coerceIn(10.0, 19.5)
        }

        private val ZOOM_ICONA = doubleArrayOf(10.0, 15.0, 17.0, 19.0)
        private val DIMENSIONE_ICONA = doubleArrayOf(0.45, 0.6, 0.85, 1.0)

        /** `icon-size` del segnaposto nello stile (`stile.dart`, strato `io`), allo [zoom]. */
        fun dimensioneIcona(zoom: Double): Double {
            val z = ZOOM_ICONA
            val v = DIMENSIONE_ICONA
            if (zoom <= z[0]) return v[0]
            for (i in 1 until z.size) {
                if (zoom <= z[i]) return v[i - 1] + (v[i] - v[i - 1]) * (zoom - z[i - 1]) / (z[i] - z[i - 1])
            }
            return v[v.size - 1]
        }

        /**
         * Quanto si avvicina la mappa arrivando a una svolta, un'uscita, una
         * rotonda: da 600 metri si comincia, a 150 si è vicini di un livello e
         * mezzo, e passata la manovra si torna allo zoom di prima. Lo scorrere
         * fra due posizioni lo rende un movimento, non un salto.
         */
        /**
         * In autostrada, con la prossima manovra lontana, la mappa si
         * allontana: fino a due livelli da 110 all'ora e con la manovra oltre
         * 2,5 km, niente sotto i 50 all'ora o entro 800 metri. Il conto di
         * `zoomLontanoInGuida` (gdanav_core, con le sue prove).
         */
        fun zoomLontano(velocitaMs: Double, allaProssimaM: Double): Double {
            val kmh = if (velocitaMs.isFinite() && velocitaMs > 0) velocitaMs * 3.6 else 0.0
            fun morbido(t: Double): Double {
                val x = t.coerceIn(0.0, 1.0)
                return x * x * (3 - 2 * x)
            }
            val v = morbido((kmh - 50.0) / (110.0 - 50.0))
            val d = if (allaProssimaM.isFinite()) morbido((allaProssimaM - 800.0) / (2500.0 - 800.0)) else 1.0
            return -2.0 * v * d
        }

        private fun zoomInSvolta(g: PonteAuto.Guida?): Double {
            g ?: return 0.0
            if (g.tipo !in 9..27 && g.tipo != 37 && g.tipo != 38) return 0.0
            return ZOOM_IN_SVOLTA * ((INIZIO_SVOLTA_M - g.distanzaM) / (INIZIO_SVOLTA_M - VICINO_SVOLTA_M)).coerceIn(0.0, 1.0)
        }
    }
}
