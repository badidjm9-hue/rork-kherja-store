plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Firebase stays optional until the owner supplies google-services.json.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "app.rork.h04xk59ettzrqz7c6l4wp"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.rork.h04xk59ettzrqz7c6l4wp"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.android)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.json)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.koin.androidx.compose)
    implementation(libs.osmdroid.android)
    implementation("com.google.firebase:firebase-messaging:24.1.1")
    debugImplementation(libs.androidx.ui.tooling)
}

// ---------------------------------------------------------------------------
// `Config.kt` (object Config with the Supabase settings) is gitignored, so it
// is missing on a fresh checkout such as CI. When the file is absent, generate
// it at build time from environment variables. Nothing is hardcoded and no
// file with secrets is committed. A local Config.kt, if present, still wins.
//
//   EXPO_PUBLIC_SUPABASE_URL
//   EXPO_PUBLIC_SUPABASE_ANON_KEY
// ---------------------------------------------------------------------------
val localConfigKt = file("src/main/java/app/rork/h04xk59ettzrqz7c6l4wp/Config.kt")
if (!localConfigKt.exists()) {
    val supabaseUrl = providers.environmentVariable("EXPO_PUBLIC_SUPABASE_URL")
    val supabaseAnonKey = providers.environmentVariable("EXPO_PUBLIC_SUPABASE_ANON_KEY")
    val generatedConfigDir = layout.buildDirectory.dir("generated/config/kotlin")

    // Static-analysis and unit-test tasks compile sources but do not run the
    // application. They may use deliberately non-routable placeholders when
    // CI has not injected production Supabase credentials. Any installable
    // app build still requires the real URL and anon key.
    val requestedTasks = gradle.startParameter.taskNames
    val ciOnlyInvocation = requestedTasks.isNotEmpty() &&
        requestedTasks.all {
            val task = it.substringAfterLast(":")
            task.startsWith("test") || task.startsWith("lint")
        }
    val ciTestUrl = "https://ci-only.invalid"
    val ciTestAnonKey = "ci-only-placeholder"

    val generateConfig = tasks.register("generateConfig") {
        inputs.property("supabaseUrl", supabaseUrl.orElse(if (ciOnlyInvocation) ciTestUrl else ""))
        inputs.property("supabaseAnonKey", supabaseAnonKey.orElse(if (ciOnlyInvocation) ciTestAnonKey else ""))
        outputs.dir(generatedConfigDir)
        doLast {
            val url = supabaseUrl.orNull?.trim().takeUnless { it.isNullOrEmpty() }
                ?: ciTestUrl.takeIf { ciOnlyInvocation }.orEmpty()
            val key = supabaseAnonKey.orNull?.trim().takeUnless { it.isNullOrEmpty() }
                ?: ciTestAnonKey.takeIf { ciOnlyInvocation }.orEmpty()
            val missing = listOfNotNull(
                "EXPO_PUBLIC_SUPABASE_URL".takeIf { url.isEmpty() },
                "EXPO_PUBLIC_SUPABASE_ANON_KEY".takeIf { key.isEmpty() },
            )
            if (missing.isNotEmpty()) {
                throw GradleException(
                    "Missing environment variable(s): ${missing.joinToString()}. " +
                        "Set them in the Bitrise/CI build environment for app builds."
                )
            }
            fun esc(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$")
            val dir = generatedConfigDir.get().asFile.resolve("app/rork/h04xk59ettzrqz7c6l4wp")
            dir.mkdirs()
            dir.resolve("Config.kt").writeText(
                """
                |package app.rork.h04xk59ettzrqz7c6l4wp
                |
                |object Config {
                |    const val EXPO_PUBLIC_SUPABASE_URL = "${esc(url)}"
                |    const val EXPO_PUBLIC_SUPABASE_ANON_KEY = "${esc(key)}"
                |}
                |""".trimMargin()
            )
        }
    }
    android.sourceSets.getByName("main").java.srcDir(generatedConfigDir)
    tasks.named("preBuild").configure {
        dependsOn(generateConfig)
    }
}
