# FLIGHTBOOK_DEVELOPER_GUIDE

...existing content...
// FLIGHT BOOK DEVELOPER GUIDE
// ===========================

## Quick Start

### 1. Access Flight Service in Your Widget
```dart
final flightService = context.watch<FlightService>();
final flights = flightService.flights;  // List<Flight>
```

### 2. Add a New Flight
```dart
final flight = Flight(
  studentUid: uid,
  schoolId: schoolId,
  date: DateTime.now().toIso8601String(),
  takeoffName: 'Flugplatz A',
  takeoffAltitude: 1000.0,
  landingName: 'Flugplatz B',
  landingAltitude: 500.0,
  altitudeDifference: 500.0,
  flightTimeMinutes: 90,
  licenseType: 'student',
);

final flightId = await flightService.addFlight(flight);
```

### 3. Update a Flight
```dart
final updatedFlight = Flight(
  id: flight.id,
  studentUid: flight.studentUid,
  schoolId: flight.schoolId,
  date: flight.date,
  takeoffName: 'New Takeoff',
  // ... other fields
  status: flight.status,  // Don't change status
);

await flightService.updateFlight(updatedFlight);
```

### 4. Delete a Flight
```dart
await flightService.deleteFlight(flightId, schoolId);
```

## Key Points

### Offline-First Behavior
- Changes appear **immediately** in the UI (optimistic update)
- Syncing happens in the background
- Works even without internet connection
- When online again, all pending changes sync automatically

### Status Management
- New flights: `status = 'pending'`
- Only instructors can change to `status = 'accepted'`
- Student sees status via yellow (pending) or green (accepted) icon
- Cannot edit flights with `status = 'accepted'` (except comment/details)

### Date Handling
- Internal format: ISO 8601 string `"2025-12-13T14:30:00.000"`
- Display format: `"dd.MM.yyyy"` in UI
- Database format: Firestore Timestamp
- Use `DateTime.parse(flight.date)` to work with it

### Cache vs Cloud
**Cache** (SharedPreferences):
- Fast local access
- Survives app restarts
- JSON-serializable format
- Used for offline support

**Cloud** (Firestore):
- Source of truth
- Real-time updates via stream listener
- Automatic sync in background
- Replaces cache when connection restored

## File Structure
```
lib/
  models/
    flight.dart              ← Flight data model
  services/
    flight_service.dart      ← State management & sync logic
  screens/
    flightbook_screen.dart   ← UI components
```

## Common Tasks

### Monitor Flight Loading
```dart
if (flightService.isLoading) {
  return CircularProgressIndicator();
}
```

### Get Specific Flight
```dart
final flight = flightService.getFlightById(flightId);
if (flight != null) {
  print('Found: ${flight.takeoffName}');
}
```

### Check if Flight is Editable
```dart
if (flight.canEdit()) {
  // Allow edit
}
```

### Listen to Flight Changes
```dart
final flightService = context.watch<FlightService>();
// Widget rebuilds whenever flights change
```

## Firestore Document Structure

### User Flight Log
```
users/{uid}/flightlog/{flightId}
{
  date: Timestamp,
  takeoffName: "Startplatz",
  takeoffAltitude: 1000.0,
  landingName: "Landeplatz",
  landingAltitude: 500.0,
  altitudeDifference: 500.0,
  flightTimeMinutes: 90,
  status: "pending",  // or "accepted"
  ...
}
```

### Public Flights
```
flights/{flightId}
// Same structure as user flightlog
```

### School Pending Review Queue
```
schools/{schoolId}/pendingFlights/{flightId}
{
  flightId: "...",
  student_uid: "...",
  school_id: "...",
  date: Timestamp,
  status: "pending"
  ...
}
```

## Error Handling Best Practice
```dart
try {
  await flightService.deleteFlight(flightId, schoolId);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Flight deleted')),
  );
} catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Error: $e'),
      backgroundColor: Colors.red,
    ),
  );
}
```

## Localization Example
```dart
const Map<String, Map<String, String>> _texts = {
  'Flight_Saved': {
    'en': 'Flight saved',
    'de': 'Flug gespeichert',
  },
};

String _t(String key, String lang) {
  return _texts[key]?[lang] ?? key;
}

// Usage:
String message = _t('Flight_Saved', appConfig.currentLanguageCode);
```

## Debugging Tips

### Log Flight Operations
```dart
debugPrint('[FlightService] Loaded ${flights.length} flights');
```

### Check Cache Content
```dart
final prefs = await SharedPreferences.getInstance();
final cached = prefs.getString('flightbook_flights');
print('Cache: $cached');
```

### Verify Firestore Writes
- Open Firebase Console
- Navigate to Firestore Database
- Check collections: users/{uid}/flightlog and flights
- Verify timestamps and field values

### Test Offline Mode
1. Stop internet on device/emulator
2. Add a flight
3. Verify it appears in list immediately
4. Restore internet
5. Check Firestore - flight should be there

## Performance Considerations

### Loading Time
- First load: ~500ms from Firestore
- Subsequent: instant from cache
- Stream listener keeps cache in sync

### Memory Usage
- Flights list held in memory (reasonable for typical pilot)
- Cache stored in SharedPreferences (text format)
- No issues up to 500+ flights

### Sync Efficiency
- Only changed fields sent to cloud (patch merging)
- Batch writes: multiple documents in single operation
- Background sync doesn't block UI

## Future Enhancements
- [ ] Location auto-suggestions
- [ ] Flight type/maneuver picker UI
- [ ] Offline map display for takeoff/landing
- [ ] CSV export of flights
- [ ] Flight photo attachment
- [ ] Instructor review workflow UI
- [ ] Flight analytics dashboard
