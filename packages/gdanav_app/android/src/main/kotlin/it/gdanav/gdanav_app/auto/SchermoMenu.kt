package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/** Uno schermo dell'auto che si rifà quando il telefono manda novità. */
abstract class SchermoAggiornato(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private var versione = PonteAuto.versioneModello
    private val aggiorna: () -> Unit = {
        if (PonteAuto.versioneModello != versione) {
            versione = PonteAuto.versioneModello
            invalidate()
        }
    }

    init {
        lifecycle.addObserver(this)
    }

    override fun onCreate(owner: LifecycleOwner) {
        PonteAuto.ascolta(aggiorna)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PonteAuto.smetti(aggiorna)
    }

    protected fun elenco(titolo: String, righe: List<Row>, vuoto: String = "Niente da mostrare"): Template {
        val lista = ItemList.Builder().setNoItemsMessage(vuoto)
        righe.forEach { lista.addItem(it) }
        return ListTemplate.Builder()
            .setTitle(titolo)
            .setHeaderAction(Action.BACK)
            .setSingleList(lista.build())
            .build()
    }

    protected fun riga(titolo: String, testo: String? = null, sfoglia: Boolean = false, azione: () -> Unit): Row {
        val r = Row.Builder().setTitle(titolo).setOnClickListener { azione() }
        if (!testo.isNullOrEmpty()) r.addText(testo)
        if (sfoglia) r.setBrowsable(true)
        return r.build()
    }

    protected fun interruttore(titolo: String, acceso: Boolean, testo: String? = null, cambia: (Boolean) -> Unit): Row {
        val r = Row.Builder().setTitle(titolo).setToggle(Toggle.Builder { cambia(it) }.setChecked(acceso).build())
        if (!testo.isNullOrEmpty()) r.addText(testo)
        return r.build()
    }

    protected fun avvisa(testo: String) = CarToast.makeText(carContext, testo, CarToast.LENGTH_LONG).show()
}

/**
 * Il menu dell'auto, come Waze: Casa e Lavoro (un tocco e si parte),
 * preferiti e recenti, colonnine vicine, segnala, impostazioni. Sei righe:
 * è il minimo che ogni auto mostra.
 */
class SchermoMenu(carContext: CarContext, private val renderer: RendererMappa) : SchermoAggiornato(carContext) {
    override fun onGetTemplate(): Template {
        val casa = PonteAuto.casa()
        val lavoro = PonteAuto.lavoro()
        return elenco(
            "Menu",
            listOf(
                if (casa != null) {
                    riga("Casa", casa.nome) { vai(casa) }
                } else {
                    riga("Casa", "Tocca per impostarla", sfoglia = true) { screenManager.push(SchermoCerca(carContext, "casa")) }
                },
                if (lavoro != null) {
                    riga("Lavoro", lavoro.nome) { vai(lavoro) }
                } else {
                    riga("Lavoro", "Tocca per impostarlo", sfoglia = true) {
                        screenManager.push(SchermoCerca(carContext, "lavoro"))
                    }
                },
                riga("Preferiti e recenti", sfoglia = true) { screenManager.push(SchermoDestinazioni(carContext)) },
                riga("Colonnine vicine", "Le rapide intorno a te", sfoglia = true) {
                    screenManager.push(SchermoColonnine(carContext))
                },
                riga("Segnala", "Polizia, incidente, traffico, pericolo…", sfoglia = true) {
                    screenManager.push(SchermoSegnala(carContext))
                },
                riga("Impostazioni", "Vista 2D/3D, voce, percorso, Casa e Lavoro", sfoglia = true) {
                    screenManager.push(SchermoImpostazioni(carContext, renderer))
                },
            ),
        )
    }

    private fun vai(l: PonteAuto.Luogo) {
        PonteAuto.vai(l)
        screenManager.popToRoot()
    }
}

