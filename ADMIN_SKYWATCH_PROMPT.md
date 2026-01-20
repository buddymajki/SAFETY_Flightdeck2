# Copilot Prompt: SkyWatch Admin Screen

Create a new Flutter screen for the admin web app called "SkyWatch" that displays live tracking data of pilots currently in flight.

---

## 1. File Location & Menu Integration

**Create new file:**
- Path: `lib/screens/admin/skywatch_screen.dart` (or wherever admin screens are located)

**Add to navigation menu:**
- Menu item: "SkyWatch" or "Live Tracking"
- Position: Below "Association" in the admin navigation
- Icon: `Icons.flight` or `Icons.radar`

---

## 2. Screen Layout (Desktop-Optimized)

### Layout Structure (2-Column + Bottom Panel)

```
┌─────────────────────────────────────────────────────────────────┐
│  🛩️ SkyWatch - Live Flight Tracking        [Auto-refresh: ON]  │
│                                             Last update: 14:23:15│
├─────────────────────────────────┬───────────────────────────────┤
│                                 │  🟢 Active Flights (3)        │
│                                 │  ─────────────────────────    │
│        INTERACTIVE MAP          │  🟢 Miki (SHV 54547)         │
│     (flutter_map package)       │     1926m | Brändlen-Nord    │
│                                 │     Student | 00:12:34       │
│     Green marker = Valid        │                               │
│     Red marker = Invalid        │  🟢 Hans Müller (12345)      │
│     Click marker = Details      │     1450m | Fiesch           │
│                                 │     Pilot | 01:05:22         │
│     Center: Switzerland         │                               │
│                                 │  🔴 Anna Schmidt (67890)     │
│                                 │     1200m | Kandersteg       │
│                                 │     Student | ⚠️ No ins.     │
│                                 │                               │
│                                 │  📊 Today's Statistics       │
│                                 │  ─────────────────────────    │
│                                 │  Total pilots today: 24      │
│                                 │  Currently flying: 3         │
│                                 │  Peak concurrent: 8          │
├─────────────────────────────────┴───────────────────────────────┤
│  ⚠️ Alerts (2)                                                  │
│  • Anna Schmidt - Insurance expired (flying since 14:10)        │
│  • [Future] Max Weber - Airspace violation CTR Bern             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Firestore Data Structure

### Collection: `/live_tracking/{uid}`

**Query for ACTIVE flights ONLY:**
```dart
FirebaseFirestore.instance
  .collection('live_tracking')
  .where('inFlight', isEqualTo: true)
  .snapshots()
