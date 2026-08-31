import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Applied only once Firebase has been set up. Without google-services.json the
// plugin fails the build outright, so a fresh clone would not compile —
// see docs/PUSH_NOTIFICATIONS.md#android.
if (rootProject.file("app/google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Supabase host and anon key live outside the repo, the same arrangement as
// Config/Secrets.xcconfig on iOS. With the file absent the app builds and runs
// on sample data rather than failing, so a fresh clone works immediately.
val secrets = Properties().apply {
    val file = rootProject.file("secrets.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun secret(name: String): String = secrets.getProperty(name) ?: ""

// Signing config lives outside the repo entirely — in ~/.cartel — because
// losing this key means the league has to uninstall and reinstall to take an
// update. Absent, release builds are simply unsigned and debug still works.
val keystore = Properties().apply {
    val file = File(System.getProperty("user.home"), ".cartel/keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.commissionerscartel.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.commissionerscartel.app"
        minSdk = 26
        targetSdk = 37
        // Bump on every build handed out: Android refuses an install whose
        // versionCode is not higher than what is already on the phone.
        versionCode = 37
        versionName = "0.36.0"

        buildConfigField("String", "SUPABASE_HOST", "\"${secret("SUPABASE_HOST")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${secret("SUPABASE_ANON_KEY")}\"")
        buildConfigField("String", "ESPN_LEAGUE_ID", "\"${secret("ESPN_LEAGUE_ID")}\"")
    }

    signingConfigs {
        if (keystore.getProperty("storeFile") != null) {
            create("release") {
                storeFile = File(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.security.crypto)
    // Custom Tabs, so an article opens inside the app.
    implementation(libs.androidx.browser)
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    debugImplementation(libs.compose.ui.tooling)

    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.auth)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.serialization.json)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
