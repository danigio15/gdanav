package it.gdanav.gdanav_app.auto

import android.animation.ValueAnimator
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
import android.view.animation.LinearInterpolator
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
import kotlin.math.ln

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
        animazione?.cancel()
        animazione = null
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
        val a = areaVisibile ?: Rect(0, 0, larghezza, altezza)
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
        val guida = PonteAuto.guida != null
        val inclinata = guida && tridimensionale
        if (inclinata != inclinataOra) {
            inclinataOra = inclinata
            s.getLayer("edifici")?.setProperties(PropertyFactory.visibility(if (inclinata) Property.NONE else Property.VISIBLE))
            s.getLayer("edifici-3d")?.setProperties(PropertyFactory.visibility(if (inclinata) Property.VISIBLE else Property.NONE))
        }
        muovi(m, s)
    }

    // --- l'auto che scorre -----------------------------------------------

    /**
     * Quello che si vede adesso e dove si va: latitudine, longitudine, rotta
     * della mappa, rotta del segnaposto, zoom, inclinazione e i quattro
     * margini. Fra una posizione e l'altra (dal telefono ogni 300 ms circa)
     * segnaposto e mappa scorrono a ogni fotogramma, invece di saltare.
     */
    private var mostrata: DoubleArray? = null
    private var obiettivo: DoubleArray? = null
    private var animazione: ValueAnimator? = null
    private var ultimaPosizione = 0L
    private var eraLibera = false
    private val sorgentiCaricate = HashMap<String, String>()

    private fun muovi(m: MapLibreMap, s: Style) {
        val qui = PonteAuto.qui
        if (qui == null) {
            animazione?.cancel()
            mostrata = null
            obiettivo = null
            s.getSourceAs<GeoJsonSource>("gdanav-io")?.setGeoJson(VUOTA)
            return
        }
        val guida = PonteAuto.guida != null
        val inclinata = guida && tridimensionale
        // L'auto al centro dell'area libera; in guida più in basso, per
        // vedere la strada davanti.
        val a = areaVisibile ?: Rect(0, 0, larghezza, altezza)
        val sopra = if (guida) (a.height() * 0.3) else 0.0
        val nuovo = doubleArrayOf(
            qui[0], qui[1],
            if (inclinata) PonteAuto.rotta else 0.0,
            PonteAuto.rottaIo,
            if (guida) zoomGuida else zoomFermo,
            if (inclinata) 55.0 else 0.0,
            a.left.toDouble(),
            a.top.toDouble() + sopra,
            (larghezza - a.right).toDouble().coerceAtLeast(0.0),
            (altezza - a.bottom).toDouble().coerceAtLeast(0.0),
        )
        // Tornando a seguire l'auto dopo averla spostata col dito: un volo.
        if (eraLibera && !libera) {
            eraLibera = false
            animazione?.cancel()
            mostrata = nuovo
            obiettivo = nuovo
            disegna(m, s, nuovo, sposta = false)
            m.animateCamera(CameraUpdateFactory.newCameraPosition(camera(nuovo)), 700)
            return
        }
        eraLibera = libera
        val prima = obiettivo
        if (prima != null && prima.contentEquals(nuovo)) return
        obiettivo = nuovo
        val da = mostrata
        val ora = SystemClock.uptimeMillis()
        val spostata = prima == null || prima[0] != nuovo[0] || prima[1] != nuovo[1]
        val passo = ora - ultimaPosizione
        if (spostata) ultimaPosizione = ora
        // Troppo lontano (prima volta, salto del GPS): subito lì.
        if (da == null || abs(da[0] - nuovo[0]) > 0.01 || abs(da[1] - nuovo[1]) > 0.01) {
            animazione?.cancel()
            mostrata = nuovo
            disegna(m, s, nuovo)
            return
        }
        // Dura quanto l'intervallo fra due posizioni: si arriva quando arriva
        // la prossima, e il moto resta continuo.
        val durata = if (spostata) passo.coerceIn(250L, 1100L) else 450L
        val partenza = da.copyOf()
        animazione?.cancel()
        animazione = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durata
            interpolator = LinearInterpolator()
            addUpdateListener { va ->
                val t = (va.animatedValue as Float).toDouble()
                val v = DoubleArray(nuovo.size) { i ->
                    if (i == 2 || i == 3) angolo(partenza[i], nuovo[i], t) else partenza[i] + (nuovo[i] - partenza[i]) * t
                }
                mostrata = v
                val st = stile ?: return@addUpdateListener
                val mm = mappa ?: return@addUpdateListener
                disegna(mm, st, v)
            }
            start()
        }
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
     * sia nell'app gdanav sia dentro gdahome (il posto vecchio resta come
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

        /** Il cerchio intorno al punto della scheda aperta (`stile.dart`). */
        const val SORGENTE_EVIDENZA = "gdanav-evidenza"
        val CARTELLE_SEGNAPOSTO = listOf(
            "flutter_assets/packages/gdanav_app/assets/segnaposto",
            "flutter_assets/assets/segnaposto",
        )
    }
}
