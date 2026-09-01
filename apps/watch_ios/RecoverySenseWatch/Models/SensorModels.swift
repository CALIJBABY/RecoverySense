import Foundation

struct HeartRateReading {
  let beatsPerMinute: Int
  let timestampMs: Int64
}

enum HeartRateQuality {
  static let valid = 0
  static let noReading = 1
  static let stale = 2
  static let offBody = 3
  static let noContact = 4
  static let unreliable = 5
  static let implausible = 6
  static let lowAccuracy = 7

  static func reason(_ code: Int) -> String {
    switch code {
    case valid: return "valid"
    case noReading: return "no_reading"
    case stale: return "stale"
    case offBody: return "off_body"
    case noContact: return "no_contact"
    case unreliable: return "unreliable"
    case implausible: return "implausible"
    case lowAccuracy: return "low_accuracy"
    default: return "unknown"
    }
  }
}

/// Conservative quality layer matching the schema-5 Android contract.
///
/// HealthKit does not expose Android-style contact/accuracy status for every
/// sample, so iOS only hard-rejects missing, stale, and broadly implausible BPM.
/// A rolling median/MAD rule marks temporal outliers without discarding them.
final class HeartRateQualityGate {
  struct EventAssessment {
    let rawBpm: Int?
    let sensorValid: Bool
    let qualityCode: Int
    let temporalOutlier: Bool
  }

  struct SampleAssessment {
    let rawBpm: Int?
    let analysisBpm: Int?
    let valid: Bool
    let qualityCode: Int
    let temporalOutlier: Bool
  }

  private struct AcceptedEvent {
    let timestampMs: Int64
    let bpm: Int
  }

  private let minimumBpm = 30
  private let maximumBpm = 220
  private let staleAfterMs: Int64 = 90_000
  private let outlierWindowMs: Int64 = 60_000
  private let outlierMinimumHistory = 5
  private let outlierAbsoluteFloorBpm = 30.0
  private let outlierMadMultiplier = 5.0
  private var acceptedHistory: [AcceptedEvent] = []

  func assessEvent(bpm: Int, timestampMs: Int64) -> EventAssessment {
    let rawBpm = bpm > 0 ? bpm : nil
    let qualityCode: Int
    if rawBpm == nil {
      qualityCode = HeartRateQuality.noReading
    } else if !(minimumBpm...maximumBpm).contains(bpm) {
      qualityCode = HeartRateQuality.implausible
    } else {
      qualityCode = HeartRateQuality.valid
    }

    let sensorValid = qualityCode == HeartRateQuality.valid
    let temporalOutlier = sensorValid ? isTemporalOutlier(bpm, timestampMs: timestampMs) : false

    if sensorValid {
      pruneHistory(nowMs: timestampMs)
      acceptedHistory.append(AcceptedEvent(timestampMs: timestampMs, bpm: bpm))
    }

    return EventAssessment(
      rawBpm: rawBpm,
      sensorValid: sensorValid,
      qualityCode: qualityCode,
      temporalOutlier: temporalOutlier
    )
  }

  func assessSample(
    event: EventAssessment?,
    eventTimestampMs: Int64,
    sampleTimestampMs: Int64
  ) -> SampleAssessment {
    let ageMs = eventTimestampMs > 0 ? max(0, sampleTimestampMs - eventTimestampMs) : -1
    let qualityCode: Int
    if event == nil || event?.rawBpm == nil {
      qualityCode = HeartRateQuality.noReading
    } else if ageMs < 0 || ageMs > staleAfterMs {
      qualityCode = HeartRateQuality.stale
    } else {
      qualityCode = event?.qualityCode ?? HeartRateQuality.noReading
    }

    let valid = event?.rawBpm != nil &&
      ageMs >= 0 && ageMs <= staleAfterMs &&
      event?.sensorValid == true

    return SampleAssessment(
      rawBpm: event?.rawBpm,
      analysisBpm: valid ? event?.rawBpm : nil,
      valid: valid,
      qualityCode: qualityCode,
      temporalOutlier: event?.temporalOutlier ?? false
    )
  }

  func reset() {
    acceptedHistory.removeAll(keepingCapacity: false)
  }

  private func isTemporalOutlier(_ bpm: Int, timestampMs: Int64) -> Bool {
    pruneHistory(nowMs: timestampMs)
    guard acceptedHistory.count >= outlierMinimumHistory else { return false }
    let values = acceptedHistory.map { Double($0.bpm) }.sorted()
    let center = median(values)
    let deviations = values.map { abs($0 - center) }.sorted()
    let mad = median(deviations)
    let threshold = max(outlierAbsoluteFloorBpm, outlierMadMultiplier * max(mad, 1.0))
    return abs(Double(bpm) - center) > threshold
  }

  private func pruneHistory(nowMs: Int64) {
    acceptedHistory.removeAll { nowMs - $0.timestampMs > outlierWindowMs }
  }

  private func median(_ sorted: [Double]) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2.0
    }
    return sorted[middle]
  }
}

struct MotionReading {
  let timestampMs: Int64
  let accelXMS2: Double
  let accelYMS2: Double
  let accelZMS2: Double
  let accelerationG: Double
  let gyroXRadS: Double?
  let gyroYRadS: Double?
  let gyroZRadS: Double?
  let gyroMagnitudeRadS: Double?
  let gyroTimestampMs: Int64?
  /// Apple equivalent of Steps Today, counted from local midnight.
  let stepCount: Double?
  let stepDetected: Int
}

struct SensorCapabilities {
  var heartRate = false
  var accelerometer = false
  var gyroscope = false
  var stepCounter = false
  var stepDetector = false

