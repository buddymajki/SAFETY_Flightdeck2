#!/bin/sh
set -e

echo "=== TestFlight-only export ==="

xcodebuild -exportArchive \
  -archivePath "$PWD/build/ios/archive/Runner.xcarchive" \
  -exportPath "$PWD/build/ios/export" \
  -exportOptionsPlist "$PWD/ios/ci_scripts/testflight-exportoptions.plist"

echo "=== TestFlight export finished ==="