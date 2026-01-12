# Automatic Location Recognition for Takeoff/Landing

## Overview
The app now automatically recognizes and matches recorded takeoff and landing coordinates to cached locations from Firebase, providing automatic site identification based on location type (takeoff or landing).

## How It Works

### 1. Location Loading
- **At App Startup**: GlobalDataService loads all locations from Firebase `globalLocations` collection
- **Structure**: Each location has:
  - `name` - Site name (multilingual support with `name_en`, `name_de`, etc.)
  - `type` - Either "takeoff" or "landing"
  - `latitude`, `longitude`, `altitude` - Coordinates
  - (Alternative: `coords.lat`, `coords.lng` for nested structure)
  - `id` - Unique location identifier

### 2. FlightTrackingService Initialization
The service is initialized with cached locations:
```dart
await trackingService.initialize(globalLocations, lang: 'en');
```

### 3. Takeoff Detection
When takeoff is detected:
1. **First Priority**: Find the nearest location with `type: "takeoff"`
   - Uses `LocationService.findNearestSiteByType(..., 'takeoff')`
   - Returns the closest takeoff location regardless of distance
   
2. **Fallback**: If no "takeoff" type location found
   - Find any nearby location with `findSitesWithinProximity()`
   - Uses 80m horizontal, ±100m vertical thresholds
   
3. **Final Fallback**: If no nearby locations
   - Use coordinates: "Unknown Takeoff (lat, lon)"

### 4. Landing Detection
When landing is detected (either by algorithm or auto-close timer):
1. **First Priority**: Find the nearest location with `type: "landing"`
   - Uses `LocationService.findNearestSiteByType(..., 'landing')`
   - Returns the closest landing location regardless of distance
   
2. **Fallback**: If no "landing" type location found
   - Find any nearby location with `findSitesWithinProximity()`
   - Uses 80m horizontal, ±100m vertical thresholds
   
3. **Final Fallback**: If no nearby locations
   - Use coordinates: "Unknown Landing (lat, lon)"

## Coordinate Matching Example

### Firebase Locations
```
Büelen Takeoff:
  type: "takeoff"
  lat: 46.8808
  lng: 8.36551
  
Büelen Landing:
  type: "landing"
  lat: 46.8827
  lng: 8.3774
```

### App Records
- **Takeoff detected at**: 46.8827, 8.3771
  - Closest takeoff location: 46.8808, 8.36551 (distance: ~450m)
  - **Will match to**: "Büelen" (takeoff type)

- **Landing detected at**: 46.8824, 8.3773
  - Closest landing location: 46.8827, 8.3774 (distance: ~40m)
  - **Will match to**: "Büelen" (landing type)

## Debug Logging

When running, check the Android logcat for matching details:

```
[FlightTrackingService] TAKEOFF: lat=46.882700, lon=8.377100, alt=1085m
[FlightTrackingService] Found takeoff site: Büelen (distance: 450m)

[FlightTrackingService] LANDING: lat=46.882400, lon=8.377300, alt=950m
[FlightTrackingService] Found landing site: Büelen (distance: 40m)
```

## Code Changes

### LocationService (lib/services/location_service.dart)
Added new method:
- `findNearestSiteByType()` - Finds nearest site matching specific type
- Supports accessing nested coordinate structure (`coords.lat`, `coords.lng`)
- Supports both flat (`latitude`, `longitude`) and nested coordinate formats

### FlightTrackingService (lib/services/flight_tracking_service.dart)
Updated three methods:
1. `_handleTakeoff()` - Uses type-based matching for takeoff sites
2. `_handleLanding()` - Uses type-based matching for landing sites
3. `_autoCloseCurrentFlight()` - Uses type-based matching when auto-closing

All methods now:
- Try to find location by type first
- Fall back to proximity-based matching
- Fall back to coordinates
- Log each step for debugging

## Configuration

### Proximity Thresholds
Located in [lib/services/location_service.dart](lib/services/location_service.dart#L10-L13):
```dart
static const double horizontalProximityThreshold = 80.0;  // meters
static const double verticalProximityThreshold = 100.0;   // meters
```

### Auto-Close Timeout
Located in [lib/services/flight_tracking_service.dart](lib/services/flight_tracking_service.dart#L51):
```dart
static const Duration autoCloseFlightTimeout = Duration(seconds: 10);
```
**For production, change to 5+ minutes**

## User Adjustment (Future Feature)

Currently not implemented, but the code structure supports allowing users to manually:
- Change the matched takeoff/landing location
- Add new locations
- Adjust matched location details

This would be added later in the flight detail editing screen.

## Testing

1. Load your KML tracklog file with coordinates
2. Check Android logcat for matching messages
3. Verify takeoff and landing sites are correctly identified
4. Check that coordinates differ between takeoff and landing in the flight record

Example expected log output:
```
Found takeoff site: Büelen (distance: 450m)
Found landing site: Büelen (distance: 40m)
```
