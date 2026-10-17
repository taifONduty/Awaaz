// Optional, pinned cache for Google Maven annotations when its endpoint times out.
// Publisher metadata is preserved. See docs/ANDROID_DEVELOPMENT_LOOP.md for provenance.
val offlineAnnotationRoot = rootDir.resolve("../../../.local/android-maven")
val offlineAnnotation = offlineAnnotationRoot.resolve("androidx/annotation/annotation-jvm/1.8.2")
val annotationHashes = mapOf(
    "jar" to "9aab326d9492800991854360ac248f493ce7f7c3183519309b78ace9e240f6f6",
    "pom" to "7d3b2860ea36511153a9713559dab60d77f72167fadc9c1c3198c23035fbc480",
    "module" to "d004657cf28982ae8da8317c0c1fec663c627d0d0c54330f0baa92cbc360cdc1",
)
val useOfflineAnnotation = offlineAnnotation.isDirectory
if (useOfflineAnnotation) {
    annotationHashes.forEach { (extension, expected) ->
        val file = offlineAnnotation.resolve("annotation-jvm-1.8.2.$extension")
        val actual = java.security.MessageDigest.getInstance("SHA-256")
            .digest(file.readBytes()).joinToString("") { "%02x".format(it) }
        check(actual == expected) { "Invalid cached Android annotation $extension" }
    }
}
val legacyAnnotation = offlineAnnotationRoot.resolve("androidx/annotation/annotation/1.0.0")
val useLegacyAnnotation = legacyAnnotation.isDirectory
if (useLegacyAnnotation) {
    mapOf(
        "jar" to "0baae9755f7caf52aa80cd04324b91ba93af55d4d1d17dcc9a7b53d99ef7c016",
        "pom" to "a179c12db43d9c0300c9db63f4811db496504be5401b951d422b78490ad1e5b4",
    ).forEach { (extension, expected) ->
        val actual = java.security.MessageDigest.getInstance("SHA-256")
            .digest(legacyAnnotation.resolve("annotation-1.0.0.$extension").readBytes())
            .joinToString("") { "%02x".format(it) }
        check(actual == expected) { "Invalid cached legacy Android annotation $extension" }
    }
}

val useGoogleMavenMirror = System.getenv("AWAAZ_USE_GOOGLE_MAVEN_MIRROR") == "true"
// Optional exact-version test cache downloaded from Maven Central over verified TLS.
val offlineJunit = offlineAnnotationRoot.resolve("junit/junit/4.13.2")
val useOfflineJunit = offlineJunit.isDirectory
if (useOfflineJunit) {
    mapOf(
        "pom" to "569b6977ee4603c965c1c46c3058fa6e969291b0160eb6964dd092cd89eadd94",
        "jar" to "8e495b634469d64fb8acfa3495a065cbacc8a0fff55ce1e31007be4c16dc57d3",
    ).forEach { (extension, expected) ->
        val actual = java.security.MessageDigest.getInstance("SHA-256")
            .digest(offlineJunit.resolve("junit-4.13.2.$extension").readBytes())
            .joinToString("") { "%02x".format(it) }
        check(actual == expected) { "Invalid cached JUnit $extension" }
    }
}
allprojects {
    // Flutter integration_test uses open-ended AndroidX versions. Resolve the
    // current stable test stack reproducibly, without daily metadata refreshes.
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.version?.contains("+") == true) {
                val pinned = when ("${requested.group}:${requested.name}") {
                    "androidx.test:runner", "androidx.test:rules" -> "1.7.0"
                    "androidx.test.espresso:espresso-core" -> "3.7.0"
                    else -> null
                }
                if (pinned != null) useVersion(pinned)
            }
        }
    }
    repositories {
        if (useOfflineJunit) {
            maven { url = uri(offlineAnnotationRoot); content { includeVersion("junit", "junit", "4.13.2") } }
        }
        if (useOfflineAnnotation || useLegacyAnnotation) {
            maven {
                url = uri(offlineAnnotationRoot)
                content {
                    if (useOfflineAnnotation) includeVersion("androidx.annotation", "annotation-jvm", "1.8.2")
                    if (useLegacyAnnotation) includeVersion("androidx.annotation", "annotation", "1.0.0")
                }
            }
        }
        // Explicit local-development fallback. Default builds use Google directly.
        if (useGoogleMavenMirror) {
            exclusiveContent {
                forRepository {
                    maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
                }
                filter { includeGroup("io.flutter") }
            }
            maven {
                url = uri("https://maven.aliyun.com/repository/google")
                content {
                    includeGroupByRegex("androidx\\..*")
                    includeGroupByRegex("com\\.android.*")
                    includeGroupByRegex("com\\.google\\.android.*")
                }
            }
        }
        google {
            content {
                includeGroupByRegex("androidx\\..*")
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google\\.android.*")
            }
        }
        mavenCentral { content { excludeGroup("io.flutter") } }
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
    // path_provider's JNI adapter needs CMake. Pin the installed tool instead
    // of letting AGP fetch an old default, and build only the requested emulator ABI.
    if (name == "jni") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                externalNativeBuild.cmake.version = "3.22.1"
                if (rootProject.findProperty("target-platform") == "android-x64") {
                    defaultConfig.ndk.abiFilters.clear()
                    defaultConfig.ndk.abiFilters.add("x86_64")
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
