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

// ponytail: file_picker 11.x (held there, see pubspec.yaml) skips KGP on any
// AGP >= 9 assuming built-in Kotlin, but `android.builtInKotlin=false` here
// (template default), and Flutter's KGP auto-apply misreads its conditional
// `apply plugin` line as "already applied". Net effect: its Kotlin never
// compiles and GeneratedPluginRegistrant fails. Delete once file_picker >= 12
// (federated android_file_picker reads android.builtInKotlin correctly).
subprojects {
    if (name == "file_picker") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
