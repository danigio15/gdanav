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
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R

/**
 * Uno schermo dell'auto che si rifà quando cambia quello che ha in pagina.
 *
 * Il telefono manda novità in continuazione: mentre si guida, la distanza
 * alla prossima manovra scende ogni secondo. Rifare a ogni novità anche gli
 * schermi che della guida non mostrano niente li fa tremare, e consuma gli
 * aggiornamenti che l'auto concede. Perciò ogni schermo dice con [firma] cosa
 * ha in pagina, e si rifà solo quando quella cambia.
 */
abstract class SchermoAggiornato(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    /** Quello che questo schermo mostra: cambia lei, si rifà lui. */
    protected abstract fun firma(): Any?

    /** Come si disegna: al posto di `onGetTemplate`, che qui segna la firma. */
    protected abstract fun schermata(): Template

    private var disegnata: Any? = null
    private val aggiorna: () -> Unit = {
        val ora = firma()
        if (ora != disegnata) {
            disegnata = ora
            invalidate()
        }
    }

    init {
        lifecycle.addObserver(this)
    }

    final override fun onGetTemplate(): Template {
        disegnata = firma()
        return schermata()
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
    // In pagina: i nomi di Casa e Lavoro, e se l'auto è elettrica (colonnine
    // o distributori). Della guida non mostra niente.
    override fun firma(): Any? = listOf(PonteAuto.casa()?.nome, PonteAuto.lavoro()?.nome, PonteAuto.cruscotto.elettrica)

    override fun schermata(): Template {
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
                            "Intorno a te, dalla più vicina",
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
                        "Mappa e simbolo dell'auto, voce, avvisi, percorso",
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

/**
 * Le impostazioni in auto. «Dall'auto devi dare la possibilità di comandare di
 * più le impostazioni: gli avvisi non si possono modificare, idem il simbolo
 * dell'auto.» Sei righe al più (quello che ogni auto mostra guidando), e
 * dentro le cose che stanno insieme: la mappa (vista, 3D aumentato, simbolo,
 * ZTL), gli avvisi uno per uno, il percorso, Casa e Lavoro.
 */
class SchermoImpostazioni(carContext: CarContext, private val renderer: RendererMappa) : SchermoAggiornato(carContext) {
    // In pagina: le opzioni e la vista della mappa.
    override fun firma(): Any? = listOf(PonteAuto.opzioni, renderer.vista)

    override fun schermata(): Template {
        val o = PonteAuto.opzioni
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
                riga(
                    "Mappa",
                    listOfNotNull(
                        renderer.vista.titolo,
                        if (o["aumentato"] == true) "3D aumentato" else null,
                        nomeDelSimbolo(o),
                    ).joinToString(" · "),
                    sfoglia = true,
                    icona = icona(R.drawable.icona_mappa, CarColor.BLUE),
                ) { screenManager.push(SchermoMappa(carContext, renderer)) },
                // L'audio: il modo (tutto, solo avvisi, silenzio), il volume e
                // la velocità della voce, e la prova. «Anche il discorso audio
                // deve essere modificabile.»
                riga(
                    when (audio(o)) {
                        "avvisi" -> "Audio: solo avvisi"
                        "silenzio" -> "Audio: silenzio"
                        else -> "Audio: tutto"
                    },
                    listOfNotNull(
                        (o["voce_volume_nome"] as? String)?.let { "volume $it".lowercase() },
                        (o["voce_velocita_nome"] as? String)?.let { "voce $it".lowercase() },
                    ).joinToString(" · ").ifEmpty { "Indicazioni, avvisi, volume" },
                    sfoglia = true,
                    icona = icona(R.drawable.icona_voce, if (audio(o) == "silenzio") CarColor.DEFAULT else CarColor.BLUE),
                ) { screenManager.push(SchermoAudio(carContext)) },
                if (avvisi(o).isNotEmpty()) {
                    riga(
                        "Avvisi",
                        riassuntoAvvisi(avvisi(o)),
                        sfoglia = true,
                        icona = icona(R.drawable.icona_segnala, CarColor.YELLOW),
                    ) { screenManager.push(SchermoAvvisi(carContext)) }
                } else {
                    null
                },
                riga(
                    "Percorso",
                    "${o["modo_nome"] ?: "Veloce"} · pedaggi, autostrade, traghetti",
                    sfoglia = true,
                    icona = icona(R.drawable.icona_percorso, CarColor.BLUE),
                ) {
                    screenManager.push(SchermoOpzioni(carContext))
                },
                riga(
                    "Casa e Lavoro",
                    listOf(PonteAuto.casa()?.nome ?: "Casa da impostare", PonteAuto.lavoro()?.nome ?: "Lavoro da impostare")
                        .joinToString(" · "),
                    sfoglia = true,
                    icona = icona(R.drawable.icona_casa),
                ) { screenManager.push(SchermoCasaLavoro(carContext)) },
            ),
        )
    }
}

/**
 * L'audio: cosa si sente (scelto direttamente, non più solo a giri), il
 * volume e la velocità della voce, e una frase di prova. Valgono anche sul
 * telefono.
 */
class SchermoAudio(carContext: CarContext) : SchermoAggiornato(carContext) {
    override fun firma(): Any? = listOf(
        PonteAuto.opzioni["audio"],
        PonteAuto.opzioni["muto"],
        PonteAuto.opzioni["voce_volume"],
        PonteAuto.opzioni["voce_velocita"],
    )

    override fun schermata(): Template {
        val o = PonteAuto.opzioni
        val ora = audio(o)
        val modi = scelte(o, "audio_modi").ifEmpty {
            listOf(Triple("tutto", "Tutto", ""), Triple("avvisi", "Solo avvisi", ""), Triple("silenzio", "Silenzio", ""))
        }
        val volumi = scelte(o, "voce_volumi")
        val velocita = scelte(o, "voce_velocitas")
        fun dopo(elenco: List<Triple<String, String, String>>, id: Any?): String? {
            if (elenco.isEmpty()) return null
            val i = elenco.indexOfFirst { it.first == id }
            return elenco[(i + 1) % elenco.size].first
        }
        return elenco(
            "Audio",
            modi.map { (id, nome, sotto) ->
                riga(if (id == ora) "✓  $nome" else nome, sotto.ifEmpty { null }) {
                    PonteAuto.scegli(mapOf("audio" to id))
                }
            } + listOfNotNull(
                dopo(volumi, o["voce_volume"])?.let { prossimo ->
                    riga("Volume della voce: ${o["voce_volume_nome"] ?: "Alto"}", "Tocca per cambiare: basso, medio, alto") {
                        PonteAuto.scegli(mapOf("voce_volume" to prossimo, "prova_voce" to true))
                    }
                },
                dopo(velocita, o["voce_velocita"])?.let { prossima ->
                    riga("Velocità della voce: ${o["voce_velocita_nome"] ?: "Normale"}", "Tocca per cambiare: lenta, normale, veloce") {
                        PonteAuto.scegli(mapOf("voce_velocita" to prossima, "prova_voce" to true))
                    }
                },
            ),
        )
    }
}

/** Le scelte di un elenco mandato dal telefono: id, nome, sotto. */
private fun scelte(o: Map<String, Any?>, chiave: String): List<Triple<String, String, String>> =
    (o[chiave] as? List<*>).orEmpty().mapNotNull { r ->
        val m = r as? Map<*, *> ?: return@mapNotNull null
        val id = m["id"] as? String ?: return@mapNotNull null
        Triple(id, m["nome"] as? String ?: id, m["sotto"] as? String ?: "")
    }

/** La mappa: la vista, il 3D aumentato, il simbolo dell'auto, le ZTL. */
class SchermoMappa(carContext: CarContext, private val renderer: RendererMappa) : SchermoAggiornato(carContext) {
    override fun firma(): Any? = listOf(PonteAuto.opzioni, renderer.vista)

    override fun schermata(): Template {
        val o = PonteAuto.opzioni
        return elenco(
            "Mappa",
            listOfNotNull(
                // La vista a tre stati, come l'audio: ogni tocco passa alla dopo.
                riga(
                    "Vista: ${renderer.vista.titolo}",
                    when (renderer.vista) {
                        Vista.PIATTA -> "Dall'alto, nord in su. Tocca per il 3D"
                        Vista.INCLINATA -> "Inclinata, con gli edifici. Tocca per l'immersiva"
                        Vista.IMMERSIVA -> "Da vicino, con le corsie sulla strada. Tocca per il 2D"
                    },
                    icona = icona(R.drawable.icona_mappa, CarColor.BLUE),
                ) {
                    renderer.alternaVista()
                    invalidate()
                },
                // Lo stesso interruttore del telefono: vale anche lì.
                (o["aumentato"] as? Boolean)?.let { acceso ->
                    interruttore(
                        "3D aumentato",
                        acceso,
                        "Viadotti, alberi ed edifici in 3D, nelle viste 3D e immersiva",
                    ) { PonteAuto.scegli(mapOf("aumentato" to it)) }
                },
                riga(
                    "Simbolo dell'auto",
                    nomeDelSimbolo(o) ?: "Freccia",
                    sfoglia = true,
                    icona = icona(R.drawable.icona_mappa),
                ) { screenManager.push(SchermoSimbolo(carContext)) },
                (o["ztl_mappa"] as? Boolean)?.let { acceso ->
                    interruttore("ZTL sulla mappa", acceso, "Le zone a traffico limitato e le aree pedonali") {
                        PonteAuto.scegli(mapOf("ztl_mappa" to it))
                    }
                },
            ),
        )
    }
}

/** Il simbolo dell'auto sulla mappa: la freccia o un'auto, come sul telefono. */
class SchermoSimbolo(carContext: CarContext) : SchermoAggiornato(carContext) {
    override fun firma(): Any? = PonteAuto.opzioni["segnaposto"]

    override fun schermata(): Template {
        val ora = PonteAuto.opzioni["segnaposto"] as? String
        return elenco(
            "Simbolo dell'auto",
            simboli(PonteAuto.opzioni).map { (id, nome) ->
                riga(if (id == ora) "✓  $nome" else nome, if (id == ora) "Scelto adesso" else null) {
                    PonteAuto.scegli(mapOf("segnaposto" to id))
                    screenManager.pop()
                }
            },
        )
    }
}

/**
 * Gli avvisi, uno per uno, divisi in due: quelli della strada (autovelox,
 * tutor, ZTL, limite) e le segnalazioni di chi passa. Due schermate e non una:
 * dieci righe in una lista l'auto non le mostra guidando.
 */
class SchermoAvvisi(carContext: CarContext) : SchermoAggiornato(carContext) {
    override fun firma(): Any? = avvisi(PonteAuto.opzioni)

    override fun schermata(): Template {
        val tutti = avvisi(PonteAuto.opzioni)
        val (segnalazioni, strada) = tutti.partition { it.segnalazione }
        return elenco(
            "Avvisi",
            listOf(
                riga("Della strada", riassuntoAvvisi(strada), sfoglia = true) {
                    screenManager.push(SchermoGruppoAvvisi(carContext, "Della strada", segnalazioni = false))
                },
                riga("Segnalati da chi passa", riassuntoAvvisi(segnalazioni), sfoglia = true) {
                    screenManager.push(SchermoGruppoAvvisi(carContext, "Segnalati da chi passa", segnalazioni = true))
                },
            ),
        )
    }
}

/** Un gruppo di avvisi: ogni tocco passa al modo dopo (voce, beep, schermo, spento). */
class SchermoGruppoAvvisi(
    carContext: CarContext,
    private val titolo: String,
    private val segnalazioni: Boolean,
) : SchermoAggiornato(carContext) {
    override fun firma(): Any? = avvisi(PonteAuto.opzioni)

    override fun schermata(): Template = elenco(
        titolo,
        avvisi(PonteAuto.opzioni).filter { it.segnalazione == segnalazioni }.map { a ->
            riga(
                "${a.nome}: ${a.comeNome}",
                "${a.sotto} · tocca per cambiare",
                icona = immagine("segnala-${a.id}")
                    ?: icona(R.drawable.icona_segnala, if (a.come == "spento") CarColor.DEFAULT else CarColor.YELLOW),
            ) { PonteAuto.scegli(mapOf("avviso" to a.id, "come" to a.dopo())) }
        },
    )
}

/** Dove sono Casa e Lavoro. */
class SchermoCasaLavoro(carContext: CarContext) : SchermoAggiornato(carContext) {
    override fun firma(): Any? = listOf(PonteAuto.casa()?.nome, PonteAuto.lavoro()?.nome)

    override fun schermata(): Template {
        val casa = PonteAuto.casa()
        val lavoro = PonteAuto.lavoro()
        return elenco(
            "Casa e Lavoro",
            listOf(
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

/** Un avviso come lo manda il telefono (`ponte_auto.dart`, opzioni). */
private data class AvvisoInAuto(
    val id: String,
    val nome: String,
    val sotto: String,
    val come: String,
    val comeNome: String,
    val soloVoce: Boolean,
    val segnalazione: Boolean,
) {
    /** Il modo dopo, in giro: voce, beep, schermo, spento. Il limite non si spegne (c'è il tachimetro). */
    fun dopo(): String {
        val giro = if (soloVoce) listOf("voce", "beep", "schermo") else listOf("voce", "beep", "schermo", "spento")
        val i = giro.indexOf(come)
        return giro[(i + 1) % giro.size]
    }
}

private fun avvisi(o: Map<String, Any?>): List<AvvisoInAuto> =
    (o["avvisi"] as? List<*>).orEmpty().mapNotNull { r ->
        val m = r as? Map<*, *> ?: return@mapNotNull null
        val id = m["id"] as? String ?: return@mapNotNull null
        AvvisoInAuto(
            id = id,
            nome = m["nome"] as? String ?: id,
            sotto = m["sotto"] as? String ?: "",
            come = m["come"] as? String ?: "voce",
            comeNome = m["come_nome"] as? String ?: "Voce",
            soloVoce = m["solo_voce"] == true,
            segnalazione = m["segnalazione"] == true,
        )
    }

/** «Tutti a voce», «2 spenti · 1 solo schermo». */
private fun riassuntoAvvisi(elenco: List<AvvisoInAuto>): String {
    val spenti = elenco.count { it.come == "spento" }
    val beep = elenco.count { it.come == "beep" }
    val schermo = elenco.count { it.come == "schermo" }
    if (spenti == 0 && beep == 0 && schermo == 0) return "Tutti a voce"
    return listOfNotNull(
        if (spenti > 0) (if (spenti == 1) "1 spento" else "$spenti spenti") else null,
        if (beep > 0) (if (beep == 1) "1 col beep" else "$beep col beep") else null,
        if (schermo > 0) "$schermo solo a schermo" else null,
    ).joinToString(" · ")
}

private fun simboli(o: Map<String, Any?>): List<Pair<String, String>> =
    (o["segnaposti"] as? List<*>).orEmpty().mapNotNull { r ->
        val m = r as? Map<*, *> ?: return@mapNotNull null
        val id = m["id"] as? String ?: return@mapNotNull null
        id to (m["nome"] as? String ?: id)
    }

private fun nomeDelSimbolo(o: Map<String, Any?>): String? {
    val ora = o["segnaposto"] as? String ?: return null
    return simboli(o).firstOrNull { it.first == ora }?.second
}

/**
 * Com'è l'audio: «tutto», «avvisi» (solo gli avvisi) o «silenzio». Un'app
 * sul telefono più vecchia manda solo «muto»: muta vuol dire senza voce.
 */
private fun audio(o: Map<String, Any?>): String =
    o["audio"] as? String ?: if (o["muto"] == true) "silenzio" else "tutto"

/** Con quanta batteria arrivare alla meta (e alle soste): si ricalcola subito. */
class SchermoArrivo(carContext: CarContext) : SchermoAggiornato(carContext) {
    private val scelte = listOf(5, 10, 15, 20, 25, 30)

    // In pagina: qual è la scelta di adesso.
    override fun firma(): Any? = PonteAuto.opzioni["arrivo"]

    override fun schermata(): Template {
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

    // In pagina: le opzioni del percorso.
    override fun firma(): Any? = PonteAuto.opzioni

    override fun schermata(): Template {
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

/** Le colonnine vicine adatte alla tua auto, anche le lente; con Premium libere e occupate. */
class SchermoColonnine(carContext: CarContext) : SchermoAggiornato(carContext) {
    private var colonnine: List<PonteAuto.Luogo>? = null

    override fun onCreate(owner: LifecycleOwner) {
        super.onCreate(owner)
        PonteAuto.colonnine {
            colonnine = it
            invalidate()
        }
    }

    // Le colonnine se le chiede da sé e da sé si rifà: del telefono, in
    // pagina, non c'è niente.
    override fun firma(): Any? = Unit

    override fun schermata(): Template {
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
            "Nessuna colonnina qui intorno",
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

    // Come le colonnine: l'elenco se lo chiede da sé.
    override fun firma(): Any? = Unit

    override fun schermata(): Template {
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

    // In pagina: i disegni delle segnalazioni, che arrivano dal telefono.
    override fun firma(): Any? = PonteAuto.immagini

    override fun schermata(): Template = elenco(
        "Segnala",
        tipi.map { (tipo, nome) ->
            riga(nome, icona = immagine("segnala-$tipo") ?: icona(R.drawable.icona_segnala, CarColor.YELLOW)) {
                PonteAuto.segnala(tipo) { frase -> avvisa(frase) }
                screenManager.pop()
            }
        },
    )
}
