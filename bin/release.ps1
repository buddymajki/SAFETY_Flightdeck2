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
    [string]$group = "testers"        # Firebase App Distribution csoport neve
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
# 2. Flutter release APK build
# ---------------------------------------------------------------
Log "Building release APK..."
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Err "Flutter build failed" }
Success "APK built: $APK_PATH"

# ---------------------------------------------------------------
# 3. Firebase App Distribution – feltöltés
#    A teszterek automatikusan emailt kapnak!
# ---------------------------------------------------------------
Log "Uploading to Firebase App Distribution (group: $group)..."
firebase appdistribution:distribute $APK_PATH `
    --app $FIREBASE_APP_ID `
    --groups $group `
    --release-notes $notes
if ($LASTEXITCODE -ne 0) { Err "Firebase App Distribution upload failed" }
Success "APK uploaded to Firebase App Distribution"

# ---------------------------------------------------------------
# 4. Firestore frissítés – app_updates/latest
#    Az app ebből tudja, hogy van-e frissítés!
# ---------------------------------------------------------------
Log "Updating Firestore app_updates/latest..."

# Firebase access token megszerzése a CLI-tól
$token = (firebase auth:print-access-token 2>$null).Trim()
if ([string]::IsNullOrEmpty($token)) {
    Write-Host "[WARN] Could not get Firebase token. Trying gcloud..." -ForegroundColor Yellow
    $token = (gcloud auth print-access-token 2>$null).Trim()
}

if ([string]::IsNullOrEmpty($token)) {
    Write-Host "[WARN] Could not get access token. Firestore update SKIPPED." -ForegroundColor Yellow
    Write-Host "       Manually update Firestore: app_updates/latest -> version: $ver" -ForegroundColor Yellow
} else {
    $firestoreUrl = "https://firestore.googleapis.com/v1/projects/$FIREBASE_PROJECT/databases/(default)/documents/app_updates/latest"
    $body = @{
        fields = @{
            version       = @{ stringValue = $ver }
            changelog     = @{ stringValue = $notes }
            isForceUpdate = @{ booleanValue = $forceUpdate }
        }
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $firestoreUrl `
            -Method PATCH `
            -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
            -Body $body | Out-Null
        Success "Firestore updated: app_updates/latest -> version=$ver"
    } catch {
        Write-Host "[WARN] Firestore update failed: $_" -ForegroundColor Yellow
        Write-Host "       Manually update: app_updates/latest -> version: $ver" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------
# 5. Git commit + tag + push
# ---------------------------------------------------------------
Log "Committing and pushing to git..."
git add .
git commit -m "Release v$ver"
if ($LASTEXITCODE -ne 0) { Err "git commit failed" }

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
