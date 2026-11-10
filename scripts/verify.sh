#!/usr/bin/env bash
# CI-style gate: regenerate the project, run static checks, build, and run every test suite.
# Usage: scripts/verify.sh            (SIMULATOR="iPhone 17 Pro,OS=26.2" to override the device)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIMULATOR="${SIMULATOR:-iPhone 18 Pro,OS=27.2}"
DESTINATION="platform=iOS Simulator,name=${SIMULATOR}"
RESULTS="$ROOT/build/TestResults.xcresult"

step() { printf '\n==> %s\n' "$1"; }

step "Generate Xcode project"
xcodegen generate --quiet
if ! git diff --quiet -- TaskManager.xcodeproj; then
    echo "warning: TaskManager.xcodeproj changed after xcodegen; commit the regenerated project."
fi

step "Force unwrap check"
scripts/check_no_force_unwraps.sh

if command -v swiftlint >/dev/null 2>&1; then
    step "SwiftLint"
    swiftlint lint --quiet --strict
else
    echo "SwiftLint not installed; skipping (force unwrap script above still ran)."
fi

step "Build (Release config, warnings are errors)"
xcodebuild build -scheme TaskManager -configuration Release -destination "$DESTINATION" -quiet

step "Test (Debug, with coverage)"
rm -rf "$RESULTS"
xcodebuild test -scheme TaskManager -destination "$DESTINATION" -resultBundlePath "$RESULTS" -quiet

step "Coverage"
xcrun xccov view --report --only-targets "$RESULTS"

if [[ -f functions/package.json ]]; then
    step "Cloud Functions tests"
    (cd functions && npm ci --silent && npm test --silent)
fi

if [[ -f firebase/package.json ]] && command -v firebase >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    step "Security rules tests (emulator)"
    (cd firebase && npm ci --silent && npm test --silent)
fi

step "All checks passed"
