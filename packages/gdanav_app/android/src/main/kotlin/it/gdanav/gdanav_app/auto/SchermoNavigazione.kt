package it.gdanav.gdanav_app.auto

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import it.gdanav.gdanav_app.R
import it.gdanav.gdanav_app.musica.AvvioMusica
import it.gdanav.gdanav_app.musica.LettoreTelefono

/**
 * Lo schermo dell'auto: la mappa di GdANav sotto (con velocità, limite, dati
 * dell'auto e il lettore musicale), sopra la prossima manovra con corsie,
 * svincolo e arrivo nelle schede di Android Auto. In alto Cerca, Menu e
 * Fine; a lato sposta, + e −, 2D/3D e Centra. In guida il viaggio va anche
 * al cruscotto dell'auto e nella notifica di navigazione.
 */
class SchermoNavigazione(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val renderer = RendererMappa(carContext)
    private val navigazione = carContext.getCarService(NavigationManager::class.java)
    private var navigando = false
    private val guidaAuto = GuidaAuto(carContext)

    /**
     * Quello che questo schermo ha in pagina: la manovra, il messaggio da
     * fermi, la segnalazione appena passata. La mappa sotto si ridisegna per
     * conto suo, che il modello si rifaccia o no.
     */
    private fun firma(): Any? = listOf(
        PonteAuto.guida,
        PonteAuto.messaggio,
        PonteAuto.avviso.ancoraId,
        PonteAuto.strada.id,
        PonteAuto.termica.id,
        PonteAuto.arrivo,
        PonteAuto.strade?.id,
        // La musica cambia i tasti in alto (⏯ ⏭) solo dove sta lì e non nel
        // lettore sulla mappa, solo quando c'è o no, e quando passa da play
        // a pausa: non a ogni brano.
        musicaInAlto(),
        musicaInAlto() && LettoreTelefono.daMostrare,
        if (musicaInAlto()) LettoreTelefono.brano?.suona else null,
        // Senza brano ⏯ dice chi parte («▶ Spotify», «Avvio…»).
        if (musicaInAlto() && LettoreTelefono.brano == null) LettoreTelefono.prossima?.nome to LettoreTelefono.inAvvio else null,
        // La strada proposta coi tasti in alto, quando il suo avviso non può
        // uscire.
        PonteAuto.stradaNeiTasti,
    )

    private var disegnata: Any? = null
    private var daAggiornare = false
    private val aggiorna: () -> Unit = {
        fermaSeVecchia()
        PonteAuto.stradaNeiTasti = stradaNeiTasti()
        renderer.aggiorna()
        sincronizzaNavigazione()
        mostraAvvisoCasa()
        avvisaPermessoMusica()
        // Il modello si rifà solo se cambia quello che mostra: l'auto concede
        // pochi aggiornamenti.
        val ora = firma()
        if (ora != disegnata) {
            disegnata = ora
            viaggioAlCruscotto()
            proponiStrada()
            proponiTermica()
            mostraArrivo()
            mostraStrade()
            invalidate()
        }
    }

    /** La strada a risparmio già chiesta all'arbitro degli avvisi. */
    private var stradaMostrata: String? = null

    /**
     * La strada a risparmio (o più rapida) proposta dal telefono. Dalle auto
     * con l'API 5 è l'avviso di Android Auto, coi due tasti, che sparisce da
     * solo dopo venti secondi come sul telefono; prima i tasti stanno in alto
     * ([azioni]) e il testo nel pannello sulla mappa. Passa dall'arbitro
     * ([ArbitroAvvisi]): se sullo schermo c'è un urgente di casa aspetta, e
     * intanto va coi tasti in alto ([stradaNeiTasti]).
     */
    private fun proponiStrada() {
        val s = PonteAuto.strada
        val id = s.id
        if (id == stradaMostrata) return
        stradaMostrata = id
        if (carContext.carAppApiLevel < 5) return
        if (id == null) {
            // Presa, rifiutata o scaduta sul telefono: via anche dall'auto.
            ArbitroAvvisi.togli(AVVISO_STRADA)
            return
        }
        ArbitroAvvisi.mostra(
            ArbitroAvvisi.Avviso(
                chiave = AVVISO_STRADA,
                precedenza = ArbitroAvvisi.STRADA,
                titolo = s.titolo ?: "Strada a risparmio",
                testo = s.testo,
                icona = icona(R.drawable.auto_foglia),
                durataMs = 20_000L,
                tasti = listOf(
                    ArbitroAvvisi.Tasto("Prendila", principale = true) { PonteAuto.rispondiStrada(id, true) },
                    ArbitroAvvisi.Tasto("Resto qui") { PonteAuto.rispondiStrada(id, false) },
                ),
            ),
        )
    }

    /**
     * La strada proposta sta coi tasti in alto: sulle auto senza avvisi, e
     * quando il suo avviso aspetta dietro uno che conta di più.
     */
    private fun stradaNeiTasti(): Boolean =
        PonteAuto.strada.id != null && (carContext.carAppApiLevel < 5 || ArbitroAvvisi.scalzata(AVVISO_STRADA))

    /** L'avviso di casa già chiesto all'arbitro: id, se era la domanda, titolo e testo. */
    private var casaChiesta: String? = null

    /**
     * Un avviso di casa (dentro GdAHome): dalle auto con l'API 5 è l'avviso di
     * Android Auto, sopra la mappa, coi suoi tasti (al più due, li sceglie il
     * telefono). Il tasto torna al telefono, che fa la domanda «Sì / No» se
     * serve e poi lo passa a GdAHome. Sulle auto più vecchie, solo il titolo
     * in un messaggio breve.
     *
     * Passa dall'arbitro ([ArbitroAvvisi]), che lo mostra solo con la mappa
     * in cima (se no dà subito il titolo e lo mostra al ritorno), lo rimette
     * se un altro avviso l'ha scalzato, e dice come è finito. La chiave
     * comprende titolo e testo: il gruppo «3 notifiche» che diventa 4 si
     * aggiorna.
     *
     * Gli urgenti e la domanda non hanno un tempo sul telefono: qui sì (dieci
     * minuti, e mezzo minuto per la domanda), e quando l'auto li toglie da
     * sola lo si dice al telefono ([PonteAuto.casaScaduta]), che fa passare
     * quelli dopo.
     */
    private fun mostraAvvisoCasa() {
        val a = PonteAuto.avvisoCasa
        val chiave = a?.let { "${it.id}|${it.conferma}|${it.titolo}|${it.testo}" }
        if (chiave == casaChiesta) return
        casaChiesta = chiave
        if (a == null) {
            ArbitroAvvisi.togli(AVVISO_CASA)
            return
        }
        val secondi = a.secondi
        val durata = when {
            secondi != null -> secondi.toLong().coerceAtLeast(3L) * 1000L
            a.conferma -> 30_000L
            else -> 600_000L
        }
        val mostrato = ArbitroAvvisi.mostra(
            ArbitroAvvisi.Avviso(
                chiave = AVVISO_CASA,
                precedenza = if (a.urgente) ArbitroAvvisi.URGENTE else ArbitroAvvisi.INFORMATIVO,
                titolo = a.titolo,
                testo = a.testo,
                icona = a.icona?.let { CarIcon.Builder(IconCompat.createWithBitmap(it)).build() },
                durataMs = durata,
                tasti = a.tasti.map { t ->
                    ArbitroAvvisi.Tasto(t.etichetta, t.principale) { PonteAuto.tastoCasa(a.id, t.id) }
                },
                alFine = { fine ->
                    when (fine) {
                        // Chiuso a mano sull'auto: via anche dal telefono.
                        ArbitroAvvisi.Fine.CHIUSO -> PonteAuto.tastoCasa(a.id, "_chiudi")
                        // Tolto dall'auto: il telefono non lo aspetta più.
                        ArbitroAvvisi.Fine.SCADUTO -> PonteAuto.casaScaduta(a.id, a.conferma)
                        ArbitroAvvisi.Fine.TASTO -> {}
                    }
                },
            ),
        )
        if (!mostrato) {
            // Un'auto senza avvisi: almeno il titolo. E il telefono non
            // aspetta un tocco che qui non può arrivare.
            try {
                CarToast.makeText(carContext, a.titolo, CarToast.LENGTH_LONG).show()
            } catch (_: Exception) {}
            if (a.secondi == null) PonteAuto.casaScaduta(a.id, a.conferma)
        }
    }

    /** L'invito al permesso della musica già dato in questa sessione. */
    private var permessoDetto = false

    /**
     * «Musica nel navigatore» è accesa ma manca l'«Accesso alle notifiche»:
     * chi usa GdANav solo in auto l'invito del telefono non lo vede mai.
     * Allora un messaggio breve sull'auto, e sul telefono una notifica
     * silenziosa che apre dritta la pagina del sistema.
     *
     * Il messaggio manda a guardare il telefono: per questo esce **solo da
     * fermi** (in marcia si rimanda alla prima sosta) e dice di farlo quando
     * è sicuro (criterio VI-1 di Google). Una volta per sessione e al più due
     * in tutto, e mai più dopo «Non ora» o con la musica spenta
     * ([LettoreTelefono.invitoPossibile]).
     */
    private fun avvisaPermessoMusica() {
        if (permessoDetto || !LettoreTelefono.invitoPossibile(carContext) || !PonteAuto.daFermi()) return
        permessoDetto = true
        LettoreTelefono.invitoDato(carContext)
        try {
            CarToast.makeText(
                carContext,
                "Musica: da fermo, quando è sicuro, consenti l'accesso alle notifiche sul telefono",
                CarToast.LENGTH_LONG,
            ).show()
        } catch (_: Exception) {}
        LettoreTelefono.notificaPermesso(carContext)
    }

    /** Il riepilogo dell'arrivo già aperto ([SchermoRiepilogoArrivo]). */
    private var arrivoMostrato: PonteAuto.Arrivo? = null

    /**
     * Arrivati: sopra la mappa la schermata del riepilogo, con i costi e
     * «Fine». Una volta per arrivo: se il riepilogo cambia (si dice quanto si
     * è pagato una ricarica) la schermata si rifà da sé.
     */
    private fun mostraArrivo() {
        val a = PonteAuto.arrivo
        val giaAperto = arrivoMostrato != null
        arrivoMostrato = a
        if (a == null || giaAperto || PonteAuto.guida != null) return
        screenManager.push(SchermoRiepilogoArrivo(carContext))
    }

    /** Le strade già aperte ([SchermoStrade]): una volta per viaggio calcolato. */
    private var stradeMostrate: String? = null

    /**
     * Calcolato il viaggio (dall'auto o dal telefono), sopra la mappa le
     * strade fra cui scegliere, con «Avvia». Se le chiude il telefono
     * (partito, o un altro viaggio) se ne vanno da sé.
     */
    private fun mostraStrade() {
        val s = PonteAuto.strade
        if (s == null || PonteAuto.guida != null || s.id == stradeMostrate) return
        stradeMostrate = s.id
        if (screenManager.top is SchermoStrade) return
        screenManager.push(SchermoStrade(carContext))
    }

    /** La proposta dell'auto termica già aperta ([SchermoTermica]). */
    private var termicaMostrata: String? = null

    /**
     * Manca la batteria: il messaggio sulla mappa non ha tasti, e in auto la
     * batteria non si scrive. Si apre sopra [SchermoTermica], col tasto per
     * passare all'auto termica; una proposta per volta.
     */
    private fun proponiTermica() {
        val id = PonteAuto.termica.id
        if (id == termicaMostrata) return
        termicaMostrata = id
        if (id == null || PonteAuto.guida != null) return
        // Quella di prima, se c'è, si chiude da sé: l'id non è più il suo.
        screenManager.push(SchermoTermica(carContext, id))
    }

    /**
     * Questa versione di GdANav è troppo vecchia (lo dice il telefono, vedi
     * `GestoreAggiornamento`): la guida si ferma e sopra la mappa resta lo
     * schermo che dice che serve un aggiornamento.
     */
    private fun fermaSeVecchia() {
        val vecchia = PonteAuto.aggiorna(carContext)
        if (vecchia && !daAggiornare) {
            if (PonteAuto.guida != null) PonteAuto.fermaDallAuto()
            screenManager.popToRoot()
            screenManager.push(SchermoPremium(carContext, sopraLaMappa = true))
        }
        daAggiornare = vecchia
    }

    /** Il viaggio anche al cruscotto dell'auto e alle altre schermate (NF-4). */
    private fun viaggioAlCruscotto() {
        val g = PonteAuto.guida ?: return
        if (!navigando) return
        try {
            navigazione.updateTrip(guidaAuto.viaggio(g))
        } catch (e: Exception) {
            // Un'auto senza cruscotto per le app: si guida lo stesso.
        }
    }

    init {
        lifecycle.addObserver(this)
        PonteAuto.conAvvisi = carContext.carAppApiLevel >= 5
        PonteAuto.pedaggioNellaStima = carContext.carAppApiLevel >= 5
        // I tocchi sulla mappa (e sul lettore musicale) arrivano dall'API 5.
        MusicaInAuto.api5 = carContext.carAppApiLevel >= 5
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(renderer)
        renderer.alCambio = { invalidate() }
        // Tocco su un distributore, una colonnina o un ristorante: la scheda.
        // Toccandone un altro con la scheda aperta sopra la mappa, la scheda
        // cambia: non se ne impilano due.
        renderer.alPunto = { proprieta, lat, lon ->
            PonteAuto.punto(proprieta, lat, lon) { info ->
                if (info != null) {
                    if (screenManager.top is SchermoPunto) screenManager.pop()
                    screenManager.push(SchermoPunto(carContext, info, renderer, lat, lon))
                }
            }
        }
        navigazione.setNavigationManagerCallback(object : NavigationManagerCallback {
            override fun onStopNavigation() {
                PonteAuto.fermaDallAuto()
            }

            // La prova di guida (NF-7): il revisore la accende da fermo, e il
            // telefono percorre il viaggio da solo.
            override fun onAutoDriveEnabled() {
                PonteAuto.provaDiGuida()
            }
        })
    }

    /**
     * La musica cambia sul telefono (un brano, la copertina, play/pausa): si
     * ridisegna il lettore sulla mappa, lui solo. Il resto (la mappa, i
     * tasti in alto) si rifà come per una novità solo se cambia quello che
     * questo schermo ha in pagina (dove i comandi stanno nel lettore, mai), o
     * se manca il permesso: l'invito a darlo si guarda lì
     * ([avvisaPermessoMusica]).
     */
    private val musica: () -> Unit = {
        renderer.aggiornaPannello()
        diciEsitoAvvio()
        if (firma() != disegnata || LettoreTelefono.senzaPermesso) PonteAuto.rinfresca()
    }

    /**
     * ▶ toccato qui con niente che suona, e dopo qualche secondo non è
     * partito niente ([AvvioMusica]): lo si dice con un messaggio breve, una
     * volta. Mai di aprire l'app ora: sul telefono, da fermi.
     */
    private fun diciEsitoAvvio() {
        val e = LettoreTelefono.esito ?: return
        if (!e.dallAuto) return
        AvvioMusica.esitoDetto(e.id)
        try {
            CarToast.makeText(carContext, e.testo, CarToast.LENGTH_SHORT).show()
        } catch (_: Exception) {}
    }

    override fun onCreate(owner: LifecycleOwner) {
        // Gli avvisi di Android Auto esistono solo sopra la mappa: l'arbitro
        // li mostra quando questo schermo è in cima e si vede.
        ArbitroAvvisi.collega(carContext) {
            screenManager.top === this && lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        }
        // Cambia chi c'è sullo schermo: la strada proposta può dover passare
        // ai tasti in alto, o tornarne.
        ArbitroAvvisi.alCambio = { PonteAuto.rinfresca() }
        PonteAuto.ascolta(aggiorna)
        LettoreTelefono.ascolta(musica)
        // Il permesso e i lettori aperti si rileggono salendo in macchina: il
        // permesso può essere stato dato mentre GdANav dormiva.
        LettoreTelefono.ricontrolla(carContext)
        sincronizzaNavigazione()
    }

    /**
     * La mappa torna in cima (chiuso il Menu, la ricerca, la casa) o davanti
     * sull'auto: gli avvisi che aspettavano escono adesso, e il permesso
     * della musica si riguarda.
     */
    override fun onStart(owner: LifecycleOwner) {
        ArbitroAvvisi.mappaTornata()
        LettoreTelefono.ricontrolla(carContext)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        PonteAuto.smetti(aggiorna)
        LettoreTelefono.smetti(musica)
        // Finita la sessione: l'avviso di casa tenuto per l'auto non vale
        // più (alla prossima il telefono rimanda quello di allora).
        ArbitroAvvisi.scollega(carContext)
        PonteAuto.fineSessione()
        // Il lettore richiuso a pillola vale per questa sessione.
        MusicaInAuto.fineSessione()
        // Finita la sessione in auto finisce anche la prova di guida.
        PonteAuto.fineProva()
        if (navigando) navigazione.navigationEnded()
        navigando = false
    }

    /** Android Auto vuole sapere quando si naviga, per le altre app e l'assistente. */
    private fun sincronizzaNavigazione() {
        val guida = PonteAuto.guida != null
        if (guida && !navigando) {
            navigazione.navigationStarted()
            navigando = true
            chiediNotifiche()
            viaggioAlCruscotto()
        } else if (!guida && navigando) {
            navigazione.navigationEnded()
            navigando = false
        }
    }

    private var notificheChieste = false

    /** Da Android 13 le notifiche (quella della guida) vanno chieste: una volta. */
    private fun chiediNotifiche() {
        if (notificheChieste || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        notificheChieste = true
        if (ContextCompat.checkSelfPermission(carContext, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        try {
            carContext.requestPermissions(listOf(Manifest.permission.POST_NOTIFICATIONS)) { concessi, _ ->
                if (concessi.isNotEmpty()) NotificaGuida.aggiorna(carContext, PonteAuto.guida)
            }
        } catch (e: Exception) {
            // Chi non può chiederlo in auto lo chiederà l'app sul telefono.
        }
    }

    private fun icona(id: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, id)).build()

    private fun tasto(id: Int, azione: () -> Unit) =
        Action.Builder().setIcon(icona(id)).setOnClickListener { azione() }.build()

    /**
     * La musica si comanda coi tasti in alto: accesa e col permesso, e i
     * comandi non stanno già nel lettore sulla mappa
     * ([MusicaInAuto.nelLettore]: le auto che mandano i tocchi, dall'API 5).
     */
    private fun musicaInAlto() = LettoreTelefono.conTasti && !MusicaInAuto.nelLettore

    /**
     * In alto, al più quattro tasti: Cerca, la casa (dentro GdAHome) e Menu
     * (in guida la lente, la casa, il menu e Fine); appena passata una
     * segnalazione, «C'è ancora?» Sì / No.
     *
     * La musica si comanda dal lettore sulla mappa, e qui non c'è: i tasti
     * sono quelli di prima della musica. Solo sulle auto che non mandano i
     * tocchi (prima dell'API 5, o con la sola manopola), e finché su
     * quest'auto non se n'è visto uno, ⏯ sta qui per primo
     * ([musicaInAlto]).
     *
     * La casa di GdAHome resta **sempre** qui, mai nel Menu: lì il percorso
     * dei suoi schermi si allunga di un passo e passa il limite dei cinque
     * che Android Auto concede (l'app verrebbe chiusa). Con la musica in
     * alto:
     *
     * - con la casa: a mappa libera ⏯, «Cerca», casa, «Menu»; in guida ⏯,
     *   casa, menu, «Fine». Per ⏭ non c'è posto;
     * - senza la casa: a mappa libera ⏯, ⏭, «Cerca», «Menu»; in guida ⏯, ⏭,
     *   menu, «Fine»;
     * - in guida la lente sta nel Menu, in alto ([SchermoMenu]);
     * - ⏭ solo se un'app ha un lettore aperto: senza, ▶ col nome dell'app
     *   che fa partire («▶ Spotify», [AvvioMusica]; «Avvio…» mentre parte).
     *
     * Con la musica spenta, senza il permesso o coi comandi nel lettore
     * sulla mappa, tutto come prima della musica.
     */
    private fun azioni(): ActionStrip {
        val striscia = ActionStrip.Builder()
        // La strada a risparmio, sulle auto senza gli avvisi di Android Auto
        // (o mentre il suo avviso aspetta dietro un urgente di casa).
        val strada = PonteAuto.strada.id
        if (strada != null && PonteAuto.stradaNeiTasti) {
            striscia.addAction(
                Action.Builder().setTitle("Prendila").setOnClickListener { PonteAuto.rispondiStrada(strada, true) }.build(),
            )
            striscia.addAction(tasto(R.drawable.auto_no) { PonteAuto.rispondiStrada(strada, false) })
            return striscia.build()
        }
        val ancora = PonteAuto.avviso.ancoraId
        if (ancora != null) {
            striscia.addAction(
                Action.Builder().setTitle("C'è ancora").setOnClickListener { PonteAuto.ancora(ancora, true) }.build(),
            )
            striscia.addAction(tasto(R.drawable.auto_no) { PonteAuto.ancora(ancora, false) })
            return striscia.build()
        }
        val guida = PonteAuto.guida != null
        val conMusica = musicaInAlto()
        if (conMusica) tastiMusica(striscia, avanti = GdanavInAuto.casa == null)
        if (guida) {
            // In guida c'è poco spazio: solo la lente, e con la musica
            // nemmeno quella (sta in alto nel Menu).
            if (!conMusica) striscia.addAction(tasto(R.drawable.auto_cerca) { screenManager.push(SchermoCerca(carContext)) })
            casa(striscia)
            striscia.addAction(tasto(R.drawable.auto_menu) { screenManager.push(SchermoMenu(carContext, renderer)) })
            striscia.addAction(Action.Builder().setTitle("Fine").setOnClickListener { PonteAuto.fermaDallAuto() }.build())
        } else {
            // Da fermi, come Google Maps: «Cerca» e «Menu» ben leggibili.
            striscia.addAction(
                Action.Builder()
                    .setTitle("Cerca")
                    .setIcon(icona(R.drawable.auto_cerca))
                    .setOnClickListener { screenManager.push(SchermoCerca(carContext)) }
                    .build(),
            )
            casa(striscia)
            striscia.addAction(
                Action.Builder()
                    .setTitle("Menu")
                    .setIcon(icona(R.drawable.auto_menu))
                    .setOnClickListener { screenManager.push(SchermoMenu(carContext, renderer)) }
                    .build(),
            )
        }
        return striscia.build()
    }

    /**
     * ⏯ (pausa se suona, play se no) e, con [avanti] e un lettore aperto, ⏭.
     * Dalle auto con l'API 5 restano in vista anche quando Android Auto, dopo
     * qualche secondo senza tocchi, nasconde gli altri tasti: per mettere in
     * pausa basta un tocco.
     */
    private fun tastiMusica(striscia: ActionStrip.Builder, avanti: Boolean) {
        val fissi = carContext.carAppApiLevel >= 5
        val suona = LettoreTelefono.brano?.suona == true
        val playPausa = Action.Builder()
            .setIcon(icona(if (suona) R.drawable.auto_pausa else R.drawable.auto_play))
            .setOnClickListener { LettoreTelefono.comando("playPausa") }
        // Niente che suona: chi parte con ▶.
        if (LettoreTelefono.brano == null) {
            val nome = if (LettoreTelefono.inAvvio) "Avvio…" else LettoreTelefono.prossima?.nome
            if (nome != null) playPausa.setTitle(nome)
        }
        if (fissi) playPausa.setFlags(Action.FLAG_IS_PERSISTENT)
        striscia.addAction(playPausa.build())
        if (avanti && LettoreTelefono.brano != null) {
            val successivo = Action.Builder()
                .setIcon(icona(R.drawable.auto_avanti))
                .setOnClickListener { LettoreTelefono.comando("successivo") }
            if (fissi) successivo.setFlags(Action.FLAG_IS_PERSISTENT)
            striscia.addAction(successivo.build())
        }
    }

    /**
     * La casa, se chi porta GdANav dentro ne ha una (GdAHome): un tasto col
     * solo disegno. Al massimo quattro tasti, e con Cerca, Menu e Fine ci sta.
     */
    private fun casa(striscia: ActionStrip.Builder) {
        GdanavInAuto.casa?.let { casa ->
            striscia.addAction(tasto(R.drawable.auto_casa) { screenManager.push(casa(carContext)) })
        }
    }

    /** A lato della mappa: sposta, + e −, e la vista (o Centra se la si è spostata). */
    private fun azioniMappa(): ActionStrip {
        val striscia = ActionStrip.Builder()
        if (carContext.carAppApiLevel >= 2) striscia.addAction(Action.PAN)
        striscia.addAction(tasto(R.drawable.auto_piu) { renderer.zoom(1.0) })
        striscia.addAction(tasto(R.drawable.auto_meno) { renderer.zoom(-1.0) })
        if (renderer.libera) {
            striscia.addAction(tasto(R.drawable.auto_centra) { renderer.segui() })
        } else {
            striscia.addAction(
                // Il tasto mostra la vista dopo: 3D → immersiva → 2D → 3D.
                tasto(
                    when (renderer.vista.dopo) {
                        Vista.PIATTA -> R.drawable.auto_2d
                        Vista.INCLINATA -> R.drawable.auto_3d
                        Vista.IMMERSIVA -> R.drawable.auto_immersiva
                    },
                ) {
                    renderer.alternaVista()
                    invalidate()
                },
            )
        }
        return striscia.build()
    }

    override fun onGetTemplate(): Template {
        disegnata = firma()
        val guida = PonteAuto.guida
        val modello = NavigationTemplate.Builder()
            .setActionStrip(azioni())
            .setMapActionStrip(azioniMappa())
        if (carContext.carAppApiLevel >= 2) {
            modello.setPanModeListener { inPan -> renderer.sposta(inPan) }
        }
        if (guida != null) {
            // La manovra (freccia, distanza, corsie, svincolo col cartello)
            // e l'arrivo nelle schede di Android Auto, come vuole Google per
            // i navigatori (NF-2): sulla mappa restano velocità, limite e dati
            // dell'auto.
            modello.setNavigationInfo(guidaAuto.scheda(guida))
            // Il pedaggio che resta accanto ai km, se l'auto sa scriverlo (API 5).
            modello.setDestinationTravelEstimate(guidaAuto.stima(guida, conTesto = PonteAuto.pedaggioNellaStima))
        } else {
            // Da fermi la mappa resta pulita; il riquadro solo se c'è qualcosa
            // da dire («Calcolo il percorso…», un errore).
            PonteAuto.messaggio?.let { testo ->
                modello.setNavigationInfo(MessageInfo.Builder(testo).build())
            }
        }
        return modello.build()
    }

    private companion object {
        /** Di chi sono gli avvisi chiesti da qui all'arbitro. */
        const val AVVISO_CASA = "casa"
        const val AVVISO_STRADA = "strada"
    }
}
