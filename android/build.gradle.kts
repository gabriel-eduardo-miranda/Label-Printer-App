// 1. Configuração global de Repositórios e Intercepção de Plugins
allprojects {
    repositories {
        google()
        mavenCentral()
        (this as ExtensionAware).extensions.add("jcenter", groovy.lang.Closure.IDENTITY)
    }

    // Intercepta e corrige as propriedades ANTES de qualquer leitura do AGP 9
    plugins.any {
        if (this.javaClass.name.startsWith("com.android.build.gradle")) {
            extensions.findByName("android")?.let { androidExt ->
                with(androidExt as com.android.build.gradle.BaseExtension) {
                    compileSdkVersion(34)
                    buildToolsVersion("34.0.0")
                    
                    // Injeta o namespace imediatamente no modelo para evitar o erro de instância do builder
                    if (namespace == null) {
                        namespace = project.group.toString()
                    }

                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_1_8
                        targetCompatibility = JavaVersion.VERSION_1_8
                    }
                }
            }
        }
        false // Mantém o fluxo normal do plugin
    }
}

subprojects {
    buildscript {
        repositories {
            google()
            mavenCentral()
            (this as ExtensionAware).extensions.add("jcenter", groovy.lang.Closure.IDENTITY)
        }
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