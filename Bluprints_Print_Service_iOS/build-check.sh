#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift test
xcodebuild -project BluprintsPrintService.xcodeproj -scheme BluprintsPrintService -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
