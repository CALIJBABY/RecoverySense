package com.recoverysense.wear.ppg

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Reflection-backed Samsung Health Sensor SDK adapter.
 *
 * This intentionally has no compile-time Samsung imports. The project builds
 * without the proprietary/downloaded AAR. If the AAR is present in app/libs,
 * Gradle includes it and this adapter connects to Health Platform at runtime.
 */
class SamsungHealthSensorPpgCollector(
    private val context: Context,
    private val onSamples: (List<RawPpgSample>) -> Unit,
    private val onStateChanged: (String, Boolean) -> Unit,
) : PpgCollector {
    @Volatile
    private var currentState = STATE_NOT_STARTED
    @Volatile
    private var available = false
    private val started = AtomicBoolean(false)
    private val flushHandler = Handler(Looper.getMainLooper())
    private val flushRunnable = object : Runnable {
        override fun run() {
            flushBufferedData()
            if (started.get()) flushHandler.postDelayed(this, FLUSH_INTERVAL_MS)
        }
    }

    private var trackingService: Any? = null
    private var tracker: Any? = null
    private var trackerListener: Any? = null

    override val state: String
        get() = currentState

    override val isAvailable: Boolean
        get() = available

    override fun start() {
        if (!started.compareAndSet(false, true)) return
        try {
            val connectionClass = Class.forName(CONNECTION_LISTENER_CLASS)
            val serviceClass = Class.forName(HEALTH_TRACKING_SERVICE_CLASS)
            val connectionListener = Proxy.newProxyInstance(
                connectionClass.classLoader,
                arrayOf(connectionClass),
            ) { _, method, args ->
                when (method.name) {
                    "onConnectionSuccess" -> connectPpgTracker()
                    "onConnectionEnded" -> updateState(STATE_CONNECTION_ENDED, false)
                    "onConnectionFailed" -> {
                        val detail = args?.firstOrNull()?.toString().orEmpty()
                        updateState("connection_failed:$detail", false)
                    }
                }
                null
            }
            val constructor = serviceClass.getConstructor(connectionClass, Context::class.java)
            trackingService = constructor.newInstance(connectionListener, context)
            updateState(STATE_CONNECTING, false)
            serviceClass.getMethod("connectService").invoke(trackingService)
        } catch (missing: ClassNotFoundException) {
            started.set(false)
            updateState(STATE_AAR_MISSING, false)
        } catch (error: Throwable) {
            started.set(false)
            updateState("startup_error:${rootMessage(error)}", false)
            Log.e(TAG, "Unable to start Samsung raw PPG collector", error)
        }
    }

    private fun connectPpgTracker() {
        try {
            val service = trackingService ?: return
            val serviceClass = service.javaClass
            val trackerTypeClass = Class.forName(HEALTH_TRACKER_TYPE_CLASS)
            val ppgTypeClass = Class.forName(PPG_TYPE_CLASS)
            val trackerType = enumConstant(trackerTypeClass, "PPG_CONTINUOUS")

            val capability = serviceClass.getMethod("getTrackingCapability").invoke(service)
            val supported = capability.javaClass
                .getMethod("getSupportHealthTrackerTypes")
                .invoke(capability) as? Collection<*>
            if (supported == null || !supported.contains(trackerType)) {
                updateState(STATE_UNSUPPORTED, false)
                return
            }

            val ppgTypes = linkedSetOf(
                enumConstant(ppgTypeClass, "GREEN"),
                enumConstant(ppgTypeClass, "IR"),
                enumConstant(ppgTypeClass, "RED"),
            )
            val getTrackerMethods = serviceClass.methods.filter { it.name == "getHealthTracker" }
            val twoArgument = getTrackerMethods.firstOrNull {
                it.parameterTypes.size == 2 &&
                    Set::class.java.isAssignableFrom(it.parameterTypes[1])
            }
            tracker = if (twoArgument != null) {
                twoArgument.invoke(service, trackerType, ppgTypes)
            } else {
                getTrackerMethods.first { it.parameterTypes.size == 1 }
                    .invoke(service, trackerType)
            }

            val listenerClass = Class.forName(TRACKER_LISTENER_CLASS)
            trackerListener = Proxy.newProxyInstance(
                listenerClass.classLoader,
                arrayOf(listenerClass),
            ) { _, method, args ->
                when (method.name) {
                    "onDataReceived" -> receiveDataPoints(args?.firstOrNull())
                    "onFlushCompleted" -> updateState(STATE_TRACKING, true)
                    "onError" -> {
                        val detail = args?.firstOrNull()?.toString().orEmpty()
                        updateState("tracker_error:$detail", false)
                    }
                }
                null
            }
            tracker?.javaClass
                ?.methods
                ?.first { it.name == "setEventListener" && it.parameterTypes.size == 1 }
                ?.invoke(tracker, trackerListener)
            updateState(STATE_TRACKING, true)
            flushHandler.removeCallbacks(flushRunnable)
            flushHandler.postDelayed(flushRunnable, FLUSH_INTERVAL_MS)
        } catch (error: Throwable) {
            updateState("tracker_start_error:${rootMessage(error)}", false)
            Log.e(TAG, "Unable to activate Samsung PPG_CONTINUOUS", error)
        }
    }

    private fun receiveDataPoints(payload: Any?) {
        val points = payload as? List<*> ?: return
        if (points.isEmpty()) return
        try {
            val ppgSetClass = Class.forName(PPG_SET_CLASS)
            val greenKey = ppgSetClass.getField("PPG_GREEN").get(null)
            val irKey = ppgSetClass.getField("PPG_IR").get(null)
            val redKey = ppgSetClass.getField("PPG_RED").get(null)
            val greenStatusKey = ppgSetClass.getField("GREEN_STATUS").get(null)
            val irStatusKey = ppgSetClass.getField("IR_STATUS").get(null)
            val redStatusKey = ppgSetClass.getField("RED_STATUS").get(null)

            val samples = points.mapNotNull { point ->
                point ?: return@mapNotNull null
                val pointClass = point.javaClass
                val timestamp = pointClass.getMethod("getTimestamp").invoke(point) as? Number
                    ?: return@mapNotNull null
                val getValue = pointClass.methods.first {
                    it.name == "getValue" && it.parameterTypes.size == 1
                }
                RawPpgSample(
                    timestampMs = timestamp.toLong(),
                    green = intValue(getValue, point, greenKey),
                    infrared = intValue(getValue, point, irKey),
                    red = intValue(getValue, point, redKey),
                    greenStatus = intValue(getValue, point, greenStatusKey),
                    infraredStatus = intValue(getValue, point, irStatusKey),
                    redStatus = intValue(getValue, point, redStatusKey),
                )
            }
            if (samples.isNotEmpty()) {
                updateState(STATE_TRACKING, true)
                onSamples(samples)
            }
        } catch (error: Throwable) {
            updateState("data_parse_error:${rootMessage(error)}", false)
            Log.e(TAG, "Unable to parse Samsung PPG data points", error)
        }
    }

    private fun intValue(method: Method, point: Any, key: Any): Int {
        return (method.invoke(point, key) as? Number)?.toInt() ?: Int.MIN_VALUE
    }

    private fun flushBufferedData() {
        try {
            tracker?.javaClass?.methods
                ?.firstOrNull { it.name == "flush" && it.parameterTypes.isEmpty() }
                ?.invoke(tracker)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to flush Samsung PPG data", error)
        }
    }

    override fun stop() {
        if (!started.getAndSet(false)) return
        flushHandler.removeCallbacks(flushRunnable)
        try {
            tracker?.javaClass?.methods
                ?.firstOrNull { it.name == "unsetEventListener" && it.parameterTypes.isEmpty() }
                ?.invoke(tracker)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to unset Samsung PPG listener", error)
        }
        try {
            trackingService?.javaClass?.getMethod("disconnectService")?.invoke(trackingService)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to disconnect Samsung Health Sensor service", error)
        }
        tracker = null
        trackerListener = null
        trackingService = null
        updateState(STATE_STOPPED, false)
    }

    private fun updateState(newState: String, isAvailable: Boolean) {
        currentState = newState
        available = isAvailable
        onStateChanged(newState, isAvailable)
    }

    private fun enumConstant(enumClass: Class<*>, name: String): Any {
        return enumClass.enumConstants.first { (it as Enum<*>).name == name }
    }

    private fun rootMessage(error: Throwable): String {
        var current = error
        while (current.cause != null) current = current.cause!!
        return current.message?.replace(':', '_') ?: current.javaClass.simpleName
    }

    private companion object {
        const val TAG = "RecoverySensePPG"
        const val CONNECTION_LISTENER_CLASS =
            "com.samsung.android.service.health.tracking.ConnectionListener"
        const val HEALTH_TRACKING_SERVICE_CLASS =
            "com.samsung.android.service.health.tracking.HealthTrackingService"
        const val TRACKER_LISTENER_CLASS =
            "com.samsung.android.service.health.tracking.HealthTracker\u0024TrackerEventListener"
        const val HEALTH_TRACKER_TYPE_CLASS =
            "com.samsung.android.service.health.tracking.data.HealthTrackerType"
        const val PPG_TYPE_CLASS =
            "com.samsung.android.service.health.tracking.data.PpgType"
        const val PPG_SET_CLASS =
            "com.samsung.android.service.health.tracking.data.ValueKey\u0024PpgSet"

        const val STATE_NOT_STARTED = "not_started"
        const val STATE_CONNECTING = "connecting"
        const val STATE_TRACKING = "tracking"
        const val STATE_CONNECTION_ENDED = "connection_ended"
        const val STATE_UNSUPPORTED = "ppg_continuous_unsupported"
        const val STATE_AAR_MISSING = "sdk_aar_missing"
        const val STATE_STOPPED = "stopped"
        const val FLUSH_INTERVAL_MS = 60_000L
    }
}
