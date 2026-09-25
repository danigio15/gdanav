package it.gdanav.gdanav_app

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/**
 * Il pezzo nativo di gdanav che viaggia col pacchetto: i permessi Bluetooth
 * per il dongle OBD. Flutter lo registra da solo in ogni app che porta gdanav
 * dentro; con l'app aperta solo da Android Auto un'attività non c'è, e la
 * risposta è «no».
 */
class GdanavAppPlugin : FlutterPlugin, ActivityAware {
    private var canale: MethodChannel? = null
    private var permessi: Permessi? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
