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

// ========== أضف الجزء ده ==========
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    // Force compileSdk 35 for all plugins
                    val setCompileSdk = android.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                    setCompileSdk.invoke(android, 35)
                } catch (e: Exception) {
                    // fallback for newer AGP
                    try {
                        val compileSdkField = android.javaClass.getDeclaredField("compileSdk")
                        compileSdkField.isAccessible = true
                        compileSdkField.set(android, 35)
                    } catch (e2: Exception) {
                        // ignore
                    }
                }
            }
        }
    }
}
// ==================================

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            val androidExtension = project.extensions.findByName("android")
            if (androidExtension != null) {
                try {
                    // For AGP 8+
                    androidExtension.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                        .invoke(androidExtension, 35)
                } catch (e: Exception) {
                    try {
                        androidExtension.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                            .invoke(androidExtension, 35)
                    } catch (e2: Exception) {
                        println("Could not set compileSdk for ${project.name}")
                    }
                }
            }
        }
    }
}
