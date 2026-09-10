# RecoverySense GitHub cleanup plan

This plan keeps the current source and research provenance while removing local,
generated, and duplicate clutter. It deliberately does not delete participant
records, credentials outside the repository, current source, or historical
version manifests.

## Recommended repository structure

```text
apps/
  phone_flutter_new/            Shared Flutter phone UI for Android and iOS
  wear_android/wear_android/    Active Galaxy Watch app
  watch_ios/                    Active Apple Watch source embedded in Runner.xcodeproj
backend/api/                    Optional fail-closed engineering API
firebase/                       Current Firestore rules and prototype notes
ml/                             Export, feature, sleep, training, and evaluation code
docs/                           Current documentation plus an archive folder
updates/                        Versioned update manifests
scripts/                        Setup, audit, cleanup, and validation scripts
```

## Keep as the current source of truth

- `README.md`
- `CURRENT_BUILD_INFO.txt`
- `docs/CURRENT_DOCUMENTATION_INDEX.md`
- `docs/ARCHITECTURE.md`
- `docs/UI_DESIGN_SYSTEM_0.5.3.md`
- `docs/ML_FRAMEWORK_GUIDE.md`
- `docs/HEART_RATE_QUALITY_LAYER.md`
- `docs/SLEEP_TRACKING_AND_MODEL.md`
- `docs/PPG_READINESS.md`
- `docs/IOS_IMPLEMENTATION.md`
- `updates/`

## Archive rather than delete

Move older planning documents into `docs/archive/` in a dedicated cleanup
commit after checking internal links:

- `docs/START_HERE.md`
- `docs/Start Here.md`
- `docs/FIREBASE_NEXT_STEPS.md`
- `docs/Firebase Later.md`
- `docs/WEEK4_TASKS.md`
- `docs/Week 4 Scope.md`
- `docs/WHAT_CHANGED_FROM_EMPTY_REPO.md`
- `docs/WHAT_CHANGED_FROM_BREATHE.md`
- superseded UI design documents after the current index is updated

Do not mix this documentation move with functional phone/watch changes. A
separate commit makes review and rollback easier.

## Remove from Git

The included `scripts/cleanup_github_repo.ps1` reports these first and removes
them only when run with `-Apply`:

- Flutter/Gradle/Xcode/Python build caches
- `local.properties`
- generated Flutter Apple environment files
- Python bytecode, pytest caches, and egg metadata
- empty obsolete sibling Wear OS directories

Model bundles, reports, and processed datasets are **not** removed by the
default cleanup. They may contain validated scientific outputs. Preserve needed
artifacts first, then add `-RemoveGeneratedMLArtifacts` only when you have
decided they are reproducible/disposable or stored through Git LFS, a release,
or controlled research storage.

If a generated file is already tracked, `.gitignore` alone is not enough. After
reviewing the dry run, use the script and commit the removals.

## Credentials and Firebase files

Never commit:

- Firebase Admin service-account JSON
- Apple signing certificates or provisioning profiles
- Android keystores
- `.env` files containing secrets

`GoogleService-Info.plist` and `google-services.json` contain app/project
identifiers rather than Admin credentials, but a public repository should still
use deliberate project policy. The provided iOS package includes only
`GoogleService-Info.plist.example`; obtain the real file from the Firebase
project during local setup.

## Git workflow

1. Create a safety tag before cleanup.
2. Put generated-file cleanup in one commit.
3. Put documentation moves in a second commit.
4. Put iOS parity/export fixes in a third commit.
5. Run static audits and platform builds before merging.

Suggested commands:

```powershell
git status --short
git tag pre-ios-parity-0.5.3.4
.\scripts\cleanup_github_repo.ps1
.\scripts\cleanup_github_repo.ps1 -Apply
# Optional only after preserving validated artifacts:
.\scripts\cleanup_github_repo.ps1 -Apply -RemoveGeneratedMLArtifacts
git status --short
python .\scripts\repository_quality_audit.py
python .\scripts\research_static_audit.py
python .\scripts\verify_ios_contract.py
```

## CI recommendation

Add GitHub Actions jobs for:

- Python ML tests
- backend tests
- repository/static audits
- `flutter analyze` and Flutter tests
- Android phone build
- Wear OS Gradle build

An iOS/watchOS compile job requires a macOS runner, Firebase configuration for
CI, and signing decisions. Keep physical HealthKit/WatchConnectivity tests as a
separate paired-device release gate.
