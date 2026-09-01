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
    private var ppgBatchSink: EventChannel.EventSink? = null
    private var emaEventSink: EventChannel.EventSink? = null
    private var pendingScanInProgress = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LIVE_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    liveSink = events
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
                }

                override fun onCancel(arguments: Any?) {
                    batchSink = null
                }
            }
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PPG_BATCH_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ppgBatchSink = events
                }

                override fun onCancel(arguments: Any?) {
                    ppgBatchSink = null
                }
            }
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EMA_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    emaEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    emaEventSink = null
                }
            }
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTROL_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPendingBatches" -> emitNextPendingItem(result)

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
                                error.message ?: "Unable to acknowledge watch batch.",
                                null,
                            )
                        }
                }

                "startSleepRecording" -> {
                    val sessionId = call.argument<String>("sleepSessionId")
                    if (sessionId.isNullOrBlank()) {
                        result.error("INVALID_SLEEP_SESSION", "A sleep session ID is required.", null)
                        return@setMethodCallHandler
                    }
                    sendWatchMessage(SLEEP_START_PATH, sessionId.toByteArray(), result)
                }

                "stopSleepRecording" -> {
                    sendWatchMessage(SLEEP_STOP_PATH, ByteArray(0), result)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
    }

    override fun onPause() {
        Wearable.getDataClient(this).removeListener(this)
        super.onPause()
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED) emitDataItem(event.dataItem)
        }
    }

    private fun emitNextPendingItem(result: MethodChannel.Result) {
        if (pendingScanInProgress) {
            result.success(false)
            return
        }
        pendingScanInProgress = true

        Wearable.getDataClient(this).dataItems
            .addOnSuccessListener { dataItems ->
                var nextItem: DataItem? = null
                try {
                    // Freeze only one item before releasing the Play services buffer.
                    // Sensor batches are prioritized because they are the high-volume
                    // stream; PPG and EMA items are drained after the sensor backlog.
                    val prefixes = arrayOf(
                        BATCH_PATH_PREFIX,
                        PPG_BATCH_PATH_PREFIX,
                        EMA_EVENT_PATH_PREFIX,
                    )
                    search@ for (prefix in prefixes) {
                        for (item in dataItems) {
                            if (item.uri.path?.startsWith(prefix) == true) {
                                nextItem = item.freeze()
                                break@search
                            }
                        }
                    }
                } finally {
                    dataItems.release()
                }

                pendingScanInProgress = false
                if (nextItem != null) {
                    emitDataItem(nextItem!!)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            .addOnFailureListener { error ->
                pendingScanInProgress = false
                result.error(
                    "WEAR_DATA_ERROR",
                    error.message ?: "Unable to read pending watch data.",
                    null,
                )
            }
    }

    private fun emitDataItem(dataItem: DataItem) {
        when {
            dataItem.uri.path == LIVE_PATH && liveSink != null -> emitLiveItem(dataItem)
            dataItem.uri.path?.startsWith(BATCH_PATH_PREFIX) == true && batchSink != null ->
                emitBatchItem(dataItem)
            dataItem.uri.path?.startsWith(PPG_BATCH_PATH_PREFIX) == true && ppgBatchSink != null ->
                emitPpgBatchItem(dataItem)
            dataItem.uri.path?.startsWith(EMA_EVENT_PATH_PREFIX) == true && emaEventSink != null ->
                emitEmaEventItem(dataItem)
        }
    }

    private fun emitLiveItem(dataItem: DataItem) {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val payload = hashMapOf<String, Any>(
            "schemaVersion" to dataMap.getInt("schemaVersion", 1),
            "heartRate" to dataMap.getInt("heartRate", -1),
            "heartRateAgeMs" to dataMap.getLong("heartRateAgeMs", -1L),
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
            "screenInteractive" to dataMap.getBoolean("screenInteractive", true),
            "ppgState" to (dataMap.getString("ppgState") ?: "unknown"),
            "timestamp" to dataMap.getLong("timestamp", System.currentTimeMillis()),
            "recordingMode" to (dataMap.getString("recordingMode") ?: "continuous"),
            "sleepSessionId" to (dataMap.getString("sleepSessionId") ?: ""),
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
        val heartRateAgeMs = dataMap.longArrayOrDefault("heartRateAgeMs", size, -1L)
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
        val screenInteractive = dataMap.intArrayOrDefault("screenInteractive", size, -1)

        val payload = hashMapOf<String, Any>(
            "uri" to dataItem.uri.toString(),
            "batchId" to (dataMap.getString("batchId") ?: dataItem.uri.lastPathSegment.orEmpty()),
            "watchSessionId" to (dataMap.getString("watchSessionId") ?: "unknown"),
            "sequence" to dataMap.getLong("sequence", 0L),
            "samplingRateHz" to dataMap.getInt("samplingRateHz", 10),
            "schemaVersion" to dataMap.getInt("schemaVersion", 1),
            "recordingMode" to (dataMap.getString("recordingMode") ?: "continuous"),
            "sleepSessionId" to (dataMap.getString("sleepSessionId") ?: ""),
            "createdAt" to dataMap.getLong("createdAt", System.currentTimeMillis()),
            "timestamps" to timestamps.toList(),
            "heartRates" to heartRates.toList(),
            "heartRateTimestamps" to heartRateTimestamps.toList(),
            "heartRateAgeMs" to heartRateAgeMs.toList(),
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
            "screenInteractive" to screenInteractive.toList(),
            "heartRateAvailable" to dataMap.getBoolean("heartRateAvailable", true),
            "accelerometerAvailable" to dataMap.getBoolean("accelerometerAvailable", true),
            "gyroscopeAvailable" to dataMap.getBoolean("gyroscopeAvailable", false),
            "stepCounterAvailable" to dataMap.getBoolean("stepCounterAvailable", false),
            "stepDetectorAvailable" to dataMap.getBoolean("stepDetectorAvailable", false),
            "offBodyAvailable" to dataMap.getBoolean("offBodyAvailable", false),
            "ppgAvailable" to dataMap.getBoolean("ppgAvailable", false),
            "ppgState" to (dataMap.getString("ppgState") ?: "unknown"),
        )

        runOnUiThread { batchSink?.success(payload) }
    }

    private fun emitPpgBatchItem(dataItem: DataItem) {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val timestamps = dataMap.getLongArray("timestamps") ?: return
        val size = timestamps.size
        if (size == 0) return
        val green = dataMap.intArrayOrNull("green", size) ?: return
        val infrared = dataMap.intArrayOrNull("infrared", size) ?: return
        val red = dataMap.intArrayOrNull("red", size) ?: return
        val greenStatus = dataMap.intArrayOrDefault("greenStatus", size, -1)
        val infraredStatus = dataMap.intArrayOrDefault("infraredStatus", size, -1)
        val redStatus = dataMap.intArrayOrDefault("redStatus", size, -1)

        val payload = hashMapOf<String, Any>(
            "uri" to dataItem.uri.toString(),
            "batchId" to (dataMap.getString("batchId") ?: dataItem.uri.lastPathSegment.orEmpty()),
            "watchSessionId" to (dataMap.getString("watchSessionId") ?: "unknown"),
            "sequence" to dataMap.getLong("sequence", 0L),
            "samplingRateHz" to dataMap.getInt("samplingRateHz", 25),
            "schemaVersion" to dataMap.getInt("schemaVersion", 1),
            "recordingMode" to (dataMap.getString("recordingMode") ?: "continuous"),
            "sleepSessionId" to (dataMap.getString("sleepSessionId") ?: ""),
            "source" to (dataMap.getString("source") ?: "unknown"),
            "createdAt" to dataMap.getLong("createdAt", System.currentTimeMillis()),
            "timestamps" to timestamps.toList(),
            "green" to green.toList(),
            "infrared" to infrared.toList(),
            "red" to red.toList(),
            "greenStatus" to greenStatus.toList(),
            "infraredStatus" to infraredStatus.toList(),
            "redStatus" to redStatus.toList(),
        )

        runOnUiThread { ppgBatchSink?.success(payload) }
    }

    private fun emitEmaEventItem(dataItem: DataItem) {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val payload = hashMapOf<String, Any>(
            "uri" to dataItem.uri.toString(),
            "eventId" to (dataMap.getString("eventId") ?: dataItem.uri.lastPathSegment.orEmpty()),
            "cravingScore" to dataMap.getInt("cravingScore", -1),
            "timestampMs" to dataMap.getLong("timestampMs", System.currentTimeMillis()),
            "openedAtMs" to dataMap.getLong("openedAtMs", System.currentTimeMillis()),
            "submittedAtMs" to dataMap.getLong("submittedAtMs", System.currentTimeMillis()),
            "source" to (dataMap.getString("source") ?: "watch_manual"),
            "watchSessionId" to (dataMap.getString("watchSessionId") ?: ""),
            "promptedAtMs" to dataMap.getLong("promptedAtMs", -1L),
        )
        runOnUiThread { emaEventSink?.success(payload) }
    }

    private fun sendWatchMessage(
        path: String,
        payload: ByteArray,
        result: MethodChannel.Result,
    ) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    result.success(0)
                    return@addOnSuccessListener
                }
                var remaining = nodes.size
                var delivered = 0
                nodes.forEach { node ->
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, path, payload)
                        .addOnCompleteListener { task ->
                            if (task.isSuccessful) delivered += 1
                            remaining -= 1
                            if (remaining == 0) result.success(delivered)
                        }
                }
            }
            .addOnFailureListener { error ->
                result.error(
                    "WATCH_COMMAND_FAILED",
                    error.message ?: "Unable to reach the paired watch.",
                    null,
                )
            }
    }

    private fun DataMap.intArrayOrDefault(key: String, size: Int, defaultValue: Int): IntArray {
        val values = getIntegerArrayList(key)?.toIntArray()
        return if (values != null && values.size == size) values else IntArray(size) { defaultValue }
    }

    private fun DataMap.intArrayOrNull(key: String, size: Int): IntArray? {
        val values = getIntegerArrayList(key)?.toIntArray() ?: return null
        return values.takeIf { it.size == size }
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
        const val PPG_BATCH_EVENT_CHANNEL = "recoverysense/ppg_batches"
        const val EMA_EVENT_CHANNEL = "recoverysense/ema_events"
        const val CONTROL_METHOD_CHANNEL = "recoverysense/sensor_control"
        const val LIVE_PATH = "/recoverysense/live"
        const val BATCH_PATH_PREFIX = "/recoverysense/sensor_batch/"
        const val PPG_BATCH_PATH_PREFIX = "/recoverysense/ppg_batch/"
        const val EMA_EVENT_PATH_PREFIX = "/recoverysense/ema_event/"
        const val SLEEP_START_PATH = "/recoverysense/sleep/start"
        const val SLEEP_STOP_PATH = "/recoverysense/sleep/stop"
    }
}
