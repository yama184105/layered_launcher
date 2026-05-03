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

// AGP 8 では android namespace が必須。古いプラグインで未指定のものへフォールバック注入。
// device_apps 2.2.0 は AndroidManifest.xml の package 属性のみで namespace 未対応のため、
// パッケージ名 fr.g123k.deviceapps を強制セットする。
// NOTE: 後段の evaluationDependsOn(":app") が :app と依存プラグインの評価をトリガーするため、
// この afterEvaluate 登録は必ずそれより前に行う必要がある。
subprojects {
    if (project.name == "device_apps") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
                if (namespace == null) {
                    namespace = "fr.g123k.deviceapps"
                }
            }
        }
    }
}

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
