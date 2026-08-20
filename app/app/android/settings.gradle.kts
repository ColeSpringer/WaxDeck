pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// Kotlin's incremental compiler opens a cache file it already has open
// while closing it, and every module with Kotlin in it fails: "Could not
// close incremental caches ... Storage for class-fq-name-to-source.tab
// is already registered". It reproduces from an empty build directory,
// so cleaning is not the way out.
//
// Windows only, so scoped rather than paid for everywhere: the Linux
// runners that build the shipped APKs do the same from-scratch compile
// with incremental on and are green. Yields to an explicit answer, so
// `-Pkotlin.incremental=true` still reaches the compiler.
val onWindows = System.getProperty("os.name").orEmpty().startsWith("Windows")
if (onWindows && !providers.gradleProperty("kotlin.incremental").isPresent) {
    gradle.beforeProject {
        extensions.extraProperties["kotlin.incremental"] = "false"
    }
}

include(":app")
