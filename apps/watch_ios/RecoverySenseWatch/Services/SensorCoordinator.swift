import Foundation

struct LiveSensorSnapshot {
  let heartRate: Int?
  let rawHeartRate: Int?
  let heartRateValid: Bool
  let heartRateQualityCode: Int
  let heartRateOutlier: Bool
  let accelerationG: Double
  let gyroMagnitude: Double?
  /// Steps since local midnight.
  let stepCount: Double?
  let recordingMode: String
  let sleepSessionId: String?
}

final class SensorCoordinator {
  var onLiveSnapshot: ((LiveSensorSnapshot) -> Void)?
  var onStatus: ((String) -> Void)?

  private let healthService = HealthSensorService()
  private let motionService = MotionSensorService()
  private let connectivity = WatchConnectivityService.shared
  private let qualityGate = HeartRateQualityGate()
  private let lock = NSLock()

  private var latestHeartRate: HeartRateReading?
  private var latestHeartRateAssessment: HeartRateQualityGate.EventAssessment?
  private var rows: [AlignedSensorRow] = []
  private var sequence: Int64 = 0
  private var capabilities = SensorCapabilities()
  private var screenInteractive = true
  private var sampleCounter = 0

  private(set) var watchSessionId = "watch_\(UUID().uuidString.lowercased())"
  private(set) var recordingMode = "continuous"
  private(set) var sleepSessionId: String?

  func start() {
    qualityGate.reset()
    connectivity.activate()
    connectivity.onStartSleep = { [weak self] sessionID in
      self?.startSleep(sessionID: sessionID)
    }
    connectivity.onStopSleep = { [weak self] in
      self?.stopSleep()
    }
    connectivity.onStatus = { [weak self] text in
      self?.emitStatus(text)
    }

    healthService.onHeartRate = { [weak self] reading in
      guard let self else { return }
      self.lock.lock()
      self.latestHeartRate = reading
      self.latestHeartRateAssessment = self.qualityGate.assessEvent(
        bpm: reading.beatsPerMinute,
        timestampMs: reading.timestampMs
      )
      self.lock.unlock()
    }
    healthService.onAvailabilityChanged = { [weak self] available in
      guard let self else { return }
      self.lock.lock()
      self.capabilities.heartRate = available
      self.lock.unlock()
    }
    healthService.onStatus = { [weak self] text in self?.emitStatus(text) }

    motionService.onCapabilitiesChanged = { [weak self] motionCapabilities in
      guard let self else { return }
      self.lock.lock()
      self.capabilities.accelerometer = motionCapabilities.accelerometer
      self.capabilities.gyroscope = motionCapabilities.gyroscope
      self.capabilities.stepCounter = motionCapabilities.stepCounter
      self.capabilities.stepDetector = motionCapabilities.stepDetector
      self.lock.unlock()
    }
    motionService.onStatus = { [weak self] text in self?.emitStatus(text) }
    motionService.onMotion = { [weak self] reading in
      self?.consume(reading)
    }

    motionService.start()
    healthService.requestAuthorizationAndStart()
  }

  func stop() {
    flushCurrentBatch()
    motionService.stop()
    healthService.stop()
  }

  func setScreenInteractive(_ interactive: Bool) {
    lock.lock()
    screenInteractive = interactive
    lock.unlock()
  }

  func startSleep(sessionID: String) {
    guard !sessionID.isEmpty else { return }
    flushCurrentBatch()
    lock.lock()
    recordingMode = "sleep"
    sleepSessionId = sessionID
    lock.unlock()
    emitStatus("Sleep recording active")
  }

  func stopSleep() {
    flushCurrentBatch()
    lock.lock()
    recordingMode = "continuous"
    sleepSessionId = nil
    lock.unlock()
    emitStatus("Continuous recording active")
  }

  func submitEMA(
    score: Int,
    openedAtMs: Int64,
    source: String = "watch_manual",
    promptedAtMs: Int64? = nil
  ) {
    let submittedAt = currentTimeMilliseconds()
    let payload = WatchEMAPayload(
      eventId: "watch_\(submittedAt)_\(UUID().uuidString.lowercased())",
      cravingScore: score,
      openedAtMs: openedAtMs,
      submittedAtMs: submittedAt,
      watchSessionId: watchSessionId,
      source: source,
      promptedAtMs: promptedAtMs
    )
    connectivity.enqueueEMA(payload)
  }

