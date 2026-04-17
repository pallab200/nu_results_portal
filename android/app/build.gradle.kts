plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

// Load release signing configuration from key.properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.nu_results_portal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"].toString()
            keyPassword = keystoreProperties["keyPassword"].toString()
            // Resolve keystore path relative to the android directory
            storeFile = file("${rootProject.projectDir}/${keystoreProperties["storeFile"]}")
            storePassword = keystoreProperties["storePassword"].toString()
        }
    }

    defaultConfig {
        applicationId = "com.nu_results_portal"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── Performance & size ──────────────────────────────────────────
        // Render with hardware acceleration
        multiDexEnabled = true

        // ABI filters are handled via the `splits` block below for release builds.
        // Avoid setting `ndk.abiFilters` together with `splits.abi` (conflict).
    }

    // NOTE: ABI splits are useful for release distribution (Play Store).
    // They are disabled here to avoid conflicts with plugins that set
    // `ndk.abiFilters` during project configuration. Re-enable splits
    // for release builds in a separate CI/release Gradle configuration.

    buildTypes {
        release {
            // Sign with release keystore
            signingConfig = signingConfigs.getByName("release")

            // ── R8 full-mode: shrink, obfuscate, optimise ───────────────
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // App Bundle splits are intentionally left disabled for local/dev builds.

    packaging {
        resources {
            // Strip unused JVM resources from the final package
            excludes += setOf(
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/*.kotlin_module",
                "DebugProbesKt.bin",
                "kotlin-tooling-metadata.json"
            )
        }
    }
}

dependencies {
    // Core-library desugaring lets plugins use Java 8+ APIs on older devices
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
