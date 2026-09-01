package com.recoverysense.wear.sleep

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.recoverysense.wear.MainActivity
import com.recoverysense.wear.ppg.PpgCollector
import com.recoverysense.wear.ppg.PpgCollectorFactory
import com.recoverysense.wear.ppg.PpgFeatureFlags
import com.recoverysense.wear.ppg.RawPpgSample
import com.recoverysense.wear.sensors.HeartRateReading
import com.recoverysense.wear.sensors.HeartRateSensorService
import com.recoverysense.wear.sensors.MotionSensorAvailability
import com.recoverysense.wear.sensors.MotionSensorService
import com.recoverysense.wear.sensors.StepCounterReading
import com.recoverysense.wear.sensors.VectorSensorReading
import com.recoverysense.wear.watch.DataLayerService
import com.recoverysense.wear.watch.PpgBatchPayload
import com.recoverysense.wear.watch.SensorBatchPayload
import java.util.UUID
import kotlin.math.sqrt

/**
 * Unified all-day and overnight foreground recorder.
 *
 * The previous version collected daytime data from MainActivity. That meant
 * collection could stop when the watch display turned off or Android removed
 * the activity. This service owns all sensors instead, remains foreground, and
 * switches between continuous/daytime and sleep modes without dropping data.
 */
class SleepTrackingService : Service() {
    private lateinit var heartRateService: HeartRateSensorService
    private lateinit var motionSensorService: MotionSensorService
    private lateinit var dataLayerService: DataLayerService
    private lateinit var ppgCollector: PpgCollector
    private lateinit var powerManager: PowerManager

    private var recordingMode = DataLayerService.RECORDING_MODE_CONTINUOUS
    private var sleepSessionId: String? = null
    private var watchSessionId: String = newWatchSessionId(recordingMode, null)
    private var batchSequence = 0L
    private var ppgBatchSequence = 0L
    private var tracking = false

    private var latestHeartRate: Int? = null
    private var latestHeartRateTimestampMs = -1L
    private var latestHeartRateAccuracy = 0
    private var latestGyroX = Float.NaN
    private var latestGyroY = Float.NaN
    private var latestGyroZ = Float.NaN
    private var latestGyroMagnitude = Float.NaN
    private var latestGyroTimestampMs = -1L
    private var latestGyroAccuracy = 0
    private var latestStepCount = Float.NaN
    private var pendingStepEvents = 0
    private var latestOffBody: Boolean? = null

    private var heartRateAvailable = false
    private var accelerometerAvailable = false
    private var gyroscopeAvailable = false
    private var stepCounterAvailable = false
    private var stepDetectorAvailable = false
    private var offBodyAvailable = false
    private var ppgAvailable = false
    private var ppgState = "not_started"

    private var lastSampleAtMs = 0L
    private var lastLiveAtMs = 0L
    private val sampleBuffer = mutableListOf<SensorSample>()
    private val ppgBuffer = mutableListOf<RawPpgSample>()

