package it.gdanav.gdanav_app

import android.app.Activity
import android.view.WindowManager
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.MethodChannel
import it.gdanav.gdanav_app.auto.Diagnosi
import it.gdanav.gdanav_app.auto.PosizioneInAuto

/**
 * Il pezzo nativo di GdANav che viaggia col pacchetto: i permessi Bluetooth
 * per il dongle OBD e la diagnosi di Android Auto. Gli schermi dell'auto
 * (`auto/`) li usa il servizio dell'app che porta GdANav dentro.
 *
 * Flutter lo registra da solo in ogni app che porta GdANav dentro; con l'app
 * aperta solo da Android Auto un'attività non c'è, e ai permessi la risposta
 * è «no».
 */
class GdanavAppPlugin : FlutterPlugin, ActivityAware {
    private var canale: MethodChannel? = null
    private var schermo: MethodChannel? = null
    private var attivita: Activity? = null
    private var permessi: Permessi? = null

    /*
     * Lo schermo acceso finché si guida (`lib/sorgenti/schermo_acceso.dart`):
     * il telefono sul supporto non si tocca, e senza chiederlo Android lo
     * scuriva fino al nero. Se la finestra era già accesa per conto dell'app
     * ospite (il pannello a muro di GdAHome), alla fine della guida resta
     * accesa: si rimette com'era.
     */
    private var primaDellaGuida: Boolean? = null

    private fun tieniAcceso(acceso: Boolean): Boolean {
        val finestra = attivita?.window ?: return false
        val bandiera = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (acceso) {
            if (primaDellaGuida == null) primaDellaGuida = (finestra.attributes.flags and bandiera) != 0
            finestra.addFlags(bandiera)
        } else {
            val prima = primaDellaGuida ?: return true
            if (!prima) finestra.clearFlags(bandiera)
            primaDellaGuida = null
        }
        return true
    }
    private var ciclo: Lifecycle? = null

    /*
     * L'app sul telefono torna davanti: se in auto la posizione non era
     * riuscita a partire col telefono in tasca (`PosizioneInAuto`), adesso
     * Android la lascia partire, e da lì resta accesa fino a fine viaggio.
     */
    private val davanti = object : DefaultLifecycleObserver {
        override fun onResume(owner: LifecycleOwner) = PosizioneInAuto.dalTelefono()
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Cosa vede il telefono di Android Auto: serve a capire perché l'app
        // non compare sull'auto.
        Diagnosi.collega(binding.applicationContext, binding.binaryMessenger)
        canale = MethodChannel(binding.binaryMessenger, "gdanav/permessi").also {
            it.setMethodCallHandler { call, risultato ->
                val p = permessi
                if (p == null) risultato.success(false) else p.chiama(call, risultato)
            }
        }
        schermo = MethodChannel(binding.binaryMessenger, "gdanav/schermo").also {
            it.setMethodCallHandler { call, risultato ->
                if (call.method != "acceso") return@setMethodCallHandler risultato.notImplemented()
                risultato.success(tieniAcceso(call.arguments == true))
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        canale?.setMethodCallHandler(null)
        canale = null
        schermo?.setMethodCallHandler(null)
        schermo = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attivita = binding.activity
        val p = Permessi(binding.activity)
        binding.addRequestPermissionsResultListener { codice, _, esiti -> p.risposta(codice, esiti) }
        permessi = p
        ciclo?.removeObserver(davanti)
        ciclo = (binding.lifecycle as? HiddenLifecycleReference)?.lifecycle?.also { it.addObserver(davanti) }
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        tieniAcceso(false)
        attivita = null
        permessi = null
        ciclo?.removeObserver(davanti)
        ciclo = null
    }
}
