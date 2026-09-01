package com.recoverysense.wear

import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {
    private var liveSink: EventChannel.EventSink? = null
    private var batchSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LIVE_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    liveSink = events
                    emitExistingItems()
                }

                override fun onCancel(arguments: Any?) {
                    liveSink = null
                }
            }
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATCH_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    batchSink = events
                    emitExistingItems()
                }

                override fun onCancel(arguments: Any?) {
                    batchSink = null
                }
            }
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTROL_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPendingBatches" -> {
                    emitExistingItems()
                    result.success(null)
                }

                "ackBatch" -> {
                    val uriText = call.argument<String>("uri")
                    if (uriText.isNullOrBlank()) {
                        result.error("INVALID_URI", "A batch URI is required.", null)
                        return@setMethodCallHandler
                    }

                    Wearable.getDataClient(this)
                        .deleteDataItems(Uri.parse(uriText))
                        .addOnSuccessListener { deletedCount -> result.success(deletedCount) }
                        .addOnFailureListener { error ->
                            result.error(
                                "ACK_FAILED",
                                error.message ?: "Unable to acknowledge sensor batch.",
                                null,
                            )
                        }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
        emitExistingItems()
    }

    override fun onPause() {
        Wearable.getDataClient(this).removeListener(this)
        super.onPause()
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED) {
                emitDataItem(event.dataItem)
            }
        }
    }

    private fun emitExistingItems() {
        Wearable.getDataClient(this).dataItems
            .addOnSuccessListener { dataItems ->
                try {
                    for (item in dataItems) emitDataItem(item)
                } finally {
                    dataItems.release()
                }
            }
            .addOnFailureListener { error ->
                runOnUiThread {
                    batchSink?.error(
                        "WEAR_DATA_ERROR",
                        error.message ?: "Unable to read watch data.",
                        null,
                    )
                }
            }
    }

    private fun emitDataItem(dataItem: DataItem) {
        when {
            dataItem.uri.path == LIVE_PATH -> emitLiveItem(dataItem)
            dataItem.uri.path?.startsWith(BATCH_PATH_PREFIX) == true -> emitBatchItem(dataItem)
        }
    }

    private fun emitLiveItem(dataItem: DataItem) {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val payload = hashMapOf<String, Any>(
            "schemaVersion" to dataMap.getInt("schemaVersion", 1),
            "heartRate" to dataMap.getInt("heartRate", -1),
            "accelX" to dataMap.getFloat("accelX", 0f).toDouble(),
            "accelY" to dataMap.getFloat("accelY", 0f).toDouble(),
            "accelZ" to dataMap.getFloat("accelZ", 0f).toDouble(),
            "accelerationG" to dataMap.getFloat("accelerationG", 0f).toDouble(),
            "gyroX" to dataMap.getFloat("gyroX", Float.NaN).toDouble(),
            "gyroY" to dataMap.getFloat("gyroY", Float.NaN).toDouble(),
            "gyroZ" to dataMap.getFloat("gyroZ", Float.NaN).toDouble(),
            "gyroMagnitude" to dataMap.getFloat("gyroMagnitude", Float.NaN).toDouble(),
            "stepCount" to dataMap.getFloat("stepCount", Float.NaN).toDouble(),
            "offBody" to dataMap.getInt("offBody", -1),
            "timestamp" to dataMap.getLong("timestamp", System.currentTimeMillis()),
        )

        runOnUiThread { liveSink?.success(payload) }
    }

    private fun emitBatchItem(dataItem: DataItem) {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val timestamps = dataMap.getLongArray("timestamps") ?: return
        val size = timestamps.size
        if (size == 0) return

        val heartRates = dataMap.intArrayOrDefault("heartRates", size, -1)
        val heartRateTimestamps = dataMap.longArrayOrDefault("heartRateTimestamps", size, -1L)
        val heartRateAccuracy = dataMap.intArrayOrDefault("heartRateAccuracy", size, 0)
        val accelX = dataMap.floatArrayOrNull("accelX", size) ?: return
        val accelY = dataMap.floatArrayOrNull("accelY", size) ?: return
        val accelZ = dataMap.floatArrayOrNull("accelZ", size) ?: return
        val accelerationG = dataMap.floatArrayOrNull("accelerationG", size) ?: return
        val accelAccuracy = dataMap.intArrayOrDefault("accelAccuracy", size, 0)
        val gyroX = dataMap.floatArrayOrDefault("gyroX", size, Float.NaN)
        val gyroY = dataMap.floatArrayOrDefault("gyroY", size, Float.NaN)
        val gyroZ = dataMap.floatArrayOrDefault("gyroZ", size, Float.NaN)
        val gyroMagnitude = dataMap.floatArrayOrDefault("gyroMagnitude", size, Float.NaN)
        val gyroTimestamps = dataMap.longArrayOrDefault("gyroTimestamps", size, -1L)
        val gyroAccuracy = dataMap.intArrayOrDefault("gyroAccuracy", size, 0)
        val stepCounts = dataMap.floatArrayOrDefault("stepCounts", size, Float.NaN)
        val stepDetected = dataMap.intArrayOrDefault("stepDetected", size, 0)
        val offBody = dataMap.intArrayOrDefault("offBody", size, -1)

        val payload = hashMapOf<String, Any>(
            "uri" to dataItem.uri.toString(),
            "batchId" to (dataMap.getString("batchId") ?: dataItem.uri.lastPathSegment.orEmpty()),
            "watchSessionId" to (dataMap.getString("watchSessionId") ?: "unknown"),
            "sequence" to dataMap.getLong("sequence", 0L),
            "samplingRateHz" to dataMap.getInt("samplingRateHz", 10),
            "schemaVersion" to dataMap.getInt("schemaVersion", 1),
            "createdAt" to dataMap.getLong("createdAt", System.currentTimeMillis()),
            "timestamps" to timestamps.toList(),
            "heartRates" to heartRates.toList(),
            "heartRateTimestamps" to heartRateTimestamps.toList(),
            "heartRateAccuracy" to heartRateAccuracy.toList(),
            "accelX" to accelX.map { it.toDouble() },
            "accelY" to accelY.map { it.toDouble() },
            "accelZ" to accelZ.map { it.toDouble() },
            "accelerationG" to accelerationG.map { it.toDouble() },
            "accelAccuracy" to accelAccuracy.toList(),
            "gyroX" to gyroX.map { it.toDouble() },
            "gyroY" to gyroY.map { it.toDouble() },
            "gyroZ" to gyroZ.map { it.toDouble() },
            "gyroMagnitude" to gyroMagnitude.map { it.toDouble() },
            "gyroTimestamps" to gyroTimestamps.toList(),
            "gyroAccuracy" to gyroAccuracy.toList(),
            "stepCounts" to stepCounts.map { it.toDouble() },
            "stepDetected" to stepDetected.toList(),
            "offBody" to offBody.toList(),
            "heartRateAvailable" to dataMap.getBoolean("heartRateAvailable", true),
            "accelerometerAvailable" to dataMap.getBoolean("accelerometerAvailable", true),
            "gyroscopeAvailable" to dataMap.getBoolean("gyroscopeAvailable", false),
            "stepCounterAvailable" to dataMap.getBoolean("stepCounterAvailable", false),
            "stepDetectorAvailable" to dataMap.getBoolean("stepDetectorAvailable", false),
            "offBodyAvailable" to dataMap.getBoolean("offBodyAvailable", false),
        )

        runOnUiThread { batchSink?.success(payload) }
    }

    private fun DataMap.intArrayOrDefault(key: String, size: Int, defaultValue: Int): IntArray {
        val values = getIntegerArrayList(key)?.toIntArray()
        return if (values != null && values.size == size) values else IntArray(size) { defaultValue }
    }

    private fun DataMap.longArrayOrDefault(key: String, size: Int, defaultValue: Long): LongArray {
        val values = getLongArray(key)
        return if (values != null && values.size == size) values else LongArray(size) { defaultValue }
    }

    private fun DataMap.floatArrayOrDefault(key: String, size: Int, defaultValue: Float): FloatArray {
        val values = getFloatArray(key)
        return if (values != null && values.size == size) values else FloatArray(size) { defaultValue }
    }

    private fun DataMap.floatArrayOrNull(key: String, size: Int): FloatArray? {
        val values = getFloatArray(key) ?: return null
        return values.takeIf { it.size == size }
    }

    private companion object {
        const val LIVE_EVENT_CHANNEL = "recoverysense/live_sensors"
        const val BATCH_EVENT_CHANNEL = "recoverysense/sensor_batches"
        const val CONTROL_METHOD_CHANNEL = "recoverysense/sensor_control"
        const val LIVE_PATH = "/recoverysense/live"
        const val BATCH_PATH_PREFIX = "/recoverysense/sensor_batch/"
    }
}
