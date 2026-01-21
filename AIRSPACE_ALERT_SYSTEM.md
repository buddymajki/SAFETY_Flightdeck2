# Airspace Violation Alert System

## Overview
The system creates **ONE alert per flight** that tracks ALL airspace violations, including overlapping airspaces.

## Key Features

### 1. Single Flight-Level Alert
- **One alert per flight** instead of one alert per airspace
- Alert is created on the FIRST violation of the flight
- All subsequent violations are added to the same alert
- Admins see the alert immediately when pilot enters first restricted airspace

### 2. Overlapping Airspace Support ✅
**Problem Solved:** Previously, if a pilot was in Airspace A and B simultaneously, exiting A while still in B would prevent the system from closing A's violation.

**Solution:**
- `_activeViolations` Map tracks EACH zone independently
- `_currentFlightViolations` List stores the complete history of ALL zones
- When exiting a zone, we ONLY remove that specific zone from `_activeViolations`
- The exit data is recorded in the violations list
- `airspaceViolation` flag is TRUE if ANY zone is active (`_activeViolations.isNotEmpty`)

### 3. Real-Time Updates
- Alert updates in real-time as pilot enters/exits zones
- Admins see:
  - Total violation count
  - Currently active zones (pilot is in them NOW)
  - Complete history of all entries/exits with timestamps

### 4. Comprehensive Data Tracking
For each violation entry, we track:
- Zone ID, name, type, class
- Entry time, location (lat/lng), altitude
- Exit time, location (lat/lng), altitude (when completed)
- Duration in seconds
- Status: `in_progress` or `completed`

## Implementation Details

### AlertService Changes

#### New Fields
```dart
String? _currentFlightAlertId;  // ID of the single flight alert
final List<Map<String, dynamic>> _currentFlightViolations = [];  // All violations
```

#### Flow
1. **First Violation:**
   - `_createFlightSafetyAlert()` creates ONE alert
   - Stores alert ID in `_currentFlightAlertId`
   - Adds violation entry to `_currentFlightViolations`
   - Updates alert with entry data

2. **Additional Violations (Same Flight):**
   - Uses same `_currentFlightAlertId`
   - Adds new violation entry to `_currentFlightViolations`
   - Updates alert with all violations

3. **Exiting Airspace:**
   - Finds violation in `_currentFlightViolations` by zoneId
   - Updates with exit data
   - Removes from `_activeViolations` (but NOT from violations list)
   - Updates alert with complete data

4. **Flight End:**
   - `clearRecentAlerts()` resets everything for next flight
   - Next flight will get a NEW alert

### Alert Structure

```json
{
  "id": "alert_123",
  "alertType": "airspace_violation",
  "reason": "🚨 FLIGHT SAFETY ALERT\n\nTotal violations: 2\nCurrently in: NO\n\nVIOLATION HISTORY:\n1. Zone A...\n2. Zone B...",
  "metadata": {
    "airspaceViolation": true,
    "flightStartTime": "2026-01-21T10:30:00Z",
    "violations": [
      {
        "zoneId": "zone_1",
        "zoneName": "Zürich CTR",
        "zoneType": "CTR",
        "zoneClass": "D",
        "entryTime": "2026-01-21T10:35:00Z",
        "entryLatitude": 47.4563,
        "entryLongitude": 8.5482,
        "entryAltitude": 1500,
        "exitTime": "2026-01-21T10:38:00Z",
        "exitLatitude": 47.4612,
        "exitLongitude": 8.5521,
        "exitAltitude": 1520,
        "durationSeconds": 180,
        "status": "completed"
      },
      {
        "zoneId": "zone_2",
        "zoneName": "Geneva TMA",
        "zoneType": "TMA",
        "entryTime": "2026-01-21T10:40:00Z",
        "entryLatitude": 46.2345,
        "entryLongitude": 6.1234,
        "entryAltitude": 2100,
        "status": "in_progress"
      }
    ]
  }
}
```

## Testing

### Test Scenario: Overlapping Airspaces
1. Generate KML that flies through overlapping zones
2. Enter Zone A → Alert created, Zone A added to violations
3. Enter Zone B (while still in A) → Zone B added to violations
4. Exit Zone A (still in B) → Zone A marked completed, B still active
5. Exit Zone B → Zone B marked completed
6. Result: ONE alert with 2 completed violations

### Verification Points
- `_activeViolations.length` correctly reflects current zones
- `_currentFlightViolations.length` shows total violations
- `airspaceViolation` flag in Firebase toggles correctly
- Alert reason text updates with complete history
- No duplicate alerts created

## Debug Logging
```dart
print('🔍 [AlertService] checkFlightSafety:');
print('   Current zones at position: ${currentZones.length}');
print('   Active violations: ${_activeViolations.length}');
print('⚠️ [AlertService] ENTERED AIRSPACE: ${zone.name}');
print('✅ [AlertService] EXITING AIRSPACE: ${tracker.zoneName}');
```

## Benefits
✅ **Admin Experience:** One notification per flight, easy to review
✅ **Complete History:** All violations in one place
✅ **Real-Time:** Updates as flight progresses
✅ **Overlapping Zones:** Correctly handles complex airspace scenarios
✅ **Scalable:** Handles any number of violations per flight
✅ **Offline Support:** Works with pending alerts queue

## Live Tracking Integration
The `airspaceViolation` flag in Firebase correctly reflects:
- `TRUE` when `_activeViolations.isNotEmpty` (in ANY zone)
- `FALSE` when `_activeViolations.isEmpty` (clear of all zones)

This works perfectly with overlapping zones because the flag checks if the map has ANY entries, not a specific zone.
