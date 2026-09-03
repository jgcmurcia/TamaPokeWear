plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("TAMAPOKE_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("TAMAPOKE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("TAMAPOKE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("TAMAPOKE_KEY_PASSWORD")
val hasReleaseSigning = !releaseKeystorePath.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.xxfalcoonx.tamapokewear"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Separate identity for this personal fork so it no longer collides with
        // the original TamaPokeWear package.
        applicationId = "com.jgcmurcia.tamapokepocket"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    flavorDimensions += "device"
    productFlavors {
        create("wear") {
            dimension = "device"
        }
        create("mobile") {
            dimension = "device"
        }
    }

    buildTypes {
        getByName("release") {
            // CI can build immediately with Android's debug signing fallback.
            // Once the four TAMAPOKE_* secrets are configured, the exact same
            // workflow produces update-safe, persistently signed releases.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
