package it.gdanav.gdanav.auto

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Cosa vede il telefono di gdanav per Android Auto: se il servizio per
 * l'auto è registrato, che versione di Android Auto c'è e chi ha installato
 * l'app. Serve a capire perché l'app non compare sull'auto.
 */
object Diagnosi {
    private const val ANDROID_AUTO = "com.google.android.projection.gearhead"

    fun collega(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "gdanav/diagnosi").setMethodCallHandler { call, risultato ->
            if (call.method == "androidAuto") risultato.success(androidAuto(context)) else risultato.notImplemented()
        }
    }

    private fun androidAuto(context: Context): Map<String, Any?> {
        val pm = context.packageManager
        val servizi = pm.queryIntentServices(
            Intent("androidx.car.app.CarAppService").setPackage(context.packageName),
            PackageManager.GET_META_DATA,
        )
        val navigazione = pm.queryIntentServices(
            Intent("androidx.car.app.CarAppService")
                .addCategory("androidx.car.app.category.NAVIGATION")
                .setPackage(context.packageName),
            0,
        )
        val versioneAuto = try {
            pm.getPackageInfo(ANDROID_AUTO, 0).versionName
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
        val installatore = try {
            if (Build.VERSION.SDK_INT >= 30) {
                pm.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(context.packageName)
            }
        } catch (e: Exception) {
            null
        }
        val meta = pm.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData
        return mapOf(
            "servizio" to servizi.isNotEmpty(),
            "navigazione" to navigazione.isNotEmpty(),
            "descrittore" to (meta?.getInt("com.google.android.gms.car.application", 0) != 0),
            "androidAuto" to versioneAuto,
            "installatore" to installatore,
            "android" to Build.VERSION.RELEASE,
            "telefono" to "${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }
}