    override fun onCreate() {
        super.onCreate()
        dataLayerService = DataLayerService(this)
        powerManager = getSystemService(PowerManager::class.java)
        heartRateService = HeartRateSensorService(
            context = this,
            onHeartRateChanged = ::handleHeartRate,
            onOffBodyChanged = { offBody, _ ->
                latestOffBody = offBody
                writeStatus()
            },
            onAvailabilityChanged = { heartRate, offBody ->
                heartRateAvailable = heartRate
                offBodyAvailable = offBody
                writeStatus()
            },
        )
        motionSensorService = MotionSensorService(
            context = this,
            onAccelerationChanged = ::handleAcceleration,
            onGyroscopeChanged = ::handleGyroscope,
            onStepCounterChanged = ::handleStepCounter,
            onStepDetected = { _, _ -> pendingStepEvents += 1 },
            onAvailabilityChanged = ::handleMotionAvailability,
        )
        ppgCollector = PpgCollectorFactory.create(
            context = this,
            onSamples = ::handlePpgSamples,
            onStateChanged = { state, available ->
                ppgState = state
                ppgAvailable = available
                writeStatus()
            },
        )
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_CONTINUOUS -> startContinuousTracking()
            ACTION_START_SLEEP -> {
                val requestedSession = intent.getStringExtra(EXTRA_SLEEP_SESSION_ID)
                if (!requestedSession.isNullOrBlank()) startSleepTracking(requestedSession)
            }
            ACTION_STOP_SLEEP -> stopSleepAndResumeContinuous()
            ACTION_STOP_ALL -> stopAllTracking()
            else -> restoreTrackingIfNeeded()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startContinuousTracking() {
        if (!tracking) {
            switchSession(DataLayerService.RECORDING_MODE_CONTINUOUS, null, flush = false)
            startSensors()
        } else if (recordingMode != DataLayerService.RECORDING_MODE_SLEEP) {
            persistActiveState()
            updateNotification()
        }
    }

    private fun startSleepTracking(sessionId: String) {
        if (tracking && recordingMode == DataLayerService.RECORDING_MODE_SLEEP &&
            sleepSessionId == sessionId
        ) return
        switchSession(DataLayerService.RECORDING_MODE_SLEEP, sessionId, flush = tracking)
        if (!tracking) startSensors() else updateNotification()
    }

    private fun stopSleepAndResumeContinuous() {
        if (recordingMode == DataLayerService.RECORDING_MODE_SLEEP) {
            switchSession(DataLayerService.RECORDING_MODE_CONTINUOUS, null, flush = true)
            updateNotification()
        } else if (!tracking) {
            startContinuousTracking()
        }
    }

    private fun switchSession(mode: String, sessionId: String?, flush: Boolean) {
        if (flush) {
            sendBufferedBatch()
            sendBufferedPpgBatch()
        }
        recordingMode = mode
        sleepSessionId = sessionId
        watchSessionId = newWatchSessionId(mode, sessionId)
        batchSequence = 0L
        ppgBatchSequence = 0L
        persistActiveState()
        writeStatus()
    }

    private fun startSensors() {
        tracking = true
        persistActiveState()
        startAsForeground()

        val activityGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACTIVITY_RECOGNITION,
        ) == PackageManager.PERMISSION_GRANTED
        if (heartRatePermissionGranted()) {
            heartRateService.start()
        } else {
            heartRateAvailable = false
            offBodyAvailable = false
        }
        motionSensorService.start(activityGranted)

        // Raw PPG is intentionally disabled until Samsung Health Sensor SDK
        // access is granted. The collector, storage, export, and ML pipeline
        // remain in place and can be enabled with one feature flag later.
        if (!PpgFeatureFlags.ENABLED) {
            ppgState = "disabled_until_sdk_access"
            ppgAvailable = false
            ppgCollector.start()
        } else if (ppgPermissionGranted()) {
            ppgCollector.start()
        } else {
            ppgState = "permission_missing"
            ppgAvailable = false
        }
        writeStatus()
    }

    private fun heartRatePermissionGranted(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 36) {
            READ_HEART_RATE_PERMISSION
        } else {
            Manifest.permission.BODY_SENSORS
        }
        return ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun ppgPermissionGranted(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 36) {
            READ_ADDITIONAL_HEALTH_DATA_PERMISSION
        } else {
            Manifest.permission.BODY_SENSORS
        }
        return ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun restoreTrackingIfNeeded() {
        if (tracking) return
        val prefs = preferences()
        if (!prefs.getBoolean(KEY_ACTIVE, false)) {
            stopSelf()
            return
        }
        recordingMode = prefs.getString(
            KEY_RECORDING_MODE,
            DataLayerService.RECORDING_MODE_CONTINUOUS,
        ) ?: DataLayerService.RECORDING_MODE_CONTINUOUS
        sleepSessionId = prefs.getString(KEY_SLEEP_SESSION_ID, null)
        if (recordingMode == DataLayerService.RECORDING_MODE_SLEEP && sleepSessionId.isNullOrBlank()) {
            recordingMode = DataLayerService.RECORDING_MODE_CONTINUOUS
            sleepSessionId = null
        }
        watchSessionId = newWatchSessionId(recordingMode, sleepSessionId)
        batchSequence = 0L
        ppgBatchSequence = 0L
        startSensors()
    }

