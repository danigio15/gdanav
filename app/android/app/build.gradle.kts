import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La chiave vera, se c'è.
//
// Sta in `android/chiave.properties`, che non entra nella repository (lo dice
// `android/.gitignore`), e la scrive chi costruisce: sulla macchina di GitHub
// la scrive il workflow «GdANav nei negozi» dai segreti, su un computer la
// scrive chi ce l'ha. Le quattro righe sono quelle di sempre — `storeFile`,
// `storePassword`, `keyAlias`, `keyPassword`.
//
// **Se non c'è, un pacchetto «release» non si fa**, a meno che chi costruisce
// non chieda apposta la firma d'anteprima (`GDANAV_FIRMA_DI_PROVA=si`
// nell'ambiente). La chiave d'anteprima sta nella repository e la sua parola
// è scritta qui sotto: un pacchetto firmato con lei lo può rifare chiunque.
// Per questo quello che esce firmato d'anteprima non si chiama come l'app
// vera — ha `.prova` in fondo al nome — e non si installa mai sopra di lei
// né arriva ai suoi dati (l'abbinamento con Home Assistant, Premium). Quale
// delle due ha firmato lo dice il riepilogo della corsa.
val chiaveVera =
    Properties().apply {
        val dove = rootProject.file("chiave.properties")
        if (dove.exists()) dove.inputStream().use { load(it) }
    }
val cELaChiaveVera = chiaveVera.getProperty("storeFile") != null
val firmaDiProvaChiesta = System.getenv("GDANAV_FIRMA_DI_PROVA") == "si"

android {
    namespace = "it.gdanav.gdanav"
    // Almeno 37: la libreria Bluetooth del dongle OBD lo chiede. È solo per
    // compilare: i telefoni supportati li decidono minSdk e targetSdk.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        // Il nome con cui i negozi conoscono l'app: lo stesso di
        // `tools/porta-nel-negozio.mjs` e del bundle su iPhone.
        applicationId = "it.gdanav.gdanav"
        // MapLibre, fotocamera e posizione vogliono Android 7 o più.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Una chiave fissa per gli APK d'anteprima: con la chiave di debug che
        // la CI rigenera a ogni build, Android rifiuta l'aggiornamento («App
        // non installata») e chi prova deve disinstallare, perdendo
        // l'abbinamento con Home Assistant. Non è un segreto: firma solo i
        // pacchetti `.prova`.
        create("anteprima") {
            storeFile = file("anteprima.jks")
            storePassword = "gdanav-anteprima"
            keyAlias = "gdanav"
            keyPassword = "gdanav-anteprima"
        }
        if (cELaChiaveVera) {
            create("vera") {
                storeFile = file(chiaveVera.getProperty("storeFile"))
                storePassword = chiaveVera.getProperty("storePassword")
                keyAlias = chiaveVera.getProperty("keyAlias") ?: "gdanav"
                keyPassword =
                    chiaveVera.getProperty("keyPassword")
                        ?: chiaveVera.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        // Quello che si costruisce per lavorarci (`flutter run`) è firmato
        // d'anteprima: si chiama come un pacchetto di prova.
        debug {
            signingConfig = signingConfigs.getByName("anteprima")
            applicationIdSuffix = ".prova"
        }
        release {
            if (cELaChiaveVera) {
                signingConfig = signingConfigs.getByName("vera")
            } else {
                // Firmato d'anteprima solo se chiesto, e mai col nome vero. Se
                // non è chiesto, qui sotto il pacchetto si ferma prima di partire.
                signingConfig = signingConfigs.getByName("anteprima")
                applicationIdSuffix = ".prova"
                versionNameSuffix = "-prova"
            }
        }
    }
}

// Un «release» senza chiave vera e senza firma d'anteprima chiesta si ferma
// **subito**, con un messaggio che dice cosa fare — non dopo sei minuti di
// costruzione, e soprattutto non con un pacchetto firmato d'anteprima che
// qualcuno potrebbe scambiare per quello vero.
if (!cELaChiaveVera && !firmaDiProvaChiesta) {
    tasks.matching { it.name == "preReleaseBuild" }.configureEach {
        doFirst {
            throw GradleException(
                "Manca la chiave vera (android/chiave.properties). Un pacchetto " +
                    "release non si firma con la chiave d'anteprima. Per un " +
                    "pacchetto da provare, che si chiama it.gdanav.gdanav.prova, " +
                    "costruisci con GDANAV_FIRMA_DI_PROVA=si nell'ambiente.",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Android Auto: la libreria delle app per l'auto, e i dati dell'auto
    // (batteria, autonomia) quando il telefono è collegato.
    implementation("androidx.car.app:app:1.4.0")
    implementation("androidx.car.app:app-projected:1.4.0")
    // La stessa MapLibre del plugin maplibre_gl, per la mappa sullo schermo dell'auto.
    implementation("org.maplibre.gl:android-sdk-opengl:13.5.0")
}
