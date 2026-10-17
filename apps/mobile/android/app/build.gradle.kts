import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Android SDK keys are intentionally absent from source and Dart defines.
// Application/API restrictions are still required because APKs are inspectable.
val mapsProperties = Properties()
val mapsPropertiesFile = rootProject.file("../../../.local/maps.android.properties")
if (mapsPropertiesFile.isFile) mapsPropertiesFile.inputStream().use { mapsProperties.load(it) }
val mapsKey = if (System.getenv("AWAAZ_DISABLE_GOOGLE_MAPS") == "true") "" else
    (System.getenv("AWAAZ_GOOGLE_MAPS_ANDROID_API_KEY") ?: mapsProperties.getProperty("GOOGLE_MAPS_ANDROID_API_KEY", "")).trim()
require(mapsKey.isEmpty() || Regex("AIza[A-Za-z0-9_-]{35}").matches(mapsKey)) { "Invalid Google Maps Android key configuration" }

android {
    buildFeatures { buildConfig = true }
    namespace = "app.awaaz.awaaz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        manifestPlaceholders["awaazGoogleMapsKey"] = mapsKey
        buildConfigField("boolean", "AWAAZ_GOOGLE_MAPS_ENABLED", mapsKey.isNotEmpty().toString())
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.awaaz.awaaz"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Configure a real release keystore before distribution. An unsigned
            // scaffold is preferable to silently shipping with the debug key.
            signingConfig = null
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
    implementation("com.google.android.gms:play-services-location:21.2.0")
    testImplementation("junit:junit:4.13.2")
}