    private fun stopAllTracking() {
        if (tracking) stopSensors(flush = true)
        tracking = false
        sleepSessionId = null
        recordingMode = DataLayerService.RECORDING_MODE_CONTINUOUS
        preferences().edit().clear().apply()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopSensors(flush: Boolean) {
        if (flush) {
            sendBufferedBatch()
            sendBufferedPpgBatch()
        }
        heartRateService.stop()
        motionSensorService.stop()
        ppgCollector.stop()
    }

    private fun handleHeartRate(reading: HeartRateReading) {
        latestHeartRate = reading.bpm.takeIf { it > 0f }?.toInt()
        latestHeartRateTimestampMs = reading.timestampMs
        latestHeartRateAccuracy = reading.accuracy
        writeStatus()
    }

    private fun handleGyroscope(reading: VectorSensorReading) {
        latestGyroX = reading.x
        latestGyroY = reading.y
        latestGyroZ = reading.z
        latestGyroMagnitude = sqrt(
            (reading.x * reading.x + reading.y * reading.y + reading.z * reading.z).toDouble()
        ).toFloat()
        latestGyroTimestampMs = reading.timestampMs
        latestGyroAccuracy = reading.accuracy
    }

    private fun handleStepCounter(reading: StepCounterReading) {
        latestStepCount = reading.totalSteps
        writeStatus()
    }

    private fun handleMotionAvailability(availability: MotionSensorAvailability) {
        accelerometerAvailable = availability.accelerometer
        gyroscopeAvailable = availability.gyroscope
        stepCounterAvailable = availability.stepCounter
        stepDetectorAvailable = availability.stepDetector
        writeStatus()
    }

    private fun handleAcceleration(reading: VectorSensorReading) {
        if (!tracking) return
        val magnitudeMs2 = sqrt(
            (reading.x * reading.x + reading.y * reading.y + reading.z * reading.z).toDouble()
        )
        val magnitudeG = (magnitudeMs2 / STANDARD_GRAVITY).toFloat()
        recordMotionSample(reading, magnitudeG)
    }

    private fun recordMotionSample(
        acceleration: VectorSensorReading,
        accelerationG: Float,
    ) {
        val now = acceleration.timestampMs
        if (now - lastSampleAtMs < SAMPLE_INTERVAL_MS) return
        lastSampleAtMs = now

        val heartRateAgeMs = if (latestHeartRateTimestampMs > 0) {
            (now - latestHeartRateTimestampMs).coerceAtLeast(0L)
        } else {
            -1L
        }
        val freshHeartRate = latestHeartRate?.takeIf {
            heartRateAgeMs in 0..HEART_RATE_STALE_AFTER_MS
        }
        val stepEvents = pendingStepEvents
        pendingStepEvents = 0
        val screenInteractive = if (powerManager.isInteractive) 1 else 0

        sampleBuffer += SensorSample(
            timestampMs = now,
            heartRate = freshHeartRate ?: -1,
            heartRateTimestampMs = latestHeartRateTimestampMs,
            heartRateAgeMs = heartRateAgeMs,
            heartRateAccuracy = latestHeartRateAccuracy,
            accelX = acceleration.x,
            accelY = acceleration.y,
            accelZ = acceleration.z,
            accelerationG = accelerationG,
            accelAccuracy = acceleration.accuracy,
            gyroX = latestGyroX,
            gyroY = latestGyroY,
            gyroZ = latestGyroZ,
            gyroMagnitude = latestGyroMagnitude,
            gyroTimestampMs = latestGyroTimestampMs,
            gyroAccuracy = latestGyroAccuracy,
            stepCount = latestStepCount,
            stepDetected = stepEvents,
            offBody = latestOffBody?.let { if (it) 1 else 0 } ?: -1,
            screenInteractive = screenInteractive,
        )

        writeStatus(
            accelerationG = accelerationG,
            gyroMagnitude = latestGyroMagnitude.takeIf { it.isFinite() },
            heartRateAgeMs = heartRateAgeMs,
        )

        if (now - lastLiveAtMs >= LIVE_INTERVAL_MS) {
            lastLiveAtMs = now
            dataLayerService.sendLiveSnapshot(
                heartRate = freshHeartRate,
                heartRateAgeMs = heartRateAgeMs,
                accelX = acceleration.x,
                accelY = acceleration.y,
                accelZ = acceleration.z,
                accelerationG = accelerationG,
                gyroX = latestGyroX.takeIf { it.isFinite() },
                gyroY = latestGyroY.takeIf { it.isFinite() },
                gyroZ = latestGyroZ.takeIf { it.isFinite() },
                gyroMagnitude = latestGyroMagnitude.takeIf { it.isFinite() },
                stepCount = latestStepCount.takeIf { it.isFinite() },
                offBody = latestOffBody,
                screenInteractive = screenInteractive == 1,
                ppgState = ppgState,
                timestampMs = now,
                recordingMode = recordingMode,
                sleepSessionId = sleepSessionId,
            )
        }

        if (sampleBuffer.size >= BATCH_SAMPLE_COUNT) sendBufferedBatch()
    }

    private fun handlePpgSamples(samples: List<RawPpgSample>) {
        if (!tracking || samples.isEmpty()) return
        ppgBuffer += samples
        while (ppgBuffer.size >= PPG_BATCH_SAMPLE_COUNT) {
            sendBufferedPpgBatch(PPG_BATCH_SAMPLE_COUNT)
        }
    }

    private fun sendBufferedBatch() {
        if (sampleBuffer.isEmpty()) return
        val batch = sampleBuffer.toList()
        sampleBuffer.clear()
        val sequence = batchSequence++
        val batchId = "${watchSessionId}_$sequence"

        dataLayerService.sendSensorBatch(
            SensorBatchPayload(
                batchId = batchId,
                watchSessionId = watchSessionId,
                sequence = sequence,
                samplingRateHz = SAMPLING_RATE_HZ,
                timestamps = batch.map { it.timestampMs }.toLongArray(),
                heartRates = batch.map { it.heartRate }.toIntArray(),
                heartRateTimestamps = batch.map { it.heartRateTimestampMs }.toLongArray(),
                heartRateAgeMs = batch.map { it.heartRateAgeMs }.toLongArray(),
                heartRateAccuracy = batch.map { it.heartRateAccuracy }.toIntArray(),
                accelX = batch.map { it.accelX }.toFloatArray(),
                accelY = batch.map { it.accelY }.toFloatArray(),
                accelZ = batch.map { it.accelZ }.toFloatArray(),
                accelerationG = batch.map { it.accelerationG }.toFloatArray(),
                accelAccuracy = batch.map { it.accelAccuracy }.toIntArray(),
                gyroX = batch.map { it.gyroX }.toFloatArray(),
                gyroY = batch.map { it.gyroY }.toFloatArray(),
                gyroZ = batch.map { it.gyroZ }.toFloatArray(),
                gyroMagnitude = batch.map { it.gyroMagnitude }.toFloatArray(),
                gyroTimestamps = batch.map { it.gyroTimestampMs }.toLongArray(),
                gyroAccuracy = batch.map { it.gyroAccuracy }.toIntArray(),
                stepCounts = batch.map { it.stepCount }.toFloatArray(),
                stepDetected = batch.map { it.stepDetected }.toIntArray(),
                offBody = batch.map { it.offBody }.toIntArray(),
                screenInteractive = batch.map { it.screenInteractive }.toIntArray(),
                heartRateAvailable = heartRateAvailable,
                accelerometerAvailable = accelerometerAvailable,
                gyroscopeAvailable = gyroscopeAvailable,
                stepCounterAvailable = stepCounterAvailable,
                stepDetectorAvailable = stepDetectorAvailable,
                offBodyAvailable = offBodyAvailable,
                ppgAvailable = ppgAvailable,
                ppgState = ppgState,
                recordingMode = recordingMode,
                sleepSessionId = sleepSessionId,
            )
        )
    }

    private fun sendBufferedPpgBatch(maxSamples: Int = Int.MAX_VALUE) {
        if (ppgBuffer.isEmpty()) return
        val takeCount = minOf(maxSamples, ppgBuffer.size)
        val batch = ppgBuffer.take(takeCount)
        ppgBuffer.subList(0, takeCount).clear()
        val sequence = ppgBatchSequence++
        val batchId = "ppg_${watchSessionId}_$sequence"
        dataLayerService.sendPpgBatch(
            PpgBatchPayload(
                batchId = batchId,
                watchSessionId = watchSessionId,
                sequence = sequence,
                samplingRateHz = PPG_SAMPLING_RATE_HZ,
                timestamps = batch.map { it.timestampMs }.toLongArray(),
                green = batch.map { it.green }.toIntArray(),
                infrared = batch.map { it.infrared }.toIntArray(),
                red = batch.map { it.red }.toIntArray(),
                greenStatus = batch.map { it.greenStatus }.toIntArray(),
                infraredStatus = batch.map { it.infraredStatus }.toIntArray(),
                redStatus = batch.map { it.redStatus }.toIntArray(),
                source = DataLayerService.PPG_SOURCE_SAMSUNG_HEALTH_SENSOR,
                recordingMode = recordingMode,
                sleepSessionId = sleepSessionId,
            )
        )
    }

    private fun startAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): android.app.Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, SleepTrackingService::class.java).setAction(ACTION_STOP_ALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val modeText = if (recordingMode == DataLayerService.RECORDING_MODE_SLEEP) {
            "Sleep session ${sleepSessionId?.take(8).orEmpty()}"
        } else {
            "All-day sensor collection"
        }
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle("RecoverySense recording")
            .setContentText("$modeText | PPG: $ppgState")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openIntent)
            .addAction(0, "Stop all", stopIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "RecoverySense sensor recording",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows when RecoverySense is collecting watch sensor data."
            }
        )
    }

    private fun persistActiveState() {
        preferences().edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_RECORDING_MODE, recordingMode)
            .putString(KEY_SLEEP_SESSION_ID, sleepSessionId)
            .apply()
    }

    private fun writeStatus(
        accelerationG: Float? = null,
        gyroMagnitude: Float? = null,
        heartRateAgeMs: Long? = null,
    ) {
        val editor = statusPreferences().edit()
            .putBoolean(STATUS_ACTIVE, tracking)
            .putString(STATUS_MODE, recordingMode)
            .putString(STATUS_SLEEP_SESSION_ID, sleepSessionId)
            .putString(STATUS_WATCH_SESSION_ID, watchSessionId)
            .putInt(STATUS_HEART_RATE, latestHeartRate ?: -1)
            .putLong(STATUS_HEART_RATE_TIMESTAMP, latestHeartRateTimestampMs)
            .putLong(
                STATUS_HEART_RATE_AGE,
                heartRateAgeMs ?: if (latestHeartRateTimestampMs > 0) {
                    (System.currentTimeMillis() - latestHeartRateTimestampMs).coerceAtLeast(0L)
                } else {
                    -1L
                },
            )
            .putFloat(STATUS_STEP_COUNT, latestStepCount)
            .putBoolean(STATUS_SCREEN_INTERACTIVE, powerManager.isInteractive)
            .putString(STATUS_PPG_STATE, ppgState)
            .putBoolean(STATUS_PPG_AVAILABLE, ppgAvailable)
            .putLong(STATUS_UPDATED_AT, System.currentTimeMillis())
        accelerationG?.let { editor.putFloat(STATUS_ACCELERATION_G, it) }
        gyroMagnitude?.let { editor.putFloat(STATUS_GYRO_MAGNITUDE, it) }
        editor.apply()
    }

    private fun preferences() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private fun statusPreferences() = getSharedPreferences(STATUS_PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun onDestroy() {
        if (tracking) stopSensors(flush = true)
        tracking = false
        writeStatus()
        super.onDestroy()
    }

    private data class SensorSample(
        val timestampMs: Long,
        val heartRate: Int,
        val heartRateTimestampMs: Long,
        val heartRateAgeMs: Long,
        val heartRateAccuracy: Int,
        val accelX: Float,
        val accelY: Float,
        val accelZ: Float,
        val accelerationG: Float,
        val accelAccuracy: Int,
        val gyroX: Float,
        val gyroY: Float,
        val gyroZ: Float,
        val gyroMagnitude: Float,
        val gyroTimestampMs: Long,
        val gyroAccuracy: Int,
        val stepCount: Float,
        val stepDetected: Int,
        val offBody: Int,
        val screenInteractive: Int,
    )

    data class TrackingStatusSnapshot(
        val active: Boolean,
        val mode: String,
        val heartRate: Int?,
        val heartRateAgeMs: Long,
        val accelerationG: Float?,
        val gyroMagnitude: Float?,
        val steps: Float?,
        val screenInteractive: Boolean,
        val ppgState: String,
        val ppgAvailable: Boolean,
        val watchSessionId: String?,
        val updatedAtMs: Long,
    )

    companion object {
        const val ACTION_START_CONTINUOUS =
            "com.recoverysense.wear.action.START_CONTINUOUS"
        const val ACTION_START_SLEEP = "com.recoverysense.wear.action.START_SLEEP"
        const val ACTION_STOP_SLEEP = "com.recoverysense.wear.action.STOP_SLEEP"
        const val ACTION_STOP_ALL = "com.recoverysense.wear.action.STOP_ALL"
        const val EXTRA_SLEEP_SESSION_ID = "sleep_session_id"
        const val START_MESSAGE_PATH = "/recoverysense/sleep/start"
        const val STOP_MESSAGE_PATH = "/recoverysense/sleep/stop"
        const val READ_ADDITIONAL_HEALTH_DATA_PERMISSION =
            "com.samsung.android.hardware.sensormanager.permission.READ_ADDITIONAL_HEALTH_DATA"
        const val READ_HEART_RATE_PERMISSION = "android.permission.health.READ_HEART_RATE"

        private const val PREFERENCES_NAME = "recoverysense_sensor_recording"
        private const val STATUS_PREFERENCES_NAME = "recoverysense_sensor_status"
        private const val KEY_ACTIVE = "active"
        private const val KEY_RECORDING_MODE = "recording_mode"
        private const val KEY_SLEEP_SESSION_ID = "sleep_session_id"
        private const val STATUS_ACTIVE = "active"
        private const val STATUS_MODE = "mode"
        private const val STATUS_SLEEP_SESSION_ID = "sleep_session_id"
        private const val STATUS_WATCH_SESSION_ID = "watch_session_id"
        private const val STATUS_HEART_RATE = "heart_rate"
        private const val STATUS_HEART_RATE_TIMESTAMP = "heart_rate_timestamp"
        private const val STATUS_HEART_RATE_AGE = "heart_rate_age_ms"
        private const val STATUS_ACCELERATION_G = "acceleration_g"
        private const val STATUS_GYRO_MAGNITUDE = "gyro_magnitude"
        private const val STATUS_STEP_COUNT = "step_count"
        private const val STATUS_SCREEN_INTERACTIVE = "screen_interactive"
        private const val STATUS_PPG_STATE = "ppg_state"
        private const val STATUS_PPG_AVAILABLE = "ppg_available"
        private const val STATUS_UPDATED_AT = "updated_at"
        private const val NOTIFICATION_CHANNEL_ID = "recoverysense_tracking"
        private const val NOTIFICATION_ID = 2001
        private const val STANDARD_GRAVITY = 9.80665
        private const val SAMPLING_RATE_HZ = 10
        private const val SAMPLE_INTERVAL_MS = 100L
        private const val LIVE_INTERVAL_MS = 1_000L
        private const val BATCH_SAMPLE_COUNT = SAMPLING_RATE_HZ * 30
        private const val HEART_RATE_STALE_AFTER_MS = 90_000L
        private const val PPG_SAMPLING_RATE_HZ = 25
        private const val PPG_BATCH_SAMPLE_COUNT = PPG_SAMPLING_RATE_HZ * 10

        fun isActive(context: Context): Boolean = context
            .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ACTIVE, false)

        fun readStatus(context: Context): TrackingStatusSnapshot {
            val prefs = context.getSharedPreferences(
                STATUS_PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val heartRate = prefs.getInt(STATUS_HEART_RATE, -1).takeIf { it > 0 }
            val acceleration = prefs.getFloat(STATUS_ACCELERATION_G, Float.NaN)
                .takeIf { it.isFinite() }
            val gyro = prefs.getFloat(STATUS_GYRO_MAGNITUDE, Float.NaN)
                .takeIf { it.isFinite() }
            val steps = prefs.getFloat(STATUS_STEP_COUNT, Float.NaN)
                .takeIf { it.isFinite() }
            return TrackingStatusSnapshot(
                active = prefs.getBoolean(STATUS_ACTIVE, false),
                mode = prefs.getString(
                    STATUS_MODE,
                    DataLayerService.RECORDING_MODE_CONTINUOUS,
                ) ?: DataLayerService.RECORDING_MODE_CONTINUOUS,
                heartRate = heartRate,
                heartRateAgeMs = prefs.getLong(STATUS_HEART_RATE_AGE, -1L),
                accelerationG = acceleration,
                gyroMagnitude = gyro,
                steps = steps,
                screenInteractive = prefs.getBoolean(STATUS_SCREEN_INTERACTIVE, true),
                ppgState = prefs.getString(STATUS_PPG_STATE, "not_started")
                    ?: "not_started",
                ppgAvailable = prefs.getBoolean(STATUS_PPG_AVAILABLE, false),
                watchSessionId = prefs.getString(STATUS_WATCH_SESSION_ID, null),
                updatedAtMs = prefs.getLong(STATUS_UPDATED_AT, -1L),
            )
        }

        private fun newWatchSessionId(mode: String, sleepSessionId: String?): String {
            val prefix = if (mode == DataLayerService.RECORDING_MODE_SLEEP) {
                "sleep_${sleepSessionId.orEmpty()}"
            } else {
                "continuous"
            }
            return "${prefix}_${System.currentTimeMillis()}_${UUID.randomUUID()}"
        }
    }
}
