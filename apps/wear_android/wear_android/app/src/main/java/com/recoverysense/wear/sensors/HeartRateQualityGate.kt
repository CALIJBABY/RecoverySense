package com.recoverysense.wear.sensors

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.max

/**
 * Conservative heart-rate quality gate used before BPM values become
 * analysis-ready RecoverySense samples.
 *
 * Raw BPM is preserved separately. Hard rejection is limited to strong sensor
 * evidence (no contact / unreliable), explicit off-body state, stale values,
 * and a deliberately broad physiological plausibility boundary. A robust
 * rolling-median/MAD rule only *flags* temporal outliers; it does not discard
 * them because rapid legitimate changes can occur during activity.
 */
class HeartRateQualityGate(
    private val minimumBpm: Int = 30,
    private val maximumBpm: Int = 220,
    private val staleAfterMs: Long = 90_000L,
    private val outlierWindowMs: Long = 60_000L,
    private val outlierMinimumHistory: Int = 5,
    private val outlierAbsoluteFloorBpm: Double = 30.0,
    private val outlierMadMultiplier: Double = 5.0,
) {
    data class EventAssessment(
        val rawBpm: Int?,
        val sensorValid: Boolean,
        val qualityCode: Int,
        val temporalOutlier: Boolean,
    )

    data class SampleAssessment(
        val rawBpm: Int?,
        val analysisBpm: Int?,
        val valid: Boolean,
        val qualityCode: Int,
        val temporalOutlier: Boolean,
    )

    private data class AcceptedEvent(val timestampMs: Long, val bpm: Int)

    private val acceptedHistory = ArrayDeque<AcceptedEvent>()

    fun assessEvent(
        bpm: Float,
        timestampMs: Long,
        accuracy: Int,
    ): EventAssessment {
        val rawBpm = bpm.takeIf { it.isFinite() && it > 0f }?.toInt()
        val hardCode = when {
            accuracy == SENSOR_STATUS_NO_CONTACT -> QUALITY_NO_CONTACT
            accuracy == SENSOR_STATUS_UNRELIABLE -> QUALITY_UNRELIABLE
            rawBpm == null -> QUALITY_NO_READING
            rawBpm !in minimumBpm..maximumBpm -> QUALITY_IMPLAUSIBLE
            accuracy == SENSOR_STATUS_ACCURACY_LOW -> QUALITY_LOW_ACCURACY
            else -> QUALITY_VALID
        }
        val sensorValid = hardCode == QUALITY_VALID || hardCode == QUALITY_LOW_ACCURACY
        val temporalOutlier = if (sensorValid && rawBpm != null) {
            isTemporalOutlier(rawBpm, timestampMs)
        } else {
            false
        }

        if (sensorValid && rawBpm != null) {
            // Keep the flag informational: legitimate sustained HR changes (for
            // example, exercise) must be allowed to move the rolling reference
            // rather than being treated as outliers for the entire window.
            pruneHistory(timestampMs)
            acceptedHistory.addLast(AcceptedEvent(timestampMs, rawBpm))
        }

        return EventAssessment(
            rawBpm = rawBpm,
            sensorValid = sensorValid,
            qualityCode = hardCode,
            temporalOutlier = temporalOutlier,
        )
    }

    fun assessSample(
        event: EventAssessment?,
        eventTimestampMs: Long,
        sampleTimestampMs: Long,
        offBody: Boolean?,
    ): SampleAssessment {
        val ageMs = if (eventTimestampMs > 0L) {
            (sampleTimestampMs - eventTimestampMs).coerceAtLeast(0L)
        } else {
            -1L
        }
        val finalCode = when {
            event == null || event.rawBpm == null -> QUALITY_NO_READING
            offBody == true -> QUALITY_OFF_BODY
            ageMs < 0L || ageMs > staleAfterMs -> QUALITY_STALE
            !event.sensorValid -> event.qualityCode
            else -> event.qualityCode
        }
        val valid = event?.rawBpm != null &&
            offBody != true &&
            ageMs in 0..staleAfterMs &&
            event.sensorValid
        return SampleAssessment(
            rawBpm = event?.rawBpm,
            analysisBpm = event?.rawBpm?.takeIf { valid },
            valid = valid,
            qualityCode = finalCode,
            temporalOutlier = event?.temporalOutlier ?: false,
        )
    }

    fun reset() {
        acceptedHistory.clear()
    }

    private fun isTemporalOutlier(bpm: Int, timestampMs: Long): Boolean {
        pruneHistory(timestampMs)
        if (acceptedHistory.size < outlierMinimumHistory) return false
        val values = acceptedHistory.map { it.bpm.toDouble() }.sorted()
        val median = median(values)
        val deviations = values.map { abs(it - median) }.sorted()
        val mad = median(deviations)
        val threshold = max(outlierAbsoluteFloorBpm, outlierMadMultiplier * max(mad, 1.0))
        return abs(bpm - median) > threshold
    }

    private fun pruneHistory(nowMs: Long) {
        while (acceptedHistory.isNotEmpty() &&
            nowMs - acceptedHistory.first().timestampMs > outlierWindowMs
        ) {
            acceptedHistory.removeFirst()
        }
    }

    private fun median(sorted: List<Double>): Double {
        if (sorted.isEmpty()) return 0.0
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[middle - 1] + sorted[middle]) / 2.0
        } else {
            sorted[middle]
        }
    }

    companion object {
        // Android SensorManager status integer values. Kept here so this gate is
        // a pure Kotlin component that can be unit-tested without Android APIs.
        const val SENSOR_STATUS_NO_CONTACT = -1
        const val SENSOR_STATUS_UNRELIABLE = 0
        const val SENSOR_STATUS_ACCURACY_LOW = 1

        const val QUALITY_VALID = 0
        const val QUALITY_NO_READING = 1
        const val QUALITY_STALE = 2
        const val QUALITY_OFF_BODY = 3
        const val QUALITY_NO_CONTACT = 4
        const val QUALITY_UNRELIABLE = 5
        const val QUALITY_IMPLAUSIBLE = 6
        const val QUALITY_LOW_ACCURACY = 7

        fun qualityReason(code: Int): String = when (code) {
            QUALITY_VALID -> "valid"
            QUALITY_NO_READING -> "no_reading"
            QUALITY_STALE -> "stale"
            QUALITY_OFF_BODY -> "off_body"
            QUALITY_NO_CONTACT -> "no_contact"
            QUALITY_UNRELIABLE -> "unreliable"
            QUALITY_IMPLAUSIBLE -> "implausible"
            QUALITY_LOW_ACCURACY -> "low_accuracy"
            else -> "unknown"
        }
    }
}
