package com.recoverysense.wear.sensors

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartRateQualityGateTest {
    @Test
    fun noContactIsRejectedButRawBpmIsPreserved() {
        val gate = HeartRateQualityGate()
        val event = gate.assessEvent(
            bpm = 88f,
            timestampMs = 1_000L,
            accuracy = HeartRateQualityGate.SENSOR_STATUS_NO_CONTACT,
        )
        val sample = gate.assessSample(event, 1_000L, 1_500L, offBody = false)

        assertFalse(sample.valid)
        assertNull(sample.analysisBpm)
        assertEquals(88, sample.rawBpm)
        assertEquals(HeartRateQualityGate.QUALITY_NO_CONTACT, sample.qualityCode)
    }

    @Test
    fun offBodyOverridesOtherwiseValidHeartRate() {
        val gate = HeartRateQualityGate()
        val event = gate.assessEvent(72f, 1_000L, accuracy = 3)
        val sample = gate.assessSample(event, 1_000L, 2_000L, offBody = true)

        assertFalse(sample.valid)
        assertNull(sample.analysisBpm)
        assertEquals(72, sample.rawBpm)
        assertEquals(HeartRateQualityGate.QUALITY_OFF_BODY, sample.qualityCode)
    }

    @Test
    fun staleHeartRateIsRejected() {
        val gate = HeartRateQualityGate()
        val event = gate.assessEvent(70f, 1_000L, accuracy = 3)
        val sample = gate.assessSample(event, 1_000L, 100_001L, offBody = false)
        assertFalse(sample.valid)
        assertEquals(HeartRateQualityGate.QUALITY_STALE, sample.qualityCode)
    }

    @Test
    fun temporalSpikeIsFlaggedButNotAutomaticallyDiscarded() {
        val gate = HeartRateQualityGate()
        listOf(70f, 71f, 70f, 72f, 71f).forEachIndexed { index, bpm ->
            gate.assessEvent(bpm, index * 1_000L, accuracy = 3)
        }
        val spike = gate.assessEvent(160f, 6_000L, accuracy = 3)
        val sample = gate.assessSample(spike, 6_000L, 6_500L, offBody = false)

        assertTrue(spike.temporalOutlier)
        assertTrue(sample.temporalOutlier)
        assertTrue(sample.valid)
        assertEquals(160, sample.analysisBpm)
    }
    @Test
    fun sustainedShiftUpdatesOutlierReference() {
        val gate = HeartRateQualityGate()
        repeat(6) { index ->
            gate.assessEvent(70f, 1_000L + index * 1_000L, 3)
        }
        val firstShift = gate.assessEvent(120f, 8_000L, 3)
        assertTrue(firstShift.temporalOutlier)

        // The outlier flag is informational; accepted readings continue to
        // update the rolling reference so a sustained real HR transition can
        // stop looking anomalous instead of remaining frozen for 60 seconds.
        var latest = firstShift
        repeat(6) { index ->
            latest = gate.assessEvent(120f, 9_000L + index * 1_000L, 3)
        }
        assertFalse(latest.temporalOutlier)
    }


    @Test
    fun resetClearsTemporalHistory() {
        val gate = HeartRateQualityGate()
        repeat(6) { index -> gate.assessEvent(70f, index * 1_000L, 3) }
        assertTrue(gate.assessEvent(150f, 7_000L, 3).temporalOutlier)
        gate.reset()
        assertFalse(gate.assessEvent(150f, 8_000L, 3).temporalOutlier)
    }

}
