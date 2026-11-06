#!/usr/bin/env bash
# One-step setup on a Mac: installs XcodeGen if needed, runs the core tests,
# generates WristPong.xcodeproj and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must run on macOS (Xcode is required to build iPhone/Watch apps)." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to install XcodeGen: https://brew.sh" >&2
    exit 1
  fi
  echo "==> Installing XcodeGen"
  brew install xcodegen
fi

if [[ ! -f Config/Local.xcconfig ]]; then
  cp Config/Local.xcconfig.example Config/Local.xcconfig
  echo "==> Created Config/Local.xcconfig - edit APP_BUNDLE_ID (and optionally DEVELOPMENT_TEAM), then re-run."
  echo "    (Continuing with the defaults so the project still generates.)"
fi

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "==> Running core unit tests"
  (cd Packages/PongCore && swift test)
fi

echo "==> Generating WristPong.xcodeproj"
xcodegen generate

echo "==> Done. Opening Xcode..."
open WristPong.xcodeproj
