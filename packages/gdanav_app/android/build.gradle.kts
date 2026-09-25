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
    compileSdk = 36

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
}
