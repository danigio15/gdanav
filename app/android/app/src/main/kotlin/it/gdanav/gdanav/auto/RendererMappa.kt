package it.gdanav.gdanav.auto

import android.app.Presentation
import android.graphics.BitmapFactory
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
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

/**
 * Disegna la mappa di gdanav sullo schermo dell'auto: una MapView di
 * MapLibre dentro una Presentation su un display virtuale che scrive sulla
 * superficie data da Android Auto. Stesso stile, stessi dati e stesso
 * segnaposto del telefono.
 */
class RendererMappa(private val carContext: CarContext) : SurfaceCallback {
    private var display: VirtualDisplay? = null
    private var presentazione: Presentation? = null
    private var mappaView: MapView? = null
    private var mappa: MapLibreMap? = null
    private var stile: Style? = null
    private var stileCaricato: String? = null
    private var inGuida = false

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
        MapLibre.getInstance(carContext)
        val p = Presentation(carContext, d.display)
        val vista = MapView(p.context)
        p.setContentView(vista)
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
    }

    override fun onSurfaceDestroyed(contenitore: SurfaceContainer) {
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
        mappa = null
        stile = null
        stileCaricato = null
    }

    /** Chiamata a ogni novità dal telefono. */
    fun aggiorna() {
        val m = mappa ?: return
        val json = (if (carContext.isDarkMode) PonteAuto.stileScuro else PonteAuto.stileChiaro) ?: return
        if (json != stileCaricato) {
            stileCaricato = json
            stile = null
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
        val guida = PonteAuto.guida != null
        if (guida != inGuida) {
            inGuida = guida
            s.getLayer("edifici")?.setProperties(PropertyFactory.visibility(if (guida) Property.NONE else Property.VISIBLE))
            s.getLayer("edifici-3d")?.setProperties(PropertyFactory.visibility(if (guida) Property.VISIBLE else Property.NONE))
        }
        val qui = PonteAuto.qui ?: return
        val posizione = CameraPosition.Builder()
            .target(LatLng(qui[0], qui[1]))
            .zoom(if (guida) 16.5 else 14.5)
            .tilt(if (guida) 55.0 else 0.0)
            .bearing(if (guida) PonteAuto.rotta else 0.0)
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
