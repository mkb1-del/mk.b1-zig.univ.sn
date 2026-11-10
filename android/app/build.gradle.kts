plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "sn.sunuyaakaar.my_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requis par flutter_local_notifications (rappels de médicaments et de rendez-vous)
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "sn.sunuyaakaar.my_app"
        // Le micro (record) et le stockage sécurisé demandent Android 6 (API 23) au minimum.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signature avec la clé de test : suffisant pour installer sur son propre téléphone.
            // (Une publication sur le Play Store demandera une vraie clé de signature.)
            signingConfig = signingConfigs.getByName("debug")

            // Le réducteur de code R8 fait planter les rappels programmés en version finale
            // (erreur « Missing type parameter »). On le désactive : l'application est
            // un peu plus lourde, mais les rappels fonctionnent.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Bibliothèque associée au « desugaring » ci-dessus
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}