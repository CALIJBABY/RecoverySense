import Foundation
import WatchConnectivity

final class WatchConnectivityService: NSObject {
  static let shared = WatchConnectivityService()

  var onStartSleep: ((String) -> Void)?
  var onStopSleep: (() -> Void)?
  var onStatus: ((String) -> Void)?

  private let session: WCSession?
  private let store = PendingPayloadStore()

  private override init() {
    session = WCSession.isSupported() ? WCSession.default : nil
    super.init()
    session?.delegate = self
    session?.activate()
  }

  func activate() {
    session?.activate()
  }

  func sendLive(_ payload: [String: Any]) {
    guard let session, session.activationState == .activated else { return }
    let envelope: [String: Any] = [
      "recoverysenseKind": "live",
      "payload": payload
    ]
    do {
      try session.updateApplicationContext(envelope)
    } catch {
      onStatus?("Live sync unavailable")
    }
  }

  func enqueueSensorBatch(_ payload: SensorBatchPayload) {
    enqueue(kind: "sensor_batch", uri: payload.uri, payload: payload.dictionary)
  }

  func enqueueEMA(_ payload: WatchEMAPayload) {
    enqueue(kind: "ema_event", uri: payload.uri, payload: payload.dictionary)
  }

  func resendPending() {
    guard let session, session.activationState == .activated else { return }
    var outstanding = outstandingURIs(in: session)
    for envelope in store.all() {
      guard let uri = uri(from: envelope), outstanding.insert(uri).inserted else {
        continue
      }
      session.transferUserInfo(envelope)
    }
  }

  private func enqueue(kind: String, uri: String, payload: [String: Any]) {
    let envelope: [String: Any] = [
      "recoverysenseKind": kind,
      "payload": payload
    ]
    store.upsert(uri: uri, envelope: envelope)
    guard let session, session.activationState == .activated else {
      onStatus?("Queued on watch")
      return
    }
    if !outstandingURIs(in: session).contains(uri) {
      session.transferUserInfo(envelope)
    }
    onStatus?("Queued for iPhone")
  }

  private func outstandingURIs(in session: WCSession) -> Set<String> {
    Set(session.outstandingUserInfoTransfers.compactMap { uri(from: $0.userInfo) })
  }

  private func uri(from envelope: [String: Any]) -> String? {
    guard
      let payload = envelope["payload"] as? [String: Any],
      let uri = payload["uri"] as? String,
      !uri.isEmpty
    else { return nil }
    return uri
  }

  private func cancelOutstanding(uri: String, in session: WCSession) {
    for transfer in session.outstandingUserInfoTransfers where self.uri(from: transfer.userInfo) == uri {
      transfer.cancel()
    }
  }

  private func receive(_ message: [String: Any]) {
    guard let kind = message["recoverysenseKind"] as? String else { return }
    switch kind {
    case "command":
      let command = message["command"] as? String
      if command == "start_sleep",
         let sessionID = message["sleepSessionId"] as? String,
         !sessionID.isEmpty {
        onStartSleep?(sessionID)
      } else if command == "stop_sleep" {
        onStopSleep?()
      }
    case "ack":
      if let uri = message["uri"] as? String {
        store.remove(uri: uri)
        if let session { cancelOutstanding(uri: uri, in: session) }
      }
    default:
      break
    }
  }
}

extension WatchConnectivityService: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      onStatus?("Watch sync error: \(error.localizedDescription)")
    } else if activationState == .activated {
      onStatus?("iPhone sync ready")
      resendPending()
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    if session.isReachable { resendPending() }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    receive(message)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    receive(userInfo)
  }
}
