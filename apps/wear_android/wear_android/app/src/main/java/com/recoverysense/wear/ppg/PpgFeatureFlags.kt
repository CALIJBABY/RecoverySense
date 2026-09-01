package com.recoverysense.wear.ppg

/**
 * Raw PPG is intentionally disabled until Samsung grants Health Sensor SDK
 * access and the official AAR is added to app/libs.
 *
 * The PPG storage, phone ingestion, export, and ML feature pipeline remain in
 * the project. To enable collection later, add the AAR and change ENABLED to
 * true. No other PPG pipeline code needs to be restored.
 */
object PpgFeatureFlags {
    const val ENABLED = false
}