```

**Document fields:**
```dart
{
  // Identity
  'uid': 'GX7IVR4heja2A92iu8hMUOQY1s63',
  'shvNumber': '54547',
  'displayName': 'Miki(buddy)',
  
  // Credentials
  'membershipValid': true,      // bool
  'insuranceValid': true,       // bool
  'licenseType': 'Student',     // 'Student' or 'Pilot'
  
  // Position (updated every second during flight)
  'latitude': 46.9070499,       // double
  'longitude': 8.3989056,       // double
  'altitude': 1926.7,           // double (meters)
  'heading': 0.0,               // double (degrees, optional)
  'speed': 0.000165,            // double (m/s, optional)
  
  // Timestamps
  'lastUpdate': Timestamp,      // Server timestamp
  'flightStartTime': Timestamp, // When flight started
  'landingTime': Timestamp?,    // When flight ended (only if landed)
  
  // Flight status
  'inFlight': true,             // bool - TRUE if flying, FALSE if landed
  
  // Metadata
  'glider': 'Nova - Aonic 2 (red)',
  'takeoffSite': 'Brändlen-Nord',
}
```

---

## 4. Left Panel: Interactive Map

### Map Configuration
- **Package:** `flutter_map: ^6.0.0` (add to pubspec.yaml)
- **Tiles:** OpenStreetMap (free, no API key needed)
- **Initial center:** Switzerland (lat: 46.8182, lon: 8.2275)
- **Initial zoom:** 8

### Map Markers
- **One marker per pilot** with `inFlight == true`
- **Marker color logic:**
  ```dart
  Color getMarkerColor(Map<String, dynamic> pilot) {
    if (!pilot['membershipValid'] || !pilot['insuranceValid']) {
      return Colors.red;  // 🔴 Invalid papers
    }
    return Colors.green;  // 🟢 Valid
  }
  ```

### Marker Popup (on tap)
Show popup with:
- Display name
- SHV number
- License type (Student/Pilot)
- Current altitude (meters)
- Takeoff site
- Flight duration (calculate: `now - flightStartTime`)
- Glider type
- Membership/Insurance status

---

## 5. Right Panel: Pilot List

### Section 1: Active Flights (Scrollable List)

**Title:** "🟢 Active Flights (X)"  
where X = count of pilots with `inFlight == true`

**Each pilot card shows:**
```dart
ListTile(
  leading: CircleAvatar(
    backgroundColor: getMarkerColor(pilot),
    child: Icon(Icons.flight),
  ),
  title: Text('${pilot['displayName']} (SHV ${pilot['shvNumber']})'),
  subtitle: Text('${pilot['altitude'].toStringAsFixed(0)}m | ${pilot['takeoffSite']}\n${pilot['licenseType']} | ${formatDuration(flightDuration)}'),
  trailing: pilot['membershipValid'] && pilot['insuranceValid'] 
    ? null 
    : Icon(Icons.warning, color: Colors.orange),
  onTap: () {
    // Center map on this pilot
    mapController.move(
      LatLng(pilot['latitude'], pilot['longitude']),
      12,
    );
  },
)
```

### Section 2: Today's Statistics

**Query all documents with `flightStartTime` from today:**
```dart
final today = DateTime.now();
final startOfDay = DateTime(today.year, today.month, today.day);

