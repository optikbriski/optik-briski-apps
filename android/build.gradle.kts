allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Plugin lama (mis. another_flutter_usb_write) tanpa namespace / compileSdk antik → AGP 8 gagal.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            if (namespace.isNullOrBlank()) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                val fromManifest =
                    if (manifestFile.exists()) {
                        Regex("""package\s*=\s*"([^"]+)"""")
                            .find(manifestFile.readText())
                            ?.groupValues
                            ?.getOrNull(1)
                    } else {
                        null
                    }
                namespace = fromManifest?.takeIf { it.isNotBlank() }
                    ?: "com.flutter.plugin.${name.replace('-', '_')}"
            }
            if ((compileSdk ?: 0) < 34) {
                compileSdk = 34
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
