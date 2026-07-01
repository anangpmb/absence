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
    // Force a consistent JVM target (17) across every plugin's Kotlin AND Java
    // compile tasks. Some plugins (e.g. flutter_timezone) leave their Java
    // target at 1.8 while we push Kotlin to 17, which trips AGP 8's
    // "Inconsistent JVM-target compatibility" check. Aligning both fixes it.
    plugins.withId("org.jetbrains.kotlin.android") {
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class).configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
    // AGP finalises the Java target from each plugin's own android.compileOptions
    // after evaluation, so we must set that DSL (not the raw JavaCompile task) to
    // make Java match the Kotlin target we force above. Skip already-evaluated
    // projects (`:app`, force-evaluated above — it sets Java 17 in its own file)
    // since afterEvaluate cannot be registered on them.
    if (!state.executed) {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
