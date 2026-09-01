import Foundation

/// Small durable queue used by the iPhone bridge.
///
/// WatchConnectivity can deliver data while Flutter is not running. The queue
/// preserves those payloads until the existing Dart ingestion service writes
/// them to Firestore and calls `ackBatch`.
final class RecoverySensePayloadStore {
  private let lock = NSLock()
  private let fileURL: URL
  private var payloadsByURI: [String: [String: Any]] = [:]

  init(fileManager: FileManager = .default) {
    let baseURL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    let directory = baseURL.appendingPathComponent("RecoverySense", isDirectory: true)
    try? fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    fileURL = directory.appendingPathComponent("pending-watch-payloads.json")
    loadFromDisk()
  }

  func upsert(_ payload: [String: Any]) {
    guard let uri = payload["uri"] as? String, !uri.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    payloadsByURI[uri] = payload
    persistLocked()
  }

  @discardableResult
  func remove(uri: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    guard payloadsByURI.removeValue(forKey: uri) != nil else { return 0 }
    persistLocked()
    return 1
  }

  func all() -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    return payloadsByURI.values.sorted { lhs, rhs in
      let lhsDate = (lhs["createdAt"] as? NSNumber)?.int64Value ?? 0
      let rhsDate = (rhs["createdAt"] as? NSNumber)?.int64Value ?? 0
      return lhsDate < rhsDate
    }
  }

  private func loadFromDisk() {
    lock.lock()
    defer { lock.unlock() }
    guard
      let data = try? Data(contentsOf: fileURL),
      let object = try? JSONSerialization.jsonObject(with: data),
      let stored = object as? [[String: Any]]
    else { return }

    payloadsByURI = Dictionary(
      uniqueKeysWithValues: stored.compactMap { payload in
        guard let uri = payload["uri"] as? String, !uri.isEmpty else { return nil }
        return (uri, payload)
      }
    )
  }

  private func persistLocked() {
    let payloads = Array(payloadsByURI.values)
    guard JSONSerialization.isValidJSONObject(payloads) else { return }
    guard let data = try? JSONSerialization.data(
      withJSONObject: payloads,
      options: [.sortedKeys]
    ) else { return }
    try? data.write(to: fileURL, options: [.atomic])
  }
}
