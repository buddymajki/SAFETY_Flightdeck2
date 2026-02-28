#!/bin/sh
set -e

echo "=== ci_post_clone.sh START ==="
echo "CI_PRIMARY_REPOSITORY_PATH: $CI_PRIMARY_REPOSITORY_PATH"
echo "CI_WORKSPACE: $CI_WORKSPACE"

# Use the primary repository path (the cloned repo root)
REPO_DIR="${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE}"
cd "$REPO_DIR"

# Install Flutter SDK to /tmp so it doesn't conflict with the repo
FLUTTER_DIR="/tmp/flutter_sdk"
if [ ! -d "$FLUTTER_DIR" ]; then
  echo "=== Cloning Flutter SDK ==="
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
else
  echo "=== Flutter SDK already exists, skipping clone ==="
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

echo "=== Flutter version ==="
flutter --version

echo "=== Flutter precache --ios ==="
flutter precache --ios

echo "=== Flutter pub get ==="
flutter pub get

echo "=== Installing CocoaPods ==="
export HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods || true

echo "=== Pod install ==="
cd "$REPO_DIR/ios" && pod install

echo "=== ci_post_clone.sh DONE ==="
