#!/usr/bin/env python3
"""Inventory every RecoverySense repository file and apply release-quality checks.

The audit is deliberately explicit about scope: authored text/source files receive
static integrity checks; binaries receive inventory/hash checks only. Flutter
platform scaffolds that are not current release targets are retained but marked
informational rather than being presented as validated applications.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TEXT_SUFFIXES = {
    ".dart", ".kt", ".kts", ".java", ".py", ".swift", ".xml", ".yaml", ".yml",
    ".json", ".md", ".txt", ".ps1", ".sh", ".gradle", ".properties", ".toml",
    ".cmake", ".cc", ".cpp", ".c", ".h", ".hpp", ".plist", ".xcconfig",
    ".pbxproj", ".xcscheme", ".storyboard", ".xib", ".html",
}
BINARY_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".jar", ".aar", ".zip"}
ACTIVE_SOURCE_PREFIXES = (
    "apps/phone_flutter_new/lib/",
    "apps/phone_flutter_new/android/app/src/main/",
    "apps/wear_android/wear_android/app/src/main/",
    "backend/api/app/",
    "ml/src/recoverysense_ml/",
)
TEST_PREFIXES = ("ml/tests/", "backend/api/tests/")
CURRENT_DOCS = {
    "README.md", "CHANGELOG.md", "CURRENT_BUILD_INFO.txt", "CURRENT_UPDATE_SUMMARY.md",
    "RECOVERYSENSE_UPDATE_SUMMARY.md", "docs/ARCHITECTURE.md",
    "docs/CURRENT_DOCUMENTATION_INDEX.md", "docs/EMA_QUESTIONS.md",
    "docs/ML_FRAMEWORK_GUIDE.md", "docs/PPG_READINESS.md",
    "docs/RESEARCH_RELEASE_CHECKLIST.md", "docs/HEART_RATE_QUALITY_LAYER.md",
    "docs/SLEEP_TRACKING_AND_MODEL.md", "firebase/README.md",
    "apps/phone_flutter_new/README.md", "apps/wear_android/ACTIVE_PROJECT.md",
    "apps/wear_android/wear_android/README.md", "apps/watch_ios/README.md",
    "updates/UPDATE_0.5.3_UI_CLEANUP.md",
    "docs/UI_DESIGN_SYSTEM_0.5.3.md",
}
RELEASE_VERSION_DOCS = {
    "CURRENT_BUILD_INFO.txt",
    "CURRENT_UPDATE_SUMMARY.md",
    "RECOVERYSENSE_UPDATE_SUMMARY.md",
    "docs/UI_DESIGN_SYSTEM_0.5.3.md",
    "updates/UPDATE_0.5.3_UI_CLEANUP.md",
}
HISTORICAL_DOC_NAMES = {
    "START_HERE_FIREBASE.md", "START_HERE_ML.md",
    "docs/FIREBASE_NEXT_STEPS.md", "docs/Firebase Later.md", "docs/START_HERE.md",
    "docs/Start Here.md", "docs/WEEK4_TASKS.md", "docs/Week 4 Scope.md",
    "docs/WHAT_CHANGED_FROM_BREATHE.md", "docs/WHAT_CHANGED_FROM_EMPTY_REPO.md",
    "docs/RESEARCH_AUDIT_0.4.2.md", "docs/RESEARCH_VALIDATION_0.5.0.md",
    "docs/UI_DESIGN_SYSTEM_0.5.0.md", "updates/UPDATE_0.4.2_RESEARCH_HARDENING.md",
    "updates/UPDATE_0.5.0_PERSONALIZED_RISK_DASHBOARD.md",
    "updates/UPDATE_0.5.1_RESEARCH_UX_POLISH.md",
    "docs/RESEARCH_UX_AUDIT_0.5.1.md", "docs/COMPETITIVE_UX_BENCHMARK_0.5.1.md",
    "docs/UI_DESIGN_SYSTEM_0.5.1.md",
    "updates/UPDATE_0.5.2_HEART_RATE_QUALITY.md",
}
INACTIVE_FLUTTER_PREFIXES = (
    "apps/phone_flutter_new/ios/", "apps/phone_flutter_new/macos/",
    "apps/phone_flutter_new/linux/", "apps/phone_flutter_new/windows/",
    "apps/phone_flutter_new/web/",
)
GENERATED_NAMES = {"__pycache__", ".pytest_cache", ".dart_tool", "build", ".gradle", ".idea"}
SECRET_RE = re.compile(r"(?:service[-_]?account|credential|secret|private[-_]?key|\.pem$|\.p12$|\.jks$|\.keystore$|\.key$)", re.I)
CONFLICT_RE = re.compile(r"^(?:<<<<<<<|=======|>>>>>>>)(?: .*)?$", re.M)
TODO_RE = re.compile(r"\b(?:TODO|FIXME|HACK|XXX)\b")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify(relative: str, path: Path) -> str:
    if relative in CURRENT_DOCS:
        return "current_documentation"
    if relative in HISTORICAL_DOC_NAMES or relative.startswith("updates/UPDATE_0.4") or relative.startswith("updates/UPDATE_0.5.0"):
        return "historical_documentation"
    if relative.startswith(ACTIVE_SOURCE_PREFIXES):
        return "active_source"
    if relative.startswith(TEST_PREFIXES):
        return "test_source"
    if relative.startswith(INACTIVE_FLUTTER_PREFIXES):
        return "inactive_flutter_scaffold"
    if relative.endswith("local.properties"):
        return "machine_local_configuration"
    if relative.startswith(("ml/config/", "firebase/", "backend/api/", "scripts/", "apps/phone_flutter_new/android/", "apps/wear_android/wear_android/")):
        return "build_or_runtime_configuration"
    if path.suffix.lower() in BINARY_SUFFIXES:
        return "binary_asset_or_dependency"
    if path.suffix.lower() in {".md", ".txt"}:
        return "supporting_documentation"
    return "other"


def inspect(path: Path, relative: str, category: str) -> tuple[str, str, str]:
    checks: list[str] = ["sha256"]
    notes: list[str] = []
    status = "PASS"

    if any(part in GENERATED_NAMES for part in path.parts):
        return "FAIL", "generated/cache artifact detected", "generated build/cache directories must not be packaged"

    if SECRET_RE.search(relative) and not relative.endswith("google-services.json"):
        status = "FAIL"
        notes.append("filename resembles a secret/private credential; manually verify and remove from release")

    if category == "machine_local_configuration":
        status = "INFO" if status == "PASS" else status
        notes.append("machine-local file; ignored by version control and not portable release source")

    if category == "inactive_flutter_scaffold":
        status = "INFO" if status == "PASS" else status
        notes.append("retained Flutter-generated scaffold; not a configured/validated RecoverySense release target")

    if category == "historical_documentation":
        status = "INFO" if status == "PASS" else status
        notes.append("historical/provenance document; current specifications are listed in CURRENT_DOCUMENTATION_INDEX.md")

    is_text = path.suffix.lower() in TEXT_SUFFIXES or path.name in {"gradlew", ".gitignore", ".metadata"}
    if is_text:
        checks.extend(["utf8", "merge_markers"])
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            return "FAIL", ";".join(checks), "; ".join(notes + ["text file is not valid UTF-8"])
        if CONFLICT_RE.search(text):
            status = "FAIL"
            notes.append("unresolved merge-conflict marker")
        if category in {"active_source", "test_source"}:
            checks.append("nonempty")
            if not text.strip():
                status = "FAIL"
                notes.append("empty active/test source")
        if category == "active_source":
            checks.append("todo_markers")
            if TODO_RE.search(text):
                status = "WARN" if status == "PASS" else status
                notes.append("TODO/FIXME/HACK marker remains in active source")
        if relative in RELEASE_VERSION_DOCS:
            checks.append("current_version_marker")
            if "0.5.3" not in text:
                status = "WARN" if status == "PASS" else status
                notes.append("release-version document does not contain an explicit 0.5.3 marker")
    else:
        checks.append("binary_inventory_only")
        if category == "binary_asset_or_dependency":
            notes.append("binary content inventoried/hashed only; semantic correctness requires the relevant build/toolchain")

    if relative == "apps/wear_android/wear_android/app/libs/samsung-health-sensor-api-1.4.1.aar":
        status = "INFO" if status == "PASS" else status
        notes.append("versioned Samsung SDK AAR is staged but not loaded by active Gradle filename; raw PPG remains disabled")

    if relative == "apps/phone_flutter_new/pubspec.lock":
        try:
            text = path.read_text(encoding="utf-8")
            if "\n  archive:" not in text or "\n  share_plus:" not in text:
                status = "WARN" if status == "PASS" else status
                notes.append("lockfile predates current export dependencies; run flutter pub get on the development machine before build/release")
        except UnicodeDecodeError:
            pass

    if relative.endswith("google-services.json"):
        notes.append("Firebase client configuration; not a service-account private key")

    return status, ";".join(checks), "; ".join(notes)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="Write the complete file-level audit CSV")
    args = parser.parse_args()

    rows: list[dict[str, str | int]] = []
    for path in sorted(p for p in ROOT.rglob("*") if p.is_file()):
        relative = path.relative_to(ROOT).as_posix()
        category = classify(relative, path)
        status, checks, notes = inspect(path, relative, category)
        rows.append({
            "path": relative,
            "file_type": path.suffix.lower() or "no_extension",
            "category": category,
            "status": status,
            "checks": checks,
            "notes": notes,
            "size_bytes": path.stat().st_size,
            "sha256": sha256(path),
        })

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    counts: dict[str, int] = {}
    for row in rows:
        counts[str(row["status"])] = counts.get(str(row["status"]), 0) + 1
    print(f"RecoverySense all-file audit: {len(rows)} files")
    for key in ("PASS", "INFO", "WARN", "FAIL"):
        print(f"{key}: {counts.get(key, 0)}")
    problems = [row for row in rows if row["status"] in {"WARN", "FAIL"}]
    for row in problems:
        print(f"{row['status']}: {row['path']} — {row['notes']}")
    return 1 if counts.get("FAIL", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
