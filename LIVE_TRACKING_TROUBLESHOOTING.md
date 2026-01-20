# Live Tracking Troubleshooting Guide

## Issue: "Takeoff detected but nothing sent to cloud"

### ✅ Changes Made to Fix

1. **Firestore Rules (firestore.rules)** - Fixed authentication check
   - Changed from `match /live_tracking/{uid}` to `match /live_tracking/{document=**}`
   - Updated `isOwner()` logic to properly check `resource.id` against auth UID
   - Made rules clearer and more explicit

2. **Enhanced Logging in LiveTrackingService**
   - Added detailed logs for profile updates
   - Added logs for upload attempts and failures
   - Stack traces now included for errors
   - Shows UID, name, and status at each step

### 🔍 How to Debug

Check the **Dart console/logs** for these patterns:

#### 1. Profile Initialization
```
[LiveTrackingService] ✓ Profile updated:
    UID: <user-id>
    Name: <pilot-name>
    SHV: <shv-number>
    License: <student|pilot>
    Membership: true, Insurance: true
```
**If missing:** Profile is not being passed to the service. Check if user is authenticated.

#### 2. Takeoff Detection → Live Tracking Start
```
[LiveTrackingService] startTracking called - enabled: true, isActive: false
[LiveTrackingService] ✓ Started live tracking from <site-name> (UID: <user-id>, Profile: <name>)
```
**If missing:** Takeoff event not being handled or service not connected.

#### 3. Position Update → Upload
```
[LiveTrackingService] Position threshold reached, uploading...
[LiveTrackingService] Uploading position for UID: <user-id>, data: {...}
[LiveTrackingService] ✓ Position uploaded: 47.xxxx, 8.xxxx, 1450m
```
**If missing:** Either throttling is active (wait 12s or move 50m) or positions not being sent to the service.

#### 4. Upload Error
```
[LiveTrackingService] ✗ Error uploading position: <error-message>
[LiveTrackingService] Stack trace: <trace>
```
**Common errors:**
- `Permission denied` → Firestore rules issue (check below)
- `User not authenticated` → Auth issue
- `Document not found` → UID mismatch

### 🚀 Checklist

- [ ] User is authenticated (logged in)
- [ ] Flight is detected (takeoff log appears)
- [ ] Profile is loaded (check UID in console)
- [ ] Firestore rules are deployed
- [ ] Firebase project is correct
- [ ] Network connection is active

### 📋 Manual Test Steps

1. **Check authentication:**
   ```dart
   print('User: ${FirebaseAuth.instance.currentUser?.uid}');
   ```

2. **Check profile in ProfileService:**
   - Print `profileService.userProfile?.uid`
   - Should match Firebase Auth UID

3. **Check if LiveTrackingService is initialized:**
   - Provider should inject it from ProfileService
   - Watch console for "Profile updated" log

4. **Check Firestore rules:**
   - Open Firebase Console → Firestore → Rules
   - Paste current version and check syntax
   - Use **Rules Playground** to test write access

5. **Test write directly:**
   ```dart
   await FirebaseFirestore.instance
     .collection('live_tracking')
     .doc(FirebaseAuth.instance.currentUser!.uid)
     .set({
       'test': true,
       'timestamp': FieldValue.serverTimestamp(),
     });
   ```

### 🔧 If Still Not Working

1. **Clear Firestore Rules** (temporary for testing):
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if true;  // ⚠️ ONLY FOR TESTING!
       }
     }
   }
   ```
   - Deploy and test
   - Then revert to strict rules

2. **Check Firebase Console Logs:**
   - Go to Cloud Functions → Logs (if using functions)
   - Go to Firestore → Rules (simulate writes)

3. **Verify Collection Path:**
   - Collection must be exactly: `live_tracking`
   - Document ID must be user's UID

---

## What Should Happen

### Normal Flow:
```
User logs in
    ↓
ProfileService loads profile
    ↓
LiveTrackingService.updateProfile() called
    ↓
FlightTrackingService.setLiveTrackingService() called
    ↓
GPS tracking enabled
    ↓
Takeoff detected
    ↓
FlightTrackingService._handleTakeoff() 
    ↓ (calls)
LiveTrackingService.startTracking()
    ↓
Position updates every 1 second
    ↓
LiveTrackingService.processPosition() throttles (12s or 50m)
    ↓
_uploadPosition() writes to Firestore /live_tracking/{uid}
    ↓
Landing detected
    ↓
LiveTrackingService.stopTracking() deletes document
```

---

## Quick Fixes

### Issue: "No authenticated user"
- **Solution:** Login first, then test

### Issue: "Profile shows NULL"
- **Solution:** Wait for ProfileService to load (check if Firestore read works)

### Issue: "Position threshold never reached"
- **Solution:** Move GPS >50m or wait 12 seconds after first upload

### Issue: "Permission denied" in logs
- **Solution:** Deploy updated firestore.rules and wait a few seconds for propagation

