# PowerShell script to simulate paragliding flight on Android Emulator
# This sends real GPS coordinates with ALTITUDE to the emulator via ADB
# Usage: .\simulate_flight.ps1

# Find ADB path - try common locations
$adbPaths = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
    "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk\platform-tools\adb.exe"
)

$adbPath = $null
foreach ($path in $adbPaths) {
    if (Test-Path $path) {
        $adbPath = $path
        break
    }
}

if (-not $adbPath) {
    Write-Host "ERROR: Could not find ADB. Please ensure Android SDK is installed." -ForegroundColor Red
    Write-Host "Tried paths:" -ForegroundColor Yellow
    $adbPaths | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "Found ADB at: $adbPath" -ForegroundColor Green

# Flight data from TEST.igc (real paraglider flight)
# Format: lat, lon, altitude (meters), delay_ms
# NOTE: Use 5000ms (5s) delays to match real GPS recording intervals
# This ensures calculated speeds match real-world values
$flightPoints = @(
    # Takeoff phase - starting at ~1100m, descending (sled ride)
    @(46.88103, 8.36563, 1103, 5000),
    @(46.88118, 8.36590, 1095, 5000),
    @(46.88143, 8.36637, 1090, 5000),
    @(46.88167, 8.36672, 1086, 5000),
    @(46.88200, 8.36692, 1083, 5000),
    @(46.88222, 8.36708, 1078, 5000),
    @(46.88223, 8.36733, 1072, 5000),
    @(46.88207, 8.36755, 1069, 5000),
    @(46.88217, 8.36803, 1062, 5000),
    @(46.88207, 8.36837, 1058, 5000),
    @(46.88193, 8.36883, 1049, 5000),
    @(46.88208, 8.36922, 1046, 5000),
    @(46.88225, 8.36968, 1038, 5000),
    @(46.88257, 8.36997, 1035, 5000),
    @(46.88292, 8.36998, 1027, 5000),
    @(46.88307, 8.37028, 1020, 5000),
    @(46.88280, 8.37082, 1016, 5000),
    @(46.88250, 8.37122, 1010, 5000),
    @(46.88245, 8.37173, 1003, 5000),
    @(46.88240, 8.37247, 998, 5000),
    @(46.88240, 8.37332, 989, 5000),
    @(46.88240, 8.37415, 980, 5000),
    @(46.88247, 8.37552, 968, 5000),
    @(46.88255, 8.37660, 957, 5000),
    @(46.88277, 8.37728, 949, 5000),
    @(46.88330, 8.37765, 941, 5000),
    @(46.88357, 8.37795, 933, 5000),
    
    # Thermal/sink patterns (mid-flight)
    @(46.88340, 8.37800, 916, 5000),
    @(46.88352, 8.37797, 885, 5000),
    @(46.88323, 8.37763, 873, 5000),
    @(46.88378, 8.37773, 867, 5000),
    @(46.88422, 8.37805, 860, 5000),
    @(46.88475, 8.37818, 840, 5000),
    @(46.88448, 8.37838, 820, 5000),
    @(46.88487, 8.37857, 813, 5000),
    @(46.88475, 8.37830, 786, 5000),
    @(46.88525, 8.37865, 777, 5000),
    @(46.88513, 8.37925, 765, 5000),
    @(46.88450, 8.37912, 754, 5000),
    @(46.88388, 8.37870, 745, 5000),
    @(46.88338, 8.37833, 738, 5000),
    @(46.88305, 8.37788, 732, 5000),
    @(46.88248, 8.37738, 720, 5000),
    @(46.88213, 8.37745, 702, 5000),
    @(46.88192, 8.37747, 647, 5000),
    @(46.88220, 8.37755, 639, 5000),
    @(46.88203, 8.37755, 624, 5000),
    @(46.88268, 8.37812, 613, 5000),
    @(46.88330, 8.37862, 601, 5000),
    @(46.88385, 8.37867, 590, 5000),
    @(46.88400, 8.37835, 586, 5000),
    @(46.88377, 8.37778, 572, 5000),
    @(46.88348, 8.37747, 562, 5000),
    @(46.88312, 8.37712, 549, 5000),
    
    # Final approach - slowing down
    @(46.88297, 8.37698, 547, 5000),
    @(46.88297, 8.37685, 548, 5000),
    @(46.88297, 8.37682, 548, 5000),
    
    # Landed - stationary for 10+ seconds (landing detection trigger)
    @(46.88298, 8.37682, 548, 2000),
    @(46.88298, 8.37682, 548, 2000),
    @(46.88298, 8.37682, 548, 2000),
    @(46.88298, 8.37682, 548, 2000),
    @(46.88298, 8.37682, 548, 2000),
    @(46.88298, 8.37682, 548, 2000)
)

Write-Host "=== Paraglider Flight Simulation ===" -ForegroundColor Cyan
Write-Host "Flight: TEST.igc - Sled ride from 1103m to 548m" -ForegroundColor Cyan
Write-Host "Total altitude loss: ~555m" -ForegroundColor Cyan
Write-Host ""
Write-Host "Make sure:" -ForegroundColor Yellow
Write-Host "1. Android Emulator is running" -ForegroundColor Yellow
Write-Host "2. FlightDeck app is open on GPS screen" -ForegroundColor Yellow
Write-Host "3. GPS tracking is started" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Press Enter to start simulation (Ctrl+C to cancel)"

$pointIndex = 0
$totalPoints = $flightPoints.Count

foreach ($point in $flightPoints) {
    $lat = $point[0]
    $lon = $point[1]
    $alt = $point[2]
    $delay = $point[3]
    
    $pointIndex++
    $progress = [math]::Round(($pointIndex / $totalPoints) * 100)
    
    # Send location via ADB (geo fix command: lon lat [alt])
    # Note: geo fix uses longitude FIRST, then latitude!
    $cmd = "geo fix $lon $lat $alt"
    
    Write-Host "[$progress%] Point $pointIndex/$totalPoints : Lat=$lat, Lon=$lon, Alt=${alt}m" -ForegroundColor Green
    
    # Execute via ADB shell to the emulator
    & $adbPath emu $cmd 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: ADB command failed. Is emulator running?" -ForegroundColor Red
        Write-Host "Try running: & '$adbPath' devices" -ForegroundColor Yellow
    }
    
    Start-Sleep -Milliseconds $delay
}

Write-Host ""
Write-Host "=== Simulation Complete ===" -ForegroundColor Cyan
Write-Host "Check the FlightDeck app - flight should have been detected!" -ForegroundColor Green
Write-Host ""
Write-Host "Expected behavior:" -ForegroundColor Yellow
Write-Host "  - Takeoff detected after ~5 seconds (speed + altitude change)" -ForegroundColor Yellow
Write-Host "  - Landing detected after ~10 seconds of being stationary" -ForegroundColor Yellow
