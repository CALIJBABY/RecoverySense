#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PHONE="$REPO_ROOT/apps/phone_flutter_new"

for tool in flutter dart xcodebuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required command: $tool" >&2
    exit 1
  fi
done

cd "$PHONE"
flutter clean
flutter pub get

if ! grep -q "static const FirebaseOptions ios" lib/firebase_options.dart; then
  echo
  echo "Firebase iOS options are not configured yet. Run:"
  echo "  dart pub global activate flutterfire_cli"
  echo "  flutterfire configure --project=recoverysense --platforms=ios,android --ios-bundle-id=com.recoverysense.phone"
  echo
fi

# This Flutter scaffold uses the generated local Swift package rather than a
# committed CocoaPods Podfile. flutter pub get prepares the package metadata.


python3 "$REPO_ROOT/scripts/verify_ios_contract.py"

echo
echo "Open the integrated iPhone + Apple Watch workspace:"
echo "  open $PHONE/ios/Runner.xcworkspace"
echo
echo "Assign the same Development Team to Runner and RecoverySenseWatch."
echo "Run paired-device tests before collecting research data."
