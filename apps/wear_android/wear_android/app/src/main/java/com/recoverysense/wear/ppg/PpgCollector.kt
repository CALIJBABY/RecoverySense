package com.recoverysense.wear.ppg

import android.content.Context

/** One raw Samsung BioActive-sensor PPG sample. Values are ADC counts. */
data class RawPpgSample(
    val timestampMs: Long,
    val green: Int,
    val infrared: Int,
    val red: Int,
    val greenStatus: Int,
    val infraredStatus: Int,
    val redStatus: Int,
)

/**
 * Compile-safe raw PPG entry point.
 *
 * Samsung's AAR is loaded reflectively so the ordinary build still compiles
 * before the SDK file is available. PPG is currently gated by
 * [PpgFeatureFlags.ENABLED], which is false until SDK access is granted.
 */
interface PpgCollector {
    val state: String
    val isAvailable: Boolean

    fun start()
    fun stop()
}

private class DisabledPpgCollector(
    private val onStateChanged: (String, Boolean) -> Unit,
) : PpgCollector {
    override val state: String = "disabled_until_sdk_access"
    override val isAvailable: Boolean = false

    override fun start() {
        onStateChanged(state, false)
    }

    override fun stop() = Unit
}

object PpgCollectorFactory {
    fun create(
        context: Context,
        onSamples: (List<RawPpgSample>) -> Unit,
        onStateChanged: (String, Boolean) -> Unit,
    ): PpgCollector {
        if (!PpgFeatureFlags.ENABLED) {
            return DisabledPpgCollector(onStateChanged)
        }
        return SamsungHealthSensorPpgCollector(
            context = context.applicationContext,
            onSamples = onSamples,
            onStateChanged = onStateChanged,
        )
    }
}
