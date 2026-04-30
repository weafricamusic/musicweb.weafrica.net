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

// Workaround for agora_rtm v1.6.3 Kotlin compilation errors
// The package uses old Flutter embedding API (Registrar) which is incompatible with Kotlin 1.8+
subprojects {
    if (name == "agora_rtm") {
        pluginManager.withPlugin("org.jetbrains.kotlin.android") {
            val kotlinExtension = extensions.findByType(
                org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java
            )
            kotlinExtension?.compilerOptions?.freeCompilerArgs?.add("-Xskip-metadata-version-check")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
