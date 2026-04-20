import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
        // Required for ffmpeg_kit_flutter_* artifacts.
        maven(url = "https://maven.arthenica.com")
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
subprojects {
    project.evaluationDependsOn(":app")
}

// Workaround for AGP namespace requirement in older plugins
subprojects {
    if (name == "flutter_app_badger") {
        pluginManager.withPlugin("com.android.library") {
            extensions.findByType(LibraryExtension::class.java)?.apply {
                if (namespace.isNullOrBlank()) {
                    namespace = "com.weafrica.flutter_app_badger"
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