/** Vista, voce, opzioni del percorso, e dove sono Casa e Lavoro. */
class SchermoImpostazioni(carContext: CarContext, private val renderer: RendererMappa) : SchermoAggiornato(carContext) {
    override fun onGetTemplate(): Template {
        val o = PonteAuto.opzioni
        val casa = PonteAuto.casa()
        val lavoro = PonteAuto.lavoro()
        return elenco(
            "Impostazioni",
            listOf(
                interruttore("Vista 3D", renderer.tridimensionale, "Spenta: mappa dall'alto, nord in su") {
                    if (it != renderer.tridimensionale) renderer.alternaVista()
                    invalidate()
                },
                interruttore("Voce", o["muto"] != true, "Le indicazioni e gli avvisi a voce") { PonteAuto.alternaVoce() },
                riga("Percorso", "${o["modo_nome"] ?: "Veloce"} · pedaggi, autostrade, traghetti", sfoglia = true) {
                    screenManager.push(SchermoOpzioni(carContext))
                },
                riga("Imposta Casa", casa?.nome ?: "Non ancora impostata", sfoglia = true) {
                    screenManager.push(SchermoCerca(carContext, "casa"))
                },
                riga("Imposta Lavoro", lavoro?.nome ?: "Non ancora impostato", sfoglia = true) {
                    screenManager.push(SchermoCerca(carContext, "lavoro"))
                },
            ),
        )
    }
}

/** Come calcolare il percorso: guida e cosa evitare. Vale anche per il viaggio in corso. */
class SchermoOpzioni(carContext: CarContext) : SchermoAggiornato(carContext) {
    private val modi = listOf("veloce" to "Veloce", "equilibrato" to "Equilibrato", "risparmio" to "Risparmio")

    override fun onGetTemplate(): Template {
        val o = PonteAuto.opzioni
        val modo = o["modo"] as? String ?: "veloce"
        val i = modi.indexOfFirst { it.first == modo }.coerceAtLeast(0)
        return elenco(
            "Percorso",
            listOf(
                riga("Guida: ${modi[i].second}", "Tocca per cambiare: veloce, equilibrato (120), risparmio (100)") {
                    PonteAuto.cambiaOpzione("modo", modi[(i + 1) % modi.size].first)
                },
                interruttore("Evita pedaggi", o["pedaggi"] == true) { PonteAuto.cambiaOpzione("pedaggi", it) },
                interruttore("Evita autostrade", o["autostrade"] == true) { PonteAuto.cambiaOpzione("autostrade", it) },
                interruttore("Evita traghetti", o["traghetti"] == true) { PonteAuto.cambiaOpzione("traghetti", it) },
                interruttore("Ricalcolo automatico", o["ricalcolo"] != false, "Se il consumo cambia, le soste si rifanno da sole") {
                    PonteAuto.cambiaOpzione("ricalcolo", it)
                },
            ),
        )
    }
}

/** Le colonnine rapide vicine, adatte alla tua auto; con Premium libere e occupate. */
class SchermoColonnine(carContext: CarContext) : SchermoAggiornato(carContext) {
    private var colonnine: List<PonteAuto.Luogo>? = null

    override fun onCreate(owner: LifecycleOwner) {
        super.onCreate(owner)
        PonteAuto.colonnine {
            colonnine = it
            invalidate()
        }
    }

    override fun onGetTemplate(): Template {
        val trovate = colonnine
            ?: return ListTemplate.Builder().setTitle("Colonnine vicine").setHeaderAction(Action.BACK).setLoading(true).build()
        return elenco(
            "Colonnine vicine",
            trovate.take(righeMassime()).map { c ->
                riga(c.nome, c.descrizione) {
                    PonteAuto.vai(c)
                    screenManager.popToRoot()
                }
            },
            "Nessuna colonnina rapida qui intorno",
        )
    }

    private fun righeMassime(): Int = try {
        carContext.getCarService(androidx.car.app.constraints.ConstraintManager::class.java)
            .getContentLimit(androidx.car.app.constraints.ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
    } catch (e: Exception) {
        6
    }
}

/** Segnala dove sei, come in Waze. */
class SchermoSegnala(carContext: CarContext) : SchermoAggiornato(carContext) {
    private val tipi = listOf(
        "polizia" to "Polizia",
        "incidente" to "Incidente",
        "traffico" to "Traffico",
        "pericolo" to "Pericolo",
        "lavori" to "Lavori",
        "autovelox" to "Autovelox",
    )

    override fun onGetTemplate(): Template = elenco(
        "Segnala",
        tipi.map { (tipo, nome) ->
            riga(nome) {
                PonteAuto.segnala(tipo) { frase -> avvisa(frase) }
                screenManager.pop()
            }
        },
    )
}
