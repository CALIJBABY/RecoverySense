# RecoverySense update 0.5.3.4 - iOS parity, export stability, and repository hygiene

## Scope

This update applies the previously created iPhone/Apple Watch implementation to
the current 0.5.3 Flutter/ML/backend tree. It does not replace or fork the phone
UI; the iPhone runs the same current Flutter screens as Android.

## iPhone and Apple Watch

- Restores the embedded `RecoverySenseWatch` Xcode target and Swift bridge.
- Updates Apple Watch sensor payloads from schema 4 to schema 5.
- Adds raw/analysis heart-rate separation, validity, quality code, stale check,
  and temporal-outlier provenance.
- Adds the current EMA local-minute/time-zone fields and schema 2.
- Uses the preferred stacked watch sensor cards with `#4F9B17` and white text.
- Changes the watch step display to **Steps Today**.
- Queries `CMPedometer` from local midnight and restarts after a day rollover.
- Changes iPhone pending replay from all-at-once to one-at-a-time until ACK.
- Updates the watch target to marketing version 0.5.3/build 7.

## Research export stability

- Moves ZIP compression to `Isolate.run`.
- Always provides a non-zero share-sheet origin.
- Supplies MIME type `application/zip`.
- Stops deleting the temporary ZIP immediately after `share` returns.
- Retains existing stale-file cleanup before the next export.

The archived crash did not contain a native stack trace, so these changes fix
concrete source-level risks rather than claiming a proven single root cause.

## Repository hygiene

- Adds `GITHUB_CLEANUP_PLAN.md`.
- Adds a dry-run-by-default PowerShell cleanup script.
- Removes packaged local properties and generated caches from this archive.
- Keeps historical documents and version manifests for provenance.

## Validation limits

Swift source is parser-checked and contracts are statically verified. Xcode,
CocoaPods, code signing, Firebase Apple setup, and physical iPhone/Apple Watch
testing require a Mac and paired devices.
