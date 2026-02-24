# LIVE_TRACKING_IMPLEMENTATION
## Overview
This document outlines the implementation of live tracking features in the FlightDeck application.
...existing content...
# Live Tracking Implementation Plan

## Feature Name: **"SkyWatch"** or **"Live Tracking"**
Suggested alternatives:
- "SkyWatch" - Implies oversight/monitoring (good for authorities)
- "Live Tracking" - Simple and clear
- "AirWatch" - Similar to SkyWatch
- "FlightRadar" - Familiar concept (like FlightRadar24)

## Overview
Replace the old "license plate" system with digital live tracking. Authorities can see who is flying, verify their credentials, and monitor for airspace violations.

---

## Architecture

### Firestore Collection: `live_tracking`
Each document represents ONE pilot currently in flight. Document ID = user's `uid`.

```
/live_tracking/{uid}
{
  // Identity
  uid: string,
  shvNumber: string,
  displayName: string,           // nickname or "forename familyname"
  
  // Status
  membershipValid: boolean,      // from association data
  insuranceValid: boolean,       // from association data
  licenseType: string,           // 'student' or 'pilot'
  
  // Position (updated every 12 seconds)
  latitude: number,
  longitude: number,
  altitude: number,              // meters
  heading: number?,              // degrees (optional)
  speed: number?,                // m/s (optional)
  
  // Timestamps
  lastUpdate: Timestamp,         // server timestamp
  flightStartTime: Timestamp,    // when flight started
  
  // Optional metadata
  glider: string?,               // glider type
  takeoffSite: string?,          // where they took off
}
```

### Why This Structure?
1. **Document per pilot** = Easy to query all active pilots
2. **Overwrite on update** = Minimal storage, one document per pilot
3. **Delete on landing** = Clean collection, only shows active flights
4. **Fast queries** = Admin can fetch all documents in one read

---

## End-User App Implementation

### 1. New Service: `LiveTrackingService`

**Location:** `lib/services/live_tracking_service.dart`

**Responsibilities:**
- Send position updates to Firestore when in flight
- Throttle updates (only send every 12 seconds OR after 50m movement)
- Register/unregister pilot from live tracking collection
- Handle connection errors gracefully

**Key Methods:**
```dart
class LiveTrackingService {
  bool _isLiveTrackingEnabled = true;  // User preference
  DateTime? _lastUploadTime;
  Position? _lastUploadedPosition;
  
  // Start live tracking when flight begins
  Future<void> startLiveTracking(UserProfile profile);
  
  // Stop live tracking when flight ends
  Future<void> stopLiveTracking();
  
  // Called every second from GPS service
  Future<void> updatePosition(TrackPoint position);
  
  // Check if should upload (12 sec OR 50m)
  bool _shouldUpload(TrackPoint position);
  
  // Actual Firestore write
  Future<void> _uploadPosition(TrackPoint position);
}
```

### 2. Integration Points

**In `FlightTrackingService`:**
- When `_handleTakeoff()` is called → Start live tracking
- When `_handleLanding()` is called → Stop live tracking
- In `processPosition()` → Pass position to LiveTrackingService

**Data Flow:**
```
GPS Sensor (1/sec) → FlightTrackingService → LiveTrackingService
                                              ↓ (every 12 sec)
                                           Firestore
```

### 3. User Settings (Optional)
- Toggle to enable/disable live tracking
- Show indicator when live tracking is active

---

## Admin Web App Implementation

### 1. New Screen: "SkyWatch" / "Live Tracking"

**Location in menu:** Below "Association" 

