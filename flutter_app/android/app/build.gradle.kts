import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val devKeystore = System.getenv("NASQO_DEV_KEYSTORE_PATH")
val devStorePassword = System.getenv("NASQO_DEV_KEYSTORE_PASSWORD")
val devKeyAlias = System.getenv("NASQO_DEV_KEY_ALIAS")
val devKeyPassword = System.getenv("NASQO_DEV_KEY_PASSWORD")
val devSigningConfigured = listOf(
    devKeystore, devStorePassword, devKeyAlias, devKeyPassword
).all { !it.isNullOrBlank() }

android {
    namespace = "com.indexesstore.nasqo_qa"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.indexesstore.nasqo_qa"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (devSigningConfigured) {
            create("nasqoDev") {
                storeFile = File(devKeystore!!)
                storePassword = devStorePassword!!
                keyAlias = devKeyAlias!!
                keyPassword = devKeyPassword!!
            }
        }
    }
    buildTypes {
        getByName("release") {
            // Fail closed: a release without a stable signing key must not be distributed.
            if (devSigningConfigured) {
                signingConfig = signingConfigs.getByName("nasqoDev")
            } else {
                signingConfig = null
            }
        }
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("com.google.android.gms:play-services-auth:21.3.0")
}

flutter {
    source = "../.."
}
