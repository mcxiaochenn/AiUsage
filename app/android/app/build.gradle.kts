plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("AIUSAGE_ANDROID_KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("AIUSAGE_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("AIUSAGE_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("AIUSAGE_ANDROID_KEY_PASSWORD")
val releaseSigningValues =
    listOf(
        releaseKeystorePath,
        releaseKeystorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    )
val releaseSigningConfigured = releaseSigningValues.all { !it.isNullOrBlank() }
val requestedReleaseAbi = providers.gradleProperty("aiusageTargetAbi").orNull
val supportedReleaseAbis = setOf("armeabi-v7a", "arm64-v8a", "x86_64")
if (requestedReleaseAbi != null && requestedReleaseAbi !in supportedReleaseAbis) {
    throw GradleException("Unsupported aiusageTargetAbi: $requestedReleaseAbi")
}
val releaseBuildRequested =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("release", ignoreCase = true)
    }

if (releaseBuildRequested && !releaseSigningConfigured) {
    throw GradleException(
        "Release signing is required. Configure the AIUSAGE_ANDROID_* environment variables.",
    )
}

android {
    namespace = "dev.chendusk.aiusage"
    // flutter_secure_storage 11 需要在 API 37 编译；运行时 target 仍由 Flutter 管理，
    // Android 的 compile SDK 向后兼容。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.chendusk.aiusage"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("aiUsageRelease") {
                storeFile = file(requireNotNull(releaseKeystorePath))
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("aiUsageRelease")
            }
            if (requestedReleaseAbi != null) {
                ndk {
                    abiFilters += requestedReleaseAbi
                }
            }
        }
    }
}

androidComponents {
    if (requestedReleaseAbi != null) {
        onVariants(selector().withBuildType("release")) { variant ->
            val excludedAbis = supportedReleaseAbis - requestedReleaseAbi
            variant.packaging.jniLibs.excludes.addAll(
                excludedAbis.map { abi -> "lib/$abi/**" },
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