**Layout (Desktop):**
```
┌─────────────────────────────────────────────────────────────────┐
│  🛩️ SkyWatch - Live Tracking                    [Refresh: 12s]  │
├─────────────────────────────────┬───────────────────────────────┤
│                                 │  Pilots in Air (24)           │
│                                 │  ─────────────────────────    │
│        INTERACTIVE MAP          │  🟢 Hans Müller (SHV 12345)  │
│     (flutter_map with markers)  │     Alt: 1450m | Fiesch      │
│                                 │  🟢 Anna Schmidt (SHV 67890) │
│     🟢 = Valid papers           │     Alt: 1200m | Kandersteg  │
│     🔴 = Missing papers         │  🔴 John Doe (SHV 11111)     │
│     🟡 = Airspace warning       │     Alt: 980m | ⚠️ No ins.   │
│                                 │                               │
├─────────────────────────────────┴───────────────────────────────┤
│  ⚠️ Alerts                                                       │
│  • John Doe - Insurance expired (flying since 14:23)            │
│  • Max Weber - Entered restricted airspace CTR Bern (15:01)     │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Real-time Updates
- Use Firestore `snapshots()` to listen to `live_tracking` collection
- Auto-refresh map markers every 12 seconds
- Show connection status indicator

### 3. Pilot Details (on click)
- Full name, SHV number, license type
- Flight duration, takeoff site
- Current altitude, speed
- Membership/insurance status

---

## Airspace Violation Detection

### Option A: Client-Side (Simpler)
- App checks if current position is in restricted airspace
- If violation detected, send alert to separate collection: `/airspace_alerts/{alertId}`
- Pro: Simple, no Cloud Functions
- Con: Relies on client device

### Option B: Cloud Functions (More Robust)
- Cloud Function triggered on every `live_tracking` write
- Checks position against airspace polygons
- Creates alert if violation detected
- Pro: Cannot be bypassed, centralized logic
- Con: Additional complexity and cost

**Recommendation:** Start with Option A for MVP, migrate to Option B if needed.

---

## Firebase Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Live tracking - users can only write their own position
    match /live_tracking/{uid} {
      allow read: if request.auth != null && 
                    (request.auth.uid == uid || 
                     exists(/databases/$(database)/documents/admins/$(request.auth.uid)));
      allow write: if request.auth != null && request.auth.uid == uid;
      allow delete: if request.auth != null && request.auth.uid == uid;
    }
    
    // Airspace alerts - users can create, only admins can read/delete
    match /airspace_alerts/{alertId} {
      allow create: if request.auth != null;
      allow read, delete: if request.auth != null && 
                            exists(/databases/$(database)/documents/admins/$(request.auth.uid)));
    }
  }
}
```

---

## Implementation Steps

### Phase 1: MVP (End-User App)
1. ✅ Create `LiveTrackingService`
2. ✅ Integrate with `FlightTrackingService`
3. ✅ Add position throttling (12 sec / 50m)
4. ✅ Test with simulation

### Phase 2: Admin Visualization
1. Create "SkyWatch" screen in admin app
2. Add map with live markers
3. Add pilot list sidebar
4. Add auto-refresh (12 sec)

### Phase 3: Alerts & Validation
1. Add membership/insurance status display
2. Implement airspace violation detection
3. Create alerts collection and UI

---

## Cost Estimate (Recap)

| Scenario | Pilots | Days/Year | Cost/Year |
|----------|--------|-----------|-----------|
| Typical  | 500-1000 | ~100     | $400-$500 |
| Busy     | 1000    | 250       | ~$2,000   |
| Worst    | 20,000  | 250       | ~$11,000  |

Budget $10,000/year to be safe.

---

## Copilot Prompt for Admin Web App

Use this prompt to implement the admin visualization screen:

```
Create a new screen called "SkyWatchScreen" for the admin web app that displays live tracking data from Firestore.

Requirements:
1. Location: lib/screens/skywatch_screen.dart
2. Menu placement: Below "Association" in the admin navigation

Layout:
- Left side (60%): Interactive map using flutter_map with OpenStreetMap tiles
  - Show markers for each pilot from /live_tracking collection
  - Green marker: Valid membership & insurance
  - Red marker: Invalid/missing papers
  - Yellow marker: Airspace violation warning
  - Popup on tap: Show pilot details (name, SHV, altitude, flight duration)

- Right side (40%): Scrollable list of pilots
  - Show pilot name, SHV number, current altitude, takeoff site
  - Status indicator (green/red/yellow)
  - Click to center map on pilot

- Bottom bar: Alerts section
  - Show airspace violations
  - Show pilots with invalid papers

Real-time updates:
- Use StreamBuilder with Firestore snapshots()
- Listen to /live_tracking collection
- Auto-update every time data changes

Data model from Firestore /live_tracking/{uid}:
{
  uid, shvNumber, displayName, membershipValid, insuranceValid,
  licenseType, latitude, longitude, altitude, heading, speed,
  lastUpdate, flightStartTime, glider, takeoffSite
}

Style: Match existing admin app style (dark theme if applicable)
```

---

## Next Steps

1. **Today:** ✅ Created `LiveTrackingService` and integrated with flight tracking
2. **Tomorrow:** Test with simulation, verify Firestore writes
3. **Next:** Implement admin visualization screen

---

## Files Created/Modified

### New Files:
- `lib/services/live_tracking_service.dart` - Live tracking service for sending positions to cloud

