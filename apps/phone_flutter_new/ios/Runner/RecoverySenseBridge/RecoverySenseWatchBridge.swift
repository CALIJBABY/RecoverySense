import Flutter
import Foundation
import WatchConnectivity

private enum RecoverySenseChannel {
  static let live = "recoverysense/live_sensors"
  static let batches = "recoverysense/sensor_batches"
  static let ppgBatches = "recoverysense/ppg_batches"
  static let emaEvents = "recoverysense/ema_events"
  static let control = "recoverysense/sensor_control"
}

private enum RecoverySensePayloadKind: String {
  case live
  case sensorBatch = "sensor_batch"
  case ppgBatch = "ppg_batch"
  case emaEvent = "ema_event"
  case command
  case acknowledgement = "ack"
}

private final class RecoverySenseStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenBlock: (FlutterEventSink?) -> Void
  private let onCancelBlock: () -> Void

  init(
    onListen: @escaping (FlutterEventSink?) -> Void,
    onCancel: @escaping () -> Void
  ) {
    onListenBlock = onListen
    onCancelBlock = onCancel
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    onListenBlock(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelBlock()
    return nil
  }
}

/// Native iPhone side of the existing Flutter platform-channel contract.
///
/// Durable watch payloads are replayed one at a time. This matches the current
/// bounded Android ingestion flow and avoids decoding a large offline backlog
/// into Flutter memory during app launch or research-data export.
final class RecoverySenseWatchBridge: NSObject, FlutterPlugin {
  private static var retainedInstance: RecoverySenseWatchBridge?

  private let payloadStore = RecoverySensePayloadStore()
  private let session: WCSession?
  private let emissionLock = NSLock()
  private var pendingEmissionURI: String?

