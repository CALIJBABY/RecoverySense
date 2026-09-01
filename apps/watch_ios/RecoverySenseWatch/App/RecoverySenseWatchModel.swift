import Combine
import Foundation

@MainActor
final class RecoverySenseWatchModel: ObservableObject {
  @Published var heartRateText = "--"
  @Published var accelerationText = "--"
  @Published var gyroscopeText = "--"
  @Published var stepsText = "--"
  @Published var statusText = "Starting sensors"
  @Published var recordingMode = "continuous"
  @Published var sleepSessionId: String?
  @Published var emaScore = 5
  @Published var emaSelectionMade = false
  @Published var emaStatusText = "0 none - 10 extreme"

  private let coordinator = SensorCoordinator()
  private var emaOpenedAtMs: Int64?
  private var started = false

  init() {
    coordinator.onLiveSnapshot = { [weak self] snapshot in
      guard let self else { return }
      heartRateText = snapshot.heartRate.map(String.init) ?? "--"
      accelerationText = String(format: "%.2f g", snapshot.accelerationG)
      gyroscopeText = snapshot.gyroMagnitude.map {
        String(format: "%.2f rad/s", $0)
      } ?? "--"
      stepsText = snapshot.stepCount.map { String(Int($0)) } ?? "--"
      recordingMode = snapshot.recordingMode
      sleepSessionId = snapshot.sleepSessionId
    }
    coordinator.onStatus = { [weak self] text in
      self?.statusText = text
    }
  }

  func start() {
    guard !started else { return }
    started = true
    coordinator.start()
  }

  func stop() {
    coordinator.stop()
    started = false
  }

  func setScreenInteractive(_ interactive: Bool) {
    coordinator.setScreenInteractive(interactive)
  }

  func updateEMAScore(_ score: Int) {
    if emaOpenedAtMs == nil { emaOpenedAtMs = currentTimeMilliseconds() }
    emaScore = min(max(score, 0), 10)
    emaSelectionMade = true
    emaStatusText = "0 none - 10 extreme"
  }

  func submitEMA() {
    guard emaSelectionMade else { return }
    let submittedAt = currentTimeMilliseconds()
    let openedAt = emaOpenedAtMs ?? submittedAt
    emaStatusText = "Saving..."
    coordinator.submitEMA(score: emaScore, openedAtMs: openedAt)
    emaStatusText = "Saved - queued for iPhone"
    emaOpenedAtMs = nil
    emaSelectionMade = false
    emaScore = 5
  }
}
