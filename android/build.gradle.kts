allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redireciona o build principal diretamente para a raiz do C: para evitar o bug de caracteres do Windows
val newBuildDir: Directory = rootProject.layout.projectDirectory.dir("C:/build_label_app")
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Mantém a dependência de avaliação segura para os subprojetos
subprojects {
    if (project.name != "app") {
        project.evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}