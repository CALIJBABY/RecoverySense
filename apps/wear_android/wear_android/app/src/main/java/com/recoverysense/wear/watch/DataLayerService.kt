package com.recoverysense.wear.watch

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

data class SensorBatchPayload(
    val batchId: String,
    val watchSessionId: String,
    val sequence: Long,
    val samplingRateHz: Int,
    val timestamps: LongArray,
    val heartRates: IntArray,
    val heartRateTimestamps: LongArray,
    val heartRateAgeMs: LongArray,
    val heartRateAccuracy: IntArray,
    val accelX: FloatArray,
    val accelY: FloatArray,
    val accelZ: FloatArray,
    val accelerationG: FloatArray,
    val accelAccuracy: IntArray,
    val gyroX: FloatArray,
    val gyroY: FloatArray,
    val gyroZ: FloatArray,
    val gyroMagnitude: FloatArray,
    val gyroTimestamps: LongArray,
    val gyroAccuracy: IntArray,
    val stepCounts: FloatArray,
    val stepDetected: IntArray,
    val offBody: IntArray,
    val screenInteractive: IntArray,
    val heartRateAvailable: Boolean,
    val accelerometerAvailable: Boolean,
    val gyroscopeAvailable: Boolean,
    val stepCounterAvailable: Boolean,
    val stepDetectorAvailable: Boolean,
    val offBodyAvailable: Boolean,
    val ppgAvailable: Boolean,
    val ppgState: String,
    val recordingMode: String = "continuous",
    val sleepSessionId: String? = null,
)

data class PpgBatchPayload(
    val batchId: String,
    val watchSessionId: String,
    val sequence: Long,
    val samplingRateHz: Int,
    val timestamps: LongArray,
    val green: IntArray,
    val infrared: IntArray,
    val red: IntArray,
    val greenStatus: IntArray,
    val infraredStatus: IntArray,
    val redStatus: IntArray,
    val source: String,
    val recordingMode: String = "continuous",
    val sleepSessionId: String? = null,
)

class DataLayerService(private val context: Context) {
    fun sendLiveSnapshot(
        heartRate: Int?,
        heartRateAgeMs: Long,
        accelX: Float,
        accelY: Float,
        accelZ: Float,
        accelerationG: Float,
        gyroX: Float?,
        gyroY: Float?,
        gyroZ: Float?,
        gyroMagnitude: Float?,
        stepCount: Float?,
        offBody: Boolean?,
        screenInteractive: Boolean,
        ppgState: String,
        timestampMs: Long,
        recordingMode: String = RECORDING_MODE_CONTINUOUS,
        sleepSessionId: String? = null,
    ): Task<DataItem> {
        val request = PutDataMapRequest.create(LIVE_PATH).apply {
            dataMap.putInt("heartRate", heartRate ?: -1)
            dataMap.putLong("heartRateAgeMs", heartRateAgeMs)
            dataMap.putFloat("accelX", accelX)
            dataMap.putFloat("accelY", accelY)
            dataMap.putFloat("accelZ", accelZ)
            dataMap.putFloat("accelerationG", accelerationG)
            dataMap.putFloat("gyroX", gyroX ?: Float.NaN)
            dataMap.putFloat("gyroY", gyroY ?: Float.NaN)
            dataMap.putFloat("gyroZ", gyroZ ?: Float.NaN)
            dataMap.putFloat("gyroMagnitude", gyroMagnitude ?: Float.NaN)
            dataMap.putFloat("stepCount", stepCount ?: Float.NaN)
            dataMap.putInt("offBody", offBody?.let { if (it) 1 else 0 } ?: -1)
            dataMap.putBoolean("screenInteractive", screenInteractive)
            dataMap.putString("ppgState", ppgState)
            dataMap.putLong("timestamp", timestampMs)
            dataMap.putString("recordingMode", recordingMode)
            sleepSessionId?.let { dataMap.putString("sleepSessionId", it) }
            dataMap.putInt("schemaVersion", SCHEMA_VERSION)
        }.asPutDataRequest().setUrgent()

        return Wearable.getDataClient(context).putDataItem(request)
    }

