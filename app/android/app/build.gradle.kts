plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "it.gdanav.gdanav"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "it.gdanav.gdanav"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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

    // Una chiave fissa per gli APK d'anteprima: con la chiave di debug che la
    // CI rigenera a ogni build, Android rifiuta l'aggiornamento («App non
    // installata»). Per il Play Store ci sarà la chiave vera, fuori dalla repo.
    signingConfigs {
        create("anteprima") {
            storeFile = file("anteprima.jks")
            storePassword = "gdanav-anteprima"
            keyAlias = "gdanav"
            keyPassword = "gdanav-anteprima"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("anteprima")
        }
        debug {
            signingConfig = signingConfigs.getByName("anteprima")
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
