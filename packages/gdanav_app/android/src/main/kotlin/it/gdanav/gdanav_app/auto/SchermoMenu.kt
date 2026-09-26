package it.gdanav.gdanav_app.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.ItemList
import androidx.car.app.model.SectionedItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R

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

    /** Un menu diviso in sezioni, ognuna col suo titolo. */
    protected fun sezioni(titolo: String, gruppi: List<Pair<String, List<Row>>>): Template {
        val t = ListTemplate.Builder().setTitle(titolo).setHeaderAction(Action.BACK)
        for ((nome, righe) in gruppi) {
            if (righe.isEmpty()) continue
            val lista = ItemList.Builder()
            righe.forEach { lista.addItem(it) }
            t.addSectionedList(SectionedItemList.create(lista.build(), nome))
        }
        return t.build()
    }

    /** Un'icona dei menu, colorata. */
    protected fun icona(id: Int, colore: CarColor = CarColor.DEFAULT): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, id)).setTint(colore).build()

    /** Un'icona disegnata dal telefono (segnalazioni, colonnine), coi suoi colori. */
    protected fun immagine(nome: String): CarIcon? =
        PonteAuto.immagini[nome]?.let { CarIcon.Builder(IconCompat.createWithBitmap(it)).build() }

    protected fun riga(
        titolo: String,
        testo: String? = null,
        sfoglia: Boolean = false,
        icona: CarIcon? = null,
        azione: () -> Unit,
    ): Row {
        val r = Row.Builder().setTitle(titolo).setOnClickListener { azione() }
        if (!testo.isNullOrEmpty()) r.addText(testo)
        if (sfoglia) r.setBrowsable(true)
        icona?.let { r.setImage(it, Row.IMAGE_TYPE_ICON) }
        return r.build()
    }

    protected fun interruttore(
        titolo: String,
        acceso: Boolean,
        testo: String? = null,
        icona: CarIcon? = null,
        cambia: (Boolean) -> Unit,
    ): Row {
        val r = Row.Builder().setTitle(titolo).setToggle(Toggle.Builder { cambia(it) }.setChecked(acceso).build())
        if (!testo.isNullOrEmpty()) r.addText(testo)
        icona?.let { r.setImage(it, Row.IMAGE_TYPE_ICON) }
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
        val blu = CarColor.BLUE
        return sezioni(
            "Menu",
            listOf(
                "Vai a" to listOf(
                    if (casa != null) {
                        riga("Casa", casa.nome, icona = icona(R.drawable.icona_casa, blu)) { vai(casa) }
                    } else {
                        riga("Casa", "Tocca per impostarla", sfoglia = true, icona = icona(R.drawable.icona_casa, blu)) {
                            screenManager.push(SchermoCerca(carContext, "casa"))
                        }
                    },
                    if (lavoro != null) {
                        riga("Lavoro", lavoro.nome, icona = icona(R.drawable.icona_lavoro, blu)) { vai(lavoro) }
                    } else {
                        riga("Lavoro", "Tocca per impostarlo", sfoglia = true, icona = icona(R.drawable.icona_lavoro, blu)) {
                            screenManager.push(SchermoCerca(carContext, "lavoro"))
                        }
                    },
                    riga("Preferiti e recenti", sfoglia = true, icona = icona(R.drawable.icona_stella, CarColor.YELLOW)) {
                        screenManager.push(SchermoDestinazioni(carContext))
                    },
                ),
                "Intorno a te" to listOf(
                    // Elettrica: le colonnine; termica: i distributori.
                    if (PonteAuto.cruscotto.elettrica) {
                        riga(
                            "Colonnine vicine",
                            "Le rapide intorno a te",
                            sfoglia = true,
                            icona = icona(R.drawable.icona_colonnina, CarColor.GREEN),
                        ) { screenManager.push(SchermoColonnine(carContext)) }
                    } else {
                        riga(
                            "Distributori vicini",
                            "Coi prezzi di oggi",
                            sfoglia = true,
                            icona = icona(R.drawable.icona_distributore, CarColor.GREEN),
                        ) { screenManager.push(SchermoDistributori(carContext)) }
                    },
                    riga(
                        "Segnala",
                        "Polizia, incidente, traffico, pericolo…",
                        sfoglia = true,
                        icona = icona(R.drawable.icona_segnala, CarColor.YELLOW),
                    ) { screenManager.push(SchermoSegnala(carContext)) },
                ),
                "Impostazioni" to listOf(
                    riga(
                        "Impostazioni",
                        "Batteria all'arrivo, vista 3D, voce, percorso",
                        sfoglia = true,
                        icona = icona(R.drawable.icona_impostazioni),
                    ) { screenManager.push(SchermoImpostazioni(carContext, renderer)) },
                ),
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
        val elettrica = o["elettrica"] != false
        val arrivo = (o["arrivo"] as? Number)?.toInt()
        return elenco(
            "Impostazioni",
            listOfNotNull(
                if (elettrica) {
                    riga(
                        "Batteria all'arrivo: ${arrivo?.let { "$it%" } ?: "—"}",
                        "Con quanta carica arrivare: le soste si ricalcolano",
                        sfoglia = true,
                        icona = icona(R.drawable.icona_batteria, CarColor.GREEN),
                    ) { screenManager.push(SchermoArrivo(carContext)) }
                } else {
                    null
                },
                interruttore(
                    "Vista 3D",
                    renderer.tridimensionale,
                    "Spenta: mappa dall'alto, nord in su",
                    icona = icona(R.drawable.icona_mappa, CarColor.BLUE),
                ) {
                    if (it != renderer.tridimensionale) renderer.alternaVista()
                    invalidate()
                },
                interruttore(
                    "Voce",
                    o["muto"] != true,
                    "Le indicazioni e gli avvisi a voce",
                    icona = icona(R.drawable.icona_voce, CarColor.BLUE),
                ) { PonteAuto.alternaVoce() },
                riga(
                    "Percorso",
                    "${o["modo_nome"] ?: "Veloce"} · pedaggi, autostrade, traghetti",
                    sfoglia = true,
                    icona = icona(R.drawable.icona_percorso, CarColor.BLUE),
                ) {
                    screenManager.push(SchermoOpzioni(carContext))
                },
                riga("Imposta Casa", casa?.nome ?: "Non ancora impostata", sfoglia = true, icona = icona(R.drawable.icona_casa)) {
                    screenManager.push(SchermoCerca(carContext, "casa"))
                },
                riga(
                    "Imposta Lavoro",
                    lavoro?.nome ?: "Non ancora impostato",
                    sfoglia = true,
                    icona = icona(R.drawable.icona_lavoro),
                ) {
                    screenManager.push(SchermoCerca(carContext, "lavoro"))
                },
            ),
        )
    }
}

/** Con quanta batteria arrivare alla meta (e alle soste): si ricalcola subito. */
class SchermoArrivo(carContext: CarContext) : SchermoAggiornato(carContext) {
    private val scelte = listOf(5, 10, 15, 20, 25, 30)

    override fun onGetTemplate(): Template {
        val ora = (PonteAuto.opzioni["arrivo"] as? Number)?.toInt()
        return elenco(
            "Batteria all'arrivo",
            scelte.map { v ->
                riga(if (v == ora) "✓  $v%" else "$v%", if (v == ora) "Scelta adesso" else null) {
                    PonteAuto.cambiaOpzione("arrivo", v)
                    screenManager.pop()
                }
            },
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
                riga(c.nome, c.descrizione, icona = icona(R.drawable.icona_colonnina, CarColor.GREEN)) {
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

/** Auto termica: i distributori vicini. In guida ci si passa e si prosegue. */
class SchermoDistributori(carContext: CarContext) : SchermoAggiornato(carContext) {
    private var distributori: List<PonteAuto.Luogo>? = null

    override fun onCreate(owner: LifecycleOwner) {
        super.onCreate(owner)
        PonteAuto.distributori {
            distributori = it
            invalidate()
        }
    }

    override fun onGetTemplate(): Template {
        val trovati = distributori
            ?: return ListTemplate.Builder().setTitle("Distributori vicini").setHeaderAction(Action.BACK).setLoading(true).build()
        val limite = try {
            carContext.getCarService(androidx.car.app.constraints.ConstraintManager::class.java)
                .getContentLimit(androidx.car.app.constraints.ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
        } catch (e: Exception) {
            6
        }
        return elenco(
            "Distributori vicini",
            trovati.take(limite).map { d ->
                riga(d.nome, d.descrizione, icona = icona(R.drawable.icona_distributore, CarColor.GREEN)) {
                    PonteAuto.passa(d)
                    screenManager.popToRoot()
                }
            },
            "Nessun distributore qui intorno",
        )
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
            riga(nome, icona = immagine("segnala-$tipo") ?: icona(R.drawable.icona_segnala, CarColor.YELLOW)) {
                PonteAuto.segnala(tipo) { frase -> avvisa(frase) }
                screenManager.pop()
            }
        },
    )
}

/** La scheda di un punto toccato sulla mappa: cosa è, le informazioni, e «Vai». */
class SchermoPunto(carContext: CarContext, private val info: Map<String, Any?>) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val righe = (info["righe"] as? List<*>)?.mapNotNull { it as? String }?.filter { it.isNotBlank() } ?: emptyList()
        val pannello = Pane.Builder()
        // Quattro righe al massimo: è il limite delle auto.
        val testi = listOfNotNull(info["sopra"] as? String) + righe
        testi.take(4).forEach { pannello.addRow(Row.Builder().setTitle(it).build()) }
        @Suppress("UNCHECKED_CAST")
        val luogo = (info["luogo"] as? Map<String, Any?>)?.let { PonteAuto.luogoDa(it) }
        if (luogo != null) {
            pannello.addAction(
                Action.Builder()
                    .setTitle(info["vai"] as? String ?: "Vai")
                    .setOnClickListener {
                        PonteAuto.passa(luogo)
                        screenManager.popToRoot()
                    }
                    .build(),
            )
        }
        return PaneTemplate.Builder(pannello.build())
            .setTitle(info["titolo"] as? String ?: "Punto")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
