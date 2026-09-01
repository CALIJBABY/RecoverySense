import Foundation

final class PendingPayloadStore {
  private let lock = NSLock()
  private let fileURL: URL
  private var envelopesByURI: [String: [String: Any]] = [:]

  init(fileManager: FileManager = .default) {
    let baseURL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    let directory = baseURL.appendingPathComponent("RecoverySenseWatch", isDirectory: true)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("pending-payloads.json")
    load()
  }

  func upsert(uri: String, envelope: [String: Any]) {
    lock.lock()
    defer { lock.unlock() }
    envelopesByURI[uri] = envelope
    persistLocked()
  }

  func remove(uri: String) {
    lock.lock()
    defer { lock.unlock() }
    envelopesByURI.removeValue(forKey: uri)
    persistLocked()
  }

  func all() -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    return Array(envelopesByURI.values)
  }

  private func load() {
    lock.lock()
    defer { lock.unlock() }
    guard
      let data = try? Data(contentsOf: fileURL),
      let object = try? JSONSerialization.jsonObject(with: data),
      let envelopes = object as? [[String: Any]]
    else { return }

    envelopesByURI = Dictionary(uniqueKeysWithValues: envelopes.compactMap { envelope in
      guard
        let payload = envelope["payload"] as? [String: Any],
        let uri = payload["uri"] as? String
      else { return nil }
      return (uri, envelope)
    })
  }

  private func persistLocked() {
    let envelopes = Array(envelopesByURI.values)
    guard JSONSerialization.isValidJSONObject(envelopes) else { return }
    guard let data = try? JSONSerialization.data(
      withJSONObject: envelopes,
      options: [.sortedKeys]
    ) else { return }
    try? data.write(to: fileURL, options: [.atomic])
  }
}
