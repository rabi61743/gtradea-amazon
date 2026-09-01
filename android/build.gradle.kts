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
// Plugins that still declare an older compile target than their own
// dependencies now demand.
//
// file_picker -- the system file browser the support form attaches from --
// pins `compileSdk 34`, while flutter_plugin_android_lifecycle, which it
// depends on, publishes AAR metadata refusing to link below 36. Without this
// the release build fails at :file_picker:checkReleaseAarMetadata.
//
// compileSdk only decides which APIs a module may be compiled against. Each
// plugin's own minSdk and targetSdk are untouched, so which devices the app
// installs on and how it behaves at runtime are unchanged.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
