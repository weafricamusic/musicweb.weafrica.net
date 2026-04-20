plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Firebase Android config is provided by android/app/google-services.json.
// Apply the plugin only when the file is present so the app can still run
// (showing an in-app setup screen) before Firebase is configured.
val googleServicesFile = file("google-services.json")
val shouldApplyGoogleServices =
    googleServicesFile.exists() &&
        runCatching {
          // Guard against truncated/invalid JSON which would fail :app:processDebugGoogleServices.
          @Suppress("UnstableApiUsage")
          groovy.json.JsonSlurper().parse(googleServicesFile)
        }.isSuccess

if (shouldApplyGoogleServices) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "google-services.json missing or invalid; Firebase Android options will not be available until replaced with a valid file from Firebase Console.",
    )
}

android {
    namespace = "com.weafrica_music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.weafrica_music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // FFmpegKit requires minSdk 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Keep Play artifacts lean: ship only ARM ABIs used on real devices.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // Release signing (required for Google Play).
    // Create `android/key.properties` (ignored by git) and point it to your `.jks`.
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    val hasKeystore = keystorePropertiesFile.exists()
    if (hasKeystore) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    } else {
        logger.warn("key.properties not found; release builds will be signed with debug keys (NOT Play Store ready).")
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                val storeFilePath = (keystoreProperties["storeFile"] as String?)?.trim().orEmpty()
                if (storeFilePath.isNotEmpty()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = (keystoreProperties["storePassword"] as String?)?.trim()
                keyAlias = (keystoreProperties["keyAlias"] as String?)?.trim()
                keyPassword = (keystoreProperties["keyPassword"] as String?)?.trim()
            }
        }
    }

    val enableAndroidShrink: Boolean =
        (project.findProperty("enableAndroidShrink") as String?)
            ?.trim()
            ?.toBoolean()
            ?: true

    // Optional size optimization: exclude Agora extension libraries (AI/video extras).
    // Enable with: `flutter build apk --release --split-per-abi -PexcludeAgoraExtensions=true`
    // Only do this if your app does not use those extension features.
    val excludeAgoraExtensions: Boolean =
        (project.findProperty("excludeAgoraExtensions") as String?)
            ?.trim()
            ?.toBoolean()
            ?: false

    // Optional size optimization: compress native libraries inside the APK.
    // This typically reduces APK download size, but the OS will extract .so files at install time
    // (so installed size may increase). Enable with:
    // `flutter build apk --release --split-per-abi -PuseLegacyNativeLibPackaging=true`
    val useLegacyNativeLibPackaging: Boolean =
        (project.findProperty("useLegacyNativeLibPackaging") as String?)
            ?.trim()
            ?.toBoolean()
            ?: false

    packaging {
        jniLibs {
            if (excludeAgoraExtensions) {
                excludes += setOf("**/libagora*_extension.so")
            }

            if (useLegacyNativeLibPackaging) {
                useLegacyPackaging = true
            }
        }
    }

    buildTypes {
        release {
            // Google Play requires a non-debug signing key. If key.properties is missing,
            // we fall back to debug so local `--release` still runs.
            signingConfig = if (hasKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")

            // Keep release artifacts small.
            // Note: This affects only Android Java/Kotlin + resources; Flutter AOT code size is mostly in libapp.so.
            isMinifyEnabled = enableAndroidShrink
            isShrinkResources = enableAndroidShrink
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase Cloud Messaging (FCM)
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