  private func consume(_ motion: MotionReading) {
    let row: AlignedSensorRow
    let live: LiveSensorSnapshot
    let shouldFlush: Bool
    let shouldSendLive: Bool
    let currentCapabilities: SensorCapabilities
    let currentMode: String
    let currentSleepID: String?

    lock.lock()
    let heart = latestHeartRate
    let sampleAssessment = qualityGate.assessSample(
      event: latestHeartRateAssessment,
      eventTimestampMs: heart?.timestampMs ?? -1,
      sampleTimestampMs: motion.timestampMs
    )
    let heartAge = heart.map { max(0, motion.timestampMs - $0.timestampMs) } ?? -1
    currentMode = recordingMode
    currentSleepID = sleepSessionId
    let interactive = screenInteractive
    currentCapabilities = capabilities

    row = AlignedSensorRow(
      timestampMs: motion.timestampMs,
      heartRate: sampleAssessment.analysisBpm ?? -1,
      rawHeartRate: sampleAssessment.rawBpm ?? -1,
      heartRateTimestampMs: heart?.timestampMs ?? -1,
      heartRateAgeMs: heartAge,
      // HealthKit does not expose Android-style per-sample sensor accuracy.
      heartRateAccuracy: 0,
      heartRateValid: sampleAssessment.valid ? 1 : 0,
      heartRateQualityCode: sampleAssessment.qualityCode,
      heartRateOutlier: sampleAssessment.temporalOutlier ? 1 : 0,
      accelX: motion.accelXMS2,
      accelY: motion.accelYMS2,
      accelZ: motion.accelZMS2,
      accelerationG: motion.accelerationG,
      accelAccuracy: 0,
      gyroX: motion.gyroXRadS ?? RecoverySenseWireValue.unavailableDouble,
      gyroY: motion.gyroYRadS ?? RecoverySenseWireValue.unavailableDouble,
      gyroZ: motion.gyroZRadS ?? RecoverySenseWireValue.unavailableDouble,
      gyroMagnitude: motion.gyroMagnitudeRadS ?? RecoverySenseWireValue.unavailableDouble,
      gyroTimestampMs: motion.gyroTimestampMs ?? -1,
      gyroAccuracy: 0,
      stepCount: motion.stepCount ?? RecoverySenseWireValue.unavailableDouble,
      stepDetected: motion.stepDetected,
      offBody: -1,
      screenInteractive: interactive ? 1 : 0
    )
    rows.append(row)
    sampleCounter += 1
    shouldFlush = rows.count >= SensorBatchPayload.nominalSamplingRateHz * 30
    shouldSendLive = sampleCounter % SensorBatchPayload.nominalSamplingRateHz == 0
    live = LiveSensorSnapshot(
      heartRate: sampleAssessment.analysisBpm,
      rawHeartRate: sampleAssessment.rawBpm,
      heartRateValid: sampleAssessment.valid,
      heartRateQualityCode: sampleAssessment.qualityCode,
      heartRateOutlier: sampleAssessment.temporalOutlier,
      accelerationG: motion.accelerationG,
      gyroMagnitude: motion.gyroMagnitudeRadS,
      stepCount: motion.stepCount,
      recordingMode: currentMode,
      sleepSessionId: currentSleepID
    )
    lock.unlock()

    if shouldSendLive {
      sendLive(
        row: row,
        capabilities: currentCapabilities,
        mode: currentMode,
        sleepID: currentSleepID
      )
      DispatchQueue.main.async { [weak self] in self?.onLiveSnapshot?(live) }
    }
    if shouldFlush { flushCurrentBatch() }
  }

  private func sendLive(
    row: AlignedSensorRow,
    capabilities: SensorCapabilities,
    mode: String,
    sleepID: String?
  ) {
    var payload: [String: Any] = [
      "schemaVersion": SensorBatchPayload.schemaVersion,
      "heartRate": row.heartRate,
      "rawHeartRate": row.rawHeartRate,
      "heartRateAgeMs": row.heartRateAgeMs,
      "heartRateValid": row.heartRateValid == 1,
      "heartRateQualityCode": row.heartRateQualityCode,
      "heartRateQualityReason": HeartRateQuality.reason(row.heartRateQualityCode),
      "heartRateOutlier": row.heartRateOutlier == 1,
      "accelX": row.accelX,
      "accelY": row.accelY,
      "accelZ": row.accelZ,
      "accelerationG": row.accelerationG,
      "gyroX": row.gyroX,
      "gyroY": row.gyroY,
      "gyroZ": row.gyroZ,
      "gyroMagnitude": row.gyroMagnitude,
      "stepCount": row.stepCount,
      "offBody": -1,
      "screenInteractive": row.screenInteractive == 1,
      "ppgState": SensorBatchPayload.disabledPPGState,
      "timestamp": row.timestampMs,
      "recordingMode": mode,
      "heartRateAvailable": capabilities.heartRate,
      "accelerometerAvailable": capabilities.accelerometer,
      "gyroscopeAvailable": capabilities.gyroscope,
      "stepCounterAvailable": capabilities.stepCounter,
      "stepDetectorAvailable": capabilities.stepDetector,
      "offBodyAvailable": capabilities.offBody,
      "ppgAvailable": capabilities.rawPPG,
      "stepCountSemantics": "local_day_since_midnight"
    ]
    if let sleepID { payload["sleepSessionId"] = sleepID }
    connectivity.sendLive(payload)
  }

  private func flushCurrentBatch() {
    let payload: SensorBatchPayload?

    lock.lock()
    if rows.isEmpty {
      payload = nil
    } else {
      let createdAt = currentTimeMilliseconds()
      let batchRows = rows
      rows.removeAll(keepingCapacity: true)
      sequence += 1
      let batchID = "ios_\(watchSessionId)_\(sequence)_\(createdAt)"
      payload = SensorBatchPayload(
        batchId: batchID,
        watchSessionId: watchSessionId,
        sequence: sequence,
        recordingMode: recordingMode,
        sleepSessionId: sleepSessionId,
        createdAtMs: createdAt,
        rows: batchRows,
        capabilities: capabilities
      )
    }
    lock.unlock()

    if let payload {
      connectivity.enqueueSensorBatch(payload)
      emitStatus("Queued batch \(payload.sequence)")
    }
  }

  private func emitStatus(_ text: String) {
    DispatchQueue.main.async { [weak self] in self?.onStatus?(text) }
  }
}
