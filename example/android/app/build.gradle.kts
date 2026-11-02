plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android 与 Kotlin Gradle 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yuanzhihong.flutter_ar_plus_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO：请替换为自己唯一的 Application ID。
        applicationId = "com.yuanzhihong.flutter_ar_plus_example"
        // 可根据应用需求调整以下配置。
        // 详情参阅：https://flutter.dev/to/review-gradle-config。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // 使用 pubspec.yaml 中的版本号。构建拆分 APK 时，Flutter 会自动加上
        // 1000 * ABI_VERSION。
        // 可通过 `-P force-version-code-ignoring-abi=true` 在构建时强制使用原始 versionCode。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO：发布构建请配置自己的签名信息。
            // 当前使用调试密钥签名，以便 `flutter run --release` 可以直接运行。
            signingConfig = signingConfigs.getByName("debug")
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
