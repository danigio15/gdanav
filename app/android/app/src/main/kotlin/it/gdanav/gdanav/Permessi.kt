package it.gdanav.gdanav

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** I permessi Bluetooth per il dongle OBD, chiesti quando servono. */
class Permessi(private val attivita: Activity) {
    private var inAttesa: MethodChannel.Result? = null

    fun collega(messenger: BinaryMessenger) {
        MethodChannel(messenger, "gdanav/permessi").setMethodCallHandler { call, risultato ->
            if (call.method != "bluetooth") return@setMethodCallHandler risultato.notImplemented()
            val servono = if (Build.VERSION.SDK_INT >= 31) {
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            val mancano = servono.filter {
                ContextCompat.checkSelfPermission(attivita, it) != PackageManager.PERMISSION_GRANTED
            }
            if (mancano.isEmpty()) return@setMethodCallHandler risultato.success(true)
            inAttesa?.success(false)
            inAttesa = risultato
            ActivityCompat.requestPermissions(attivita, mancano.toTypedArray(), CODICE)
        }
    }

    fun risposta(codice: Int, esiti: IntArray): Boolean {
        if (codice != CODICE) return false
        inAttesa?.success(esiti.isNotEmpty() && esiti.all { it == PackageManager.PERMISSION_GRANTED })
        inAttesa = null
        return true
    }

    companion object {
        const val CODICE = 4242
    }
}
