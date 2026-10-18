package it.gdanav.gdanav_app.auto

import android.app.Presentation
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Point
import android.graphics.PointF
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
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Disegna la mappa di gdanav sullo schermo dell'auto: una MapView di
 * MapLibre dentro una Presentation su un display virtuale che scrive sulla
 * superficie data da Android Auto, con sopra il cruscotto. Stesso stile,
 * stessi dati e stesso segnaposto del telefono. Si sposta e si ingrandisce
 * col dito (o la manopola): dopo un po' torna da sola sull'auto.
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
    private var mappa: MapLibreMap? = null
    private var stile: Style? = null
    private var stileCaricato: String? = null
    private var inclinataOra: Boolean? = null
    private var immaginiCaricate = 0
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

    /** Lo zoom quando segue l'auto: i tasti + e − lo cambiano. */
    private var zoomGuida = preferenze.getFloat("auto_zoom_guida", 16.5f).toDouble()
    private var zoomFermo = preferenze.getFloat("auto_zoom_fermo", 15.5f).toDouble()

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
        val sopra = if (soloMappa) null else PannelloAuto(p.context, contenitore.dpi / 160f)
        sopra?.area = areaVisibile
        val tutto = FrameLayout.LayoutParams.MATCH_PARENT
        contenuto.addView(vista, FrameLayout.LayoutParams(tutto, tutto))
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
        /* Il calore in auto. La mappa si ridisegnava a ogni fotogramma dello
         * schermo, sessanta al secondo, finché si guida: lo scorrere fra due
         * posizioni non si ferma mai. Sessanta fotogrammi di una mappa 3D, e
         * Android Auto che li codifica tutti in video per l'auto, scaldano il
         * telefono come un videogioco. Trenta sono il tetto; lo scorrere
         * stesso ne chiede venticinque (vedi [FOTOGRAMMA_MS]). */
        vista.setMaximumFps(FPS_MASSIMI)
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
        if (!soloMappa) principale.postDelayed(contaTraffico, 10_000)
    }

    /** Ogni dieci secondi, quanti tratti di coda ci sono sullo schermo. */
    private val contaTraffico: Runnable = object : Runnable {
        override fun run() {
            val m = mappa
            if (m != null && stile != null) DiagnosiTraffico.contaTratti(m, larghezza, altezza)
            if (mappaView != null) principale.postDelayed(this, 10_000)
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
        spegniFotogrammi()
        mostrata = null
        obiettivo = null
        sorgentiCaricate.clear()
        mappaView?.let {
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
        mappa = null
        stile = null
        stileCaricato = null
        inclinataOra = null
        immaginiCaricate = 0
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

    /** I tasti + e −: seguendo l'auto cambiano lo zoom della guida (e si ricorda). */
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
            zoomFermo = (zoomFermo + passo).coerceIn(8.0, 19.0)
            preferenze.edit().putFloat("auto_zoom_fermo", zoomFermo.toFloat()).apply()
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
            immaginiCaricate = 0
            sorgentiCaricate.clear()
            m.setStyle(Style.Builder().fromJson(json)) { s ->
                stile = s
                if (!soloMappa) {
                    DiagnosiTraffico.strato = s.getSource(DiagnosiTraffico.SORGENTE) != null &&
                        s.getLayer(DiagnosiTraffico.SORGENTE) != null
                }
                caricaSegnaposto(s)
                aggiornaDati(m, s)
                accendi(s)
            }
            return
        }
        stile?.let { aggiornaDati(m, it) }
    }

    private fun aggiornaDati(m: MapLibreMap, s: Style) {
        // Solo le sorgenti cambiate: rileggere il percorso a ogni novità del
        // cruscotto fa perdere fotogrammi.
        for ((id, dati) in PonteAuto.sorgenti) {
            if (sorgentiCaricate[id] === dati) continue
            s.getSourceAs<GeoJsonSource>(id)?.setGeoJson(dati)
            sorgentiCaricate[id] = dati
        }
        val immagini = PonteAuto.immagini
        if (immagini.size != immaginiCaricate) {
            immaginiCaricate = immagini.size
            for ((nome, bitmap) in immagini) s.addImage(nome, bitmap)
        }
        // In 3D anche senza guida: la vista scelta è una, guidando o no.
        val inclinata = tridimensionale
        if (inclinata != inclinataOra) {
            inclinataOra = inclinata
            s.getLayer("edifici")?.setProperties(PropertyFactory.visibility(if (inclinata) Property.NONE else Property.VISIBLE))
            s.getLayer("edifici-3d")?.setProperties(PropertyFactory.visibility(if (inclinata) Property.VISIBLE else Property.NONE))
        }
        muovi(m, s)
    }

    // --- l'auto che scorre -----------------------------------------------

    /*
     * Dal campo: «la freccia sulla mappa non è fluida, prende pause e poi
     * cammina». A ogni posizione dal telefono (una al secondo, col GPS) si
     * partiva da dov'era la freccia verso la posizione nuova, in un tempo pari
     * all'intervallo di prima, e lì ci si fermava ad aspettare la prossima:
     * con una posizione in ritardo, la pausa; con una in anticipo, lo scatto.
     *
     * Adesso è il conto di `MotoFluido` (gdanav_core, con le sue prove), rifatto
     * qui coi suoi numeri: fra una posizione e l'altra l'auto va avanti da sola
     * con la velocità che manda il telefono (`velocita_ms`) e girando come
     * stava girando, al più per [OLTRE_AL_PIU_MS]; quello che si disegna la
     * insegue a ogni fotogramma con la costante di tempo [TAU_S], mai indietro
     * lungo la strada; da fermi, arrivata, i fotogrammi si spengono fino alla
     * posizione dopo.
     *
     * I fotogrammi li dà un `Handler` ogni [FOTOGRAMMA_MS], non il vsync del
     * telefono: la mappa va sullo schermo dell'auto (un display virtuale che
     * Android Auto codifica in video), e col telefono in tasca a schermo
     * spento il vsync del telefono non c'è. Venticinque al secondo, sotto il
     * tetto di [FPS_MASSIMI]: di più scalda e basta.
     */

    /**
     * Quello che si vede adesso: latitudine, longitudine, rotta della mappa,
     * rotta del segnaposto, zoom, inclinazione e i quattro margini.
     */
    private var mostrata: DoubleArray? = null

    /** L'ultima posizione dal telefono, con zoom e margini di adesso. */
    private var obiettivo: DoubleArray? = null

    /** Quando è arrivata l'ultima posizione, a che velocità (m/s) e quanto si girava (gradi al secondo). */
    private var fixAlle = 0L
    private var fixVelocita = 0.0
    private var fixGira = 0.0
    private var ultimoFotogramma = 0L
    private var scorrendo = false
    private var eraLibera = false
    private val sorgentiCaricate = HashMap<String, String>()

    private val fotogramma = object : Runnable {
        override fun run() {
            if (!scorrendo) return
            val m = mappa
            val s = stile
            if (m == null || s == null || !passo(m, s)) {
                scorrendo = false
                return
            }
            principale.postDelayed(this, FOTOGRAMMA_MS)
        }
    }

    private fun accendiFotogrammi() {
        if (scorrendo) return
        scorrendo = true
        ultimoFotogramma = SystemClock.uptimeMillis()
        principale.postDelayed(fotogramma, FOTOGRAMMA_MS)
    }

    private fun spegniFotogrammi() {
        scorrendo = false
        principale.removeCallbacks(fotogramma)
    }

    private fun muovi(m: MapLibreMap, s: Style) {
        val qui = PonteAuto.qui
        if (qui == null) {
            spegniFotogrammi()
            mostrata = null
            obiettivo = null
            s.getSourceAs<GeoJsonSource>("gdanav-io")?.setGeoJson(VUOTA)
            return
        }
        val guida = PonteAuto.guida != null
        /* Il 3D anche senza una meta, come sul telefono: prima la vista 3D
         * valeva solo in guida, e fuori la mappa tornava piatta e col nord in
         * su qualunque cosa si fosse scelto. Adesso la mappa segue l'auto girata come va (la rotta che il
         * telefono manda anche fuori guida) e inclinata; lo zoom resta quello
         * scelto coi tasti per la mappa senza guida. */
        val inclinata = tridimensionale
        // L'auto al centro dell'area libera; in guida, o in 3D, più in basso,
        // per vedere la strada davanti.
        val a = areaLibera()
        val sopra = if (guida) (a.height() * 0.3) else if (inclinata) (a.height() * 0.2) else 0.0
        val nuovo = doubleArrayOf(
            qui[0], qui[1],
            if (inclinata) PonteAuto.rotta else 0.0,
            PonteAuto.rottaIo,
            if (guida) zoomGuida + zoomInSvolta(PonteAuto.guida) else zoomFermo,
            if (inclinata) 55.0 else 0.0,
            a.left.toDouble(),
            a.top.toDouble() + sopra,
            (larghezza - a.right).toDouble().coerceAtLeast(0.0),
            (altezza - a.bottom).toDouble().coerceAtLeast(0.0),
        )
        val ora = SystemClock.uptimeMillis()
        // Tornando a seguire l'auto dopo averla spostata col dito: un volo.
        if (eraLibera && !libera) {
            eraLibera = false
            spegniFotogrammi()
            mostrata = nuovo
            obiettivo = nuovo
            fixAlle = ora
            fixVelocita = 0.0
            fixGira = 0.0
            disegna(m, s, nuovo, sposta = false)
            m.animateCamera(CameraUpdateFactory.newCameraPosition(camera(nuovo)), 700)
            return
        }
        eraLibera = libera
        val prima = obiettivo
        if (prima != null && prima.contentEquals(nuovo)) return
        // Una posizione nuova (non solo zoom o margini, che cambiano di
        // continuo avvicinandosi a una svolta): da qui riparte la previsione.
        if (prima == null || prima[0] != nuovo[0] || prima[1] != nuovo[1]) {
            val passo = (ora - fixAlle) / 1000.0
            val v = PonteAuto.velocita
            fixGira = if (prima != null && v >= 2.0 && passo >= 0.2 && passo <= 3.0) {
                (giro(prima[3], nuovo[3]) / passo).coerceIn(-GIRA_AL_PIU, GIRA_AL_PIU)
            } else if (prima == null || passo > 0.2) {
                0.0
            } else {
                fixGira
            }
            fixAlle = ora
            fixVelocita = if (v.isFinite() && v > 0.0) v else 0.0
        }
        obiettivo = nuovo
        val da = mostrata
        // Troppo lontano (prima volta, salto del GPS, ricalcolo): subito lì.
        if (da == null || distanzaM(da[0], da[1], nuovo[0], nuovo[1]) > SALTO_M) {
            mostrata = nuovo.copyOf()
            disegna(m, s, nuovo)
            ultimoFotogramma = ora
            if (fixVelocita < FERMO_SOTTO_MS) return
        }
        accendiFotogrammi()
    }

    /** Dove l'auto dovrebbe essere adesso: l'ultima posizione portata avanti. */
    private fun previsione(o: DoubleArray, ora: Long): DoubleArray {
        val v = o.copyOf()
        if (fixVelocita < FERMO_SOTTO_MS) return v
        val t = ((ora - fixAlle) / 1000.0).coerceIn(0.0, OLTRE_AL_PIU_MS / 1000.0)
        val r0 = Math.toRadians(o[3])
        val w = Math.toRadians(fixGira)
        val est: Double
        val nord: Double
        if (abs(w) < 1e-4) {
            est = fixVelocita * t * sin(r0)
            nord = fixVelocita * t * cos(r0)
        } else {
            val r1 = r0 + w * t
            est = fixVelocita / w * (cos(r0) - cos(r1))
            nord = fixVelocita / w * (sin(r1) - sin(r0))
        }
        v[0] = o[0] + nord / METRI_PER_GRADO
        v[1] = o[1] + est / (METRI_PER_GRADO * cos(Math.toRadians(o[0])))
        v[3] = ((o[3] + fixGira * t) % 360.0 + 360.0) % 360.0
        return v
    }

    /** Un fotogramma: un passo verso la previsione. `false` quando non ne servono altri. */
    private fun passo(m: MapLibreMap, s: Style): Boolean {
        val o = obiettivo ?: return false
        val da = mostrata ?: return false
        val ora = SystemClock.uptimeMillis()
        // Un fotogramma saltato non diventa un salto: al più un decimo di secondo.
        val dt = ((ora - ultimoFotogramma) / 1000.0).coerceIn(0.0, 0.1)
        ultimoFotogramma = ora
        val p = previsione(o, ora)
        val k = 1 - exp(-dt / TAU_S)
        val coslat = cos(Math.toRadians(da[0]))
        var est = (p[1] - da[1]) * METRI_PER_GRADO * coslat * k
        var nord = (p[0] - da[0]) * METRI_PER_GRADO * k
        if (fixVelocita >= FERMO_SOTTO_MS) {
            // Mai indietro lungo la strada: quella parte del passo si toglie.
            val r = Math.toRadians(p[3])
            val ve = sin(r)
            val vn = cos(r)
            val lungo = est * ve + nord * vn
            if (lungo < 0) {
                est -= lungo * ve
                nord -= lungo * vn
            }
        }
        val v = DoubleArray(o.size) { i ->
            when (i) {
                0 -> da[0] + nord / METRI_PER_GRADO
                1 -> da[1] + est / (METRI_PER_GRADO * coslat)
                2, 3 -> angolo(da[i], p[i], k)
                else -> da[i] + (p[i] - da[i]) * k
            }
        }
        mostrata = v
        disegna(m, s, v)
        var arrivata = distanzaM(v[0], v[1], p[0], p[1]) < 0.3
        for (i in 2 until v.size) {
            val scarto = if (i == 2 || i == 3) abs(giro(v[i], p[i])) else abs(v[i] - p[i])
            if (scarto > 0.05) arrivata = false
        }
        val ferma = fixVelocita < FERMO_SOTTO_MS || ora - fixAlle >= OLTRE_AL_PIU_MS
        return !(arrivata && ferma)
    }

    /**
     * Quanto si avvicina la mappa arrivando a una svolta, un'uscita, una
     * rotonda: da 600 metri si comincia, a 150 si è vicini di un livello e
     * mezzo, e passata la manovra si torna allo zoom di prima. Lo scorrere
     * fra due posizioni lo rende un movimento, non un salto.
     */
    private fun zoomInSvolta(g: PonteAuto.Guida?): Double {
        g ?: return 0.0
        if (g.tipo !in 9..27 && g.tipo != 37 && g.tipo != 38) return 0.0
        return ZOOM_IN_SVOLTA * ((INIZIO_SVOLTA_M - g.distanzaM) / (INIZIO_SVOLTA_M - VICINO_SVOLTA_M)).coerceIn(0.0, 1.0)
    }

    private fun camera(v: DoubleArray) = CameraPosition.Builder()
        .target(LatLng(v[0], v[1]))
        .bearing(v[2])
        .zoom(v[4])
        .tilt(v[5])
        .padding(v[6], v[7], v[8], v[9])
        .build()

    private fun disegna(m: MapLibreMap, s: Style, v: DoubleArray, sposta: Boolean = true) {
        val icona = PonteAuto.icona.replace("\"", "")
        s.getSourceAs<GeoJsonSource>("gdanav-io")?.setGeoJson(
            "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\"," +
                "\"geometry\":{\"type\":\"Point\",\"coordinates\":[${v[1]},${v[0]}]}," +
                "\"properties\":{\"icona\":\"$icona\",\"rotta\":${v[3]}}}]}",
        )
        if (sposta && !libera) m.moveCamera(CameraUpdateFactory.newCameraPosition(camera(v)))
    }

    /** Di quanto si gira da [da] ad [a], fra -180 e 180. */
    private fun giro(da: Double, a: Double): Double = ((a - da + 540.0) % 360.0 + 360.0) % 360.0 - 180.0

    /** Metri fra due punti vicini. */
    private fun distanzaM(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val nord = (lat2 - lat1) * METRI_PER_GRADO
        val est = (lon2 - lon1) * METRI_PER_GRADO * cos(Math.toRadians(lat1))
        return sqrt(nord * nord + est * est)
    }

    /** Da un angolo all'altro per la via più corta. */
    private fun angolo(da: Double, a: Double, t: Double): Double {
        var d = (a - da) % 360.0
        if (d > 180) d -= 360.0
        if (d < -180) d += 360.0
        return ((da + d * t) % 360.0 + 360.0) % 360.0
    }

    /**
     * Le immagini del segnaposto, prese dagli asset dell'app Flutter. gdanav
     * è un pacchetto: le sue immagini stanno sotto `packages/gdanav_app/`,
     * sia nell'app gdanav sia dentro GdAHome (il posto vecchio resta come
     * riserva).
     */
    private fun caricaSegnaposto(s: Style) {
        for (nome in listOf("freccia", "auto_blu", "auto_bianca", "auto_rossa", "auto_nera", "auto_grigia")) {
            for (cartella in CARTELLE_SEGNAPOSTO) {
                val bitmap = try {
                    carContext.assets.open("$cartella/$nome.png").use { BitmapFactory.decodeStream(it) }
                } catch (e: Exception) {
                    null
                }
                if (bitmap != null) {
                    s.addImage(nome, bitmap)
                    break
                }
            }
        }
    }

    private companion object {
        const val VUOTA = "{\"type\":\"FeatureCollection\",\"features\":[]}"

        /** Il tetto dei fotogrammi della mappa sull'auto. */
        const val FPS_MASSIMI = 30

        /** Lo scorrere fra due posizioni: 25 fotogrammi al secondo. */
        const val FOTOGRAMMA_MS = 40L

        /** I numeri di `MotoFluido` (gdanav_core): inseguimento, previsione, salto, fermi, curva. */
        const val TAU_S = 0.2
        const val OLTRE_AL_PIU_MS = 1500L
        const val SALTO_M = 120.0
        const val FERMO_SOTTO_MS = 0.5
        const val GIRA_AL_PIU = 45.0
        const val METRI_PER_GRADO = 111195.08

        /** Lo zoom in più vicino a una svolta, e da dove a dove si avvicina. */
        const val ZOOM_IN_SVOLTA = 1.5
        const val INIZIO_SVOLTA_M = 600.0
        const val VICINO_SVOLTA_M = 150.0

        /** Il cerchio intorno al punto della scheda aperta (`stile.dart`). */
        const val SORGENTE_EVIDENZA = "gdanav-evidenza"
        val CARTELLE_SEGNAPOSTO = listOf(
            "flutter_assets/packages/gdanav_app/assets/segnaposto",
            "flutter_assets/assets/segnaposto",
        )
    }
}
