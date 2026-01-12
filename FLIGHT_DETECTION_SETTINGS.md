# Flight Detection Settings & Thresholds

## Location: `lib/services/flight_detection_service.dart` (Lines 1-30)

### Takeoff Detection Thresholds
- **`takeoffHorizontalSpeedThreshold`**: 2.0 m/s
  - Minimum forward speed to trigger takeoff detection
  
- **`takeoffVerticalSpeedThreshold`**: 0.5 m/s
  - *(Currently unused - simplified to horizontal speed only)*

### Landing Detection Thresholds
- **`landingSpeedThreshold`**: 1.0 m/s
  - Maximum horizontal speed to detect landing (slow gliding descent allowed)
  
- **`landingDescentThreshold`**: 2.0 m/s
  - Maximum vertical descent rate for landing detection (allows natural descent)
  
- **`landingConfirmationSeconds`**: 5 seconds
  - Duration of sustained low speed to confirm landing

---

## Auto-Close Flight Feature

### Location: `lib/services/flight_tracking_service.dart` (Line 51)

```dart
static const Duration autoCloseFlightTimeout = Duration(seconds: 10);
```

### What It Does
- **Automatically completes an active flight** if no GPS position updates are received for 10 seconds
- Uses the last known position as landing location
- Saves flight as **COMPLETED** (not cancelled) with landing coordinates
- Triggers when a KML tracklog file ends or simulation stops
- Prevents "stuck in flight" status when data source runs out

### How It Works
1. **Flight starts** (takeoff detected) → Timer starts
2. **Position updates received** → Timer resets
3. **No updates for 10 seconds** → Flight auto-closes with:
   - Status: **COMPLETED**
   - Landing time: Last position timestamp
   - Landing site: Nearest site or coordinates
   - Landing coordinates: Last GPS position
   - Complete flight record saved

### ⚠️ IMPORTANT NOTE
This 10-second timeout is designed for **testing with tracklog files**. In real-world flying:
- Should be 5-10+ minutes
- Accounts for GPS signal loss, tunnels, etc.
- Should only close if completely disconnected from GPS

**For production, change:**
```dart
static const Duration autoCloseFlightTimeout = Duration(minutes: 5); // or higher
```

---

## How the Features Work Together

### Landing Not Detected in KML Files?
The auto-close feature automatically closes the flight after the tracklog ends, saving a complete flight record with:
- ✅ Takeoff location and coordinates
- ✅ Landing location and coordinates  
- ✅ Flight duration
- ✅ Status: COMPLETED (not CANCELLED)

### Landing Detection Challenges
1. **Requires 5 seconds** of sustained low speed (horizontal < 1.0 m/s, vertical < 2.0 m/s)
2. **KML files may end before** sustained low-speed phase is recorded
3. **Solution**: Auto-close feature completes the flight using the last position as landing

### Recommended For Better Landing Detection
- Increase landing detection window from 5 to 10-15 seconds for test files
- Reduce thresholds if aircraft still moving at landing
- Use auto-close as fallback when landing not detected

---

## Testing
Run with your KML file:
1. Takeoff detected when speed > 2.0 m/s
2. Landing detected when speed slows + 5 seconds low-speed sustained
3. If landing not detected → Auto-closes after 10 seconds no updates
