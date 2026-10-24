#!/bin/bash
# Usage: scripts/verify.sh <label>
# Generates the project, runs core tests, builds for the simulator, then runs the app unit tests
# on a temporary simulator that is deleted afterwards.
set -euo pipefail
# Xcode-beta (the default xcode-select) hangs the simulator test runner; use the release Xcode.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LABEL="${1:?usage: scripts/verify.sh <label>}"
cd "$(dirname "$0")/.."
xcodegen generate
swift test --package-path Packages/SheafnoteCore
xcodebuild -project Sheafnote.xcodeproj -scheme Sheafnote -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ".derived/$LABEL" CODE_SIGNING_ALLOWED=NO build
UDID=$(xcrun simctl create "sheafnote-$LABEL" "iPad Air 13-inch (M4)" com.apple.CoreSimulator.SimRuntime.iOS-26-5)
trap 'xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
xcodebuild -project Sheafnote.xcodeproj -scheme Sheafnote -destination "id=$UDID" \
  -derivedDataPath ".derived/$LABEL" CODE_SIGNING_ALLOWED=NO test -only-testing:SheafnoteTests
echo "verify: OK"
