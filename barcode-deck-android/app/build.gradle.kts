plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.kotlin.serialization)
}

import java.util.Properties

// Local signing credentials live in a git-ignored keystore.properties at the
// project root (storeFile / storePassword / keyAlias / keyPassword).
// Without that file the project still builds — release output is simply
// unsigned, which is fine for CI and fresh clones.
val keystoreProperties = Properties().apply {
    rootProject.file("keystore.properties").takeIf { it.exists() }?.let { file ->
        file.inputStream().use { load(it) }
    }
}

android {
    namespace = "dev.barcodedeck.app"
    compileSdk {
        version = release(37) {
            minorApiLevel = 2
        }
    }

    defaultConfig {
        applicationId = "dev.barcodedeck.app"
        minSdk = 26
        // Play requires targeting the latest API for new submissions
        // (Android 16 / API 36 since Aug 31, 2026).
        targetSdk = 36
        // versionCode history: 1 burned (first upload), 2 burned (R8
        // rebuild), 3 burned (debug-symbols rebuild), 4 burned (camera
        // fix, first upload), 5 burned (camera fix on the release track),
        // 6 = 1.0.1 (ITF rendering, QR support).
        versionCode = 6
        versionName = "1.0.1"
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // R8 shrinking/optimization — Play Console's "DEX code
            // optimization" score requires it, and it cuts the bundle
            // size substantially (ML Kit dominates the uncompressed code).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Include extracted native debug symbols (from ML Kit's .so
            // files) so Play can symbolicate native crashes and ANRs.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
            if (keystoreProperties.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.mlkit.barcode)
    // QR code *generation* for presentation mode (ML Kit only scans).
    // Pure-Java, offline, no Play Services — safe to bundle alongside ML Kit.
    implementation(libs.zxing.core)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.kotlinx.coroutines.guava)
    implementation(libs.kotlinx.serialization.json)

    testImplementation("junit:junit:4.13.2")
}
