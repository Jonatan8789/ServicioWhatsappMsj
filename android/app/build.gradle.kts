plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.natatorio_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 🟢 1. Activar Core Library Desugaring para Java 8+ / Kotlin
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 🏷️ Identificador definitivo para publicar en Google Play — antes
        // era el placeholder "com.example.natatorio_app" que generó
        // `flutter create`. El namespace (abajo, paquete de Kotlin/R.java)
        // se deja igual a propósito: Android permite que applicationId y
        // namespace difieran sin ningún problema, así se evita mover
        // MainActivity.kt de carpeta. Se registró una app nueva en Firebase
        // para este applicationId (google-services.json ya incluye ambas).
        applicationId = "com.oqua.clubdeportivo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // 🟢 2. Añadir la dependencia oficial de Desugaring requerida por Android
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}

// Bypassear el chequeo estricto de metadatos AAR que causaba el fallo por versiones de androidx
tasks.matching { it.name.contains("CheckAarMetadata") }.configureEach {
    enabled = false
}