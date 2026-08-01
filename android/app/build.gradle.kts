plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.toko_kacamata_natan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Aset Windows dari package win_ble tidak dipakai di Android (~0.5MB).
    androidResources {
        ignoreAssetsPattern =
            "!.svn:!.git:!.ds_store:!*.scc:.*:!CVS:!thumbs.db:!picasa.ini:!*~:!BLEServer.exe"
    }

compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        // Base ID — tiap flavor punya applicationId sendiri agar tidak saling “update”.
        applicationId = "com.example.toko_kacamata_natan"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "app"
    productFlavors {
        create("karyawan") {
            dimension = "app"
            // Tetap ID lama supaya update Karyawan yang sudah terpasang tidak putus.
            applicationId = "com.example.toko_kacamata_natan"
        }
        create("member") {
            dimension = "app"
            // ID baru → install berdampingan, bukan overwrite Karyawan.
            applicationId = "com.optikbriski.member"
        }
        create("admin") {
            dimension = "app"
            applicationId = "com.optikbriski.admin"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Member tidak pakai OCR KTP — buang native/model OCR (~12 MB) agar lolos WA <50 MB desimal.
androidComponents {
    onVariants(selector().withFlavor("app" to "member")) { variant ->
        variant.packaging.jniLibs.excludes.add("**/libmlkit_google_ocr_pipeline.so")
        variant.packaging.resources.excludes.add("**/mlkit-google-ocr-models/**")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