### Modified Files:
- `lib/services/flight_tracking_service.dart` - Integrated with LiveTrackingService
- `lib/main.dart` - Added LiveTrackingService provider
- `firestore.rules` - Added security rules for live_tracking and airspace_alerts collections

---

## Copilot Prompt for Admin Web App Visualization Screen

Copy this prompt to create the admin visualization screen:

```
Create a new screen called "SkyWatchScreen" for the Flutter admin web app that displays live tracking data from Firestore.

## Requirements

### 1. File Location
- Path: `lib/screens/skywatch_screen.dart`
- Menu placement: Below "Association" in the admin navigation (add to main_navigation.dart or wherever admin menu is defined)

### 2. Layout (Responsive Desktop-First)
The screen should have a two-column layout:

**Left Panel (60-70% width): Interactive Map**
- Use `flutter_map` package with OpenStreetMap tiles
- Center on Switzerland initially (lat: 46.8182, lon: 8.2275, zoom: 8)
- Show markers for each pilot from Firestore `/live_tracking` collection
- Marker colors based on status:
  - 🟢 Green: Valid membership AND insurance (both `membershipValid` AND `insuranceValid` are true)
  - 🔴 Red: Invalid/missing papers (either field is false)
  - 🟡 Yellow: Airspace violation warning (if you implement airspace checking)
- On marker tap: Show popup with pilot details:
  - Name, SHV Number
  - Current altitude
  - Flight duration (calculated from `flightStartTime`)
  - Takeoff site
  - Glider type

**Right Panel (30-40% width): Pilot List**
- Scrollable list of all pilots currently in air
- For each pilot show:
  - Status indicator (colored dot)
  - Display name
  - SHV number
  - Current altitude
  - Takeoff site
- On tap: Center map on that pilot's location

**Bottom Section: Alerts Panel (collapsible)**
- Show warnings for:
  - Pilots with invalid papers (membershipValid or insuranceValid = false)
  - Airspace violations (if implemented)

### 3. Real-Time Data
- Use `StreamBuilder` with Firestore `snapshots()` to listen to `/live_tracking` collection
- Auto-update map markers when data changes
- Show connection status indicator (connected/disconnected)
- Show "Last updated: XX:XX:XX" timestamp
- Display total count of pilots in air

### 4. Firestore Data Model
Collection: `/live_tracking/{uid}`
Document fields:
```dart
{
  'uid': String,
  'shvNumber': String,
  'displayName': String,
  'membershipValid': bool,
  'insuranceValid': bool,
  'licenseType': String,        // 'student' or 'pilot'
  'latitude': double,
  'longitude': double,
  'altitude': double,
  'heading': double?,           // optional
  'speed': double?,             // optional
  'lastUpdate': Timestamp,
  'flightStartTime': Timestamp,
  'glider': String?,
  'takeoffSite': String?,
}
```

### 5. Dependencies
Add to pubspec.yaml if not present:
- `flutter_map: ^6.0.0` (or latest)
- `latlong2: ^0.9.0`

### 6. Style Guidelines
- Match existing admin app theme
- Use Material 3 components
- Responsive layout (works on large screens)
- Dark theme support if admin app has it

### 7. Localization
- Support German and English
- Use same localization pattern as other screens in the app
- Key texts:
  - "SkyWatch - Live Tracking" / "SkyWatch - Live-Tracking"
  - "Pilots in Air" / "Piloten in der Luft"
  - "Altitude" / "Höhe"
  - "Flight Duration" / "Flugdauer"
  - "No pilots currently airborne" / "Derzeit keine Piloten in der Luft"
  - "Connection Status" / "Verbindungsstatus"
  - "Alerts" / "Warnungen"
  - "Invalid Papers" / "Ungültige Papiere"

### 8. Example Code Structure
```dart
class SkyWatchScreen extends StatefulWidget {
  const SkyWatchScreen({super.key});
  
  @override
  State<SkyWatchScreen> createState() => _SkyWatchScreenState();
}

class _SkyWatchScreenState extends State<SkyWatchScreen> {
  final MapController _mapController = MapController();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SkyWatch - Live Tracking')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('live_tracking').snapshots(),
        builder: (context, snapshot) {
          // Build map and list from snapshot.data.docs
        },
      ),
    );
  }
}
```

### 9. Additional Features (Nice to Have)
- Filter by license type (student/pilot)
- Search by name or SHV number
- Export current snapshot as CSV
- Historical playback (if we store track history later)
```
