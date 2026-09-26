package it.gdanav.gdanav_app.auto

import android.content.Intent
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Il quadro strumenti dietro al volante (NF-9), sulle auto che lo danno alle
 * app: solo la mappa, col percorso e il segnaposto, niente cruscotto né meteo
 * né tasti. L'auto lo mostra solo mentre si guida (navigationStarted).
 */
class SessioneQuadro : Session() {
    override fun onCreateScreen(intent: Intent): Screen = SchermoQuadro(carContext)
}

/** Lo schermo del quadro: la mappa di gdanav e basta. */
class SchermoQuadro(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val renderer = RendererMappa(carContext, soloMappa = true)
    private val aggiorna: () -> Unit = { renderer.aggiorna() }

    init {
        lifecycle.addObserver(this)
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(renderer)
    }

    override fun onCreate(owner: LifecycleOwner) {
        PonteAuto.ascolta(aggiorna)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PonteAuto.smetti(aggiorna)
    }

    // Il modello vuole una striscia di tasti; il quadro non la mostra (non
    // si tocca).
    override fun onGetTemplate(): Template =
        NavigationTemplate.Builder()
            .setActionStrip(
                ActionStrip.Builder().addAction(Action.Builder().setTitle("gdanav").setOnClickListener {}.build()).build(),
            )
            .build()
}

/**
 * Per il servizio d'auto di chi porta gdanav dentro (l'app gdanav,
 * gdahome): la sessione giusta per lo schermo che l'auto apre, quello
 * centrale o il quadro strumenti.
 */
object SessioniGdanav {
    fun per(info: SessionInfo, principale: () -> Session): Session =
        if (info.displayType == SessionInfo.DISPLAY_TYPE_CLUSTER) SessioneQuadro() else principale()
}
