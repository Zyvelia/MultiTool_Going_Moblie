import com.android.build.gradle.LibraryExtension
import org.gradle.api.ProjectState

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// ZS_PLUGIN_COMPILE_SDK_PATCH — align plugin modules with androidx deps (API 34+).
// flutter_webrtc still declares compileSdkVersion 31 in its own build.gradle;
// pluginManager.withPlugin runs before that block, so override after configure.
subprojects {
    val zsRaiseLibraryCompileSdk = {
        extensions.findByType<LibraryExtension>()?.apply {
            compileSdk = 37
        }
    }
    if (state == ProjectState.EVALUATED) {
        zsRaiseLibraryCompileSdk()
    } else {
        afterEvaluate { zsRaiseLibraryCompileSdk() }
    }
}
