package com.recoverysense.wear.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock

data class HeartRateReading(
    val bpm: Float,
    val timestampMs: Long,
    val accuracy: Int,
)

class HeartRateSensorService(
    context: Context,
    private val onHeartRateChanged: (HeartRateReading) -> Unit,
    private val onOffBodyChanged: (offBody: Boolean?, timestampMs: Long) -> Unit = { _, _ -> },
    private val onAvailabilityChanged: (heartRateAvailable: Boolean, offBodyAvailable: Boolean) -> Unit = { _, _ -> },
) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val heartRateSensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)
    private val offBodySensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT)

    fun start() {
        onAvailabilityChanged(heartRateSensor != null, offBodySensor != null)

        heartRateSensor?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_NORMAL,
            )
        }

        offBodySensor?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_NORMAL,
            )
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        val timestampMs = eventTimestampToWallClockMs(event.timestamp)

        when (event.sensor.type) {
            Sensor.TYPE_HEART_RATE -> {
                if (event.values.isNotEmpty()) {
                    onHeartRateChanged(
                        HeartRateReading(
                            bpm = event.values[0],
                            timestampMs = timestampMs,
                            accuracy = event.accuracy,
                        )
                    )
                }
            }

            Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT -> {
                val rawValue = event.values.firstOrNull()
                onOffBodyChanged(
                    rawValue?.let { it >= 0.5f },
                    timestampMs,
                )
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun eventTimestampToWallClockMs(eventTimestampNs: Long): Long {
        val elapsedDeltaNs = SystemClock.elapsedRealtimeNanos() - eventTimestampNs
        return System.currentTimeMillis() - elapsedDeltaNs / 1_000_000L
    }
}
