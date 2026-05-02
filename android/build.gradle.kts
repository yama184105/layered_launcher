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

// AGP 8 では android namespace が必須。古いプラグインで未指定のものへフォールバック注入。
// device_apps 2.2.0 は AndroidManifest.xml の package 属性のみで namespace 未対応のため、
// パッケージ名 fr.g123k.deviceapps を強制セットする。
subprojects {
    afterEvaluate {
        if (project.name == "device_apps") {
            project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
                if (namespace == null) {
                    namespace = "fr.g123k.deviceapps"
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
