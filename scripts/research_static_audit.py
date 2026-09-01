#!/usr/bin/env python3
"""Static research/source guardrails for the current RecoverySense release.

This script is intentionally conservative. It checks source/configuration contracts
that can be verified without Flutter, Gradle, Xcode, Firebase credentials, or
physical devices. It does not replace those build/device/field validation steps.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

import yaml

ROOT = Path(__file__).resolve().parents[1]
FAILURES: list[str] = []
PASSES: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        FAILURES.append(f"missing required file: {relative}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def require(condition: bool, message: str) -> None:
    (PASSES if condition else FAILURES).append(message)


def require_contains(relative: str, needle: str, description: str) -> None:
    require(needle in read(relative), description)


def require_absent(relative: str, needle: str, description: str) -> None:
    require(needle not in read(relative), description)


def verify_dart_imports() -> None:
    lib_root = ROOT / "apps/phone_flutter_new/lib"
    import_pattern = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
    missing: list[str] = []
    for source in lib_root.rglob("*.dart"):
        text = source.read_text(encoding="utf-8", errors="replace")
        for match in import_pattern.finditer(text):
            imported = match.group(1)
            target: Path | None = None
            if imported.startswith("package:recoverysense_phone/"):
                target = lib_root / imported.split("/", 1)[1]
            elif imported.startswith(".") or not (
                imported.startswith("dart:") or imported.startswith("package:")
            ):
                target = (source.parent / imported).resolve()
            if target is not None and not target.exists():
                missing.append(f"{source.relative_to(ROOT)} -> {imported}")
    require(not missing, "all local Dart imports resolve")
    FAILURES.extend(f"unresolved Dart import: {item}" for item in missing)


def verify_source_hygiene() -> None:
    source_roots = [
        ROOT / "apps/phone_flutter_new/lib",
        ROOT / "apps/phone_flutter_new/android/app/src/main",
        ROOT / "apps/wear_android/wear_android/app/src/main",
        ROOT / "backend/api/app",
        ROOT / "ml/src/recoverysense_ml",
    ]
    conflict_pattern = re.compile(r"^(<<<<<<<|=======|>>>>>>>)(?: .*)?$", re.MULTILINE)
    conflicts: list[str] = []
    empty_sources: list[str] = []
    for source_root in source_roots:
        if not source_root.exists():
            FAILURES.append(f"missing active source root: {source_root.relative_to(ROOT)}")
            continue
        for path in source_root.rglob("*"):
            if not path.is_file() or path.suffix not in {
                ".dart",
                ".kt",
                ".java",
                ".py",
                ".xml",
                ".yaml",
                ".yml",
            }:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if conflict_pattern.search(text):
                conflicts.append(str(path.relative_to(ROOT)))
            if path.suffix in {".dart", ".kt", ".java", ".py"} and not text.strip():
                empty_sources.append(str(path.relative_to(ROOT)))
    require(not conflicts, "active source has no unresolved merge-conflict markers")
    require(not empty_sources, "active source has no empty source files")
    FAILURES.extend(f"merge-conflict marker in: {item}" for item in conflicts)
    FAILURES.extend(f"empty source file: {item}" for item in empty_sources)


def verify_transport_contracts() -> None:
    watch = read(
        "apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/watch/DataLayerService.kt"
    )
    native_phone = read(
        "apps/phone_flutter_new/android/app/src/main/kotlin/com/recoverysense/wear/MainActivity.kt"
    )
    dart_phone = read(
        "apps/phone_flutter_new/lib/services/watch/watch_connection_service.dart"
    )
    for path in (
        "/recoverysense/live",
        "/recoverysense/sensor_batch",
        "/recoverysense/ppg_batch",
        "/recoverysense/ema_event",
    ):
        require(path in watch and path in native_phone, f"watch/phone transport path matches: {path}")
    for channel in (
        "recoverysense/live_sensors",
        "recoverysense/sensor_batches",
        "recoverysense/ppg_batches",
        "recoverysense/ema_events",
        "recoverysense/sensor_control",
    ):
        require(
            channel in native_phone and channel in dart_phone,
            f"native/Dart channel matches: {channel}",
        )


def verify_structured_files() -> None:
    json_files = [
        "firebase.json",
        "apps/phone_flutter_new/firebase.json",
        "apps/phone_flutter_new/android/app/google-services.json",
    ]
    for relative in json_files:
        try:
            json.loads(read(relative))
            PASSES.append(f"JSON parses: {relative}")
        except Exception as exc:
            FAILURES.append(f"JSON parse failed ({relative}): {exc}")

    yaml_files = [
        "apps/phone_flutter_new/pubspec.yaml",
        "apps/phone_flutter_new/analysis_options.yaml",
        "ml/config/default.yaml",
    ]
    for relative in yaml_files:
        try:
            yaml.safe_load(read(relative))
            PASSES.append(f"YAML parses: {relative}")
        except Exception as exc:
            FAILURES.append(f"YAML parse failed ({relative}): {exc}")

    xml_files = [
        "apps/phone_flutter_new/android/app/src/main/AndroidManifest.xml",
        "apps/phone_flutter_new/android/app/src/main/res/xml/data_extraction_rules.xml",
        "apps/wear_android/wear_android/app/src/main/AndroidManifest.xml",
    ]
    for relative in xml_files:
        try:
            ET.parse(ROOT / relative)
            PASSES.append(f"XML parses: {relative}")
        except Exception as exc:
            FAILURES.append(f"XML parse failed ({relative}): {exc}")


def main() -> int:
    # Release/version contracts.
    phone_pubspec = yaml.safe_load(read("apps/phone_flutter_new/pubspec.yaml")) or {}
    require(phone_pubspec.get("version") == "0.5.3+10", "phone version is 0.5.3+10")
    deps = phone_pubspec.get("dependencies", {})
    require("archive" in deps and "share_plus" in deps, "research-export dependencies are declared")

    watch_gradle = read("apps/wear_android/wear_android/app/build.gradle.kts")
    require('applicationId = "com.recoverysense.wear"' in watch_gradle, "watch package is current")
    require('versionName = "0.5.3"' in watch_gradle, "watch version is 0.5.3")
    require("versionCode = 7" in watch_gradle, "watch versionCode is 7")

    phone_gradle = read("apps/phone_flutter_new/android/app/build.gradle.kts")
    require(
        'applicationId = "com.recoverysense.wear"' in phone_gradle,
        "phone/watch Data Layer package IDs match",
    )
    require('version="0.5.3"' in read("ml/pyproject.toml").replace(" ", ""), "ML package version is 0.5.3")
    require('version="0.5.3"' in read("backend/api/app/main.py").replace(" ", ""), "backend API version is 0.5.3")

    # Heart-rate quality and cross-layer semantics.
    hr_service = read("apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/sensors/HeartRateSensorService.kt")
    require("rawValue?.let { it < 0.5f }" in hr_service, "watch converts Android 1=on-body/0=off-body into true=off-body semantics")
    quality_gate = read("apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/sensors/HeartRateQualityGate.kt")
    for needle, description in (
        ("QUALITY_NO_CONTACT", "HR quality gate includes no-contact rejection"),
        ("QUALITY_UNRELIABLE", "HR quality gate includes unreliable-status rejection"),
        ("minimumBpm: Int = 30", "HR quality gate has documented broad lower plausibility boundary"),
        ("maximumBpm: Int = 220", "HR quality gate has documented broad upper plausibility boundary"),
        ("staleAfterMs: Long = 90_000L", "HR quality gate rejects stale BPM after 90 seconds"),
        ("temporalOutlier", "HR quality gate preserves temporal-outlier provenance"),
    ):
        require(needle in quality_gate, description)
    data_layer = read("apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/watch/DataLayerService.kt")
    require("const val SCHEMA_VERSION = 5" in data_layer, "Wear sensor Data Layer schema is 5")
    for field in ("rawHeartRates", "heartRateValid", "heartRateQualityCodes", "heartRateOutlier"):
        require(field in data_layer, f"Wear sensor payload carries {field}")
    dart_batch = read("apps/phone_flutter_new/lib/models/watch_sensor_batch.dart")
    require("schemaVersion <= 4" in dart_batch and "value == 1 ? 0 : 1" in dart_batch, "phone normalizes legacy off-body values")
    require("HeartRateQuality.offBody" in dart_batch, "legacy off-body samples are not marked HR-valid")
    firestore_repo = read("apps/phone_flutter_new/lib/services/firebase/firestore_sensor_repository.dart")
    require("'schema_version': 5" in firestore_repo, "phone sensor storage schema is 5")
    hr_preprocessing = read("ml/src/recoverysense_ml/preprocessing.py")
    require("hard_invalid_hr" in hr_preprocessing and "segment.loc[hard_invalid_hr, hr] = np.nan" in hr_preprocessing, "ML reapplies hard HR invalidity after filling/smoothing")
    require("exclude_temporal_outliers" in hr_preprocessing, "ML temporal-outlier exclusion is explicit/configurable")
    hr_doc = read("docs/HEART_RATE_QUALITY_LAYER.md")
    require("engineering sanity boundary" in hr_doc and "not a normal-range claim" in hr_doc, "HR thresholds are documented as engineering rather than clinical")

    # Phone participant UI and research-response integrity.
    dashboard = read("apps/phone_flutter_new/lib/screens/dashboard/dashboard_screen.dart")
    for needle, description in (
        ("CravingGauge", "dashboard contains the participant model-probability gauge"),
        ("Craving Risk Now", "dashboard labels the main value as current craving risk"),
        ("Top patterns", "dashboard exposes three plain-language local contributors"),
        ("latest rating is not copied here", "dashboard separates model probability from current EMA self-report"),
        ("Higher-Risk Times", "dashboard includes the safeguarded time-of-day pattern section"),
        ("AppBottomNavigation(currentIndex: 0)", "dashboard participates in the five-page bottom navigation"),
        ("AppRoutes.settings", "settings remains in the dashboard app bar"),
    ):
        require(needle in dashboard, description)
    require("Research Data Status" not in dashboard, "engineering research-data status card is absent from dashboard")
    require("List<Widget>.generate(3" in dashboard, "dashboard always allocates three contributor boxes")
    require("contributor.contribution * 100" in dashboard, "contributor boxes show local probability-point influence")

    gauge = read("apps/phone_flutter_new/lib/widgets/craving_gauge.dart")
    require("model-estimated elevated craving probability" in gauge and "0%" in gauge and "100%" in gauge, "craving-risk gauge has a labeled 0–100 percent scale")
    require("Semantics(" in gauge, "custom craving-risk gauge includes accessibility semantics")

    bottom_nav = read("apps/phone_flutter_new/lib/widgets/app_bottom_navigation.dart")
    for route in ("AppRoutes.dashboard", "AppRoutes.watch", "AppRoutes.ema", "AppRoutes.sleep", "AppRoutes.history"):
        require(route in bottom_nav, f"bottom navigation includes {route}")
    require("onlyShowSelected" in bottom_nav, "bottom navigation uses icons with restrained selected labeling")

    ema_screen = read("apps/phone_flutter_new/lib/screens/ema/ema_screen.dart")
    require("min: 0" in ema_screen and "max: 10" in ema_screen and "divisions: 10" in ema_screen, "phone EMA is bounded 0–10")
    require("_hasSelectedRating" in ema_screen, "phone EMA tracks deliberate participant selection")
    require("onPressed: _hasSelectedRating ? _submit : null" in ema_screen, "phone EMA cannot save an untouched neutral slider")
    require("EmaPrimaryButton" in ema_screen, "phone EMA uses the standardized participant CTA")
    require("AppBottomNavigation(currentIndex: 2)" in ema_screen, "check-in is a bottom-navigation destination")

    dimensions = read("apps/phone_flutter_new/lib/core/theme/app_dimensions.dart")
    require("emaCtaHeight = 50" in dimensions and "emaCtaRadius = 14" in dimensions, "rounded primary action dimensions are centralized")
    theme = read("apps/phone_flutter_new/lib/core/theme/app_theme.dart")
    require("0xFF4F9B17" in theme, "phone uses the supplied lighter green")
    require("foregroundColor: textBlack" in theme, "bright-green phone actions use dark text")
    require("cardRadius = 20" in dimensions, "rounded card radius is centralized")
    require("Times New Roman" not in theme, "phone theme does not force an inconsistent display font")

    live_screen = read("apps/phone_flutter_new/lib/screens/watch/watch_screen.dart")
    require("Live Sensors" in live_screen and "AppBottomNavigation(currentIndex: 1)" in live_screen, "live sensor data has its own navigation screen")
    sleep_screen = read("apps/phone_flutter_new/lib/screens/sleep/sleep_screen.dart")
    require("BlockScoreBar" in sleep_screen and "Sleep Quality" in sleep_screen, "sleep has its own block-score quality screen")
    require("AppBottomNavigation(currentIndex: 3)" in sleep_screen, "sleep is a bottom-navigation destination")

    baseline_screen = read("apps/phone_flutter_new/lib/screens/onboarding/baseline_assessment_screen.dart")
    require("Baseline Assessment" in baseline_screen and "Step ${_page + 1} of 5" in baseline_screen, "one-time five-step baseline assessment UI exists")
    for flag in (
        "_daysEngagedAnswered",
        "_typicalCravingAnswered",
        "_episodeDurationAnswered",
        "_bedtimeConfirmed",
        "_wakeTimeConfirmed",
        "_confidenceAnswered",
        "_stressAnswered",
    ):
        require(flag in baseline_screen, f"baseline deliberate-response safeguard exists: {flag}")
    baseline_repo = read("apps/phone_flutter_new/lib/services/firebase/baseline_assessment_repository.dart")
    require("baseline_assessments" in baseline_repo and "has already been completed" in baseline_repo, "baseline assessment is versioned and write-once")

    for flag in (
        "_sleepQualityAnswered",
        "_restedScoreAnswered",
        "_awakeningsAnswered",
        "bool? _watchRemoved",
    ):
        require(flag in sleep_screen, f"morning sleep confirmation requires deliberate response: {flag}")
    require(sleep_screen.count("initialDate: local") == 1, "sleep date picker has exactly one initialDate argument")
    require("wake.isAfter(onset)" in sleep_screen, "sleep confirmation rejects wake time at/before onset")

    history = read("apps/phone_flutter_new/lib/screens/history/history_screen.dart")
    require("collection('sleep_sessions')" in history, "History reads canonical sleep_sessions")
    require("collection('sleep_logs')" not in history, "History does not query legacy sleep_logs")
    require("/5" in history, "History displays subjective sleep quality on the implemented 1–5 scale")

    sleep_repo = read("apps/phone_flutter_new/lib/services/firebase/sleep_repository.dart")
    require("'start_error_code': 'watch_start_failed'" in sleep_repo, "sleep start failures persist a stable error code")
    require("'start_error': error.toString()" not in sleep_repo, "raw sleep-start exceptions are not persisted as research data")

    export_card = read("apps/phone_flutter_new/lib/widgets/research_data_export_card.dart")
    require("counts['sleep_sessions']" in export_card, "participant export summary reports current sleep-session count")

    settings = read("apps/phone_flutter_new/lib/screens/settings/settings_screen.dart")
    require("if (kDebugMode)" in settings, "developer scheduler controls are hidden from release builds")
    require("app-process timer" in settings, "current notification-scheduler limitation is disclosed")

    auth = read("apps/phone_flutter_new/lib/services/firebase/auth_service.dart")
    require("_ensureParticipantProfile" in auth, "sign-in/account creation ensure a research participant profile")
    require("'email':" not in auth, "research participant documents do not duplicate email")
    require("await _auth.signOut();" in auth, "profile-initialization failure does not leave a partial authenticated state")

    # Model display, temporal analysis, and scheduling safeguards.
    risk_prediction = read("apps/phone_flutter_new/lib/models/risk_prediction.dart")
    require("displayEligible" in risk_prediction, "phone has explicit fail-closed model-display eligibility")
    require("participant_display_allowed" in risk_prediction and "demo_only" in risk_prediction, "phone requires participant-display provenance and rejects demo predictions")
    require("prediction_basis" in risk_prediction and "current_ema_direct_input" in risk_prediction, "phone requires sensor-window provenance and rejects copied current EMA")
    require("schemaVersion >= 2" in risk_prediction and "input_modalities" in risk_prediction, "phone requires schema-2 wearable input provenance")
    require("rankedContributors.sort" in risk_prediction and ".take(3)" in risk_prediction, "participant UI sorts and caps positive local contributors at three")
    participant_insights = read("apps/phone_flutter_new/lib/services/firebase/participant_insights_repository.dart")
    require(".limit(20)" in participant_insights and "prediction.displayEligible" in participant_insights, "prediction stream skips invalid newer records and refreshes the latest eligible result")

    temporal = read("apps/phone_flutter_new/lib/services/insights/temporal_risk_service.dart")
    require("minimumEligibleEvents = 30" in temporal and "minimumEventsPerWindow = 5" in temporal, "time-of-day display has minimum-data safeguards")
    require("scheduled_stratified" in temporal and "local_minute_of_day" in temporal, "time-of-day analysis uses independently timed participant-local EMA")
    require("elevatedCravingThreshold = 7" in temporal, "descriptive elevated-time fraction has an explicit 7/10 threshold")

    scheduler = read("apps/phone_flutter_new/lib/services/ema/ema_prompt_service.dart")
    require("ensureStudyScheduleStarted" in scheduler, "study check-in schedule starts through an explicit service entry point")
    require("scheduled_stratified" in scheduler, "EMA collection schedule is stratified across dayparts")
    require("_lastDeliveredWindowIndex" in scheduler and "index <= deliveredIndex" in scheduler, "app-active scheduler prevents duplicate delivery within a delivered stratum")
    require("scheduled_test" in scheduler, "debug test prompts remain distinguishable from study-scheduled prompts")

    # Watch participant UI and sensing permissions.
    watch_ui = read("apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/MainActivity.kt")
    require("statusText" not in watch_ui and "Recorder inactive" not in watch_ui, "engineering recorder status is absent from participant watch UI")
    require("Craving now?" in watch_ui and "0 none · 10 extreme" in watch_ui, "watch 0–10 micro-EMA is present")
    require("emaSelectionMade" in watch_ui and "enabled = emaSelectionMade" in watch_ui, "watch EMA cannot save an untouched neutral slider")
    require("Color(0xFF4F9B17)" in watch_ui, "watch uses the supplied lighter green")
    require(".height(48.dp)" in watch_ui and "RoundedCornerShape(14.dp)" in watch_ui, "watch EMA CTA uses rounded reference dimensions")
    require('symbol = "♥"' in watch_ui and 'symbol = "+"' in watch_ui, "watch bottom controls expose compact page symbols")

    watch_manifest = read("apps/wear_android/wear_android/app/src/main/AndroidManifest.xml")
    require('android.permission.BODY_SENSORS"\n        android:maxSdkVersion="35"' in watch_manifest, "legacy BODY_SENSORS permission is capped at API 35")
    require('android.permission.BODY_SENSORS_BACKGROUND"\n        android:maxSdkVersion="35"' in watch_manifest, "legacy background body-sensor permission is capped at API 35")
    require("android.permission.health.READ_HEART_RATE" in watch_manifest, "Wear OS 6 heart-rate permission is declared")
    require("android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND" in watch_manifest, "Wear OS 6 background health-data permission is declared")
    try:
        manifest_root = ET.fromstring(watch_manifest)
        android_ns = "{http://schemas.android.com/apk/res/android}"
        declared_permissions = {
            element.attrib.get(f"{android_ns}name", "")
            for element in manifest_root.findall("uses-permission")
        }
    except ET.ParseError:
        declared_permissions = set()
    require(
        "com.samsung.android.hardware.sensormanager.permission.READ_ADDITIONAL_HEALTH_DATA" not in declared_permissions,
        "disabled raw-PPG-only permission is not declared",
    )
    require(re.search(r'<receiver\s+android:name="\.sleep\.SensorBootReceiver"[\s\S]*?android:exported="false"', watch_manifest) is not None, "watch boot receiver is not exported to third-party apps")

    data_layer = read("apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/watch/DataLayerService.kt")
    require(data_layer.count("DataLayerService.RECORDING_MODE_CONTINUOUS") >= 2, "top-level payload defaults use qualified recording-mode constant")
    require("localMinuteOfDay" in data_layer and "timezoneOffsetMinutes" in data_layer, "watch EMA transport records local-time metadata")
    native_phone = read("apps/phone_flutter_new/android/app/src/main/kotlin/com/recoverysense/wear/MainActivity.kt")
    require("localMinuteOfDay" in native_phone and "timezoneOffsetMinutes" in native_phone, "native phone bridge forwards watch EMA local-time metadata")
    watch_ema = read("apps/phone_flutter_new/lib/models/watch_ema_event.dart")
    require("localMinuteOfDay" in watch_ema and "timezoneOffsetMinutes" in watch_ema, "Dart watch EMA model preserves local-time metadata")

    ppg_flags = read("apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/ppg/PpgFeatureFlags.kt")
    require(re.search(r"ENABLED\s*=\s*false", ppg_flags) is not None, "raw PPG remains explicitly disabled")

    # Phone Android privacy/manifest basics.
    phone_manifest = read("apps/phone_flutter_new/android/app/src/main/AndroidManifest.xml")
    require("android.permission.INTERNET" in phone_manifest, "phone release manifest includes Internet permission")
    require('android:allowBackup="false"' in phone_manifest, "phone Android backup is disabled")
    require('android:dataExtractionRules="@xml/data_extraction_rules"' in phone_manifest, "phone data-extraction rules are configured")
    require('android:label="RecoverySense"' in phone_manifest, "phone application label is RecoverySense")

    # ML causality/evaluation/local time.
    config_source = read("ml/src/recoverysense_ml/config.py")
    require("REPOSITORY_ROOT" in config_source and "candidates" in config_source and "Path.cwd()" in config_source, "ML config paths resolve independently of working directory")
    preprocessing = read("ml/src/recoverysense_ml/preprocessing.py")
    require("sosfiltfilt" not in preprocessing and "filtfilt" not in preprocessing, "craving preprocessing avoids forward-backward filtering")
    require("sosfilt(" in preprocessing, "craving preprocessing uses causal SOS filtering")
    require("center=True" not in preprocessing, "craving preprocessing has no centered rolling input")
    require("heart_rate_age_ms" in preprocessing and "screen_interactive" in preprocessing, "quality fields survive craving preprocessing")

    dataset = read("ml/src/recoverysense_ml/dataset.py")
    require("local_time_context_available" in dataset, "ML includes explicit local-time availability")
    require("timezone_offset_minutes" in dataset and "pd.Timedelta" in dataset, "ML cyclic clock features use timezone-offset metadata")
    require("UTC as local time" in dataset, "ML source documents the no-UTC-as-local safeguard")

    inference = read("ml/src/recoverysense_ml/inference.py")
    require("timezone_offset_minutes" in inference and "_time_features" in inference, "streaming inference uses the same participant-local time transform")
    require("top_contributors" in inference and "interpretability_model" in inference, "inference returns model provenance and local contributors")

    sleep_model = read("ml/src/recoverysense_ml/sleep_model.py")
    require("next_" not in sleep_model, "sleep-model source has no future-epoch next_* feature names")
    labeling = read("ml/src/recoverysense_ml/labeling.py")
    require("negative_lookback_seconds" in labeling, "negative craving labels require a nearby low EMA")

    training = read("ml/src/recoverysense_ml/training.py")
    require("participant-grouped" in training, "participant-grouped evaluation is implemented")
    require("session-grouped-fallback" in training, "session-grouped fallback is implemented")
    require("purged-temporal-holdout-fallback" in training, "purged temporal fallback is implemented")
    require("StratifiedShuffleSplit" not in training, "random row fallback is absent")
    for metric in ("balanced_accuracy", "specificity", "false_positive_rate", "brier_score"):
        require(metric in training, f"research metric is implemented: {metric}")

    explainability = read("ml/src/recoverysense_ml/explainability.py")
    require("decision_tree_path_contributions" in explainability, "local decision-tree path explanation is implemented")
    require("not a causal attribution" in explainability, "explainability source explicitly rejects causal interpretation")

    # Backend safeguards and data schemas.
    backend_schema = read("backend/api/app/models/schemas.py")
    require("timezone_offset_minutes" in backend_schema and "ge=-840" in backend_schema and "le=840" in backend_schema, "backend bounds timezone offset metadata")
    require("prior_sleep_quality" in backend_schema and "ge=1, le=5" in backend_schema, "backend uses current 1–5 sleep-quality scale")
    require("prior_rested_score" in backend_schema and backend_schema.count("ge=1, le=5") >= 2, "backend uses current 1–5 rested scale")

    model_service = read("backend/api/app/services/model_service.py")
    require('self.error = "Model bundle could not be loaded."' in model_service, "backend does not expose raw model-loader exception text")
    sensors_route = read("backend/api/app/routes/sensors.py")
    require("model_runtime.model_path.name" in sensors_route, "model-status route does not expose a server filesystem path")

    trigger = read("backend/api/app/services/trigger_service.py")
    require("RECOVERYSENSE_ENABLE_RULE_TRIGGER" in trigger, "engineering trigger requires explicit opt-in")
    guard = read("backend/api/app/services/prototype_api_guard.py")
    require("RECOVERYSENSE_ENABLE_PROTOTYPE_API" in guard, "unauthenticated engineering API requires explicit opt-in")
    persistence = read("backend/api/app/services/prediction_record_service.py")
    require('"participant_display_allowed": True' in persistence and '"demo_only": False' in persistence, "server-authored real predictions carry explicit participant-display provenance")
    require('"prediction_basis": "sensor_window_plus_prior_context"' in persistence, "server records sensor-window prediction basis")
    require('"current_ema_direct_input": False' in persistence and '"ema_role": "training_and_validation_label"' in persistence, "server distinguishes EMA label role from current prediction input")
    require('"input_modalities": _input_modalities(reading)' in persistence and '"schema_version": 2' in persistence, "server records schema-2 input modality provenance")

    # Firestore/export contracts.
    rules = read("firebase/firestore.rules")
    require("match /baseline_assessments/{assessmentId}" in rules and "allow update, delete: if false;" in rules, "baseline write-once behavior is enforced by Firestore rules")
    for collection in ("risk_predictions", "model_predictions", "trigger_events"):
        require(f"match /{collection}/" in rules and "allow write: if false;" in rules, f"client writes are denied for server-authored {collection}")
    require("match /sleep_logs/{logId}" in rules and "allow create, update, delete: if false;" in rules, "legacy sleep_logs are read-only")

    export_service = read("apps/phone_flutter_new/lib/services/export/research_data_export_service.dart")
    require("Source.server" in export_service, "research export requests server-backed Firestore records")
    require("synthetic_labels_added': false" in export_service, "research export declares that no synthetic labels are added")
    require("baseline_assessments.csv" in export_service, "research export includes baseline assessments")
    require("local_minute_of_day" in export_service and "timezone_offset_minutes" in export_service, "research export preserves local EMA timing metadata")
    require("raw_heart_rate" in export_service and "heart_rate_quality_reason" in export_service, "research export includes HR quality provenance")
    require("storageSchemaVersion" in export_service and ">= 5" in export_service, "phone export avoids double-inverting normalized legacy watch batches")
    require("exportSchemaVersion = 3" in export_service, "research ZIP export schema is 3")
    sleep_epoch = read("apps/phone_flutter_new/lib/models/sleep_epoch.dart")
    require("rules-v2-hr-quality" in sleep_epoch and "heart_rate_quality_semantics_version" in sleep_epoch, "new phone-derived sleep epochs carry corrected HR-quality semantics provenance")

    # Repository/project hygiene.
    require(not (ROOT / "apps/wear_android/app").exists(), "obsolete sibling Wear OS project is absent")
    require(not (ROOT / "apps/watch_ios/RecoverySenseWatch/Views/WatchDashboardView.swift").exists(), "TODO-only Apple Watch dashboard placeholder is absent")
    require((ROOT / ".gitignore").is_file(), "repository-wide .gitignore exists")
    require(not (ROOT / "apps/phone_flutter_new/lib/services/sensors/mock_sensor_service.dart").exists(), "unused mock sensor service is absent")
    require(not (ROOT / "apps/phone_flutter_new/lib/models/sensor_snapshot.dart").exists(), "unused mock sensor snapshot model is absent")

    verify_dart_imports()
    verify_source_hygiene()
    verify_transport_contracts()
    verify_structured_files()

    required_docs = [
        "CHANGELOG.md",
        "docs/CURRENT_DOCUMENTATION_INDEX.md",
        "docs/ARCHITECTURE.md",
        "docs/EMA_QUESTIONS.md",
        "docs/ML_FRAMEWORK_GUIDE.md",
        "docs/HEART_RATE_QUALITY_LAYER.md",
        "docs/SLEEP_TRACKING_AND_MODEL.md",
        "docs/PPG_READINESS.md",
        "docs/RESEARCH_RELEASE_CHECKLIST.md",
        "docs/COMPETITIVE_UX_BENCHMARK_0.5.1.md",
        "docs/UI_DESIGN_SYSTEM_0.5.3.md",
        "docs/UI_DESIGN_SYSTEM_0.5.1.md",
        "docs/RESEARCH_UX_AUDIT_0.5.1.md",
        "apps/wear_android/ACTIVE_PROJECT.md",
        "updates/UPDATE_0.4.2_RESEARCH_HARDENING.md",
        "updates/UPDATE_0.5.0_PERSONALIZED_RISK_DASHBOARD.md",
        "updates/UPDATE_0.5.3_UI_CLEANUP.md",
        "updates/UPDATE_0.5.2_HEART_RATE_QUALITY.md",
        "updates/UPDATE_0.5.1_RESEARCH_UX_POLISH.md",
    ]
    for relative in required_docs:
        require((ROOT / relative).is_file(), f"required release document exists: {relative}")

    print("RecoverySense static research audit")
    print("=" * 39)
    for message in PASSES:
        print(f"PASS: {message}")
    if FAILURES:
        for message in FAILURES:
            print(f"FAIL: {message}", file=sys.stderr)
        print(f"\n{len(FAILURES)} check(s) failed; {len(PASSES)} passed.", file=sys.stderr)
        return 1
    print(f"\nAll {len(PASSES)} static checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
