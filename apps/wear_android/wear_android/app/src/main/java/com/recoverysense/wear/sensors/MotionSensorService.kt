package com.recoverysense.wear.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock

data class VectorSensorReading(
    val x: Float,
    val y: Float,
    val z: Float,
    val timestampMs: Long,
    val accuracy: Int,
)

data class StepCounterReading(
    val totalSteps: Float,
    val timestampMs: Long,
    val accuracy: Int,
)

data class MotionSensorAvailability(
    val accelerometer: Boolean,
    val gyroscope: Boolean,
    val stepCounter: Boolean,
    val stepDetector: Boolean,
)

class MotionSensorService(
    context: Context,
    private val onAccelerationChanged: (VectorSensorReading) -> Unit,
    private val onGyroscopeChanged: (VectorSensorReading) -> Unit = {},
    private val onStepCounterChanged: (StepCounterReading) -> Unit = {},
    private val onStepDetected: (timestampMs: Long, accuracy: Int) -> Unit = { _, _ -> },
    private val onAvailabilityChanged: (MotionSensorAvailability) -> Unit = {},
) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val stepCounter: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    private val stepDetector: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

    fun start(activityRecognitionGranted: Boolean) {
        onAvailabilityChanged(
            MotionSensorAvailability(
                accelerometer = accelerometer != null,
                gyroscope = gyroscope != null,
                stepCounter = activityRecognitionGranted && stepCounter != null,
                stepDetector = activityRecognitionGranted && stepDetector != null,
            )
        )

        accelerometer?.let {
            sensorManager.registerListener(this, it, SENSOR_INTERVAL_US)
        }
        gyroscope?.let {
            sensorManager.registerListener(this, it, SENSOR_INTERVAL_US)
        }

        if (activityRecognitionGranted) {
            stepCounter?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            }
            stepDetector?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            }
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        val timestampMs = eventTimestampToWallClockMs(event.timestamp)

        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                if (event.values.size >= 3) {
                    onAccelerationChanged(
                        VectorSensorReading(
                            x = event.values[0],
                            y = event.values[1],
                            z = event.values[2],
                            timestampMs = timestampMs,
                            accuracy = event.accuracy,
                        )
                    )
                }
            }

            Sensor.TYPE_GYROSCOPE -> {
                if (event.values.size >= 3) {
                    onGyroscopeChanged(
                        VectorSensorReading(
                            x = event.values[0],
                            y = event.values[1],
                            z = event.values[2],
                            timestampMs = timestampMs,
                            accuracy = event.accuracy,
                        )
                    )
                }
            }

            Sensor.TYPE_STEP_COUNTER -> {
                event.values.firstOrNull()?.let { totalSteps ->
                    onStepCounterChanged(
                        StepCounterReading(
                            totalSteps = totalSteps,
                            timestampMs = timestampMs,
                            accuracy = event.accuracy,
                        )
                    )
                }
            }

            Sensor.TYPE_STEP_DETECTOR -> {
                if (event.values.firstOrNull()?.let { it > 0f } == true) {
                    onStepDetected(timestampMs, event.accuracy)
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun eventTimestampToWallClockMs(eventTimestampNs: Long): Long {
        val elapsedDeltaNs = SystemClock.elapsedRealtimeNanos() - eventTimestampNs
        return System.currentTimeMillis() - elapsedDeltaNs / 1_000_000L
    }

    private companion object {
        const val SENSOR_INTERVAL_US = 100_000
    }
}
