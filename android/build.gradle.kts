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
subprojects {
    project.evaluationDependsOn(":app")
}

// Flutter keeps android.builtInKotlin=false so plugins that still apply the
// Kotlin Gradle Plugin keep working on AGP 9. file_picker 11+ skips KGP
// whenever AGP is 9+, so its .kt sources never compile unless we apply it.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val hasKotlin =
            pluginManager.hasPlugin("org.jetbrains.kotlin.android") ||
                pluginManager.hasPlugin("kotlin-android")
        if (!hasKotlin && file("src/main/kotlin").exists()) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
