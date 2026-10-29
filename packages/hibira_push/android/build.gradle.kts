group = "io.hibira.push.flutter"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// hibira-push-android is published on JitPack. The app module resolves this
// plugin's dependencies with its own repositories, so add JitPack there too
// (only for com.github.hibira-io, so nothing else is fetched from it).
rootProject.allprojects {
    repositories {
        maven {
            url = uri("https://jitpack.io")
            content { includeGroup("com.github.hibira-io") }
        }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "io.hibira.push.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.github.hibira-io:hibira-push-android:1.1.0")
    implementation("com.google.firebase:firebase-messaging:23.4.0")
    implementation("com.google.firebase:firebase-installations:17.2.0")
}
