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

// REGLA DE DOBLE NIVEL CON ESCUDO DE SEGURIDAD
subprojects {
    fun configureProject() {
        if (project.hasProperty("android")) {
            val isApp = project.name == "app"
            
            // 1. Intentamos forzar Java (solo si no está sellado)
            try {
                val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
                android.compileOptions {
                    sourceCompatibility = if (isApp) JavaVersion.VERSION_17 else JavaVersion.VERSION_1_8
                    targetCompatibility = if (isApp) JavaVersion.VERSION_17 else JavaVersion.VERSION_1_8
                }
            } catch (e: Exception) {}

            // 2. Forzamos Kotlin para que coincida
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(
                        if (isApp) org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 
                        else org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                    )
                }
            }
        }
    }

    // Escudo para Gradle 8
    if (project.state.executed) {
        configureProject()
    } else {
        afterEvaluate {
            configureProject()
        }
    }
}
