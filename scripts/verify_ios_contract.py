"""Static parity checks for the current Android, Dart, iPhone, and watchOS paths.

This does not replace Xcode/device tests. It prevents accidental drift in the
platform channels, schema-5 sensor contract, EMA timing fields, watch target,
daily-step semantics, bounded backlog replay, and iOS export safeguards.
"""
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
DART_SERVICE = ROOT / "apps/phone_flutter_new/lib/services/watch/watch_connection_service.dart"
DART_BATCH = ROOT / "apps/phone_flutter_new/lib/models/watch_sensor_batch.dart"
DART_SAMPLE = ROOT / "apps/phone_flutter_new/lib/models/watch_sensor_sample.dart"
DART_EMA = ROOT / "apps/phone_flutter_new/lib/models/watch_ema_event.dart"
DART_EXPORT = ROOT / "apps/phone_flutter_new/lib/services/export/research_data_export_service.dart"
DART_EXPORT_CARD = ROOT / "apps/phone_flutter_new/lib/widgets/research_data_export_card.dart"
ANDROID_BRIDGE = ROOT / "apps/phone_flutter_new/android/app/src/main/kotlin/com/recoverysense/wear/MainActivity.kt"
IOS_BRIDGE = ROOT / "apps/phone_flutter_new/ios/Runner/RecoverySenseBridge/RecoverySenseWatchBridge.swift"
IOS_MODELS = ROOT / "apps/watch_ios/RecoverySenseWatch/Models/SensorModels.swift"
IOS_MOTION = ROOT / "apps/watch_ios/RecoverySenseWatch/Services/MotionSensorService.swift"
IOS_DASHBOARD = ROOT / "apps/watch_ios/RecoverySenseWatch/Views/WatchDashboardView.swift"
XCODE_PROJECT = ROOT / "apps/phone_flutter_new/ios/Runner.xcodeproj/project.pbxproj"
WATCH_INFO = ROOT / "apps/watch_ios/RecoverySenseWatch/SupportingFiles/Info.plist"
WATCH_SOURCE_ROOT = ROOT / "apps/watch_ios/RecoverySenseWatch"

CHANNELS = {
    "recoverysense/live_sensors",
    "recoverysense/sensor_batches",
    "recoverysense/ppg_batches",
    "recoverysense/ema_events",
    "recoverysense/sensor_control",
}

BATCH_FIELDS = {
    "uri", "batchId", "watchSessionId", "sequence", "samplingRateHz",
    "schemaVersion", "recordingMode", "sleepSessionId", "createdAt",
    "timestamps", "heartRates", "rawHeartRates", "heartRateTimestamps",
    "heartRateAgeMs", "heartRateAccuracy", "heartRateValid",
    "heartRateQualityCodes", "heartRateOutlier", "accelX", "accelY",
    "accelZ", "accelerationG", "accelAccuracy", "gyroX", "gyroY",
    "gyroZ", "gyroMagnitude", "gyroTimestamps", "gyroAccuracy",
    "stepCounts", "stepDetected", "offBody", "screenInteractive",
    "heartRateAvailable", "accelerometerAvailable", "gyroscopeAvailable",
    "stepCounterAvailable", "stepDetectorAvailable", "offBodyAvailable",
    "ppgAvailable", "ppgState",
}

LIVE_QUALITY_FIELDS = {
    "heartRate", "rawHeartRate", "heartRateAgeMs", "heartRateValid",
    "heartRateQualityCode", "heartRateOutlier",
}

EMA_FIELDS = {
    "uri", "eventId", "cravingScore", "timestampMs", "openedAtMs",
    "submittedAtMs", "source", "localMinuteOfDay",
    "timezoneOffsetMinutes", "watchSessionId", "promptedAtMs",
}


def require_tokens(path: Path, tokens: set[str], label: str) -> list[str]:
    text = path.read_text(encoding="utf-8")
    missing = sorted(
        token for token in tokens
        if f'"{token}"' not in text and f"'{token}'" not in text
    )
    if missing:
        return [f"{label} is missing: {', '.join(missing)}"]
    return []


