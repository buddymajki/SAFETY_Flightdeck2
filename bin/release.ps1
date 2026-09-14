# =============================================================
# FlightDeck Release Script
# Használat: .\bin\release.ps1 -ver "1.0.30" -notes "Bug fixes"
# Opcionális: -forceUpdate $true
#
# Mit csinál:
#   1. Verzió frissítés (pubspec.yaml + app_version_service.dart)
#   2. Flutter release APK build
#   3. Firebase App Distribution feltöltés (testers emailt kapnak)
#   4. Firestore app_updates/latest dokumentum frissítése
#      (az app ebből tudja, hogy van-e új verzió)
#   5. Git commit + tag + push
# =============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$ver,           # pl. "1.0.30"

    [Parameter(Mandatory=$false)]
    [string]$notes = "New release",   # changelog szöveg

    [Parameter(Mandatory=$false)]
    [bool]$forceUpdate = $false,      # kötelező frissítés-e

    [Parameter(Mandatory=$false)]
    [string]$group = "testers",       # Firebase App Distribution csoport neve

    [Parameter(Mandatory=$false)]
    [ValidateSet("android","ios","both")]
    [string]$platform = "android"     # platform: android, ios, or both
)

# ---------------------------------------------------------------
# KONFIGURÁCIÓ – módosítsd ha szükséges
# ---------------------------------------------------------------
$FIREBASE_APP_ID   = "1:598912312840:android:03bd8df4fa0de8a12013bd"
$FIREBASE_PROJECT  = "flightdeck-v2"
$APK_PATH          = "build\app\outputs\flutter-apk\app-release.apk"
# ---------------------------------------------------------------

$ErrorActionPreference = "Stop"

function Log($msg) { Write-Host "[release] $msg" -ForegroundColor Cyan }
function Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

Log "========================================"
Log "  FlightDeck Release v$ver"
Log "========================================"

# ---------------------------------------------------------------
# 1. Verzió frissítés
# ---------------------------------------------------------------
Log "Updating version to $ver..."
dart bin/update_version.dart
if ($LASTEXITCODE -ne 0) { Err "update_version.dart failed" }
Success "Version updated"

# ---------------------------------------------------------------
# 2. Build / Distribute / Firestore Update
# ---------------------------------------------------------------
$forceStr = if ($forceUpdate) { "true" } else { "false" }

if ($platform -eq "android" -or $platform -eq "both") {
    Log "Building Android release APK..."
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { Err "Flutter build failed" }
    Success "APK built: $APK_PATH"

    Log "Uploading Android to Firebase App Distribution (group: $group)..."
    firebase appdistribution:distribute $APK_PATH `
        --app $FIREBASE_APP_ID `
        --groups $group `
        --release-notes $notes
    if ($LASTEXITCODE -ne 0) { Err "Firebase App Distribution upload failed" }
    Success "APK uploaded to Firebase App Distribution"

    # A Firestore-írás NEM opcionális: ha ez kimarad, a telepített appok
    # sosem kapnak frissítés-értesítést (az app_updates dokumentum a jelzés).
    Log "Updating Firestore app_updates/android..."
    node bin/update_firestore.js $ver "$notes" $forceStr "android"
    if ($LASTEXITCODE -ne 0) {
        Err "Firestore update failed for app_updates/android. The APK is already uploaded to App Distribution, but nobody will be prompted to update. Run: firebase login; then: node bin/update_firestore.js $ver `"$notes`" $forceStr android"
    }
    Success "Firestore updated: app_updates/android -> version=$ver"

    Log "Updating Firestore app_updates/latest..."
    node bin/update_firestore.js $ver "$notes" $forceStr "latest"
    if ($LASTEXITCODE -ne 0) {
        Err "Firestore update failed for app_updates/latest. Run: node bin/update_firestore.js $ver `"$notes`" $forceStr latest"
    }
    Success "Firestore updated: app_updates/latest -> version=$ver"
}

if ($platform -eq "ios" -or $platform -eq "both") {
    Log "Updating Firestore app_updates/ios..."
    node bin/update_firestore.js $ver "$notes" $forceStr "ios"
    if ($LASTEXITCODE -ne 0) {
        Err "Firestore update failed for app_updates/ios. Run: node bin/update_firestore.js $ver `"$notes`" $forceStr ios"
    }
    Success "Firestore updated: app_updates/ios -> version=$ver"

    
    Log "NOTE: iOS release to TestFlight typically requires macOS/Xcode."
    Log "Please ensure you build and upload the iOS app to TestFlight manually, or it won't be available."
}

# ---------------------------------------------------------------
# 5. Git commit + tag + push
# ---------------------------------------------------------------
Log "Committing and pushing to git..."
# Csak a release által érintett fájlok (a `git add .` bármilyen félkész
# munkát és véletlenül bent maradt titkot is felvinne).
git add pubspec.yaml lib/services/app_version_service.dart metadata.json
git commit -m "Release v$ver"
if ($LASTEXITCODE -ne 0) { Err "git commit failed" }

Log "Pulling remote changes before push (rebase)..."
git pull --rebase origin master
if ($LASTEXITCODE -ne 0) { Err "git pull --rebase failed. Resolve conflicts manually and re-run." }

git tag "v$ver"
git push origin master
git push origin --tags
if ($LASTEXITCODE -ne 0) { Err "git push failed" }

Success "Git pushed and tagged v$ver"

# ---------------------------------------------------------------
# KÉSZ
# ---------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Release v$ver complete!" -ForegroundColor Green
Write-Host "  - APK: Firebase App Distribution (testers notified by email)" -ForegroundColor Green
Write-Host "  - Firestore: app_updates/latest updated" -ForegroundColor Green
Write-Host "  - Git: tagged and pushed" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