  private var liveSink: FlutterEventSink?
  private var batchSink: FlutterEventSink?
  private var ppgBatchSink: FlutterEventSink?
  private var emaEventSink: FlutterEventSink?
  private var streamHandlers: [RecoverySenseStreamHandler] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let bridge = RecoverySenseWatchBridge(messenger: registrar.messenger())
    retainedInstance = bridge
  }

  private init(messenger: FlutterBinaryMessenger) {
    session = WCSession.isSupported() ? WCSession.default : nil
    super.init()

    let liveHandler = RecoverySenseStreamHandler(
      onListen: { [weak self] sink in
        self?.liveSink = sink
        self?.emitLatestApplicationContext()
      },
      onCancel: { [weak self] in self?.liveSink = nil }
    )
    let batchHandler = RecoverySenseStreamHandler(
      onListen: { [weak self] sink in
        self?.batchSink = sink
        _ = self?.emitNextPendingPayload()
      },
      onCancel: { [weak self] in self?.batchSink = nil }
    )
    let ppgHandler = RecoverySenseStreamHandler(
      onListen: { [weak self] sink in
        self?.ppgBatchSink = sink
        _ = self?.emitNextPendingPayload()
      },
      onCancel: { [weak self] in self?.ppgBatchSink = nil }
    )
    let emaHandler = RecoverySenseStreamHandler(
      onListen: { [weak self] sink in
        self?.emaEventSink = sink
        _ = self?.emitNextPendingPayload()
      },
      onCancel: { [weak self] in self?.emaEventSink = nil }
    )
    streamHandlers = [liveHandler, batchHandler, ppgHandler, emaHandler]

    FlutterEventChannel(
      name: RecoverySenseChannel.live,
      binaryMessenger: messenger
    ).setStreamHandler(liveHandler)
    FlutterEventChannel(
      name: RecoverySenseChannel.batches,
      binaryMessenger: messenger
    ).setStreamHandler(batchHandler)
    FlutterEventChannel(
      name: RecoverySenseChannel.ppgBatches,
      binaryMessenger: messenger
    ).setStreamHandler(ppgHandler)
    FlutterEventChannel(
      name: RecoverySenseChannel.emaEvents,
      binaryMessenger: messenger
    ).setStreamHandler(emaHandler)

    let controlChannel = FlutterMethodChannel(
      name: RecoverySenseChannel.control,
      binaryMessenger: messenger
    )
    controlChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    session?.delegate = self
    session?.activate()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPendingBatches":
      result(emitNextPendingPayload(force: true))

    case "ackBatch":
      guard
        let arguments = call.arguments as? [String: Any],
        let uri = arguments["uri"] as? String,
        !uri.isEmpty
      else {
        result(FlutterError(
          code: "INVALID_URI",
          message: "A batch URI is required.",
          details: nil
        ))
        return
      }
      let removedCount = payloadStore.remove(uri: uri)
      emissionLock.lock()
      if pendingEmissionURI == uri { pendingEmissionURI = nil }
      emissionLock.unlock()
      sendAcknowledgement(uri: uri)
      _ = emitNextPendingPayload()
      result(removedCount)

    case "startSleepRecording":
      guard
        let arguments = call.arguments as? [String: Any],
        let sessionID = arguments["sleepSessionId"] as? String,
        !sessionID.isEmpty
      else {
        result(FlutterError(
          code: "INVALID_SLEEP_SESSION",
          message: "A sleep session ID is required.",
          details: nil
        ))
        return
      }
      result(sendCommand(name: "start_sleep", sleepSessionID: sessionID))

    case "stopSleepRecording":
      result(sendCommand(name: "stop_sleep", sleepSessionID: nil))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func sendCommand(name: String, sleepSessionID: String?) -> Int {
    guard let session, session.activationState == .activated else { return 0 }
    var message: [String: Any] = [
      "recoverysenseKind": RecoverySensePayloadKind.command.rawValue,
      "command": name,
      "timestampMs": currentTimeMilliseconds()
    ]
    if let sleepSessionID { message["sleepSessionId"] = sleepSessionID }

    if session.isReachable {
      session.sendMessage(message, replyHandler: nil) { error in
        NSLog("RecoverySense watch command failed: %@", error.localizedDescription)
      }
    } else {
      session.transferUserInfo(message)
    }
    return 1
  }

  private func sendAcknowledgement(uri: String) {
    guard let session, session.activationState == .activated else { return }
    let message: [String: Any] = [
      "recoverysenseKind": RecoverySensePayloadKind.acknowledgement.rawValue,
      "uri": uri,
      "timestampMs": currentTimeMilliseconds()
    ]
    if session.isReachable {
      session.sendMessage(message, replyHandler: nil) { error in
        NSLog("RecoverySense watch acknowledgement failed: %@", error.localizedDescription)
      }
    }
    session.transferUserInfo(message)
  }

  private func receiveEnvelope(_ envelope: [String: Any]) {
    guard
      let kindText = envelope["recoverysenseKind"] as? String,
      let kind = RecoverySensePayloadKind(rawValue: kindText)
    else { return }

    switch kind {
    case .live:
      emit(normalizedPayload(from: envelope, kind: kind), kind: kind)

    case .sensorBatch, .ppgBatch, .emaEvent:
      let payload = normalizedPayload(from: envelope, kind: kind)
      payloadStore.upsert(payload)
      _ = emitNextPendingPayload()

    case .command, .acknowledgement:
      break
    }
  }

  private func normalizedPayload(
    from envelope: [String: Any],
    kind: RecoverySensePayloadKind
  ) -> [String: Any] {
    var payload = envelope["payload"] as? [String: Any] ?? envelope
    payload.removeValue(forKey: "recoverysenseKind")

    if payload["uri"] == nil {
      switch kind {
      case .sensorBatch:
        let identifier = payload["batchId"] as? String ?? UUID().uuidString
        payload["uri"] = "ios://sensor_batch/\(identifier)"
      case .ppgBatch:
        let identifier = payload["batchId"] as? String ?? UUID().uuidString
        payload["uri"] = "ios://ppg_batch/\(identifier)"
      case .emaEvent:
        let identifier = payload["eventId"] as? String ?? UUID().uuidString
        payload["uri"] = "ios://ema_event/\(identifier)"
      case .live, .command, .acknowledgement:
        break
      }
    }
    return payload
  }

  private func kind(for payload: [String: Any]) -> RecoverySensePayloadKind? {
    let uri = payload["uri"] as? String ?? ""
    if uri.contains("/sensor_batch/") { return .sensorBatch }
    if uri.contains("/ppg_batch/") { return .ppgBatch }
    if uri.contains("/ema_event/") { return .emaEvent }
    return nil
  }

  private func canEmit(_ kind: RecoverySensePayloadKind) -> Bool {
    switch kind {
    case .sensorBatch: return batchSink != nil
    case .ppgBatch: return ppgBatchSink != nil
    case .emaEvent: return emaEventSink != nil
    case .live: return liveSink != nil
    case .command, .acknowledgement: return false
    }
  }

  @discardableResult
  private func emitNextPendingPayload(force: Bool = false) -> Bool {
    emissionLock.lock()
    defer { emissionLock.unlock() }

    if pendingEmissionURI != nil && !force { return false }

    let payloads = payloadStore.all()
    var selected: ([String: Any], RecoverySensePayloadKind)?

    if force, let existingURI = pendingEmissionURI,
       let existing = payloads.first(where: { ($0["uri"] as? String) == existingURI }),
       let existingKind = kind(for: existing), canEmit(existingKind) {
      selected = (existing, existingKind)
    } else {
      selected = payloads.compactMap { payload -> ([String: Any], RecoverySensePayloadKind)? in
        guard let payloadKind = kind(for: payload), canEmit(payloadKind) else { return nil }
        return (payload, payloadKind)
      }.first
    }

    guard let selected else {
      pendingEmissionURI = nil
      return false
    }

    pendingEmissionURI = selected.0["uri"] as? String
    emit(selected.0, kind: selected.1)
    return true
  }

  private func emit(_ payload: [String: Any], kind: RecoverySensePayloadKind) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      switch kind {
      case .live:
        liveSink?(payload)
      case .sensorBatch:
        batchSink?(payload)
      case .ppgBatch:
        ppgBatchSink?(payload)
      case .emaEvent:
        emaEventSink?(payload)
      case .command, .acknowledgement:
        break
      }
    }
  }

  private func emitLatestApplicationContext() {
    guard let context = session?.receivedApplicationContext, !context.isEmpty else { return }
    receiveEnvelope(context)
  }

  private func currentTimeMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000.0).rounded())
  }
}

extension RecoverySenseWatchBridge: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      NSLog("RecoverySense WatchConnectivity activation failed: %@", error.localizedDescription)
    }
    _ = emitNextPendingPayload()
    emitLatestApplicationContext()
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    receiveEnvelope(applicationContext)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    receiveEnvelope(userInfo)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    receiveEnvelope(message)
  }
}
