import com.android.Version
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

plugins {
    id("com.android.library")
}

group = "it.gdanav.gdanav_app"
version = "1.0-SNAPSHOT"

// Con AGP 9 Kotlin lo compila Android da sé, salvo dove l'app l'ha spento
// (`android.builtInKotlin=false`, come gdanav e gdahome): lì si accende qui.
val agpMaggiore = Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
val kotlinIncorporato = agpMaggiore >= 9 &&
    (findProperty("android.builtInKotlin")?.toString() ?: "true").toBoolean()
if (!kotlinIncorporato) {
    apply(plugin = "kotlin-android")
}

android {
    namespace = "it.gdanav.gdanav_app"
    // Come l'app: la 37 la chiede la libreria Bluetooth del dongle.
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }
}

fun configuraKotlin() {
    extensions.configure(KotlinAndroidProjectExtension::class.java) {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_17
        }
    }
}
if (extensions.findByName("kotlin") != null) {
    configuraKotlin()
} else {
    plugins.withId("org.jetbrains.kotlin.android") { configuraKotlin() }
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    // Android Auto: la libreria delle app per l'auto, e i dati dell'auto
    // (batteria, autonomia) quando il telefono è collegato. `api` perché
    // l'app che porta gdanav dentro dichiara il servizio con queste classi.
    api("androidx.car.app:app:1.4.0")
    api("androidx.car.app:app-projected:1.4.0")
    // La stessa MapLibre del plugin maplibre_gl, per la mappa sullo schermo dell'auto.
    implementation("org.maplibre.gl:android-sdk-opengl:13.5.0")
}
