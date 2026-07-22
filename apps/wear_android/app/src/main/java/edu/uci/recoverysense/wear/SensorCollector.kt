package edu.uci.recoverysense.wear

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.random.Random

class SensorCollector(context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private var accelX = 0f
    private var accelY = 0f
    private var accelZ = 0f

    fun start() {
        accelerometer?.also { sensor ->
            sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    fun currentReading(): SensorReading {
        // Week 4 placeholder: real heart rate API can replace this simulated value.
        val simulatedHeartRate = Random.nextInt(70, 110).toFloat()
        return SensorReading(
            heartRate = simulatedHeartRate,
            accelX = accelX,
            accelY = accelY,
            accelZ = accelZ,
        )
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_ACCELEROMETER) {
            accelX = event.values.getOrNull(0) ?: 0f
            accelY = event.values.getOrNull(1) ?: 0f
            accelZ = event.values.getOrNull(2) ?: 0f
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
