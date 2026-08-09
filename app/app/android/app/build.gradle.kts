import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, when there is a keystore to sign with. The file is
// gitignored and absent on CI and on a fresh clone, which is why the
// release build type falls back to the debug keys rather than failing:
// `flutter run --release` and the CI release build are both worth more
// than refusing to produce an unsigned-for-distribution APK. What ships
// is signed by Cole locally, where key.properties exists.
// Presence of the file is the whole question, and deliberately so: it is
// how you declare an intent to sign. Keying off a property inside it
// instead would mean a misspelled `storefile=` fell back to debug keys
// and produced a release APK that looked publishable.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) keystorePropertiesFile.inputStream().use { load(it) }
}

// A file that exists and is incomplete is a mistake, not a configuration.
fun keystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)
        ?: throw GradleException(
            "android/key.properties is missing `$name`. It needs storeFile, " +
                "storePassword, keyAlias and keyPassword; delete the file to " +
                "build with debug keys instead. See docs/releasing.md.",
        )

android {
    namespace = "com.colespringer.waxdeck"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.colespringer.waxdeck"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperty("storeFile"))
                storePassword = keystoreProperty("storePassword")
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // No proguardFiles here. R8 is already on (Flutter's Gradle
            // plugin defaults minify + shrinkResources for release), and
            // that same plugin already adds proguard-android-optimize,
            // its own flutter_proguard_rules, and this module's
            // proguard-rules.pro when the file exists - which it does.
            // Repeating them would only give the duplicate something to
            // drift from.
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
