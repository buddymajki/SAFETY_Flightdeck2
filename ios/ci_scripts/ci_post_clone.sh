#!/bin/sh
set -e

# The default execution directory of this script is the ci_scripts directory.
cd "$CI_WORKSPACE"

# Export HOME to avoid permission issues
export HOME="$CI_WORKSPACE"

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$CI_WORKSPACE/flutter"
export PATH="$CI_WORKSPACE/flutter/bin:$PATH"

# Install Flutter artifacts for iOS.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Install CocoaPods using Homebrew.
export HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods

# Install CocoaPods dependencies.
cd ios && pod install