  // Apple does not expose a direct third-party off-body stream or raw optical
  // PPG samples through the public APIs used by this project.
  let offBody = false
  let rawPPG = false
}

struct AlignedSensorRow {
  let timestampMs: Int64
  let heartRate: Int
  let rawHeartRate: Int
  let heartRateTimestampMs: Int64
  let heartRateAgeMs: Int64
  let heartRateAccuracy: Int
  let heartRateValid: Int
  let heartRateQualityCode: Int
  let heartRateOutlier: Int
  let accelX: Double
  let accelY: Double
  let accelZ: Double
  let accelerationG: Double
  let accelAccuracy: Int
  let gyroX: Any
  let gyroY: Any
  let gyroZ: Any
  let gyroMagnitude: Any
  let gyroTimestampMs: Int64
  let gyroAccuracy: Int
  let stepCount: Any
  let stepDetected: Int
  let offBody: Int
  let screenInteractive: Int
}

struct SensorBatchPayload {
  static let schemaVersion = 5
  static let nominalSamplingRateHz = 10
  static let disabledPPGState = "disabled_public_api_no_raw_ppg"

  let batchId: String
  let watchSessionId: String
  let sequence: Int64
  let recordingMode: String
  let sleepSessionId: String?
  let createdAtMs: Int64
  let rows: [AlignedSensorRow]
  let capabilities: SensorCapabilities

  var uri: String { "ios://sensor_batch/\(batchId)" }

  var dictionary: [String: Any] {
    var payload: [String: Any] = [
      "uri": uri,
      "batchId": batchId,
      "watchSessionId": watchSessionId,
      "sequence": sequence,
      "samplingRateHz": Self.nominalSamplingRateHz,
      "schemaVersion": Self.schemaVersion,
      "recordingMode": recordingMode,
      "createdAt": createdAtMs,
      "timestamps": rows.map(\.timestampMs),
      "heartRates": rows.map(\.heartRate),
      "rawHeartRates": rows.map(\.rawHeartRate),
      "heartRateTimestamps": rows.map(\.heartRateTimestampMs),
      "heartRateAgeMs": rows.map(\.heartRateAgeMs),
      "heartRateAccuracy": rows.map(\.heartRateAccuracy),
      "heartRateValid": rows.map(\.heartRateValid),
      "heartRateQualityCodes": rows.map(\.heartRateQualityCode),
      "heartRateOutlier": rows.map(\.heartRateOutlier),
      "accelX": rows.map(\.accelX),
      "accelY": rows.map(\.accelY),
      "accelZ": rows.map(\.accelZ),
      "accelerationG": rows.map(\.accelerationG),
      "accelAccuracy": rows.map(\.accelAccuracy),
      "gyroX": rows.map(\.gyroX),
      "gyroY": rows.map(\.gyroY),
      "gyroZ": rows.map(\.gyroZ),
      "gyroMagnitude": rows.map(\.gyroMagnitude),
      "gyroTimestamps": rows.map(\.gyroTimestampMs),
      "gyroAccuracy": rows.map(\.gyroAccuracy),
      "stepCounts": rows.map(\.stepCount),
      "stepDetected": rows.map(\.stepDetected),
      "offBody": rows.map(\.offBody),
      "screenInteractive": rows.map(\.screenInteractive),
      "heartRateAvailable": capabilities.heartRate,
      "accelerometerAvailable": capabilities.accelerometer,
      "gyroscopeAvailable": capabilities.gyroscope,
      "stepCounterAvailable": capabilities.stepCounter,
      "stepDetectorAvailable": capabilities.stepDetector,
      "offBodyAvailable": capabilities.offBody,
      "ppgAvailable": capabilities.rawPPG,
      "ppgState": Self.disabledPPGState,
      "heartRateQualitySemanticsVersion": 1,
      "stepCountSemantics": "local_day_since_midnight"
    ]
    if let sleepSessionId { payload["sleepSessionId"] = sleepSessionId }
    return payload
  }
}

struct WatchEMAPayload {
  let eventId: String
  let cravingScore: Int
  let openedAtMs: Int64
  let submittedAtMs: Int64
  let watchSessionId: String?
  let source: String
  let promptedAtMs: Int64?

  var uri: String { "ios://ema_event/\(eventId)" }

  var dictionary: [String: Any] {
    let submittedDate = Date(timeIntervalSince1970: Double(submittedAtMs) / 1_000.0)
    let components = Calendar.autoupdatingCurrent.dateComponents(
      [.hour, .minute],
      from: submittedDate
    )
    let localMinuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    let timezoneOffsetMinutes = TimeZone.autoupdatingCurrent.secondsFromGMT(
      for: submittedDate
    ) / 60

    var payload: [String: Any] = [
      "uri": uri,
      "eventId": eventId,
      "cravingScore": max(0, min(10, cravingScore)),
      "timestampMs": submittedAtMs,
      "openedAtMs": openedAtMs,
      "submittedAtMs": submittedAtMs,
      "source": source,
      "localMinuteOfDay": localMinuteOfDay,
      "timezoneOffsetMinutes": timezoneOffsetMinutes,
      "schemaVersion": 2,
      "createdAt": submittedAtMs
    ]
    if let watchSessionId { payload["watchSessionId"] = watchSessionId }
    if let promptedAtMs { payload["promptedAtMs"] = promptedAtMs }
    return payload
  }
}

enum RecoverySenseWireValue {
  /// JSON- and property-list-safe representation parsed by Dart as double.nan.
  static let unavailableDouble: Any = "NaN"
}

func currentTimeMilliseconds() -> Int64 {
  Int64((Date().timeIntervalSince1970 * 1_000.0).rounded())
}