    fun sendSensorBatch(payload: SensorBatchPayload): Task<DataItem> {
        val size = payload.timestamps.size
        require(size > 0) { "A sensor batch cannot be empty." }
        val allSizes = listOf(
            payload.heartRates.size,
            payload.heartRateTimestamps.size,
            payload.heartRateAgeMs.size,
            payload.heartRateAccuracy.size,
            payload.accelX.size,
            payload.accelY.size,
            payload.accelZ.size,
            payload.accelerationG.size,
            payload.accelAccuracy.size,
            payload.gyroX.size,
            payload.gyroY.size,
            payload.gyroZ.size,
            payload.gyroMagnitude.size,
            payload.gyroTimestamps.size,
            payload.gyroAccuracy.size,
            payload.stepCounts.size,
            payload.stepDetected.size,
            payload.offBody.size,
            payload.screenInteractive.size,
        )
        require(allSizes.all { it == size }) { "All sensor arrays must have the same length." }

        val request = PutDataMapRequest.create("$BATCH_PATH_PREFIX/${payload.batchId}").apply {
            dataMap.putString("batchId", payload.batchId)
            dataMap.putString("watchSessionId", payload.watchSessionId)
            dataMap.putLong("sequence", payload.sequence)
            dataMap.putInt("samplingRateHz", payload.samplingRateHz)
            dataMap.putInt("schemaVersion", SCHEMA_VERSION)
            dataMap.putString("recordingMode", payload.recordingMode)
            payload.sleepSessionId?.let { dataMap.putString("sleepSessionId", it) }
            dataMap.putLongArray("timestamps", payload.timestamps)
            dataMap.putIntegerArrayList("heartRates", ArrayList(payload.heartRates.toList()))
            dataMap.putLongArray("heartRateTimestamps", payload.heartRateTimestamps)
            dataMap.putLongArray("heartRateAgeMs", payload.heartRateAgeMs)
            dataMap.putIntegerArrayList(
                "heartRateAccuracy",
                ArrayList(payload.heartRateAccuracy.toList()),
            )
            dataMap.putFloatArray("accelX", payload.accelX)
            dataMap.putFloatArray("accelY", payload.accelY)
            dataMap.putFloatArray("accelZ", payload.accelZ)
            dataMap.putFloatArray("accelerationG", payload.accelerationG)
            dataMap.putIntegerArrayList("accelAccuracy", ArrayList(payload.accelAccuracy.toList()))
            dataMap.putFloatArray("gyroX", payload.gyroX)
            dataMap.putFloatArray("gyroY", payload.gyroY)
            dataMap.putFloatArray("gyroZ", payload.gyroZ)
            dataMap.putFloatArray("gyroMagnitude", payload.gyroMagnitude)
            dataMap.putLongArray("gyroTimestamps", payload.gyroTimestamps)
            dataMap.putIntegerArrayList("gyroAccuracy", ArrayList(payload.gyroAccuracy.toList()))
            dataMap.putFloatArray("stepCounts", payload.stepCounts)
            dataMap.putIntegerArrayList("stepDetected", ArrayList(payload.stepDetected.toList()))
            dataMap.putIntegerArrayList("offBody", ArrayList(payload.offBody.toList()))
            dataMap.putIntegerArrayList(
                "screenInteractive",
                ArrayList(payload.screenInteractive.toList()),
            )
            dataMap.putBoolean("heartRateAvailable", payload.heartRateAvailable)
            dataMap.putBoolean("accelerometerAvailable", payload.accelerometerAvailable)
            dataMap.putBoolean("gyroscopeAvailable", payload.gyroscopeAvailable)
            dataMap.putBoolean("stepCounterAvailable", payload.stepCounterAvailable)
            dataMap.putBoolean("stepDetectorAvailable", payload.stepDetectorAvailable)
            dataMap.putBoolean("offBodyAvailable", payload.offBodyAvailable)
            dataMap.putBoolean("ppgAvailable", payload.ppgAvailable)
            dataMap.putString("ppgState", payload.ppgState)
            dataMap.putLong("createdAt", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        return Wearable.getDataClient(context).putDataItem(request)
    }

    fun sendEmaEvent(
        eventId: String,
        cravingScore: Int,
        openedAtMs: Long,
        submittedAtMs: Long,
        watchSessionId: String?,
        source: String = "watch_manual",
        promptedAtMs: Long? = null,
    ): Task<DataItem> {
        require(cravingScore in 0..10) { "EMA score must be between 0 and 10." }
        val request = PutDataMapRequest.create("$EMA_EVENT_PATH_PREFIX/$eventId").apply {
            dataMap.putString("eventId", eventId)
            dataMap.putInt("cravingScore", cravingScore)
            dataMap.putLong("timestampMs", submittedAtMs)
            dataMap.putLong("openedAtMs", openedAtMs)
            dataMap.putLong("submittedAtMs", submittedAtMs)
            dataMap.putString("source", source)
            watchSessionId?.let { dataMap.putString("watchSessionId", it) }
            promptedAtMs?.let { dataMap.putLong("promptedAtMs", it) }
            dataMap.putInt("schemaVersion", EMA_SCHEMA_VERSION)
            dataMap.putLong("createdAt", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        return Wearable.getDataClient(context).putDataItem(request)
    }

    fun sendPpgBatch(payload: PpgBatchPayload): Task<DataItem> {
        val size = payload.timestamps.size
        require(size > 0) { "A PPG batch cannot be empty." }
        val allSizes = listOf(
            payload.green.size,
            payload.infrared.size,
            payload.red.size,
            payload.greenStatus.size,
            payload.infraredStatus.size,
            payload.redStatus.size,
        )
        require(allSizes.all { it == size }) { "All PPG arrays must have the same length." }

        val request = PutDataMapRequest.create("$PPG_BATCH_PATH_PREFIX/${payload.batchId}").apply {
            dataMap.putString("batchId", payload.batchId)
            dataMap.putString("watchSessionId", payload.watchSessionId)
            dataMap.putLong("sequence", payload.sequence)
            dataMap.putInt("samplingRateHz", payload.samplingRateHz)
            dataMap.putInt("schemaVersion", PPG_SCHEMA_VERSION)
            dataMap.putString("recordingMode", payload.recordingMode)
            payload.sleepSessionId?.let { dataMap.putString("sleepSessionId", it) }
            dataMap.putString("source", payload.source)
            dataMap.putLongArray("timestamps", payload.timestamps)
            dataMap.putIntegerArrayList("green", ArrayList(payload.green.toList()))
            dataMap.putIntegerArrayList("infrared", ArrayList(payload.infrared.toList()))
            dataMap.putIntegerArrayList("red", ArrayList(payload.red.toList()))
            dataMap.putIntegerArrayList("greenStatus", ArrayList(payload.greenStatus.toList()))
            dataMap.putIntegerArrayList(
                "infraredStatus",
                ArrayList(payload.infraredStatus.toList()),
            )
            dataMap.putIntegerArrayList("redStatus", ArrayList(payload.redStatus.toList()))
            dataMap.putLong("createdAt", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        return Wearable.getDataClient(context).putDataItem(request)
    }

    companion object {
        const val LIVE_PATH = "/recoverysense/live"
        const val BATCH_PATH_PREFIX = "/recoverysense/sensor_batch"
        const val PPG_BATCH_PATH_PREFIX = "/recoverysense/ppg_batch"
        const val EMA_EVENT_PATH_PREFIX = "/recoverysense/ema_event"
        const val RECORDING_MODE_CONTINUOUS = "continuous"
        const val RECORDING_MODE_SLEEP = "sleep"
        const val PPG_SOURCE_SAMSUNG_HEALTH_SENSOR = "samsung_health_sensor_sdk"
        const val SCHEMA_VERSION = 4
        const val PPG_SCHEMA_VERSION = 1
        const val EMA_SCHEMA_VERSION = 1
    }
}