FirebaseFirestore.instance
  .collection('live_tracking')
  .where('flightStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
  .get()
```

**Display:**
- **Total pilots today:** Count of unique UIDs with flights today
- **Currently flying:** Count of `inFlight == true`
- **Peak concurrent:** (Optional, requires additional tracking)

---

## 6. Bottom Panel: Alerts

### Alert Types

**1. Invalid Papers:**
Show pilots currently flying (`inFlight == true`) with:
- `membershipValid == false` OR
- `insuranceValid == false`

**Example alert:**
```
⚠️ Anna Schmidt (SHV 67890) - Insurance expired (flying since 14:10)
```

**2. Airspace Violations (Future Feature):**
Placeholder for when you implement airspace violation detection:
```
⚠️ Max Weber (SHV 11111) - Entered restricted airspace CTR Bern (15:01)
```

---

## 7. Real-Time Updates

### StreamBuilder Implementation
```dart
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
    .collection('live_tracking')
    .where('inFlight', isEqualTo: true)
    .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }
    
    if (!snapshot.hasData) {
      return CircularProgressIndicator();
    }
    
    final pilots = snapshot.data!.docs;
    
    return Row(
      children: [
        // Left: Map
        Expanded(
          flex: 7,
          child: buildMap(pilots),
        ),
        // Right: Pilot list
        Expanded(
          flex: 3,
          child: buildPilotList(pilots),
        ),
      ],
    );
  },
)
```

### Auto-Refresh Indicator
- Show "Last update: HH:MM:SS" in header
- Update every second to show data freshness
- Optional: Green dot when connected, red when disconnected

---

## 8. Localization (German & English)

**Key translations:**
```dart
static const Map<String, Map<String, String>> _texts = {
  'SkyWatch': {'en': 'SkyWatch - Live Flight Tracking', 'de': 'SkyWatch - Live-Flugverfolgung'},
  'Active_Flights': {'en': 'Active Flights', 'de': 'Aktive Flüge'},
  'Currently_Flying': {'en': 'Currently flying', 'de': 'Derzeit fliegend'},
  'Total_Pilots_Today': {'en': 'Total pilots today', 'de': 'Piloten heute gesamt'},
  'Altitude': {'en': 'Altitude', 'de': 'Höhe'},
  'Flight_Duration': {'en': 'Flight duration', 'de': 'Flugdauer'},
  'Student': {'en': 'Student', 'de': 'Schüler'},
  'Pilot': {'en': 'Pilot', 'de': 'Pilot'},
  'Takeoff_Site': {'en': 'Takeoff', 'de': 'Start'},
  'Glider': {'en': 'Glider', 'de': 'Gleitschirm'},
  'Membership': {'en': 'Membership', 'de': 'Mitgliedschaft'},
  'Insurance': {'en': 'Insurance', 'de': 'Versicherung'},
  'Valid': {'en': 'Valid', 'de': 'Gültig'},
  'Invalid': {'en': 'Invalid', 'de': 'Ungültig'},
  'Alerts': {'en': 'Alerts', 'de': 'Warnungen'},
  'No_Pilots': {'en': 'No pilots currently airborne', 'de': 'Derzeit keine Piloten in der Luft'},
  'Last_Update': {'en': 'Last update', 'de': 'Letzte Aktualisierung'},
};
```

---

## 9. Helper Functions

### Format Flight Duration
```dart
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  
  if (hours > 0) {
    return '${hours}h ${minutes}m ${seconds}s';
  }
  return '${minutes}m ${seconds}s';
}
```

### Calculate Flight Duration
```dart
Duration getFlightDuration(Timestamp flightStartTime) {
  final start = flightStartTime.toDate();
  final now = DateTime.now();
  return now.difference(start);
}
```

### Get Today's Start Timestamp
```dart
Timestamp getStartOfToday() {
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);
  return Timestamp.fromDate(startOfDay);
}
```

---

## 10. Example Code Structure

```dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
      appBar: AppBar(
        title: const Text('SkyWatch - Live Flight Tracking'),
        actions: [
          // Auto-refresh indicator
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, _) {
                return Text(
                  'Last update: ${TimeOfDay.now().format(context)}',
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Main content: Map + List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('live_tracking')
                  .where('inFlight', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final pilots = snapshot.data!.docs;
                
                return Row(
                  children: [
                    // Map (70%)
                    Expanded(
                      flex: 7,
                      child: _buildMap(pilots),
                    ),
                    // Pilot list (30%)
                    Expanded(
                      flex: 3,
                      child: _buildPilotList(pilots),
                    ),
                  ],
                );
              },
            ),
          ),
          // Alerts panel
          _buildAlertsPanel(),
        ],
      ),
    );
  }
  
  Widget _buildMap(List<QueryDocumentSnapshot> pilots) {
    // TODO: Implement map with markers
  }
  
  Widget _buildPilotList(List<QueryDocumentSnapshot> pilots) {
    // TODO: Implement scrollable list
  }
  
  Widget _buildAlertsPanel() {
    // TODO: Implement alerts
  }
}
```

---

## 11. Dependencies to Add

Add to `pubspec.yaml`:
```yaml
dependencies:
  flutter_map: ^6.0.0
  latlong2: ^0.9.0
```

Run: `flutter pub get`

---

## 12. Testing Checklist

- [ ] Map loads and centers on Switzerland
- [ ] Markers appear for each pilot with `inFlight == true`
- [ ] Marker colors match credential status (green/red)
- [ ] Clicking marker shows popup with pilot details
- [ ] Pilot list shows all active flights
- [ ] Clicking pilot in list centers map on them
- [ ] Flight duration updates every second
- [ ] "Total pilots today" shows correct count
- [ ] Alerts show pilots with invalid papers
- [ ] Real-time updates when new pilots take off/land
- [ ] German/English translations work

---

## 13. Additional Features (Nice to Have)

- **Search/Filter:** Filter by name, SHV number, or license type
- **Export:** Export current snapshot as CSV
- **Sound alerts:** Beep when pilot with invalid papers takes off
- **Map clustering:** Group nearby markers when zoomed out
- **Flight path:** Show track history (requires storing tracklog)

---

## 14. Important Notes

1. **Only show pilots with `inFlight == true`** in the active list
2. **Query all today's flights** (regardless of `inFlight` status) for statistics
3. **Handle empty state:** Show "No pilots currently airborne" when no active flights
4. **Error handling:** Gracefully handle Firestore connection issues
5. **Performance:** Use proper `const` constructors and efficient rebuilds

---

**Start by creating the basic screen structure with the map and pilot list, then add statistics and alerts incrementally.**