def main() -> int:
    errors: list[str] = []
    for path in (DART_SERVICE, ANDROID_BRIDGE, IOS_BRIDGE):
        errors.extend(require_tokens(path, CHANNELS, str(path.relative_to(ROOT))))
    errors.extend(require_tokens(DART_BATCH, BATCH_FIELDS, "Dart batch model"))
    errors.extend(require_tokens(IOS_MODELS, BATCH_FIELDS, "iOS batch model"))
    errors.extend(require_tokens(DART_SAMPLE, LIVE_QUALITY_FIELDS, "Dart live model"))
    errors.extend(require_tokens(IOS_MODELS, EMA_FIELDS, "iOS EMA model"))
    errors.extend(require_tokens(DART_EMA, EMA_FIELDS, "Dart EMA model"))

    ios_text = IOS_MODELS.read_text(encoding="utf-8")
    if "static let schemaVersion = 5" not in ios_text:
        errors.append("iOS batch schema version is not 5")
    if "nominalSamplingRateHz = 10" not in ios_text:
        errors.append("iOS nominal sampling rate is not 10 Hz")
    if "disabled_public_api_no_raw_ppg" not in ios_text:
        errors.append("iOS PPG-disabled state is missing")

    motion_text = IOS_MOTION.read_text(encoding="utf-8")
    for token in ("startOfDay", "startPedometerForCurrentDay", "Steps Today"):
        if token not in motion_text and token not in IOS_DASHBOARD.read_text(encoding="utf-8"):
            errors.append(f"Daily-step parity token missing: {token}")

    bridge_text = IOS_BRIDGE.read_text(encoding="utf-8")
    if "emitNextPendingPayload" not in bridge_text or "pendingEmissionURI" not in bridge_text:
        errors.append("iPhone bridge is not using bounded one-at-a-time replay")
    if "emitPendingPayloads" in bridge_text:
        errors.append("iPhone bridge still contains all-at-once pending replay")

    export_text = DART_EXPORT.read_text(encoding="utf-8")
    export_card_text = DART_EXPORT_CARD.read_text(encoding="utf-8")
    if "Isolate.run" not in export_text:
        errors.append("Research export compression is not isolated from the UI")
    if "mimeType: 'application/zip'" not in export_text:
        errors.append("Research export ZIP MIME type is missing")
    if "deleteTemporaryExport(result)" in export_card_text:
        errors.append("Participant export still deletes the ZIP immediately after sharing")
    if "Rect.fromLTWH" not in export_card_text or "sharePositionOrigin" not in export_card_text:
        errors.append("iOS/iPad share origin safeguard is missing")

    project_text = XCODE_PROJECT.read_text(encoding="utf-8")
    project_tokens = {
        "RecoverySenseWatch",
        "com.apple.product-type.application.watchapp2",
        "Embed Watch Content",
        "com.recoverysense.phone.watchkitapp",
        "../../watch_ios/RecoverySenseWatch",
        "RecoverySenseWatchBridge.swift",
        "RecoverySensePayloadStore.swift",
        "MARKETING_VERSION = 0.5.3",
        "CURRENT_PROJECT_VERSION = 7",
    }
    for token in sorted(project_tokens):
        if token not in project_text:
            errors.append(f"Xcode project is missing integration token: {token}")

    watch_source_files = {
        "App/RecoverySenseWatchApp.swift",
        "App/RecoverySenseWatchModel.swift",
        "Models/SensorModels.swift",
        "Services/HealthSensorService.swift",
        "Services/MotionSensorService.swift",
        "Services/PendingPayloadStore.swift",
        "Services/SensorCoordinator.swift",
        "Services/WatchConnectivityService.swift",
        "Views/WatchDashboardView.swift",
        "Views/WatchEMAView.swift",
    }
    for relative in sorted(watch_source_files):
        source_path = WATCH_SOURCE_ROOT / relative
        if not source_path.is_file():
            errors.append(f"Missing watch source file: {relative}")
        elif source_path.name not in project_text:
            errors.append(f"Watch source is not referenced by Xcode: {relative}")

    with WATCH_INFO.open("rb") as stream:
        watch_info = plistlib.load(stream)
    expected_info = {
        "WKApplication": True,
        "WKCompanionAppBundleIdentifier": "com.recoverysense.phone",
        "WKRunsIndependentlyOfCompanionApp": False,
    }
    for key, expected in expected_info.items():
        if watch_info.get(key) != expected:
            errors.append(f"Watch Info.plist {key} does not equal {expected!r}")
    if "workout-processing" not in watch_info.get("WKBackgroundModes", []):
        errors.append("Watch Info.plist is missing workout-processing background mode")

    if errors:
        print("iOS parity verification failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("RecoverySense Android/Dart/iPhone/watchOS parity checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
