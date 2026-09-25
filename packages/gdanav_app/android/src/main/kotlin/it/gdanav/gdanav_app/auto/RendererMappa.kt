package it.gdanav.gdanav_app.auto

import android.app.Presentation
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Point
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.os.Handler
import android.os.Looper
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
import kotlin.math.ln

/**
 * Disegna la mappa di gdanav sullo schermo dell'auto: una MapView di
 * MapLibre dentro una Presentation su un display virtuale che scrive sulla
 * superficie data da Android Auto, con sopra il cruscotto. Stesso stile,
 * stessi dati e stesso segnaposto del telefono. Si sposta e si ingrandisce
 * col dito (o la manopola): dopo un po' torna da sola sull'auto.
 */
class RendererMappa(private val carContext: CarContext) : SurfaceCallback {
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
            "gdanav-auto",
            contenitore.width,
            contenitore.height,
            contenitore.dpi,
            superficie,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
        )
        display = d
        larghezza = contenitore.width
        altezza = contenitore.height
        MapLibre.getInstance(carContext)
        val p = Presentation(carContext, d.display)
        val contenuto = FrameLayout(p.context)
        val vista = MapView(p.context)
        val sopra = PannelloAuto(p.context, contenitore.dpi / 160f)
        sopra.area = areaVisibile
        val tutto = FrameLayout.LayoutParams.MATCH_PARENT
        contenuto.addView(vista, FrameLayout.LayoutParams(tutto, tutto))
        contenuto.addView(sopra, FrameLayout.LayoutParams(tutto, tutto))
        p.setContentView(contenuto)
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
    }

    override fun onSurfaceDestroyed(contenitore: SurfaceContainer) {
        principale.removeCallbacks(torna)
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
    }

    override fun onStableAreaChanged(area: Rect) {
        if (areaVisibile == null) {
            areaVisibile = Rect(area)
            pannello?.area = areaVisibile
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
        if (libera) {
            libera = false
            alCambio()
        }
        aggiorna()
    }

    private fun liberaPerUnPo() {
        principale.removeCallbacks(torna)
        principale.postDelayed(torna, 20_000)
        if (!libera) {
            libera = true
            alCambio()
        }
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
            m.setStyle(Style.Builder().fromJson(json)) { s ->
                stile = s
                caricaSegnaposto(s)
                aggiornaDati(m, s)
            }
            return
        }
        stile?.let { aggiornaDati(m, it) }
    }

    private fun aggiornaDati(m: MapLibreMap, s: Style) {
        for ((id, dati) in PonteAuto.sorgenti) {
            s.getSourceAs<GeoJsonSource>(id)?.setGeoJson(dati)
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
        if (libera) return
        val qui = PonteAuto.qui ?: return
        // L'auto al centro dell'area libera; in guida più in basso, per
        // vedere la strada davanti.
        val a = areaVisibile ?: Rect(0, 0, larghezza, altezza)
        val sopra = if (guida) (a.height() * 0.3) else 0.0
        val posizione = CameraPosition.Builder()
            .target(LatLng(qui[0], qui[1]))
            .zoom(if (guida) zoomGuida else zoomFermo)
            .tilt(if (inclinata) 55.0 else 0.0)
            .bearing(if (guida && tridimensionale) PonteAuto.rotta else 0.0)
            .padding(
                a.left.toDouble(),
                a.top.toDouble() + sopra,
                (larghezza - a.right).toDouble().coerceAtLeast(0.0),
                (altezza - a.bottom).toDouble().coerceAtLeast(0.0),
            )
            .build()
        m.animateCamera(CameraUpdateFactory.newCameraPosition(posizione), 900)
    }

    /** Le immagini del segnaposto, prese dagli asset dell'app Flutter. */
    private fun caricaSegnaposto(s: Style) {
        for (nome in listOf("freccia", "auto_blu", "auto_bianca", "auto_rossa", "auto_nera", "auto_grigia")) {
            try {
                carContext.assets.open("flutter_assets/assets/segnaposto/$nome.png").use {
                    s.addImage(nome, BitmapFactory.decodeStream(it))
                }
            } catch (e: Exception) {
                // Senza immagine il segnaposto non si vede; la guida resta.
            }
        }
    }
}
