plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.recoverysense.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.recoverysense.wear"
        minSdk = 28
        targetSdk = 36
        versionCode = 7
        versionName = "0.5.3"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

val samsungHealthSensorAar = file("libs/samsung-health-sensor-api.aar")

dependencies {
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.ui:ui:1.8.3")
    implementation("androidx.compose.material3:material3:1.3.2")
    implementation("androidx.compose.ui:ui-tooling-preview:1.8.3")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    if (samsungHealthSensorAar.exists()) {
        implementation(files(samsungHealthSensorAar))
    }
    debugImplementation("androidx.compose.ui:ui-tooling:1.8.3")
    testImplementation("junit:junit:4.13.2")
}
