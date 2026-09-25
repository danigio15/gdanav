package it.gdanav.gdanav_app

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import it.gdanav.gdanav_app.auto.Diagnosi

/**
 * Il pezzo nativo di gdanav che viaggia col pacchetto: i permessi Bluetooth
 * per il dongle OBD e la diagnosi di Android Auto. Gli schermi dell'auto
 * (`auto/`) li usa il servizio dell'app che porta gdanav dentro.
 *
 * Flutter lo registra da solo in ogni app che porta gdanav dentro; con l'app
 * aperta solo da Android Auto un'attività non c'è, e ai permessi la risposta
 * è «no».
 */
class GdanavAppPlugin : FlutterPlugin, ActivityAware {
    private var canale: MethodChannel? = null
    private var permessi: Permessi? = null

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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        canale?.setMethodCallHandler(null)
        canale = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val p = Permessi(binding.activity)
        binding.addRequestPermissionsResultListener { codice, _, esiti -> p.risposta(codice, esiti) }
        permessi = p
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        permessi = null
    }
}
