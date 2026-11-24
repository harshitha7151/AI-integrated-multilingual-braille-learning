
plugins {
    id("com.android.application")
    id("kotlin-android")

    // Flutter Gradle plugin must be applied after Android and Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.resonant.braille.resonant_braille"

    // Updated for flutter_tts compatibility.
    compileSdk = 36

    // Updated NDK version required by the plugins.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.resonant.braille.resonant_braille"

        // flutter_tts requires Android API 24 or newer.
        minSdk = 24

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug signing for development builds.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
